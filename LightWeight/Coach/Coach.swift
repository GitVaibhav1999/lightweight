import Foundation
import SwiftData
import SwiftUI

/// Coach pipeline logger: prints AND appends to Documents/coach.log (retrievable from sim container and via devicectl).
func coachLog(_ m: String) {
    let f = DateFormatter(); f.dateFormat = "HH:mm:ss.SSS"
    let line = "\(f.string(from: .now)) \(m)\n"
    print("[coach] \(m)")
    let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("coach.log")
    if let h = try? FileHandle(forWritingTo: url) { h.seekToEndOfFile(); h.write(Data(line.utf8)); try? h.close() }
    else { try? line.write(to: url, atomically: true, encoding: .utf8) }
}

/// One piece of LLM reasoning, cached in the store. Rendering is always store-first (absence-first: no note → no UI).
@Model final class CoachNote {
    var kindRaw: String      // cycleInsight | stallAdvice | verdictWhy
    var key: String          // cycle-N | <workoutID>-<sessionCount> | <sessionID>
    var text: String
    var chipsJSON: String
    var modelName: String
    var createdAt: Date
    init(kind: String, key: String, text: String, chipsJSON: String = "[]", modelName: String = "fixture") {
        kindRaw = kind; self.key = key; self.text = text; self.chipsJSON = chipsJSON; self.modelName = modelName; createdAt = .now
    }
}

struct CoachChip: Codable, Hashable { var action: String; var label: String; var value: Double? }
struct CoachAction: Codable, Hashable { var type: String; var exercise: String; var from: String?; var to: String?; var label: String; var reason: String? }
/// Unified AI read (Insight Collapse handoff): headline row collapsed by default, body on expand, changes as rows.
struct CoachRead: Codable { var headline: String; var body: String; var actions: [CoachAction]? }
struct SessionCoachResponse: Codable { var verdict: String; var p1: String; var p2: String?; var p3: String?; var actions: [CoachAction]? }
struct CoachResponse: Codable { var text: String; var chips: [CoachChip]? }

struct SplitWorkoutCtx: Codable { var name: String; var exercises: [String]; var slots: [Int]? }   // "Squat · quads · 3x8-12"
struct CycleTimingCtx: Codable { var cycle: Int; var days: Int; var avgRestDays: String; var sessionsPerWeek: String }
struct CoachWorkoutCtx: Codable { var name: String; var sessions: Int; var stalled: Bool; var indexSeries: [String] }
struct CycleRow: Codable { var cycle: Int; var vol: String; var sets: Int; var up: Int; var stalled: Int; var prs: Int }
struct SetBrief: Codable { var kg: Double?; var reps: Int?; var done: Bool; var bw: Bool? }   // bw: no load, so the model never reads a missing kg as zero
struct ExBrief: Codable { var name: String; var sets: [SetBrief] }
/// Deterministic progression facts per exercise: the app decides plate math and readiness, the model only judges.
struct ProgressionBrief: Codable {
    var name: String
    var equipment: String?
    var repRange: String?        // the range the user set on the slot, e.g. "8-12"
    var topSets: [String]        // last sessions, oldest first: "75x10"
    var atTopOfRange: Int        // consecutive recent sessions whose top set met or beat repHi
    var ownStep: Double?         // the user's own usual jump on THIS lift, from their history
    var stepToUse: Double?       // ownStep, else a sane default for the equipment
    var recentTrend: String      // rising · flat · dip1 · declining
    var setCurves: [String]      // last sessions in full: "70: 15/15/15" — the fatigue curve, not just the top set
    var stepPct: Double?         // stepToUse as a share of current load; over ~6% the next rung is unreachable
    var belowFloor: Int          // consecutive sessions whose top set fell under repLo: drifting out of the range
    var sessionsAtLoad: Int      // sessions parked on the current load
    var vector: String           // ok · noStep · stepTooBig · outOfRange · stuck — can this lift even go up?
}
struct SessionBrief: Codable { var workout: String; var date: String; var vol: String; var verdict: String; var topSets: [String]; var rpe: Int?; var srpe: Int?; var prs: Int? }
struct CoachLandmarks: Codable { var bestCycleVol: String; var bestCycleNum: Int; var totalSessions: Int }
struct WorkoutSessionsCtx: Codable { var slot: Int; var name: String; var top: [String] }   // per-exercise top sets that cycle
struct CycleDetail: Codable { var cycle: Int; var workouts: [WorkoutSessionsCtx] }
/// One slot's own history across cycles, oldest first — so a heavy push¹ and a lighter push²
/// are never averaged into one claim about "push".
struct SlotSeriesCtx: Codable { var slot: Int; var workout: String; var occurrence: String; var vol: [String] }
struct CoachContext: Codable {
    var routineName: String; var cycle: Int; var next: String
    var workouts: [CoachWorkoutCtx]
    var cycles: [CycleRow]                 // every cycle, aggregate resolution
    var landmarks: CoachLandmarks?
    var recent: [SessionBrief]             // last ~2 cycles at session level
    var subject: [ExBrief]?                // full set detail for the narrated session
    var subjectPrev: [ExBrief]?            // previous session of the same workout
    var subjectHistory: [SessionBrief]?    // last 5 sessions of the narrated workout
    var window: [SessionBrief]?            // session-coach: last min(30, all) sessions across every workout
    var thisRPE: String?                   // the user's feel tap for this session
    /// Effort and recovery for this session, and how they read together. Effort rises with
    /// fatigue AND with genuine intensity, so it cannot separate the two on its own.
    var thisEffort: Int?                   // 0-10 Borg CR-10
    var thisRecovery: Int?                 // 0-10 perceived recovery before the session
    var loadState: String?                 // productive · underRecovered · stepTooBig · underStimulated
    var subjectVerdicts: [String: String]? // per-exercise verdicts of the narrated session
    var progression: [ProgressionBrief]?   // rep range, the user's own step size, and dip vs decline
    var mixDiffs: [String]?                // engine-computed workout-mix changes over the window, with volumes
    var split: [SplitWorkoutCtx]?          // the whole routine: each workout with its exercises + targets
    var timing: [CycleTimingCtx]?          // per cycle: days to complete, avg rest between sessions, sessions/week
    var catalog: [String: [String]]?       // bodyPart -> exercises available to ADD (not in the split)
    var history: [CycleDetail]?            // EVERY cycle: each workout's per-exercise top sets, by slot
    var slots: [SlotSeriesCtx]?            // only where a workout fills more than one slot
}

protocol CoachClient {
    func generateRead(kind: String, context: String, hint: String) async -> CoachRead?
}

/// Deterministic client for tests/demo — same register as the design reference.
struct FixtureCoachClient: CoachClient {
    func generateRead(kind: String, context: String, hint: String) async -> CoachRead? {
        if CommandLine.arguments.contains("--coach-fail-once"), !UserDefaults.standard.bool(forKey: "coach.fixture.didFail") {
            UserDefaults.standard.set(true, forKey: "coach.fixture.didFail")
            return nil                                       // suite drives the error row + tap-to-retry path
        }
        switch kind {
        case "cycleInsight":
            return CoachRead(
                headline: "Index climbed on the *same* set count",
                body: "The block is working where it counts: more work from the sets you already do, a density gain. Pull is the weak point, flat for three cycles while everything else moved.",
                actions: [CoachAction(type: "weight", exercise: "Bent Over Row (Barbell)", from: "70", to: "72.5", label: "row 70 → 72.5", reason: "top of rep range three sessions running"),
                          CoachAction(type: "repRange", exercise: "Lat Pulldown (Cable)", from: "8–12", to: "6–10", label: "pulldown 8–12 → 6–10", reason: "reps drifting past the growth zone")])
        default:
            return CoachRead(
                headline: "*Held* where it counted",
                body: "You called it about right, and the log agrees: the sets you finished sat level with your previous session of this workout. Steady volume on the same set count.",
                actions: [CoachAction(type: "weight", exercise: "Bench Press (Barbell)", from: "60", to: "62.5", label: "bench 60 → 62.5", reason: "two clean sessions at the top of the range"),
                          CoachAction(type: "swap", exercise: "Triceps Pushdown", from: nil, to: nil, label: "swap pushdown variation", reason: "stalled while everything else moved")])
        }
    }
}

/// Streaming side-channel: coachGenerate arms this; LiveCoachClient feeds it the body-so-far as tokens arrive (§5).
enum CoachStreamHub {
    nonisolated(unsafe) static var onToken: ((String) -> Void)?
    /// Best-effort prose extraction from the accumulating raw JSON: the "body" string value, unescaped.
    static func streamedBody(from raw: String) -> String? {
        guard let k = raw.range(of: "\"body\"") else { return nil }
        guard let q = raw.range(of: "\"", range: raw.index(after: k.upperBound)..<raw.endIndex) else { return nil }
        var out = ""; var i = raw.index(after: q.lowerBound); var esc = false
        while i < raw.endIndex {
            let c = raw[i]
            if esc { out.append(c == "n" ? "\n" : c); esc = false }
            else if c == "\\" { esc = true }
            else if c == "\"" { break }
            else { out.append(c) }
            i = raw.index(after: i)
        }
        return out
    }
}

