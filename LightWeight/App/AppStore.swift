import Foundation
import UIKit
import SwiftData
import WidgetKit
import ActivityKit
import Observation

/// App-wide state: the model container, a cached analysis over all finished sessions, and the session lifecycle.
@MainActor @Observable final class AppStore {
    static weak var shared: AppStore?
    let container: ModelContainer
    var context: ModelContext { container.mainContext }
    private(set) var analysis = Analysis()
    private(set) var exercisesByID: [String: Exercise] = [:]
    private var sessionsCache: [Session] = []            // finished, chronological
    private var sessionsByID: [UUID: Session] = [:]
    private var exercisesCache: [Exercise] = []
    private var sessionCounts: [UUID: Int] = [:]
    var importReport: HevyImporter.Report?
    var today: Date = .now
    private(set) var liveSessionID: UUID?   // observable: views re-render when a session goes live / ends
    var pinnedWorkoutIDs: [String] = UserDefaults.standard.stringArray(forKey: "pinned.workouts") ?? []
    @ObservationIgnored private var liveActivity: Activity<WorkoutActivityAttributes>?
    @ObservationIgnored var coachClient: CoachClient = CommandLine.arguments.contains("--coach-fixture") ? FixtureCoachClient() : LiveCoachClient()
    var coachTick = 0                       // bumped on note upsert so views re-read the store
    var dataTick = 0                        // bumped on reload() — pages re-render after imports/finishes
    var coachPending: Set<String> = []      // generation keys in flight (drives loading panels)
    var coachStatus: [String: String] = [:] // stage-driven status line per pending key
    var coachStream: [String: String] = [:] // live token stream (body prose so far) per pending key
    @ObservationIgnored var usedFallbackStore = false   // emergency in-memory store — never let it overwrite shared state
    var coachFailed: Set<String> = []       // keys whose last generation failed (visible retry state)
    var coachFailReason: [String: String] = [:]