struct LiveCoachClient: CoachClient {
    func generateRead(kind: String, context: String, hint: String) async -> CoachRead? {
        let persona = kind == "sessionCoach"
            ? "a seasoned certified strength coach debriefing a client right after a session"
            : "a seasoned certified strength coach reviewing the client's closed training cycle"
        let system = """
        You are \(persona) inside LIGHTWEIGHT, a personal strength-training app. The client's goal is HYPERTROPHY. \
        Interpret, don't recite: what worked, what is going wrong, which area is lacking. Grounded in DATA only; \
        cite at most 3 figures and only figures that appear verbatim in DATA; put other comparisons in plain words. \
        Never use em dashes or hyphens as punctuation. Statements, not cheerleading. \
        Output fields: headline = one line, max 60 characters, wrap exactly ONE signal word in *asterisks*. \
        body = max 320 characters of prose; NEVER mention the suggested changes in body, they render separately. \
        actions = suggested changes, ONLY when the data shows a load-increase opportunity, an intensity increase, or a plateau or decline; \
        each with type (weight, reorder, sets, swap, repRange, addExercise, step, loadType), exercise, from, to, a short label like "row 70 -> 72.5", and a reason under 60 characters. \
        When DATA carries split[], timing[] and catalog[]: judge whether rest and training frequency helped or hurt the numbers, \
        and whether each workout actually covers what its name promises; call out a lacking muscle or movement. \
        addExercise: exercise = an exact catalog[] name, from = the workout to add it to, to = set count as a string. \
        Suggest an addition ONLY when a gap has persisted for multiple cycles, never routinely; the client's first goal is CONSISTENCY, prefer keeping the routine stable. \
        Omit actions entirely when nothing is warranted. \
        Respond ONLY with JSON: {"headline": "...", "body": "...", "actions": [...]} \
        SCOPE: for a session read, judge the SUBJECT session against subjectPrev, exercise by exercise; \
        workouts[], cycles[] and mixDiffs[] are background only, never the topic. \
        Even so, cite at most three figures in total across headline and body; name movements in words rather than listing every set. \
        A set with no kg is bodyweight: write it as BW or as reps alone, never as 0 kg. \
        In the headline surround exactly one meaningful word with * characters; never mark a filler word such as progress or consistency. \
        Output the JSON object and nothing else: no code fence, no preamble, no thinking, no trailing prose. \
        PROGRESSION: progression[] carries the facts; do not do plate math yourself. \
        Propose a weight action only where atTopOfRange is 2 or more, meaning the client has held the top of \
        their own rep range for at least two sessions; the new load is topSets last weight plus stepToUse, exactly. \
        Never invent an increment and never suggest one where stepToUse is null: those lifts progress by reps. \
        One lower session is fatigue, not a trend. Where recentTrend is dip1, say so and change nothing; \
        only recentTrend declining, two sessions or more, justifies calling something a regression or reworking it. \
        VECTOR: progression[].vector says whether a lift can progress at all, and it outranks a weight bump. \
        outOfRange: reps have fallen under the client's own floor twice; the load ran ahead of the prescription, \
        so hold the weight and rebuild reps, or move repRange deliberately. Never call this climbing. \
        stepTooBig: the next rung is over six percent of the working load, unreachable on an isolation; propose \
        step with a smaller increment. noStep: bodyweight at the top of its range with nowhere to go; propose \
        repRange or loadType weighted. stuck: parked at a load without earning the top of the range; look at the \
        set curve before touching load. Where a lift set a record in the same session, bank that first, then make \
        the trade off; never open by correcting a session the client just won. \
        setCurves give every set, not just the top one: reps holding across sets means room to load, reps \
        collapsing across sets means the load is already at the limit. \
        SLOTS: the routine is an ordered list of slots and one workout can fill more than one, so a cycle \
        can hold two sessions of the same workout on different days. history[].workouts carry a slot number: \
        read a cycle against the one before it SLOT BY SLOT, slot 4 against slot 4, and never average a \
        workout's two turns into one claim. Where slots[] is present it gives each slot its own volume \
        series across cycles, oldest first; say which turn you mean, such as the second push of the cycle.
        """
        guard let raw = await complete(system: system, user: "DATA: \(context)\nTASK: \(hint)", maxTokens: 9000) else { return nil }
        if let r = try? JSONDecoder().decode(CoachRead.self, from: Data(raw.utf8)) { return r }
        // some models fence the object or add a preamble; take the first {...} block
        if let lo = raw.firstIndex(of: "{"), let hi = raw.lastIndex(of: "}"), lo < hi,
           let r = try? JSONDecoder().decode(CoachRead.self, from: Data(raw[lo...hi].utf8)) { return r }
        note("unparseable coach JSON"); return nil
    }
    private func note(_ why: String) { coachLog("FAIL: \(why)"); UserDefaults.standard.set(why, forKey: "coach.lastError") }
    private func complete(system: String, user: String, maxTokens: Int = 4000) async -> String? {
        guard let key = Bundle.main.object(forInfoDictionaryKey: "COACH_API_KEY") as? String, !key.isEmpty else { note("no API key in build"); return nil }
        let day = { let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f.string(from: .now) }()
        let capKey = "coach.calls.\(day)"; let used = UserDefaults.standard.integer(forKey: capKey)
        // daily call cap removed for now (was: guard used < 20)
        UserDefaults.standard.set(used + 1, forKey: capKey)
        let body: [String: Any] = ["model": "z-ai/glm-5.3-flash-20260826", "max_tokens": maxTokens,
            "reasoning": ["effort": "low"],   // medium burned the whole budget on thinking and returned empty
            "messages": [["role": "system", "content": system], ["role": "user", "content": user]]]
        var req = URLRequest(url: URL(string: "https://openrouter.ai/api/v1/chat/completions")!)
        req.httpMethod = "POST"
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 30; cfg.timeoutIntervalForResource = 150
        let session = URLSession(configuration: cfg)
        let streaming = CoachStreamHub.onToken != nil
        if streaming {   // re-encode with stream flag
            var b = body; b["stream"] = true
            req.httpBody = try? JSONSerialization.data(withJSONObject: b)
        }
        coachLog("request -> maxTokens \(maxTokens) · body \(req.httpBody?.count ?? 0)B · stream=\(streaming)")
        let t0 = Date()
        let raw: String
        if streaming {
            do {
                let (bytes, resp) = try await session.bytes(for: req)
                let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
                guard code == 200 else { note("HTTP \(code)"); return nil }
                var acc = ""
                for try await line in bytes.lines {
                    guard line.hasPrefix("data: ") else { continue }
                    let payload = String(line.dropFirst(6))
                    if payload == "[DONE]" { break }
                    guard let obj = try? JSONSerialization.jsonObject(with: Data(payload.utf8)) as? [String: Any],
                          let delta = ((obj["choices"] as? [[String: Any]])?.first?["delta"] as? [String: Any]),
                          let tok = delta["content"] as? String, !tok.isEmpty else { continue }
                    acc += tok
                    if let body = CoachStreamHub.streamedBody(from: acc) { CoachStreamHub.onToken?(body) }
                }
                coachLog("stream done in \(String(format: "%.1f", Date().timeIntervalSince(t0)))s · \(acc.count) chars")
                raw = acc
            } catch { note("network: \(error.localizedDescription)"); return nil }
        } else {
            let out: (Data, URLResponse)
            do { out = try await session.data(for: req) } catch { note("network: \(error.localizedDescription)"); return nil }
            coachLog("response in \(String(format: "%.1f", Date().timeIntervalSince(t0)))s · \(out.0.count)B")
            let code = (out.1 as? HTTPURLResponse)?.statusCode ?? 0
            guard code == 200 else { note("HTTP \(code)"); return nil }
            guard let root = try? JSONSerialization.jsonObject(with: out.0) as? [String: Any],
                  let choices = root["choices"] as? [[String: Any]],
                  let msg = choices.first?["message"] as? [String: Any],
                  let r = (msg["content"] as? String) ?? (msg["content"] as? [[String: Any]])?.compactMap({ $0["text"] as? String }).joined() else {
                note("bad response shape"); return nil }
            raw = r
        }
        coachLog("content head: \(String(raw.prefix(110)).replacingOccurrences(of: "\n", with: " "))")
        let cleaned = raw.replacingOccurrences(of: "```json", with: "").replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("{") { return cleaned }
        if let a = cleaned.firstIndex(of: "{"), let b = cleaned.lastIndex(of: "}") { return String(cleaned[a...b]) }
        return cleaned
    }
}

// MARK: - Orchestration (engine computes → LLM narrates → store caches → UI reads)
extension AppStore {
    /// Hero caption shared by loading and resolved states: "FROM CYCLES N−1–N · K SESSIONS".
    func insightCaption() -> String {
        guard let r = activeRoutine(), r.cyclesCompleted > 0 else { return "" }
        let n = r.cyclesCompleted
        let k = cycleChunks().past.suffix(2).map(\.count).reduce(0, +)
        return n > 1 ? "FROM CYCLES \(n - 1)–\(n) · \(k) SESSIONS" : "FROM CYCLE 1 · \(k) SESSIONS"
    }
    func coachNote(kind: String, key: String) -> CoachNote? {
        (try? context.fetch(FetchDescriptor<CoachNote>(predicate: #Predicate { $0.kindRaw == kind && $0.key == key })))?.first
    }
    private func upsertCoach(kind: String, key: String, _ read: CoachRead, model: String) {
        var read = read
        for (dash, repl) in [(" — ", ": "), (" – ", ": "), ("—", ", "), ("–", ", ")] {
            read.headline = read.headline.replacingOccurrences(of: dash, with: repl)
            read.body = read.body.replacingOccurrences(of: dash, with: repl)
        }
        if let old = coachNote(kind: kind, key: key) { context.delete(old) }
        let text = (try? JSONEncoder().encode(read)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        context.insert(CoachNote(kind: kind, key: key, text: text, chipsJSON: "[]", modelName: model))
        try? context.save(); coachTick += 1
        coachLog("stored \(kind) \(key.prefix(8)) · \(text.count) chars")
    }
    // MARK: context v2 — all cycles at aggregate resolution, detail only for the subject
    /// Payload numbers are display-formatted; raw floats never reach the model.
    static func fmtVol(_ v: Double) -> String { let f = NumberFormatter(); f.numberStyle = .decimal; f.maximumFractionDigits = 0; return f.string(from: NSNumber(value: v)) ?? "0" }
    static func fmtIdx(_ v: Double) -> String { String(format: "%.2f", v) }
    func sessionVolume(_ s: Session) -> Double {
        s.exercises.flatMap(\.sets).filter { $0.done && $0.type != "warmup" }
            .reduce(0) { $0 + (($1.kg ?? 0) * Double($1.reps ?? 0)) }
    }
    func loopSessions() -> [Session] {
        guard let r = activeRoutine() else { return [] }
        let ids = Set(r.orderedEntries.map(\.workoutID))
        return finishedSessions().filter { s in s.workoutID.map { ids.contains($0) } ?? false }
    }
    private func verdictString(_ s: Session) -> String {
        analysis.results[s.id].map { String(describing: $0.state) } ?? "—"
    }
    private func topSetStrings(_ s: Session) -> [String] {
        s.orderedExercises.compactMap { se in
            se.orderedSets.filter { $0.done && $0.type != "warmup" }
                .max { Engine.e1rm(kg: $0.kg, reps: $0.reps ?? 0) < Engine.e1rm(kg: $1.kg, reps: $1.reps ?? 0) }
                .map { "\(se.exerciseName) \(Fmt.kg($0.kg ?? 0))×\($0.reps ?? 0)" }
        }
    }
    func sessionBrief(_ s: Session) -> SessionBrief {
        SessionBrief(workout: s.title, date: Fmt.date(s.startedAt, "d MMM"), vol: Self.fmtVol(sessionVolume(s)),
                     verdict: verdictString(s), topSets: topSetStrings(s), rpe: s.rpe,
                     srpe: s.srpe, prs: s.prs)
    }
    /// Per-exercise progression facts for the subject session: rep range, the user's own step size, and
    /// whether a dip is one bad day or a real decline. Computed here so the model never guesses plate math.
    func progressionBriefs(_ s: Session) -> [ProgressionBrief] {
        let slots = s.workoutID.flatMap { workout($0)?.orderedSlots } ?? []
        var byExercise: [String: [(Date, Double?, Int)]] = [:]
        for past in finishedSessions() where past.startedAt <= s.startedAt {
            for ex in past.orderedExercises {
                guard let top = ex.orderedSets.filter({ $0.done && $0.type != "warmup" })
                    .max(by: { Engine.e1rm(kg: $0.kg, reps: $0.reps ?? 0) < Engine.e1rm(kg: $1.kg, reps: $1.reps ?? 0) })
                else { continue }
                byExercise[ex.exerciseID, default: []].append((past.startedAt, top.kg, top.reps ?? 0))
            }
        }
        return s.orderedExercises.map { se in
            let hist = Array((byExercise[se.exerciseID] ?? []).sorted { $0.0 < $1.0 }.suffix(8))
            let slot = slots.first { $0.exerciseID == se.exerciseID }
            let equip = exercise(se.exerciseID)?.equipment
            let loads = hist.compactMap { $0.1 }
            // the user's own jump: the median positive step they have actually taken on this lift
            var steps: [Double] = []
            for (a, b) in zip(loads, loads.dropFirst()) where b > a { steps.append(((b - a) * 100).rounded() / 100) }
            // snapped: the median of raw differences is an artifact of how the data was logged
            let own = Self.snapStep(steps.sorted().dropFirst(steps.count / 2).first, equip)
            var atTop = 0
            if let hi = slot?.repHi {
                for h in hist.reversed() { if h.2 >= hi { atTop += 1 } else { break } }
            }
            var trend = "flat"
            if loads.count >= 2 {
                let e = hist.map { Engine.e1rm(kg: $0.1, reps: $0.2) }
                if let last = e.last, e.count >= 2 {
                    let prev = e[e.count - 2]
                    if last > prev { trend = "rising" }
                    else if last < prev { trend = (e.count >= 3 && prev < e[e.count - 3]) ? "declining" : "dip1" }
                }
            }
            // the full set curve of recent sessions: three flat sets and a collapsing three read alike on a top set
            var curves: [String] = []
            for past in finishedSessions().suffix(40) where past.startedAt <= s.startedAt {
                guard let ex = past.orderedExercises.first(where: { $0.exerciseID == se.exerciseID }) else { continue }
                let work = ex.orderedSets.filter { $0.done && $0.type != "warmup" }
                guard let first = work.first else { continue }
                let load = first.kg.map { Fmt.kg($0) } ?? "BW"
                curves.append("\(load): " + work.map { "\($0.reps ?? 0)" }.joined(separator: "/"))
            }
            let step = own ?? Self.defaultStep(equip)
            let current = loads.last
            let pct = (step != nil && (current ?? 0) > 0) ? (step! / current!) : nil
            var below = 0
            if let lo = slot?.repLo { for h in hist.reversed() { if h.2 < lo { below += 1 } else { break } } }
            var atLoad = 0
            if let cur = current { for h in hist.reversed() { if h.1 == cur { atLoad += 1 } else { break } } }
            var vector = "ok"
            if below >= 2 { vector = "outOfRange" }                            // reps have left the prescription
            else if step == nil && atTop >= 3 { vector = "noStep" }            // bodyweight with nowhere to go
            else if let p = pct, p > 0.06 { vector = "stepTooBig" }            // next rung is an unreachable jump
            else if atLoad >= 5 && atTop < 2 { vector = "stuck" }              // parked, and not earning the rung
            return ProgressionBrief(
                name: se.exerciseName, equipment: equip,
                repRange: slot.map { "\($0.repLo)-\($0.repHi)" },
                topSets: hist.suffix(6).map { h in h.1.map { "\(Fmt.kg($0))x\(h.2)" } ?? "BWx\(h.2)" },
                atTopOfRange: atTop, ownStep: own,
                stepToUse: step, recentTrend: trend,
                setCurves: Array(curves.suffix(4)),
                stepPct: pct.map { ($0 * 1000).rounded() / 1000 },
                belowFloor: below, sessionsAtLoad: atLoad, vector: vector)
        }
    }
    /// The jumps the equipment can actually make. A step the gym cannot produce is not
    /// advice, however good the arithmetic behind it — you cannot add 1.25 kg to a dumbbell.
    /// Empty means the load is not adjustable at all and progress has to come from reps.
    static func stepLadder(_ equipment: String?) -> [Double] {
        switch (equipment ?? "").lowercased() {
        case let e where e.contains("body weight") || e.contains("assisted"): return []
        case let e where e.contains("band"): return []
        case let e where e.contains("dumbbell"): return [2, 2.5, 4, 5]          // per bell, as racks are built
        case let e where e.contains("barbell") || e.contains("smith"): return [2.5, 5, 10, 20]   // pairs of plates
        case let e where e.contains("cable") || e.contains("machine") || e.contains("leverage"): return [2.5, 5, 10]
        default: return [2.5, 5, 10]
        }
    }

    /// Nearest rung the equipment actually has. Imported history carries pound-denominated
    /// jumps (2.5 lb = 1.13 kg), so a median of raw load differences lands on numbers that
    /// describe the data and exist nowhere in the gym.
    static func snapStep(_ v: Double?, _ equipment: String?) -> Double? {
        guard let v, v > 0 else { return nil }
        let rungs = stepLadder(equipment)
        guard !rungs.isEmpty else { return nil }
        return rungs.min { abs($0 - v) < abs($1 - v) }
    }

    /// Only used when the user has no history of their own on that lift.
    private static func defaultStep(_ equipment: String?) -> Double? {
        switch (equipment ?? "").lowercased() {
        case let e where e.contains("body weight") || e.contains("assisted"): return nil   // progress by reps
        case let e where e.contains("dumbbell"): return 2
        case let e where e.contains("cable") || e.contains("band"): return 2.5
        case let e where e.contains("barbell") || e.contains("smith"): return 5
        case let e where e.contains("machine") || e.contains("leverage"): return 5
        default: return 2.5
        }
    }

    private func exBriefs(_ s: Session) -> [ExBrief] {
        s.orderedExercises.map { se in
            ExBrief(name: se.exerciseName, sets: se.orderedSets.filter { $0.type != "warmup" }
                .map { SetBrief(kg: $0.kg, reps: $0.reps, done: $0.done, bw: $0.kg == nil ? true : nil) })
        }
    }
    /// Chunk finished loop sessions from the end into cycles of loop length; current partial = pointer position.
    func cycleChunks() -> (past: [[Session]], current: [Session]) {
        guard let p = routineProgress(), p.total > 0, let r = activeRoutine() else { return ([], []) }
        // Cycles exist only since the routine was built: pointer + cyclesCompleted track them.
        // Imported pre-routine history stays out of cycle stats (it still feeds charts and per-workout views).
        let tracked = r.cyclesCompleted * p.total + p.done
        var all = Array(loopSessions().suffix(tracked))
        let current = p.done > 0 ? Array(all.suffix(p.done)) : []
        all = Array(all.dropLast(p.done))
        var past: [[Session]] = []
        while all.count >= p.total { past.insert(Array(all.suffix(p.total)), at: 0); all = Array(all.dropLast(p.total)) }
        return (past, current)
    }
    func cycleRows() -> [CycleRow] {
        guard let r = activeRoutine() else { return [] }
        let chunks = cycleChunks().past
        return chunks.enumerated().map { i, chunk in
            let results = chunk.compactMap { analysis.results[$0.id] }
            return CycleRow(cycle: r.cyclesCompleted - (chunks.count - 1 - i),
                            vol: Self.fmtVol(chunk.reduce(0) { $0 + sessionVolume($1) }),
                            sets: chunk.flatMap(\.exercises).flatMap(\.sets).filter(\.done).count,
                            up: results.map(\.upCount).reduce(0, +),
                            stalled: results.filter { String(describing: $0.state).lowercased().contains("stall") }.count,
                            prs: results.map { $0.prs.count }.reduce(0, +))
        }
    }
    /// Current-cycle volume for the hero (falls back to the just-closed cycle), and the best previous cycle.
    func cycleVolumes() -> (current: Double, prevBest: Double?, closed: Bool) {
        let c = cycleChunks()
        let closed = c.current.isEmpty
        let showing = closed ? (c.past.last ?? []) : c.current
        let prior = closed ? c.past.dropLast() : c.past[...]
        let best = prior.map { $0.reduce(0) { $0 + sessionVolume($1) } }.max()
        return (showing.reduce(0) { $0 + sessionVolume($1) }.rounded(), best?.rounded(), closed)
    }
    func coachContextJSON(subjectSession: Session? = nil, subjectWorkoutID: UUID? = nil) -> String {
        let r = activeRoutine()   // optional: sessions/subject must ground the coach even before a routine exists
        let ws = (r?.orderedEntries ?? []).compactMap { e -> CoachWorkoutCtx? in
            guard let w = workout(e.workoutID) else { return nil }
            let series = (analysis.sessionsPerGroup[w.id.uuidString] ?? []).compactMap(\.index).suffix(6).map { Self.fmtIdx($0) }
            let stalled = String(describing: workoutStats(w.id).lastResult).lowercased().contains("stall")
            return CoachWorkoutCtx(name: w.name, sessions: sessionCount(workoutID: w.id), stalled: stalled, indexSeries: Array(series))
        }
        let next = r.flatMap { rr in rr.orderedEntries.indices.contains(rr.pointer) ? workout(rr.orderedEntries[rr.pointer].workoutID)?.name : nil } ?? "—"
        let rows = cycleRows()
        let bestRow = rows.max { (Double($0.vol.replacingOccurrences(of: ",", with: "")) ?? 0) < (Double($1.vol.replacingOccurrences(of: ",", with: "")) ?? 0) }
        let loop = loopSessions()
        var ctx = CoachContext(routineName: r?.name ?? "—", cycle: r?.cyclesCompleted ?? 0, next: next, workouts: ws,
            cycles: rows,
            landmarks: bestRow.map { CoachLandmarks(bestCycleVol: $0.vol, bestCycleNum: $0.cycle, totalSessions: loop.count) },
            recent: (loop.isEmpty ? Array(finishedSessions().suffix(8)) : Array(loop.suffix(max((r?.orderedEntries.count ?? 4) * 2, 8)))).map { sessionBrief($0) },
            subject: nil, subjectPrev: nil, subjectHistory: nil)
        if let s = subjectSession {
            ctx.subject = exBriefs(s)
            ctx.progression = progressionBriefs(s)
            ctx.subjectPrev = finishedSessions().last { $0.groupKey == s.groupKey && $0.id != s.id }.map { exBriefs($0) }
        }
        if let wid = subjectWorkoutID {
            ctx.subjectHistory = (analysis.sessionsPerGroup[wid.uuidString] ?? []).suffix(5)
                .compactMap { sessionsByIDPublic($0.sessionID) }.map { sessionBrief($0) }
        }
        return (try? JSONEncoder().encode(ctx)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
    }
    /// Workout-mix changes across consecutive sessions of one workout in the window, with before/after volume.
    func mixDiffs(groupKey: String, window: Int = 30) -> [String] {
        let sessions = finishedSessions().filter { $0.groupKey == groupKey }.suffix(window)
        var out: [String] = []
        for (a, b) in zip(sessions, sessions.dropFirst()) {
            let ea = a.orderedExercises.map(\.exerciseName), eb = b.orderedExercises.map(\.exerciseName)
            guard ea != eb else { continue }
            let added = Set(eb).subtracting(ea), removed = Set(ea).subtracting(eb)
            var what: [String] = []
            if !added.isEmpty { what.append("added " + added.joined(separator: ", ")) }
            if !removed.isEmpty { what.append("removed " + removed.joined(separator: ", ")) }
            if what.isEmpty { what.append("reordered") }
            out.append("\(Fmt.date(b.startedAt, "d MMM")): \(what.joined(separator: "; ")); volume \(Self.fmtVol(sessionVolume(a))) → \(Self.fmtVol(sessionVolume(b)))")
        }
        for applied in UserDefaults.standard.stringArray(forKey: "coach.applied.\(groupKey)") ?? [] { out.append(applied) }
        return Array(out.suffix(6))
    }
    func cycleInsightContext() -> String {
        var json = coachContextJSON()
        guard var ctx = try? JSONDecoder().decode(CoachContext.self, from: Data(json.utf8)), let r = activeRoutine() else { return json }
        let chunks = Array(cycleChunks().past.suffix(15))
        // Sessions sit in slot order inside a cycle, so the slot number is the position — and it is
        // what makes cycle-over-cycle a like-for-like read once one workout fills two slots.
        ctx.history = chunks.enumerated().map { i, chunk in
            CycleDetail(cycle: r.cyclesCompleted - (chunks.count - 1 - i),
                        workouts: chunk.enumerated().map { j, s in WorkoutSessionsCtx(slot: j + 1, name: s.title, top: topSetStrings(s)) })
        }
        let slots = routineSlots()
        if routineHasRepeats() {
            ctx.slots = slots.map { s in
                SlotSeriesCtx(slot: s.index + 1, workout: s.name,
                              occurrence: "\(s.occurrence) of \(s.fills.count)",
                              vol: chunks.map { chunk in
                                  chunk.indices.contains(s.index) ? Self.fmtVol(sessionVolume(chunk[s.index])) : "—" })
            }
        }
        ctx.recent = []
        // Split, timing and catalog (coach upgrade 2026-09-04): judge rest/frequency and split adequacy; enable addExercise.
        let lib = (try? context.fetch(FetchDescriptor<Exercise>())) ?? []
        let byID = Dictionary(lib.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var inSplit = Set<String>()
        var listed = Set<UUID>()
        // Each workout once, with the slots it fills: the split is what the workouts contain,
        // not how many turns they take.
        ctx.split = slots.compactMap { slot in
            guard listed.insert(slot.workoutID).inserted, let w = workout(slot.workoutID) else { return nil }
            return SplitWorkoutCtx(name: w.name, exercises: w.orderedSlots.map { s in
                inSplit.insert(s.exerciseName.lowercased())
                let t = byID[s.exerciseID]?.target ?? "?"
                return "\(s.exerciseName) · \(t) · \(s.sets)x\(s.repLo)-\(s.repHi)"
            }, slots: slot.repeated ? slot.fills.map { $0 + 1 } : nil)
        }
        let cal = Calendar.current
        ctx.timing = chunks.enumerated().compactMap { i, chunk in
            let dates = chunk.map { cal.startOfDay(for: $0.startedAt) }.sorted()
            guard let first = dates.first, let last = dates.last else { return nil }
            let days = (cal.dateComponents([.day], from: first, to: last).day ?? 0) + 1
            let rests = zip(dates, dates.dropFirst()).map { cal.dateComponents([.day], from: $0, to: $1).day ?? 0 }
            let avgRest = rests.isEmpty ? 0 : Double(rests.reduce(0, +)) / Double(rests.count)
            let spw = Double(chunk.count) / max(1, Double(days)) * 7
            return CycleTimingCtx(cycle: r.cyclesCompleted - (chunks.count - 1 - i), days: days,
                                  avgRestDays: String(format: "%.1f", avgRest), sessionsPerWeek: String(format: "%.1f", spw))
        }
        var cat: [String: [String]] = [:]
        for e in lib.sorted(by: { $0.name < $1.name }) where !inSplit.contains(e.name.lowercased()) {
            if cat[e.bodyPart, default: []].count < 5 { cat[e.bodyPart, default: []].append(e.name) }
        }
        ctx.catalog = cat
        json = (try? JSONEncoder().encode(ctx)).flatMap { String(data: $0, encoding: .utf8) } ?? json
        return json
    }
    func sessionCoachContext(_ s: Session) -> String {
        var json = coachContextJSON(subjectSession: s)
        guard var ctx = try? JSONDecoder().decode(CoachContext.self, from: Data(json.utf8)) else { return json }
        ctx.window = finishedSessions().suffix(15).map { sess in
            var b = sessionBrief(sess)
            if sess.groupKey != s.groupKey { b.topSets = [] }        // detail only where the read needs it
            return b
        }
        ctx.recent = []
        ctx.thisRPE = s.rpe.map { ["easy", "about right", "brutal"][max(0, min(2, $0 - 1))] }
        ctx.thisEffort = s.srpe
        ctx.thisRecovery = s.prs
        ctx.loadState = Self.loadState(srpe: s.srpe, prs: s.prs, verdict: verdictString(s))
        ctx.subjectVerdicts = analysis.results[s.id].map { r in r.exerciseVerdicts.mapValues { String(describing: $0) } }
        ctx.mixDiffs = mixDiffs(groupKey: s.groupKey)
        json = (try? JSONEncoder().encode(ctx)).flatMap { String(data: $0, encoding: .utf8) } ?? json
        return json
    }
    /// Claims (verdict/p1/p2) must cite payload-verbatim figures; p3 prescriptions are NEW numbers by design. ctx nil = trusted (fixture).
    func sessionCoach(_ s: Session) -> CoachRead? {
        coachNote(kind: "sessionCoach", key: s.id.uuidString)
            .flatMap { try? JSONDecoder().decode(CoachRead.self, from: Data($0.text.utf8)) }
    }
    func insightRead(_ key: String) -> CoachRead? {
        coachNote(kind: "cycleInsight", key: key)
            .flatMap { try? JSONDecoder().decode(CoachRead.self, from: Data($0.text.utf8)) }
    }
    /// What the pair reads as together. Effort rises with fatigue AND with genuine intensity,
    /// so it cannot separate a productive hard session from an under-recovered one on its own —
    /// recovery breaks that tie, and the verdict says whether the work actually landed.
    static func loadState(srpe: Int?, prs: Int?, verdict: String) -> String? {
        guard let effort = srpe, let recovery = prs else { return nil }
        let regressed = verdict.lowercased().contains("down") || verdict.lowercased().contains("stall")
        let hard = effort >= 7
        if hard && recovery <= 4 { return "underRecovered" }   // Laurent: 0-2 predicts a decrement
        if hard && regressed { return "stepTooBig" }           // recovered, still went backwards
        if hard { return "productive" }
        if effort <= 4 && recovery >= 6 && !regressed { return "underStimulated" }
        return "ok"
    }

    /// Store effort and recovery, then one-shot generate (cached forever per session).
    /// Both nil means a retry of a call that failed silently.
    func askCoach(session: Session, srpe: Int? = nil, prs: Int? = nil) {
        if let srpe { session.srpe = srpe }
        if let prs { session.prs = prs }
        if srpe != nil || prs != nil { try? context.save() }
        let key = session.id.uuidString
        coachLog("askCoach srpe=\(session.srpe.map(String.init) ?? "-") prs=\(session.prs.map(String.init) ?? "-") key=\(key.prefix(8)) noteExists=\(coachNote(kind: "sessionCoach", key: key) != nil) pending=\(coachPending.contains(key)) retries=\(UserDefaults.standard.integer(forKey: "coach.retry.\(key)")) live=\(coachClient is LiveCoachClient)")
        guard coachNote(kind: "sessionCoach", key: key) == nil, !coachPending.contains(key),
              UserDefaults.standard.integer(forKey: "coach.retry.\(key)") < 3 else { return }
        let ctx = sessionCoachContext(session); let live = coachClient is LiveCoachClient
        coachLog("context \(ctx.count) chars")
        coachPending.insert(key); coachFailed.remove(key)
        coachStatus[key] = "reading \(min(30, finishedSessions().count)) sessions…"
        if live { CoachStreamHub.onToken = { [weak self] text in Task { @MainActor in self?.coachStream[key] = text } } }
        Task { @MainActor in
            defer { coachPending.remove(key); coachStatus[key] = nil; coachStream[key] = nil; CoachStreamHub.onToken = nil }
            @MainActor func failed() {
                coachFailed.insert(key)
                coachFailReason[key] = UserDefaults.standard.string(forKey: "coach.lastError") ?? "unknown"
                UserDefaults.standard.set(UserDefaults.standard.integer(forKey: "coach.retry.\(key)") + 1, forKey: "coach.retry.\(key)")
            }
            guard let read = await coachClient.generateRead(kind: "sessionCoach", context: ctx,
                hint: "The session-end coach read for the subject session (subject vs subjectPrev, plus thisRPE).") else { failed(); return }
            coachStatus[key] = "writing…"
            guard let validated = readValidated(read, ctx: live ? ctx : nil) else { UserDefaults.standard.set("validation rejected a figure", forKey: "coach.lastError"); failed(); return }
            upsertCoach(kind: "sessionCoach", key: session.id.uuidString, validated, model: live ? "api" : "fixture")
        }
    }
    /// Apply rights: weight (next-session prefill override) and slot reorder. Workout resolved from the exercise name.
    /// addExercise: the coach edits the workout — appends a library exercise as a new slot (fills a persistent gap).
    private func applyAddExercise(_ a: CoachAction) -> Bool {
        let wName = a.from ?? ""
        guard let w = workouts().first(where: { $0.name.caseInsensitiveCompare(wName) == .orderedSame }),
              let e = ((try? context.fetch(FetchDescriptor<Exercise>())) ?? []).first(where: { $0.name.caseInsensitiveCompare(a.exercise) == .orderedSame }),
              !w.orderedSlots.contains(where: { $0.exerciseID == e.id }) else { return false }
        let s = WorkoutSlot(order: w.slots.count, exerciseID: e.id, exerciseName: e.name, sets: Int(a.to ?? "") ?? 3, repLo: 8, repHi: 12)
        s.workout = w; context.insert(s); try? context.save(); dataTick += 1
        var history = UserDefaults.standard.stringArray(forKey: "coach.applied.\(w.id.uuidString)") ?? []
        history.append("applied by coach on \(Fmt.date(.now, "d MMM")): \(a.label)")
        UserDefaults.standard.set(history, forKey: "coach.applied.\(w.id.uuidString)")
        return true
    }

    func applyCoachAction(_ a: CoachAction) -> Bool {
        if a.type == "addExercise" { return applyAddExercise(a) }
        guard ["weight", "reorder"].contains(a.type),
              let w = workouts().first(where: { wk in wk.orderedSlots.contains { $0.exerciseName == a.exercise } }) else { return false }
        let record = "applied by coach on \(Fmt.date(.now, "d MMM")): \(a.label)"
        var history = UserDefaults.standard.stringArray(forKey: "coach.applied.\(w.id.uuidString)") ?? []
        if a.type == "weight", let kg = Double(a.to ?? ""), let slot = w.orderedSlots.first(where: { $0.exerciseName == a.exercise }) {
            UserDefaults.standard.set(kg, forKey: "coach.weight.\(w.id.uuidString).\(slot.exerciseID)")
            UserDefaults.standard.set("\(a.to ?? "")|\(a.from ?? "")|\(a.reason ?? "")", forKey: "coach.mark.\(w.id.uuidString).\(slot.exerciseID)")
            history.append(record); UserDefaults.standard.set(history, forKey: "coach.applied.\(w.id.uuidString)")
            return true
        }
        if a.type == "reorder", let to = Int(a.to ?? ""), let slot = w.orderedSlots.first(where: { $0.exerciseName == a.exercise }) {
            var slots = w.orderedSlots
            slots.removeAll { $0 === slot }
            slots.insert(slot, at: max(0, min(slots.count, to - 1)))
            for (i, sl) in slots.enumerated() { sl.order = i }
            try? context.save(); dataTick += 1
            history.append(record); UserDefaults.standard.set(history, forKey: "coach.applied.\(w.id.uuidString)")
            return true
        }
        return false
    }
    func sessionsByIDPublic(_ id: UUID) -> Session? {
        (try? context.fetch(FetchDescriptor<Session>(predicate: #Predicate { $0.id == id })))?.first
    }
    /// Live responses fail closed: unknown chip actions dropped, any number not present in the payload rejects the note.
    /// Unified validation: claims (headline+body) must cite payload-verbatim figures; suggested-change numbers live in actions and are exempt.
    func readValidated(_ read: CoachRead, ctx: String?) -> CoachRead? {
        var r = read
        r.actions = read.actions?.filter { ["weight", "reorder", "sets", "swap", "repRange", "addExercise", "step", "loadType"].contains($0.type) }
        guard let ctx else { return r }
        let claims = read.headline + " " + read.body
        let plain = ctx.replacingOccurrences(of: ",", with: "")
        let nums = claims.components(separatedBy: CharacterSet(charactersIn: "0123456789.").inverted)
            .filter { $0.contains(where: \.isNumber) }.filter { $0.count >= 3 || $0.contains(".") }
        for n in nums where !plain.contains(n.trimmingCharacters(in: CharacterSet(charactersIn: "."))) { return nil }
        r.actions = r.actions.map { gateWeightActions($0, ctx: ctx) }
        return r
    }
    /// A weight bump is only legitimate where the client has held the top of their own rep range for two
    /// sessions, and only by their own step. Models that ignore that rule get their suggestion dropped here.
    private func gateWeightActions(_ actions: [CoachAction], ctx: String) -> [CoachAction] {
        struct Ctx: Decodable { var progression: [ProgressionBrief]? }
        guard let facts = (try? JSONDecoder().decode(Ctx.self, from: Data(ctx.utf8)))?.progression, !facts.isEmpty
        else { return actions }
        return actions.filter { a in
            // A proposed step has to be a rung the equipment has. The model reasons in
            // percentages, which is sound arithmetic and useless if the number cannot be loaded.
            if a.type == "step" {
                guard let p = facts.first(where: { $0.name == a.exercise }),
                      let want = Double(a.to ?? ""),
                      Self.stepLadder(p.equipment).contains(where: { abs($0 - want) < 0.01 })
                else { coachLog("dropped step for \(a.exercise): \(a.to ?? "?") is not a real increment"); return false }
                return true
            }
            guard a.type == "weight" else { return true }        // loadType, repRange and the rest pass through
            guard let p = facts.first(where: { $0.name == a.exercise }),
                  let lastTop = p.topSets.last?.split(separator: "x").first, let from = Double(lastTop),
                  let target = a.to, let want = Double(target.split(separator: "x").first.map(String.init) ?? target)
            else { coachLog("dropped weight action for \(a.exercise): no progression facts"); return false }
            if want < from {                                     // pulling the load back is right when reps left the range
                guard p.vector == "outOfRange" else {
                    coachLog("dropped weight cut for \(a.exercise): reps are inside the range"); return false
                }
                return true
            }
            guard p.atTopOfRange >= 2, let step = p.stepToUse, abs(want - (from + step)) < 0.01 else {
                coachLog("dropped weight rise for \(a.exercise): not earned by progression[]"); return false
            }
            return true
        }
    }
    private func coachGenerate(kind: String, key: String, hint: String, ctx: String? = nil) {
        guard coachNote(kind: kind, key: key) == nil, !coachPending.contains(key) else { coachLog("generate \(kind) \(key): cached or pending"); return }
        coachLog("generate \(kind) \(key) live=\(coachClient is LiveCoachClient)")
        let ctx = ctx ?? coachContextJSON(); let live = coachClient is LiveCoachClient
        coachPending.insert(key); coachFailed.remove(key)
        coachStatus[key] = "reading \(min(30, finishedSessions().count)) sessions…"
        Task { @MainActor in
            defer { coachPending.remove(key); coachStatus[key] = nil }
            guard var read = await coachClient.generateRead(kind: kind, context: ctx, hint: hint) else {
                coachFailed.insert(key)
                coachFailReason[key] = UserDefaults.standard.string(forKey: "coach.lastError") ?? "unknown"
                UserDefaults.standard.set(UserDefaults.standard.integer(forKey: "coach.retry.\(key)") + 1, forKey: "coach.retry.\(key)"); return
            }
            coachStatus[key] = "writing…"
            guard let v = readValidated(read, ctx: live ? ctx : nil) else {
                UserDefaults.standard.set(UserDefaults.standard.integer(forKey: "coach.retry.\(key)") + 1, forKey: "coach.retry.\(key)"); return
            }
            read = v
            upsertCoach(kind: kind, key: key, read, model: live ? "api" : "fixture")
        }
    }
    func retryCycleInsight() {
        guard let r = activeRoutine() else { return }
        UserDefaults.standard.removeObject(forKey: "coach.retry.cycle-\(r.cyclesCompleted)")
        ensureCycleInsight()
    }
    func ensureCycleInsight() {
        guard let r = activeRoutine() else { coachLog("insight: no active routine"); return }
        guard r.cyclesCompleted > 0 else { coachLog("insight: cyclesCompleted=0 — gated until first loop closes"); return }
        guard UserDefaults.standard.integer(forKey: "coach.retry.cycle-\(r.cyclesCompleted)") < 2 else { coachLog("insight: retry cap for cycle-\(r.cyclesCompleted)"); return }
        coachGenerate(kind: "cycleInsight", key: "cycle-\(r.cyclesCompleted)",
                      hint: "Debrief the closed cycle against the one before it using cycles[], history[] and workouts[], comparing slot to slot (and slots[] where it is present): what worked, what regressed, which workout or lift is the weak point, and the one concrete change for the next cycle. Max 3 numbers, interpret the rest in words. No chips.",
                      ctx: cycleInsightContext())
    }
    func coachReconcile() {
        // insight is on-demand (2026-09-04): generated only from the Home ask-row tap
    }
    func seedCoachDemo() {
        guard let r = activeRoutine() else { return }
        let fx = FixtureCoachClient()
        Task { @MainActor in
            if let a = await fx.generateRead(kind: "cycleInsight", context: "", hint: "") {
                upsertCoach(kind: "cycleInsight", key: "cycle-\(r.cyclesCompleted)", a, model: "demo")
            }
        }
    }
}

// MARK: - UI: the box is typography, not chrome
struct CoachBox: View {
    let text: String
    let caption: String
    var chips: [CoachChip] = []
    var onChip: ((CoachChip) -> Void)? = nil
    let aid: String
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .top, spacing: 8) {
                CoachMark9c(size: chips.isEmpty ? 16 : 13).padding(.top, 1)
                Text(text).font(LWFont.mono(12)).foregroundStyle(LW.ink(0.85))
                    .fixedSize(horizontal: false, vertical: true).lineSpacing(3)
            }
            if !chips.isEmpty {
                HStack(spacing: 8) {
                    ForEach(Array(chips.enumerated()), id: \.offset) { i, chip in
                        Button { onChip?(chip) } label: {
                            Text(chip.label).font(LWFont.mono(11)).foregroundStyle(i == 0 ? AIMist.base : LW.ink(0.7))
                                .padding(.horizontal, 12).padding(.vertical, 7)
                                .overlay(Capsule().strokeBorder(i == 0 ? AIMist.base.opacity(0.55) : LW.ink(0.2), lineWidth: 1))
                                .contentShape(Capsule())
                        }.buttonStyle(.plain).accessibilityIdentifier("coach.chip.\(i)")
                    }
                }.padding(.top, 2)
            }
            Text(caption).lwLabel(9, tracking: 0.14, color: LW.ink(0.3))
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(AIPanelBackground(alpha: chips.isEmpty ? 1 : 0.6, radius: chips.isEmpty ? 14 : 12))
        .accessibilityElement(children: .contain).accessibilityIdentifier(aid)
    }
    static func chips(from json: String) -> [CoachChip] {
        (try? JSONDecoder().decode([CoachChip].self, from: Data(json.utf8))) ?? []
    }
}


// MARK: - Session-end coach panel (S3): invited, one-shot, absence-first
struct CoachPanel: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let session: Session
    @State private var expanded = false
    @State private var toast: String?
    @State private var askEffort = true
    @State private var draftEffort: Int?
    @State private var undo: (() -> Void)?
    @State private var applied: Set<String> = []
    @State private var sweep = false

    var body: some View {
        let _ = store.coachTick
        let resp = store.sessionCoach(session)
        Group {
            if let resp {
                CoachReadPanel(read: resp, key: session.id.uuidString,
                               caption: "FROM YOUR LAST \(min(30, store.finishedSessions().count)) SESSIONS",
                               aid: "coach.read",
                               onReview: { if let wid = session.workoutID { router.push(.workoutEdit(wid)) } })
            }
            else if store.coachPending.contains(session.id.uuidString) { sweepPanel { AnyView(waiting) } }
            else if store.coachFailed.contains(session.id.uuidString) { errorRow }
            else if expanded && session.srpe == nil { panel { AnyView(rpeAsk) } }
            else { collapsedRow }
        }
        .overlay(alignment: .bottom) {
            if let toast {
                HStack(spacing: 12) {
                    Text(toast).font(LWFont.mono(11)).foregroundStyle(LW.ink(0.85)).lineLimit(1)
                    Button("UNDO") { undo?(); self.toast = nil; undo = nil }
                        .font(LWFont.mono(11)).foregroundStyle(LW.accent).buttonStyle(.plain)
                }
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(Capsule().fill(Color(red: 0.06, green: 0.07, blue: 0.05)))
                .overlay(Capsule().strokeBorder(LW.accent(0.4), lineWidth: 1))
                .offset(y: 24)
            }
        }
    }

    private var collapsedRow: some View {
        Button {
            if session.srpe != nil { store.askCoach(session: session) }   // silent-failure path: tap retries
            else { withAnimation(.easeOut(duration: 0.2)) { expanded = true } }
        } label: {
            HStack(spacing: 9) {
                CoachMark9c(size: 16)
                Text("Ask coach · what changed this session?").font(LWFont.mono(12)).foregroundStyle(LW.ink(0.75))
                Spacer()
            }
            .padding(.horizontal, 14).frame(height: 46)
            .background(gradientBorder(fillOpacity: 0.5))
            .contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityIdentifier("coach.ask")
    }

    /// Two questions, asked one at a time. Effort first, then recovery — a single effort
    /// scale cannot tell a heavy session from an under-recovered one, because both raise it.
    private var rpeAsk: some View {
        VStack(alignment: .leading, spacing: 12) {
            header(sub: askEffort ? "two quick ones" : "one more")
            if askEffort {
                Text("How hard was that session overall?").font(LWFont.body(15, weight: 800))
                scale(low: "very easy", high: "maximal", recent: recent(\.srpe)) { v in
                    draftEffort = v
                    withAnimation(.easeOut(duration: 0.18)) { askEffort = false }
                }
            } else {
                Text("Before you started, how recovered did you feel?").font(LWFont.body(15, weight: 800))
                scale(low: "not at all", high: "fully", recent: recent(\.prs)) { v in
                    store.askCoach(session: session, srpe: draftEffort, prs: v)
                }
            }
        }
    }

    /// Borg CR-10 is a category-ratio scale: a 4 is twice a 2, which is what makes
    /// effort x duration a real load number. Collapsing it to 5 points breaks that.
    private func scale(low: String, high: String, recent: [Int], onPick: @escaping (Int) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 4) {
                ForEach(0...10, id: \.self) { v in
                    Button { UIImpactFeedbackGenerator(style: .light).impactOccurred(); onPick(v) } label: {
                        Text("\(v)").font(LWFont.mono(11, semibold: recent.contains(v)))
                            .foregroundStyle(LW.ink(0.85)).frame(maxWidth: .infinity).frame(height: 34)
                            .background(RoundedRectangle(cornerRadius: 8).fill(LW.ink(recent.contains(v) ? 0.10 : 0.04)))
                            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(LW.ink(0.18), lineWidth: 1))
                            .contentShape(RoundedRectangle(cornerRadius: 8))
                    }.buttonStyle(.plain).accessibilityIdentifier("coach.scale.\(v)")
                }
            }
            HStack {
                Text(low); Spacer()
                // Answering next to your own recent numbers keeps this a comparison rather
                // than an absolute — the documented failure of daily self-report is anchor drift.
                if !recent.isEmpty { Text("you: " + recent.map(String.init).joined(separator: " · ")) }
                Spacer(); Text(high)
            }
            .font(LWFont.mono(8.5)).foregroundStyle(LW.ink(0.4))
        }
    }

    /// The last three answers on THIS workout, newest last.
    private func recent(_ key: KeyPath<Session, Int?>) -> [Int] {
        store.finishedSessions()
            .filter { $0.groupKey == session.groupKey && $0.id != session.id }
            .suffix(3).compactMap { $0[keyPath: key] }
    }

    private var waiting: some View {
        VStack(alignment: .leading, spacing: 10) {
            header(sub: store.coachStatus[session.id.uuidString] ?? "reading \(min(30, store.finishedSessions().count)) sessions…", pulsing: true)
            Text("▌").font(LWFont.mono(13)).foregroundStyle(AIMist.base).opacity(0.8)
        }
    }


    private func header(sub: String, pulsing: Bool = false) -> some View {
        HStack(spacing: 8) {
            CoachMark9c(size: 16)
            Text("COACH READ").font(LWFont.mono(11)).tracking(1.2).foregroundStyle(LW.ink(0.7))
            Spacer()
            Text(sub).font(LWFont.mono(9)).foregroundStyle(pulsing ? AIMist.base : LW.ink(0.3))
                .opacity(pulsing ? 0.4 : 1)
                .animation(pulsing ? .easeInOut(duration: 1.2).repeatForever(autoreverses: true) : nil, value: pulsing)
        }
    }
    private var errorRow: some View {
        Button {
            if session.srpe != nil { store.askCoach(session: session) }
            else { withAnimation(.easeOut(duration: 0.2)) { expanded = true } }
        } label: {
            HStack(spacing: 9) {
                CoachMark9c(size: 16)
                Text("coach failed: \(store.coachFailReason[session.id.uuidString] ?? "unknown") · tap to retry")
                    .font(LWFont.mono(11)).foregroundStyle(LW.ink(0.6)).lineLimit(1).minimumScaleFactor(0.7)
                Spacer()
            }
            .padding(.horizontal, 14).frame(height: 46)
            .background(gradientBorder(fillOpacity: 0.5))
            .contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityIdentifier("coach.error")
    }
    /// Waiting panel with the same sweeping border as the Home insight loading state.
    private func sweepPanel<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        content()
            .padding(15).frame(maxWidth: .infinity, alignment: .leading)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 14).fill(AIMist.bg)
                    RoundedRectangle(cornerRadius: 14).fill(AIMist.wash)
                    GeometryReader { g in
                        Rectangle().fill(AngularGradient(stops: [
                            .init(color: AIMist.base.opacity(0.12), location: 0),
                            .init(color: AIMist.bright.opacity(0.95), location: 0.07),
                            .init(color: AIMist.bright.opacity(0.8), location: 0.125),
                            .init(color: AIMist.slate.opacity(0.12), location: 0.25),
                            .init(color: AIMist.slate.opacity(0.12), location: 1)], center: .center))
                            .frame(width: max(g.size.width, g.size.height) * 2, height: max(g.size.width, g.size.height) * 2)
                            .position(x: g.size.width / 2, y: g.size.height / 2)
                            .rotationEffect(.degrees(sweep ? 360 : 0))
                    }
                    .mask(RoundedRectangle(cornerRadius: 14).strokeBorder(lineWidth: 1.5))
                }
            )
            .onAppear { withAnimation(.linear(duration: 2.2).repeatForever(autoreverses: false)) { sweep = true } }
            .accessibilityElement(children: .contain).accessibilityIdentifier("coach.panel")
    }
    private func panel<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        content()
            .padding(15).frame(maxWidth: .infinity, alignment: .leading)
            .background(gradientBorder(fillOpacity: 1))
            .accessibilityElement(children: .contain).accessibilityIdentifier("coach.panel")
    }
    private func gradientBorder(fillOpacity: Double) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14).fill(AIMist.bg.opacity(fillOpacity))
            RoundedRectangle(cornerRadius: 14).fill(AIMist.wash)
            RoundedRectangle(cornerRadius: 14).strokeBorder(AIMist.border(), lineWidth: 1)
        }
    }
}