    init(inMemory: Bool = false) {
        let testing = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        let schema = SwiftData.Schema(Schema.all)
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let config = (inMemory || testing) ? ModelConfiguration(isStoredInMemoryOnly: true) : ModelConfiguration(url: dir.appendingPathComponent("LightWeight.store"))
        // A fast relaunch can race the dying instance's file lock — retry before the in-memory fallback,
        // or the app looks wiped while the store sits intact on disk.
        var opened: ModelContainer?
        for attempt in 1...5 {
            if let c = try? ModelContainer(for: schema, configurations: [config]) { opened = c; break }
            coachLog("store open failed (attempt \(attempt)) — retrying")
            usleep(500_000)
        }
        if let c = opened {
            container = c
        } else {
            coachLog("store open FAILED after retries — falling back to empty in-memory store")
            usedFallbackStore = true
            container = try! ModelContainer(for: schema, configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        }
        Seed.seedIfNeeded(context)
        Self.shared = self
        handleLaunchArguments()
        importDocumentsCSVs()
        reload()
        syncLiveActivity()
        for n in (try? context.fetch(FetchDescriptor<CoachNote>())) ?? []
            where (try? JSONDecoder().decode(CoachRead.self, from: Data(n.text.utf8))) == nil {
            context.delete(n)                               // pre-CoachRead contracts regenerate fresh
        }
        try? context.save()
        if CommandLine.arguments.contains("--coach-fail-once") { UserDefaults.standard.removeObject(forKey: "coach.fixture.didFail") }
        for k in UserDefaults.standard.dictionaryRepresentation().keys where k.hasPrefix("coach.retry.") {
            UserDefaults.standard.removeObject(forKey: k)   // fresh retries every launch — a fixed bug shouldn't stay muted
        }
        if let i = CommandLine.arguments.firstIndex(of: "--seed-cycles"), i + 1 < CommandLine.arguments.count,
           let n = Int(CommandLine.arguments[i + 1]) { seedDesignedCycles(n) }
        if CommandLine.arguments.contains("--dump-coach-ctx") { dumpCoachContexts() }
        if CommandLine.arguments.contains("--coach-demo") { seedCoachDemo() } else { coachReconcile()
        if !inMemory, !usedFallbackStore { pushWidgetSnapshot() } }   // in-memory or fallback stores must never zero the shared widget snapshot
    }

    /// Any Hevy export dropped into the app's Documents folder (Files app, devicectl, AirDrop) is imported on launch; idempotent.
    func importDocumentsCSVs() {
        guard !CommandLine.arguments.contains("--empty-demo") else { return }
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let files = ((try? FileManager.default.contentsOfDirectory(at: docs, includingPropertiesForKeys: nil)) ?? []).filter { $0.pathExtension.lowercased() == "csv" }
        for f in files {
            if let text = try? String(contentsOf: f, encoding: .utf8), let r = try? HevyImporter.importCSV(text, into: context) {
                if r.imported > 0 || importReport == nil { importReport = r }
            }
        }
    }

    // MARK: queries
    /// Rebuilds every cache. Call after anything that changes finished sessions or the exercise library.
    func reload() {
        exercisesCache = (try? context.fetch(FetchDescriptor<Exercise>(sortBy: [SortDescriptor(\.name)]))) ?? []
        exercisesByID = Dictionary(uniqueKeysWithValues: exercisesCache.map { ($0.id, $0) })
        sessionsCache = ((try? context.fetch(FetchDescriptor<Session>())) ?? []).filter { !$0.isDraft }.sorted { $0.startedAt < $1.startedAt }
        sessionsByID = Dictionary(uniqueKeysWithValues: sessionsCache.map { ($0.id, $0) })
        sessionCounts = sessionsCache.reduce(into: [:]) { if let w = $1.workoutID { $0[w, default: 0] += 1 } }
        let actives = ((try? context.fetch(FetchDescriptor<Routine>())) ?? []).filter(\.isActive)
        if actives.count > 1 {                                 // heal the duplicate-routine bug: keep the fullest loop
            let keep = actives.max { $0.entries.count < $1.entries.count }
            for r in actives where r !== keep { r.isActive = false }
            try? context.save()
        }
        liveSessionID = ((try? context.fetch(FetchDescriptor<Session>())) ?? []).first { $0.isDraft && $0.isStarted }?.id
        dataTick += 1
        analysis = Engine.run(sessionsCache.map(Self.input))
    }
    func allExercises() -> [Exercise] { exercisesCache }
    func finishedSessions() -> [Session] { sessionsCache }
    func sessionsNewestFirst() -> [Session] { sessionsCache.reversed() }
    func draftSession() -> Session? { ((try? context.fetch(FetchDescriptor<Session>())) ?? []).first { $0.isDraft } }
    /// The minimized in-progress session, if any. Reads the observable id so views track liveness.
    func liveSession() -> Session? {
        guard let id = liveSessionID else { return nil }
        return ((try? context.fetch(FetchDescriptor<Session>())) ?? []).first { $0.id == id && $0.isDraft }
    }
    /// Any session by id, straight from the store — usable before `reload()` has refreshed the cache.
    func anySession(_ id: UUID) -> Session? {
        ((try? context.fetch(FetchDescriptor<Session>())) ?? []).first { $0.id == id }
    }
    /// A fresh draft begins its life here (the Fresh page's slider).
    func markLive(_ s: Session) { s.isStarted = true; s.startedAt = .now; liveSessionID = s.id; try? context.save(); startLiveActivity(s) }
    static func progress(_ s: Session) -> Double {
        let all = s.exercises.flatMap(\.sets).filter { $0.type != "warmup" }
        let done = all.filter(\.done).count
        return all.isEmpty ? 0 : Double(done) / Double(all.count)
    }

    // MARK: rest timer (Session V2) — one global wall-clock timer, one persisted preset
    var restAnchor: Date?                 // nil = idle
    var restDuration: TimeInterval?       // nil while running = count-up mode
    var settling = false                  // finishing: derived data is still catching up
    var restFlash = false                 // 1s bright flip at 0:00
    var restScreenUp = false              // 11a: raised whenever the clock starts, dismissed by any tap
    private var restTask: Task<Void, Never>?
    var restPreset: TimeInterval {
        get { UserDefaults.standard.object(forKey: "rest.preset") as? TimeInterval ?? 90 }
        set { UserDefaults.standard.set(newValue, forKey: "rest.preset") }
    }
    var restEndsAt: Date? { restAnchor.flatMap { a in restDuration.map { a.addingTimeInterval($0) } } }
    /// Countdown remaining, count-up elapsed, or nil when idle. Pure wall-time — survives kill/relaunch of the process clock.
    func restDisplay(at date: Date) -> TimeInterval? {
        guard let a = restAnchor else { return nil }
        if let d = restDuration { return max(0, d - date.timeIntervalSince(a)) }
        return date.timeIntervalSince(a)
    }
    /// Quick start (chip tap) and restart (any set check). No preset → plain count-up.
    func startRest() {
        restTask?.cancel(); restFlash = false
        restScreenUp = true                            // 11a — the screen comes up with the clock
        restAnchor = .now
        restDuration = restPreset > 0 ? restPreset : nil
        if let end = restEndsAt {
            restTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(max(0, end.timeIntervalSinceNow)))
                guard !Task.isCancelled, let self else { return }
                await MainActor.run {
                    self.restFlash = true; self.restAnchor = nil; self.restDuration = nil; self.restScreenUp = false
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()   // gentle haptic, never a sound
                    self.updateLiveActivity(self.liveSession())
                }
                try? await Task.sleep(for: .seconds(1))
                await MainActor.run { self.restFlash = false }
            }
        }
        updateLiveActivity(liveSession())
    }
    func cancelRest() {
        restTask?.cancel(); restAnchor = nil; restDuration = nil; restFlash = false
        updateLiveActivity(liveSession())
    }
    /// One active routine, ever: fetch-or-create, append, tick. (View-side creation raced and spawned duplicates.)
    /// A routine is an ordered list of SLOTS, so a workout already in the loop simply takes another
    /// one — push · pull · legs · push is a loop of four slots over three workouts, not a mistake.
    func addToRoutine(_ w: Workout) {
        let r = activeRoutine() ?? { let n = Routine(name: "My routine", isActive: true); context.insert(n); return n }()
        let e = RoutineEntry(order: r.orderedEntries.count, workoutID: w.id); e.routine = r; context.insert(e)
        try? context.save(); dataTick += 1
    }

    // MARK: slots
    /// One place in the loop. `occurrence` and `fills` are what separate two slots holding the
    /// same workout wherever both are on screen; with every workout in one slot they say nothing.
    struct Slot: Identifiable {
        let id: PersistentIdentifier
        let index: Int                 // 0-based place in the loop
        let entry: RoutineEntry
        let workoutID: UUID
        let name: String
        let occurrence: Int            // 1-based among the slots this workout fills
        let fills: [Int]               // every slot index this workout fills
        var repeated: Bool { fills.count > 1 }
        /// The other slots this workout fills, 1-based — the editor's "also 2, 5".
        var alsoFills: [Int] { fills.filter { $0 != index }.map { $0 + 1 } }
    }
    /// The active routine as slots. Occurrences are grouped by workout id, numbered in slot order.
    func routineSlots() -> [Slot] {
        guard let r = activeRoutine() else { return [] }
        let entries = r.orderedEntries
        var fills: [UUID: [Int]] = [:]
        for (i, e) in entries.enumerated() { fills[e.workoutID, default: []].append(i) }
        let names = Dictionary(workouts().map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })
        return entries.enumerated().map { i, e in
            let all = fills[e.workoutID] ?? [i]
            return Slot(id: e.persistentModelID, index: i, entry: e, workoutID: e.workoutID,
                        name: names[e.workoutID] ?? "—", occurrence: (all.firstIndex(of: i) ?? 0) + 1, fills: all)
        }
    }
    /// True only when some workout fills more than one slot — every repeat affordance hangs off this.
    func routineHasRepeats() -> Bool {
        let ids = (activeRoutine()?.entries ?? []).map(\.workoutID)
        return Set(ids).count < ids.count
    }
    /// Reorder slots. The pointer follows its OWN slot by identity: matching on workout id would
    /// land on the first slot a repeated workout fills and silently move the place in the cycle.
    func moveSlot(from: Int, to: Int) {
        guard let r = activeRoutine() else { return }
        var es = r.orderedEntries
        guard es.indices.contains(from), es.indices.contains(to) else { return }
        let pointed = es.indices.contains(r.pointer) ? es[r.pointer] : nil
        let e = es.remove(at: from); es.insert(e, at: to)
        for (i, x) in es.enumerated() { x.order = i }
        if let pointed, let i = es.firstIndex(where: { $0 === pointed }) { r.pointer = i }
        try? context.save(); dataTick += 1
    }
    /// Drop one slot. The workout survives — even its last slot is only a place in the loop.
    /// The pointer keeps its slot; when that slot is the one removed it takes whatever now stands
    /// at the same index, or wraps to the first. A routine never empties: one slot is the floor.
    @discardableResult func removeSlot(_ e: RoutineEntry) -> Bool {
        guard let r = activeRoutine(), r.entries.count > 1 else { return false }
        let es = r.orderedEntries
        guard let i = es.firstIndex(where: { $0 === e }) else { return false }
        let pointed = es.indices.contains(r.pointer) ? es[r.pointer] : nil
        context.delete(e)
        let left = es.filter { $0 !== e }
        for (j, x) in left.enumerated() { x.order = j }
        if let pointed, pointed !== e, let j = left.firstIndex(where: { $0 === pointed }) { r.pointer = j }
        else { r.pointer = i < left.count ? i : 0 }
        try? context.save(); dataTick += 1
        return true
    }
    func togglePin(_ workoutID: UUID) {
        let id = workoutID.uuidString
        if let i = pinnedWorkoutIDs.firstIndex(of: id) { pinnedWorkoutIDs.remove(at: i) } else { pinnedWorkoutIDs.append(id) }
        UserDefaults.standard.set(pinnedWorkoutIDs, forKey: "pinned.workouts")
    }
    func isPinned(_ workoutID: UUID) -> Bool { pinnedWorkoutIDs.contains(workoutID.uuidString) }
    /// User-pinned workouts for the Calendar progression section. No pins → no section (absence-first).
    func pinnedWorkouts() -> [Workout] {
        pinnedWorkoutIDs.compactMap { id in UUID(uuidString: id).flatMap { workout($0) } }
    }
    func workouts() -> [Workout] { (try? context.fetch(FetchDescriptor<Workout>(sortBy: [SortDescriptor(\.name)]))) ?? [] }
    func workout(_ id: UUID?) -> Workout? { id.flatMap { id in workouts().first { $0.id == id } } }
    func activeRoutine() -> Routine? { ((try? context.fetch(FetchDescriptor<Routine>())) ?? []).first { $0.isActive } }
    func sessionCount(workoutID: UUID) -> Int { sessionCounts[workoutID] ?? 0 }
    func exercise(_ id: String) -> Exercise? { exercisesByID[id] }
    func result(_ s: Session) -> SessionResult? { analysis.results[s.id] }

    /// Next = the routine's pointer. Nil when there is no active routine.
    func nextWorkout() -> Workout? {
        guard let r = activeRoutine(), !r.entries.isEmpty else { return nil }
        let entries = r.orderedEntries
        return workout(entries[r.pointer % entries.count].workoutID)
    }
    func daysSinceLastSession() -> Int? { finishedSessions().last.map { Calendar.current.dateComponents([.day], from: $0.startedAt, to: today).day ?? 0 } }

    // MARK: routine-first home
    struct WorkoutStats { var last: Session?; var lastResult: SessionResult?; var lastVolume: Double; var bestVolume: Double; var lastIndex: Double?; var bestIndex: Double?; var lastDate: Date? }
    func workoutStats(_ workoutID: UUID) -> WorkoutStats {
        let rs = analysis.sessionsPerGroup[workoutID.uuidString] ?? []
        let last = rs.last
        return WorkoutStats(last: last.flatMap { sessionsByID[$0.sessionID] }, lastResult: last,
                            lastVolume: last?.volume ?? 0, bestVolume: rs.map(\.volume).max() ?? 0,
                            lastIndex: last?.index, bestIndex: rs.compactMap(\.index).max(), lastDate: last?.date)
    }
    /// Deleting a workout that sits in the loop has to repair the loop, not just drop the
    /// rows: close the gap left in `order`, and park the pointer. A pointer left aiming at a
    /// position that no longer exists makes nextWorkout() serve the wrong workout silently,
    /// and routineProgress() report a place in the cycle that cannot be reached.
    func deleteWorkout(_ w: Workout) {
        let r = activeRoutine()
        // SwiftData keeps deleted objects in the relationship until save, so the survivors
        // have to be identified by reference rather than re-read from r.entries.
        let doomed = (r?.entries ?? []).filter { $0.workoutID == w.id }
        for e in doomed { context.delete(e) }
        context.delete(w)
        if let r, !doomed.isEmpty {
            let left = r.orderedEntries.filter { e in !doomed.contains { $0 === e } }
            for (i, x) in left.enumerated() { x.order = i }
            // A part-finished cycle whose composition changed is no longer that cycle.
            // Matches what removing an entry already does.
            r.pointer = 0
        }
        try? context.save(); dataTick += 1
    }

    /// (sessions done in the current cycle, loop length, 1-based cycle number)
    func routineProgress() -> (done: Int, total: Int, cycle: Int)? {
        guard let r = activeRoutine(), !r.entries.isEmpty else { return nil }
        return (r.pointer, r.orderedEntries.count, r.cyclesCompleted + 1)
    }
    /// The most recently trained slot's e1RM index against the SAME SLOT one cycle ago —
    /// the login screen's proof the loop works. Where a workout fills one slot its two most
    /// recent sessions are a cycle apart, so the plain per-workout walk is that comparison;
    /// where it fills two, they are days apart, and only slot-to-slot is a cycle.
    func cycleProof() -> (pct: Double, workout: String)? {
        guard let r = activeRoutine() else { return nil }
        var best: (date: Date, pct: Double, name: String)?
        func consider(_ last: SessionResult, _ prev: SessionResult, _ name: String) {
            guard let li = last.index, let pi = prev.index, pi > 0 else { return }
            let row = (last.date, (li - pi) / pi * 100, name)
            if best == nil || row.0 > best!.date { best = row }
        }
        if routineHasRepeats() {
            let c = cycleChunks()
            var bySlot: [Int: [Session]] = [:]
            for chunk in c.past + [c.current] { for (i, s) in chunk.enumerated() { bySlot[i, default: []].append(s) } }
            for ss in bySlot.values where ss.count >= 2 {
                guard let last = analysis.results[ss[ss.count - 1].id], let prev = analysis.results[ss[ss.count - 2].id],
                      let name = workout(ss[ss.count - 1].workoutID)?.name else { continue }
                consider(last, prev, name)
            }
        } else {
            for id in r.orderedEntries.map(\.workoutID) {
                let rs = analysis.sessionsPerGroup[id.uuidString] ?? []
                guard rs.count >= 2, let last = rs.last, let prev = rs.dropLast().last,
                      let name = workout(id)?.name else { continue }
                consider(last, prev, name)
            }
        }
        return best.map { ($0.pct, $0.name) }
    }

    /// Chronological e1RM workout-index series across every loop workout — the hero chart.
    func routineIndexSeries() -> [Double] {
        guard let r = activeRoutine() else { return [] }
        let groups = Set(r.orderedEntries.map { $0.workoutID.uuidString })
        return analysis.ordered.filter { groups.contains($0.groupKey) }.compactMap(\.index)
    }

    static func input(_ s: Session) -> SessionInput {
        SessionInput(id: s.id, groupKey: s.groupKey, title: s.title, start: s.startedAt, end: s.endedAt,
                     exercises: s.orderedExercises.map { se in ExerciseInput(exerciseID: se.exerciseID, name: se.exerciseName,
                        sets: se.orderedSets.map { SetInput(kg: $0.kg, reps: $0.reps, isWarmup: $0.type == "warmup", done: $0.done) }) })
    }

    // MARK: session lifecycle
    /// Start from a template: rows prefilled with last session's same-numbered set (PRD §6.2 — no progression rule).
    @discardableResult func startSession(from w: Workout?) -> Session {
        if let d = draftSession() { context.delete(d) }
        let s = Session(title: w?.name ?? "Fresh workout", workoutID: w?.id, startedAt: .now, source: "app")
        s.isStarted = w != nil          // fresh drafts start on the Fresh page's slider
        if s.isStarted { liveSessionID = s.id }
        context.insert(s)
        for (i, slot) in (w?.orderedSlots ?? []).enumerated() { addExercise(to: s, exerciseID: slot.exerciseID, name: slot.exerciseName, sets: slot.sets, order: i) }
        if let w, let mult = UserDefaults.standard.object(forKey: "coach.deload.\(w.id.uuidString)") as? Double {
            for se in s.exercises { for st in se.sets { if let kg = st.kg { st.kg = (kg * mult / 2.5).rounded() * 2.5 } } }
            UserDefaults.standard.removeObject(forKey: "coach.deload.\(w.id.uuidString)")
        }
        if let w {
            for se in s.exercises {
                let key = "coach.weight.\(w.id.uuidString).\(se.exerciseID)"
                if let kg = UserDefaults.standard.object(forKey: key) as? Double {
                    for st in se.sets { st.kg = kg }
                    UserDefaults.standard.removeObject(forKey: key)
                    let markKey = "coach.mark.\(w.id.uuidString).\(se.exerciseID)"
                    if let mark = UserDefaults.standard.string(forKey: markKey) {   // first session after acceptance only
                        UserDefaults.standard.set(mark, forKey: "coach.smark.\(s.id.uuidString).\(se.exerciseID)")
                        UserDefaults.standard.removeObject(forKey: markKey)
                    }
                }
            }
        }
        try? context.save()
        if s.isStarted { startLiveActivity(s) }
        return s
    }
    func addExercise(to s: Session, exerciseID: String, name: String, sets: Int = 3, order: Int? = nil) {
        let se = SessionExercise(order: order ?? s.exercises.count, exerciseID: exerciseID, exerciseName: name)
        se.session = s; context.insert(se)
        let last = analysis.exerciseHistory[exerciseID]?.last
        let lastSets = lastSessionSets(exerciseID: exerciseID)
        for i in 0..<max(sets, 1) {
            let prev = i < lastSets.count ? lastSets[i] : (last.map { ($0.kg, $0.reps) })
            let log = SetLog(index: i, kg: prev?.0, reps: prev?.1, done: false); log.exercise = se; context.insert(log)
        }
        try? context.save()
    }
    /// Session V2 "+ set": append one set ghosted from the exercise's current last set.
    @discardableResult func addSet(to se: SessionExercise) -> Int {
        let last = se.orderedSets.last
        let log = SetLog(index: se.sets.count, kg: last?.kg, reps: last?.reps, done: false)
        log.exercise = se; context.insert(log); try? context.save()
        return log.index
    }
    func lastSessionSets(exerciseID: String) -> [(Double?, Int)] {
        guard let point = analysis.exerciseHistory[exerciseID]?.last, let last = sessionsByID[point.sessionID],
              let se = last.exercises.first(where: { $0.exerciseID == exerciseID }) else { return [] }
        return se.orderedSets.filter { $0.type != "warmup" }.map { ($0.kg, $0.reps ?? 0) }
    }
    /// Live PR check for the reward moment: does this set beat the all-time best e1RM?
    func isPR(exerciseID: String, kg: Double?, reps: Int) -> Bool {
        guard (analysis.exerciseHistory[exerciseID]?.count ?? 0) >= Engine.prMinPrior else { return false }
        return Engine.e1rm(kg: kg, reps: reps) > (analysis.bestE1RM[exerciseID] ?? 0)
    }

    // MARK: focus mode — the table and the one-set-at-a-time view are two views over one session
    /// The set focus is parked on, as a row id the table can scroll to. Switching views must not lose the place.
    var focusRowID: String?
    /// "<session>|<exercise>" keys that already had their reward moment — at most one per exercise per session.
    @ObservationIgnored var focusRewarded: Set<String> = []
    static func rowID(_ se: SessionExercise, _ st: SetLog) -> String { "row.\(se.order).\(st.index)" }

    /// The single write behind a checked set — table row and focus check both land here.
    /// Nothing typed accepts the prefilled (last-time) numbers; a skip mark clears.
    func check(_ set: SetLog, exerciseID: String, prev: (Double?, Int)?) {
        if set.kg == nil, let p = prev { set.kg = p.0 }
        if set.reps == nil, let p = prev { set.reps = p.1 }
        set.done = true
        set.skipped = false
        let localBest = (set.exercise?.sets ?? []).filter { $0.done && $0.index != set.index }
            .map { Engine.e1rm(kg: $0.kg, reps: $0.reps ?? 0) }.max() ?? 0
        let v = Engine.e1rm(kg: set.kg, reps: set.reps ?? 0)
        set.isPR = isPR(exerciseID: exerciseID, kg: set.kg, reps: set.reps ?? 0) && v > localBest
        try? context.save()
        updateLiveActivity(set.exercise?.session)
    }
    func uncheck(_ set: SetLog) {
        set.done = false; set.isPR = false
        try? context.save()
        updateLiveActivity(set.exercise?.session)
    }
    func setWeight(_ set: SetLog, _ kg: Double?) {
        set.kg = kg; try? context.save(); updateLiveActivity(set.exercise?.session)
    }
    func setReps(_ set: SetLog, _ reps: Int) {
        set.reps = max(0, reps); try? context.save(); updateLiveActivity(set.exercise?.session)
    }
    /// Left behind without a check. Cleared by `check`, so coming back and checking undoes it.
    func markSkipped(_ set: SetLog) {
        guard !set.done, !set.skipped else { return }
        set.skipped = true
        try? context.save()
    }

    /// Focus mode's reward test: a weight best for the exercise, or ≥1.5 % over its previous best e1RM.
    /// Returns what the overlay prints about the record it just broke.
    func newBest(exerciseID: String, kg: Double?, reps: Int) -> (e1rm: Double, prev: Double, date: Date?, pct: Double)? {
        let history = analysis.exerciseHistory[exerciseID] ?? []
        guard let top = history.max(by: { $0.e1rm < $1.e1rm }), top.e1rm > 0 else { return nil }
        let v = Engine.e1rm(kg: kg, reps: reps)
        let pct = (v - top.e1rm) / top.e1rm * 100
        let heaviest = history.compactMap(\.kg).max() ?? 0
        guard (kg ?? 0) > heaviest || pct >= 1.5 else { return nil }
        return (v, top.e1rm, top.date, pct)
    }
    /// Unchecked sets are dropped; exercises left with no sets are dropped with them.
    func finish(_ s: Session) {
        cancelRest()                                   // session end kills the timer, keeps the preset
        if liveSessionID == s.id { liveSessionID = nil; endLiveActivity() }
        s.endedAt = .now; s.isDraft = false
        for se in s.exercises { for st in se.sets where !st.done { context.delete(st) } }
        try? context.save()
        for se in s.exercises where se.sets.allSatisfy({ !$0.done }) { context.delete(se) }
        for (i, se) in s.orderedExercises.enumerated() { se.order = i }
        if let wid = s.workoutID, let r = activeRoutine() {
            let ids = r.orderedEntries.map(\.workoutID)
            // The slot just trained is the one the pointer stands on. Searching by workout would
            // land on the FIRST slot a repeated workout fills and rewind the loop; the search is
            // only the fallback for a session started out of turn.
            let onPointer = ids.indices.contains(r.pointer) && ids[r.pointer] == wid
            if let i = onPointer ? r.pointer : ids.firstIndex(of: wid) {
                if i + 1 >= ids.count { r.cyclesCompleted += 1 }
                r.pointer = (i + 1) % ids.count
            }
        }
        try? context.save()
        settling = true                                // the summary can open now; the engine catches up behind it
    }
    /// The expensive tail of finishing: Engine.run over every session, then the widget snapshot.
    /// Deliberately NOT part of `finish` — it used to hold the session screen on screen while it ran.
    func settleFinish() {
        reload()
        if !usedFallbackStore { pushWidgetSnapshot() }
        settling = false
    }
    /// Session Updates §4: save corrections to a finished session — full engine recompute downstream; pointer untouched.
    func saveSessionEdit(_ s: Session) {
        s.edited = true
        try? context.save()
        reload()                                   // Engine.run over everything: verdicts, PRs, graphs, index all re-derive
        if !usedFallbackStore { pushWidgetSnapshot() }
    }

    /// Remove a finished session from history: verdicts, PRs, graphs and the widget all re-derive.
    func deleteSession(_ s: Session) {
        if liveSessionID == s.id { liveSessionID = nil; endLiveActivity() }
        context.delete(s)
        try? context.save()
        reload()
        if !usedFallbackStore { pushWidgetSnapshot() }
    }

    func discard(_ s: Session) { cancelRest(); if liveSessionID == s.id { liveSessionID = nil; endLiveActivity() }; context.delete(s); try? context.save() }

    // MARK: Dynamic Island / lock screen (Live Activity)
    private func activityState(_ s: Session) -> WorkoutActivityAttributes.ContentState {
        var ex: String?, detail: String?
        var kg: String?, reps: String?, setNo: Int?, setTotal: Int?, isNext: Bool?
        if let (se, st) = nextUndoneSet(s) {
            ex = se.exerciseName.uppercased()
            let load = st.kg.map { "\(Fmt.kg($0)) KG" } ?? "BW"
            detail = "SET \(st.index + 1) · \(load)" + ((st.reps ?? 0) > 0 ? " × \(st.reps!)" : "")
            kg = st.kg.map(Fmt.kg) ?? "BW"
            reps = st.reps.map(String.init)
            setNo = st.index + 1; setTotal = se.sets.count
            let anyDone = s.exercises.contains { e in e.sets.contains { $0.done } }
            isNext = anyDone && !se.sets.contains { $0.done }
        }
        return .init(progress: Self.progress(s), startedAt: s.startedAt, nextExercise: ex, nextDetail: detail,
                     exercise: ex, kg: kg, reps: reps, setNo: setNo, setTotal: setTotal, isNextExercise: isNext, logged: false,
                     restEndsAt: restEndsAt)
    }
    private func nextUndoneSet(_ s: Session) -> (SessionExercise, SetLog)? {
        for se in s.orderedExercises {
            if let st = se.orderedSets.first(where: { !$0.done && $0.type != "warmup" }) { return (se, st) }
        }
        return nil
    }
    /// Lock-screen button: accept the prefilled numbers for the next set and advance the banner.
    func markNextSetFromIntent() {
        guard let s = liveSession(), let (se, st) = nextUndoneSet(s) else { return }
        st.done = true
        try? context.save()
        // §2 logged flash: solid-sage state with the just-logged numbers, then the next ready state.
        if s.id == liveSessionID, let a = liveActivity {
            var flash = activityState(s)
            flash.exercise = se.exerciseName.uppercased() + " · SET \(st.index + 1)"
            flash.kg = st.kg.map(Fmt.kg) ?? "BW"; flash.reps = st.reps.map(String.init)
            flash.logged = true; flash.isNextExercise = false
            let next = activityState(s)
            Task {
                await a.update(ActivityContent(state: flash, staleDate: nil))
                try? await Task.sleep(for: .milliseconds(850))
                await a.update(ActivityContent(state: next, staleDate: nil))
            }
        } else { updateLiveActivity(s) }
    }
    func startLiveActivity(_ s: Session) {
        endLiveActivity()
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        liveActivity = try? Activity.request(attributes: .init(workoutName: s.title), content: .init(state: activityState(s), staleDate: nil))
    }
    func updateLiveActivity(_ s: Session?) {
        guard let s, s.id == liveSessionID, let a = liveActivity else { return }
        let content = ActivityContent(state: activityState(s), staleDate: nil)
        Task { await a.update(content) }
    }
    func endLiveActivity() {
        for a in Activity<WorkoutActivityAttributes>.activities { Task { await a.end(nil, dismissalPolicy: .immediate) } }
        liveActivity = nil
    }
    /// On launch: re-attach to a surviving activity, or clean up strays.
    private func syncLiveActivity() {
        if let s = liveSession() {
            if let a = Activity<WorkoutActivityAttributes>.activities.first { liveActivity = a; updateLiveActivity(s) }
            else { startLiveActivity(s) }
        } else if !Activity<WorkoutActivityAttributes>.activities.isEmpty { endLiveActivity() }
    }

    // MARK: import
    func importHevy(text: String) {
        importReport = try? HevyImporter.importCSV(text, into: context)
        reload()
    }

    private func handleLaunchArguments() {
        #if DEBUG
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--hevy-csv"), i + 1 < args.count, let text = try? String(contentsOfFile: args[i + 1], encoding: .utf8) {
            importReport = try? HevyImporter.importCSV(text, into: context)
        }
        if args.contains("--rename-only"), let text = try? String(contentsOfFile: args[(args.firstIndex(of: "--rename-only")! + 1)], encoding: .utf8) {
            importReport = try? HevyImporter.importCSV(text, into: context)
        }
        if args.contains("--demo-pr"), let w = nextWorkout() {
            reload()
            let s = startSession(from: w)
            if let se = s.orderedExercises.first {
                let sets = se.orderedSets
                if sets.count > 0 { sets[0].done = true }
                if sets.count > 1 { sets[1].done = true; sets[1].isPR = true; sets[1].kg = (sets[1].kg ?? 0) + 2.5 }
                try? context.save()
            }
        }
        if args.contains("--build-demo-routine") { buildDemoLoop(["Legs", "Shoulders and biceps", "Back", "Push 1"], name: "Hevy split", pointer: 1) }
        // A loop with a workout in two slots, for the repeat frames — slot 4 is push's second turn.
        if args.contains("--demo-repeats") { buildDemoLoop(["Push 1", "Pull", "Legs", "Push 1", "Pull", "Shoulders"], name: "PPL × 2", pointer: 3) }
        if let i = args.firstIndex(of: "--today"), i + 1 < args.count {
            let f = ISO8601DateFormatter(); f.formatOptions = [.withFullDate]; today = f.date(from: args[i + 1]) ?? .now
        }
        #endif
    }

    /// Dev: a named loop over existing workouts, rebuilt from scratch so a relaunch is deterministic.
    /// A name repeated in `names` is a repeated SLOT, which is the point.
    private func buildDemoLoop(_ names: [String], name: String, pointer: Int) {
        reload()
        for r in ((try? context.fetch(FetchDescriptor<Routine>())) ?? []) { context.delete(r) }
        try? context.save()
        for n in names { if let w = workouts().first(where: { $0.name == n }) { addToRoutine(w) } }
        if let r = activeRoutine() { r.name = name; r.pointer = pointer; r.cyclesCompleted = 92; try? context.save() }
        reload()
    }
}