// MARK: - Home insight loading state: sweeping border, stage-driven status, no layout shift
struct CoachInsightLoading: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let cycle: Int
    let status: String
    let caption: String
    @State private var spin = false
    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 8) {
                CoachMark9c(size: 16)
                Text("NEW INSIGHT").font(LWFont.mono(10)).tracking(1.2).foregroundStyle(LW.ink(0.5))
                Spacer()
                Text(reduceMotion ? "reading cycle \(cycle)…" : status)
                    .font(LWFont.mono(9.5)).foregroundStyle(AIMist.base)
                    .animation(.easeOut(duration: 0.25), value: status)
            }
            RoundedRectangle(cornerRadius: 5).fill(LW.ink(reduceMotion ? 0.024 : 0.06))
                .frame(height: 10).padding(.trailing, 10)
            RoundedRectangle(cornerRadius: 5).fill(LW.ink(reduceMotion ? 0.024 : 0.06))
                .frame(height: 10).padding(.trailing, 96)
            Text(caption).font(LWFont.mono(8.5)).tracking(0.8).foregroundStyle(LW.ink(0.2))
        }
        .padding(15).frame(maxWidth: .infinity, alignment: .leading)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 14).fill(AIMist.bg)
                RoundedRectangle(cornerRadius: 14).fill(AIMist.wash)
                if reduceMotion {
                    RoundedRectangle(cornerRadius: 14).strokeBorder(AIMist.border(), lineWidth: 1.5)
                } else {
                    GeometryReader { g in
                        Rectangle().fill(AngularGradient(stops: [
                            .init(color: AIMist.base.opacity(0.12), location: 0),
                            .init(color: AIMist.bright.opacity(0.95), location: 0.07),
                            .init(color: AIMist.bright.opacity(0.8), location: 0.125),
                            .init(color: AIMist.slate.opacity(0.12), location: 0.25),
                            .init(color: AIMist.slate.opacity(0.12), location: 1)], center: .center))
                            .frame(width: max(g.size.width, g.size.height) * 2, height: max(g.size.width, g.size.height) * 2)
                            .position(x: g.size.width / 2, y: g.size.height / 2)
                            .rotationEffect(.degrees(spin ? 360 : 0))
                    }
                    .mask(RoundedRectangle(cornerRadius: 14).strokeBorder(lineWidth: 1.5))
                }
            }
        )
        .onAppear { withAnimation(.linear(duration: 2.2).repeatForever(autoreverses: false)) { spin = true } }
        .accessibilityElement(children: .combine).accessibilityLabel("New insight loading")
        .accessibilityIdentifier("coach.loading")
    }
}

// MARK: - AI brand: mist accent + whistle mark (AI voice; sage stays action/engine)
enum AIMist {
    // Report Card Handoff §2 — iridescent accent: lavender → teal → brand sage
    static let bright = lwDyn(lwHex(0x9FD0E4), lwHex(0x3E6E86))   // signal word / applied ✓ / deltas
    static let base   = lwDyn(lwHex(0x65AAC2), lwHex(0x4E86A0))   // secondary labels & pills
    static let slate  = lwDyn(lwHex(0x4E86A0), lwHex(0x4E86A0))   // rules / frame mid-tone
    static let bg     = lwDyn(lwHex(0x0A0B0C), lwHex(0xFBFAF6))   // AI panel fill
    static let bgFlat = lwDyn(lwHex(0x0C0C10), lwHex(0xFBFAF6))   // reduced-transparency
    static let gradA = lwDyn(lwHex(0x9FD0E4), lwHex(0x9FD0E4))
    static let gradB = lwDyn(lwHex(0x65AAC2), lwHex(0x65AAC2))
    static let gradC = lwDyn(lwHex(0x4E86A0), lwHex(0x4E86A0))   // AI never borrows the action green
    static var gradient: LinearGradient {
        LinearGradient(colors: [gradA, gradB, gradC], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
    static func border(_ alpha: Double = 1) -> LinearGradient {
        LinearGradient(colors: [base.opacity(0.75 * alpha), base.opacity(0.3 * alpha),
                                base.opacity(0.12 * alpha), base.opacity(0.55 * alpha)],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }
    static var wash: RadialGradient {
        RadialGradient(colors: [base.opacity(0.09), .clear], center: .topLeading, startRadius: 0, endRadius: 220)
    }
}

/// Shared AI panel chrome: #0A0A0C fill + mist wash + 1px mist gradient border.
struct AIPanelBackground: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var scheme
    var alpha: Double = 1
    var radius: CGFloat = 15
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: radius).fill(reduceTransparency ? AIMist.bgFlat : AIMist.bg)
            // corner wash: radial from top-left (§2)
            if !reduceTransparency {
                RoundedRectangle(cornerRadius: radius).fill(
                    RadialGradient(colors: [AIMist.slate.opacity(0.08), .clear], center: .topLeading, startRadius: 0, endRadius: 300))
            }
            if scheme == .light {   // Light Mode Handoff §3 top tint, kept under the shared frame
                RoundedRectangle(cornerRadius: radius).fill(LinearGradient(stops: [
                    .init(color: AIMist.gradA.opacity(0.10), location: 0),
                    .init(color: AIMist.gradB.opacity(0.04), location: 0.6),
                    .init(color: .clear, location: 1)], startPoint: .top, endPoint: .bottom))
            }
            RoundedRectangle(cornerRadius: radius).strokeBorder(LinearGradient(stops: [
                .init(color: AIMist.gradA, location: 0),
                .init(color: AIMist.gradB.opacity(0.5), location: 0.4),
                .init(color: AIMist.gradC.opacity(0.35), location: 0.75),
                .init(color: AIMist.gradC, location: 1)],
                startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: alpha < 1 ? 1 : 2)
        }
    }
}