extension AppStore {
    /// Year View §5: consecutive Mon–Sun weeks with ≥1 committed session, back from the current week
    /// (the current week counts as soon as it has one; an empty current week doesn't break the run yet).
    func weekStreak() -> Int {
        var cal = Calendar(identifier: .iso8601); cal.firstWeekday = 2
        let weekOf = { (d: Date) -> Date in cal.dateInterval(of: .weekOfYear, for: d)!.start }
        let trained = Set(finishedSessions().map { weekOf($0.startedAt) })
        guard !trained.isEmpty else { return 0 }
        var week = weekOf(today); var streak = 0
        if !trained.contains(week) { week = cal.date(byAdding: .weekOfYear, value: -1, to: week)! }
        while trained.contains(week) { streak += 1; week = cal.date(byAdding: .weekOfYear, value: -1, to: week)! }
        return streak
    }

    /// Widget Handoff §4: snapshot on session commit; the widget re-renders from it and at midnight rollovers.
    /// Dev: log N designed cycles against a four workout routine, using the client's real workouts and
    /// their real last loads as the baseline, so cycle insights can be exercised on known-shaped data.
    /// Cycle stories: 0 baseline · 1 good progression · 2 weak · 3 one workout dips · 4 rebound.
    func seedDesignedCycles(_ count: Int) {
        let names = ["Legs", "Push 1", "Back", "Shoulders and biceps"]
        let picked = names.compactMap { n in workouts().first { $0.name.lowercased() == n.lowercased() } }
        guard picked.count == names.count else { coachLog("seed: missing workouts"); return }

        // baseline load per exercise = the client's own last top set, read before the wipe
        var base: [String: Double] = [:]
        for s in finishedSessions() {
            for ex in s.orderedExercises {
                if let top = ex.orderedSets.filter({ $0.done }).compactMap(\.kg).max() { base[ex.exerciseID] = top }
            }
        }
        // deterministic: the seeded cycles must be the only sessions in the loop
        for s in ((try? context.fetch(FetchDescriptor<Session>())) ?? []) { context.delete(s) }
        for r in ((try? context.fetch(FetchDescriptor<Routine>())) ?? []) { context.delete(r) }
        let routine = Routine(name: "Hevy split", isActive: true)
        for (i, w) in picked.enumerated() { routine.entries.append(RoutineEntry(order: i, workoutID: w.id)) }
        context.insert(routine)

        func factor(cycle: Int, workout: String) -> Double {
            switch cycle {
            case 0: return 1.00                                        // baseline
            case 1: return 1.05                                        // everything moves
            case 2: return 0.99                                        // weak cycle, nothing lands
            case 3: return workout == "Push 1" ? 0.90 : 1.04           // one workout dips, others climb
            default: return workout == "Push 1" ? 1.03 : 1.01          // the dip recovers
            }
        }
        let cal = Calendar.current
        var day = cal.date(byAdding: .day, value: -(count * 8), to: today) ?? today
        for c in 0..<count {
            for w in picked {
                let s = Session(title: w.name, workoutID: w.id, startedAt: day, source: "seed")
                s.isDraft = false
                s.endedAt = cal.date(byAdding: .minute, value: 47, to: day)
                for (i, slot) in w.orderedSlots.enumerated() {
                    let se = SessionExercise(order: i, exerciseID: slot.exerciseID, exerciseName: slot.exerciseName)
                    let load = (base[slot.exerciseID] ?? 40) * factor(cycle: c, workout: w.name)
                    let kg = (load / 2.5).rounded() * 2.5
                    // reps sit at the top of the range in strong cycles, mid in weak ones
                    let reps = max(slot.repLo, slot.repHi - 1)   // steady reps: the load tells the story
                    for setIdx in 0..<max(1, slot.sets) {
                        se.sets.append(SetLog(index: setIdx, kg: kg > 0 ? kg : nil,
                                              reps: max(1, reps - setIdx), done: true))
                    }
                    s.exercises.append(se)
                }
                context.insert(s)
                day = cal.date(byAdding: .day, value: 2, to: day) ?? day
            }
        }
        routine.pointer = 0
        routine.cyclesCompleted = count
        try? context.save()
        reload()
        coachLog("seeded \(count) designed cycles over \(picked.count) workouts")
    }