/// The pea-whistle mark, mist gradient, no glow. 16px headers / 13px inline.
/// §5 writing state: real tokens as they arrive, caret riding the last character, pulsing WRITING… status.
struct CoachWritingPanel: View {
    let cycle: Int
    let text: String
    let caption: String
    @State private var pulse = false
    @State private var blink = false
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 9) {
                CoachMark9c(size: 16)
                Text("CYCLE \(cycle) REPORT").font(LWFont.mono(10)).tracking(1.4).foregroundStyle(LW.ink(0.65))
                Spacer(minLength: 6)
                Text("WRITING…").font(LWFont.mono(9.5)).tracking(0.8).foregroundStyle(AIMist.base)
                    .opacity(pulse ? 1 : 0.5)
                    .animation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true), value: pulse)
            }.frame(height: 24)
            Rectangle().fill(AIMist.slate.opacity(0.22)).frame(height: 1)
            (Text(text).foregroundStyle(LW.ink(0.55)) + Text("▍").foregroundStyle(AIMist.base.opacity(blink ? 0.9 : 0.15)))
                .font(LWFont.mono(11)).lineSpacing(7)
                .fixedSize(horizontal: false, vertical: true)
                .animation(.linear(duration: 0.45).repeatForever(autoreverses: true), value: blink)
            Text(caption.replacingOccurrences(of: "FROM", with: "READING")).font(LWFont.mono(8.5)).tracking(0.8).foregroundStyle(LW.ink(0.22))
        }
        .padding(.horizontal, 13).padding(.vertical, 12)
        .background(AIPanelBackground())
        .onAppear { pulse = true; blink = true }
        .accessibilityIdentifier("coach.writing")
    }
}

/// 9c — the coach mark: report card with the UP-arrow verdict punched through + star cluster (Report Card Handoff §3).
struct CoachMark9c: View {
    var size: CGFloat = 16
    var body: some View {
        let u = size / 26
        ZStack {
            RoundedRectangle(cornerRadius: 2.5 * u).fill(AIMist.gradient)
                .frame(width: 16 * u, height: 21 * u)
                .position(x: 12 * u, y: 13 * u)
            Path { p in
                p.move(to: CGPoint(x: 8.5 * u, y: 17.5 * u)); p.addLine(to: CGPoint(x: 15.5 * u, y: 10.5 * u))
                p.move(to: CGPoint(x: 10.2 * u, y: 10.5 * u)); p.addLine(to: CGPoint(x: 15.5 * u, y: 10.5 * u))
                p.addLine(to: CGPoint(x: 15.5 * u, y: 15.8 * u))
            }.stroke(AIMist.bg, style: StrokeStyle(lineWidth: (size < 26 ? 3 : 2.5) * u, lineCap: .round, lineJoin: .round))
            Star4().fill(AIMist.gradient).frame(width: 5.6 * u, height: 5.6 * u).position(x: 21 * u, y: 4.6 * u)
            if size >= 16 {
                Star4().fill(AIMist.gradient).frame(width: 4.4 * u, height: 4.4 * u).position(x: 24.4 * u, y: 9.5 * u)
                Star4().fill(AIMist.gradient).frame(width: 3.4 * u, height: 3.4 * u).position(x: 17.6 * u, y: 9.9 * u)
            }
        }
        .frame(width: 26 * u, height: 26 * u)
    }
}

struct WhistleMark: View {
    var size: CGFloat = 16
    var body: some View {
        let u = size / 26
        ZStack {
            // lanyard loop
            Ellipse().strokeBorder(AIMist.gradient, lineWidth: max(1.2, 1.6 * u * 2))
                .frame(width: 7 * u, height: 4.6 * u)
                .rotationEffect(.degrees(-38))
                .position(x: 20 * u, y: 5.4 * u)
            // mouthpiece block
            RoundedRectangle(cornerRadius: 1.6 * u).fill(AIMist.gradient)
                .frame(width: 7.2 * u, height: 4 * u)
                .rotationEffect(.degrees(-14))
                .position(x: 6 * u, y: 10.6 * u)
            // body with punched pea
            Circle().fill(AIMist.gradient).frame(width: 14.6 * u, height: 14.6 * u)
                .overlay(Circle().fill(AIMist.bg).frame(width: 5.2 * u, height: 5.2 * u).offset(x: -0.8 * u, y: 0.4 * u))
                .position(x: 14.6 * u, y: 15.4 * u)
            // 4-point star at the mouth
            Star4().fill(AIMist.gradient).frame(width: (size >= 15 ? 5.6 : 4.4) * u * (size >= 15 ? 1 : 1.15),
                                                height: (size >= 15 ? 5.6 : 4.4) * u * (size >= 15 ? 1 : 1.15))
                .position(x: 22.6 * u, y: 9.4 * u)
        }
        .frame(width: size, height: size)
        .accessibilityLabel("Coach")
    }
}