    /// Dev: write the exact payloads the coach would send, for offline model evaluation.
    func dumpCoachContexts() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        try? cycleInsightContext().data(using: .utf8)?.write(to: docs.appendingPathComponent("coach-ctx-cycle.json"))
        if let last = finishedSessions().last {
            try? sessionCoachContext(last).data(using: .utf8)?.write(to: docs.appendingPathComponent("coach-ctx-session.json"))
        }
        coachLog("dumped coach contexts")
    }

    func pushWidgetSnapshot() {
        guard let ud = UserDefaults(suiteName: WidgetStore.suite) else { return }
        let cal = Calendar.current
        let cutoff = cal.date(byAdding: .day, value: -371, to: today) ?? today   // 53 ISO weeks for the year strip
        var byDay: [Int: WidgetDay] = [:]
        for s in finishedSessions() where s.startedAt >= cutoff {
            let d = Int(cal.startOfDay(for: s.startedAt).timeIntervalSince1970 / 86_400)
            var e = byDay[d] ?? WidgetDay(epochDay: d, sessions: 0, minutes: 0, best: false)
            e.sessions += 1; e.minutes += s.durationMinutes
            if result(s)?.state == .best { e.best = true }
            byDay[d] = e
        }
        var nextName: String?; var lastDays: Int?
        if let next = nextWorkout() {
            nextName = next.name
            if let last = finishedSessions().last(where: { $0.workoutID == next.id }) {
                lastDays = cal.dateComponents([.day], from: cal.startOfDay(for: last.startedAt), to: cal.startOfDay(for: today)).day
            }
        }
        let snap = WidgetSnapshot(days: byDay.values.sorted { $0.epochDay < $1.epochDay },
                                  streak: weekStreak(), nextUp: nextName, nextUpLastDays: lastDays, updated: .now)
        if let data = try? JSONEncoder().encode(snap) { ud.set(data, forKey: WidgetStore.key) }
        WidgetCenter.shared.reloadTimelines(ofKind: "CalendarWidget")
    }
}