struct Star4: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let c = CGPoint(x: r.midX, y: r.midY), ro = min(r.width, r.height) / 2, ri = ro * 0.28
        for i in 0..<4 {
            let a = Double(i) * .pi / 2 - .pi / 2
            let outer = CGPoint(x: c.x + cos(a) * ro, y: c.y + sin(a) * ro)
            let inA = a + .pi / 4
            let inner = CGPoint(x: c.x + cos(inA) * ri, y: c.y + sin(inA) * ri)
            if i == 0 { p.move(to: outer) } else { p.addLine(to: outer) }
            p.addLine(to: inner)
        }
        p.closeSubpath()
        return p
    }
}

// MARK: - Collapsed AI read (Insight Collapse handoff): headline row → expand → prose + change rows
struct CoachReadPanel: View {
    @Environment(AppStore.self) private var store
    let read: CoachRead
    let key: String
    let caption: String
    let aid: String
    var onReview: (() -> Void)? = nil
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var open: Bool
    @State private var accepted: Set<String>
    @State private var skipped: Set<String>
    @State private var sweepAngle: Double = 0    // one revolution of the border highlight on expand
    @State private var sweeping = false

    private var reportCycle: Int? { key.hasPrefix("cycle-") ? Int(key.dropFirst(6)) : nil }
    private var reportStatus: String {
        if let m = caption.range(of: #"(\d+) SESSIONS"#, options: .regularExpression) { return caption[m].replacingOccurrences(of: "SESSIONS", with: "SESSIONS READ") }
        return "READ"
    }
    /// Body with cited figures (numbers) lifted to 85% ink (§4).
    private var bodyText: Text {
        var t = Text(""); var rest = Substring(read.body)
        let rx = try! NSRegularExpression(pattern: #"\d[\d,\.]*"#)
        while let m = rx.firstMatch(in: String(rest), range: NSRange(rest.startIndex..., in: rest)), let r = Range(m.range, in: rest) {
            t = t + Text(rest[..<r.lowerBound]).foregroundStyle(LW.ink(0.55)) + Text(rest[r]).foregroundStyle(LW.ink(0.85))
            rest = rest[r.upperBound...]
        }
        return t + Text(rest).foregroundStyle(LW.ink(0.55))
    }

    private func runSweep() {
        guard !reduceMotion else { return }
        sweepAngle = 0; sweeping = true
        withAnimation(.easeInOut(duration: 0.9).delay(0.05)) { sweepAngle = 360 }
        Task { try? await Task.sleep(for: .seconds(1.05)); withAnimation(.easeOut(duration: 0.25)) { sweeping = false } }
    }

    init(read: CoachRead, key: String, caption: String, aid: String, onReview: (() -> Void)? = nil) {
        self.read = read; self.key = key; self.caption = caption; self.aid = aid; self.onReview = onReview
        _open = State(initialValue: UserDefaults.standard.object(forKey: "insight.open.\(key)") as? Bool ?? false)  // 10b: lands as a collapsed strip; the chevron opens the full report
        _accepted = State(initialValue: Set(UserDefaults.standard.stringArray(forKey: "coach.accepted.\(key)") ?? []))
        _skipped = State(initialValue: Set(UserDefaults.standard.stringArray(forKey: "coach.skipped.\(key)") ?? []))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeOut(duration: 0.2)) { open.toggle() }
                UserDefaults.standard.set(open, forKey: "insight.open.\(key)")
                if open { runSweep() }
            } label: {
                HStack(spacing: 9) {
                    CoachMark9c(size: open && reportCycle != nil ? 16 : 15)
                    if open, let c = reportCycle {
                        Text("CYCLE \(c) REPORT").font(LWFont.mono(10)).tracking(1.4).foregroundStyle(LW.ink(0.65))
                        Spacer(minLength: 6)
                        Text(reportStatus).font(LWFont.mono(9.5)).tracking(0.8).foregroundStyle(AIMist.base)
                    } else {
                        headlineText.font(LWFont.mono(10.5)).lineLimit(2).minimumScaleFactor(0.8).multilineTextAlignment(.leading)
                        Spacer(minLength: 6)
                        if let n = read.actions?.count, n > 0 {
                            let done = accepted.count
                            Text(done > 0 ? "\(done) ✓" : "\(n)").font(LWFont.mono(10)).foregroundStyle(AIMist.base)
                                .padding(.horizontal, 7).frame(height: 20)
                                .overlay(Capsule().strokeBorder(AIMist.slate.opacity(0.45), lineWidth: 1))
                        }
                    }
                    Icon(kind: .chevronDown, size: 12, color: LW.ink(0.4), weight: 2)
                        .rotationEffect(.degrees(open ? 180 : 0))
                }
                .padding(.horizontal, 13).frame(height: open && reportCycle != nil ? 44 : 40).contentShape(Rectangle())
            }.buttonStyle(.plain)
            if open {
                VStack(alignment: .leading, spacing: 10) {
                    Rectangle().fill(AIMist.slate.opacity(0.22)).frame(height: 1)
                    if reportCycle != nil {
                        headlineText.font(LWFont.mono(12, semibold: true))
                            .fixedSize(horizontal: false, vertical: true)
                    } else if scheme == .light {
                        Text("COACH READ").font(LWFont.mono(9, semibold: true)).tracking(1.6).foregroundStyle(AIMist.base)
                    }
                    HStack(alignment: .top, spacing: 10) {
                        Rectangle().fill(AIMist.slate.opacity(0.35)).frame(width: 2)
                        bodyText.font(LWFont.mono(11)).lineSpacing(7)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .accessibilityIdentifier("\(aid).body")
                    Text(caption).font(LWFont.mono(8.5)).tracking(0.8).foregroundStyle(LW.ink(0.3))
                    if let actions = read.actions, !actions.isEmpty {
                        HStack {
                            Text("NEXT CYCLE · \(actions.count) CHANGE\(actions.count == 1 ? "" : "S")")
                                .font(LWFont.mono(8.5)).tracking(1.2).foregroundStyle(AIMist.base)
                            Spacer()
                            Text("weight + order only").font(LWFont.mono(8)).foregroundStyle(LW.ink(0.3))
                        }.padding(.top, 2)
                        ForEach(Array(actions.enumerated()), id: \.offset) { i, a in
                            changeRow(i, a)
                            if i < actions.count - 1 { Hairline() }
                        }
                    }
                }
                .padding(.horizontal, 13).padding(.bottom, 12)
                .transition(.opacity)
            }
        }
        .background(AIPanelBackground())
        .overlay {
            if sweeping {   // highlight travels once around the frame — mirrors the loading sweep
                Rectangle().fill(AngularGradient(stops: [
                    .init(color: .clear, location: 0),
                    .init(color: AIMist.gradA.opacity(0.95), location: 0.06),
                    .init(color: AIMist.gradB.opacity(0.45), location: 0.13),
                    .init(color: .clear, location: 0.24),
                    .init(color: .clear, location: 1)], center: .center))
                    .scaleEffect(1.7)
                    .rotationEffect(.degrees(sweepAngle))
                    .mask(RoundedRectangle(cornerRadius: 14).strokeBorder(style: StrokeStyle(lineWidth: 2.5)))
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        .onAppear { if open { runSweep() } }
        .accessibilityElement(children: .contain).accessibilityIdentifier(aid)
    }

    private var headlineText: Text {
        var t = Text("")
        for (i, part) in read.headline.components(separatedBy: "*").enumerated() {
            t = t + Text(part).foregroundStyle(i % 2 == 1 ? AIMist.bright : LW.ink(0.85))
        }
        return t
    }

    @ViewBuilder private func changeRow(_ i: Int, _ a: CoachAction) -> some View {
        let applyRight = ["weight", "reorder", "addExercise"].contains(a.type)
        let isAccepted = accepted.contains(a.label)
        let isSkipped = skipped.contains(a.label)
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                if !a.exercise.isEmpty {
                    Text(a.exercise.uppercased()).font(LWFont.mono(8.5)).tracking(1)
                        .foregroundStyle(LW.ink(isSkipped ? 0.25 : 0.45)).lineLimit(1)
                }
                Text(a.label).font(LWFont.mono(11)).foregroundStyle(LW.ink(isSkipped ? 0.4 : 0.85))
                if let r = a.reason, !r.isEmpty { Text(r).font(LWFont.mono(9.5)).foregroundStyle(LW.ink(isSkipped ? 0.25 : 0.35)).lineLimit(1) }
            }
            Spacer(minLength: 8)
            if isAccepted {
                Text("applied ✓").font(LWFont.mono(10)).foregroundStyle(AIMist.bright)
            } else if !isSkipped {
                if applyRight {
                    Button {
                        if store.applyCoachAction(a) {
                            accepted.insert(a.label)
                            UserDefaults.standard.set(Array(accepted), forKey: "coach.accepted.\(key)")
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        }
                    } label: {
                        Text("accept").font(LWFont.mono(10.5, semibold: true)).foregroundStyle(Color(red: 0x0A/255, green: 0x0B/255, blue: 0x0C/255))
                            .padding(.horizontal, 12).frame(height: 28)
                            .background(Capsule().fill(AIMist.gradient)).contentShape(Capsule())
                    }.buttonStyle(.plain).accessibilityIdentifier("\(aid).accept.\(i)")
                    Button {
                        withAnimation(.easeOut(duration: 0.15)) { skipped.insert(a.label) }
                        UserDefaults.standard.set(Array(skipped), forKey: "coach.skipped.\(key)")
                    } label: {
                        Text("skip").font(LWFont.mono(10.5)).foregroundStyle(LW.ink(0.45))
                            .padding(.horizontal, 10).frame(height: 28)
                            .overlay(Capsule().strokeBorder(LW.ink(0.18), lineWidth: 1)).contentShape(Capsule())
                    }.buttonStyle(.plain).accessibilityIdentifier("\(aid).skip.\(i)")
                } else {
                    Button { onReview?() } label: {
                        Text("review").font(LWFont.mono(10.5)).foregroundStyle(AIMist.base)
                            .padding(.horizontal, 12).frame(height: 28)
                            .overlay(Capsule().strokeBorder(AIMist.base.opacity(0.55), lineWidth: 1)).contentShape(Capsule())
                    }.buttonStyle(.plain).accessibilityIdentifier("\(aid).review.\(i)")
                }
            }
        }
        .opacity(isSkipped ? 0.4 : 1)
        .accessibilityElement(children: .contain).accessibilityIdentifier("\(aid).change.\(i)")
    }
}
