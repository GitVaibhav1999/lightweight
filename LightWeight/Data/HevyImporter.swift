import Foundation
import SwiftData

/// Hevy CSV -> Sessions (idempotent on hevyKey) + workout/routine reconstruction (PRD §7a).
@MainActor enum HevyImporter {
    struct Report { var imported = 0, skipped = 0, customCreated: [String] = [], workoutsCreated = 0, routineCreated = false }

    static func importCSV(_ text: String, into context: ModelContext) throws -> Report {
        var report = Report()
        let parsed = HevyCSV.parse(text)
        let aliases = Seed.loadAliases()
        let existingKeys = Set(((try? context.fetch(FetchDescriptor<Session>())) ?? []).compactMap(\.hevyKey))
        var exByID: [String: Exercise] = Dictionary(uniqueKeysWithValues: ((try? context.fetch(FetchDescriptor<Exercise>())) ?? []).map { ($0.id, $0) })
        var customByName: [String: Exercise] = Dictionary(exByID.values.filter { $0.source == "custom" }.map { ($0.name, $0) }, uniquingKeysWith: { a, _ in a })
        var renamed = Set<String>()

        func resolve(_ hevyName: String, bodyweight: Bool) -> Exercise {
            // A mapped library exercise takes the name you already know it by.
            if let id = aliases[hevyName]?.id, let e = exByID[id] { if e.source == "dataset", !renamed.contains(e.id) { e.name = hevyName; renamed.insert(e.id) }; return e }
            if let e = customByName[hevyName] { return e }
            let e = Exercise(id: "custom-" + UUID().uuidString, name: hevyName, bodyPart: "", target: "custom", equipment: "", loadType: bodyweight ? "bodyweight+reps" : "weight+reps", source: "custom")
            context.insert(e); exByID[e.id] = e; customByName[hevyName] = e; report.customCreated.append(hevyName)
            return e
        }

        // Resolve every name up front so mapped library exercises pick up your Hevy names even on a re-import.
        for p in parsed { for ex in p.exercises { _ = resolve(ex.name, bodyweight: ex.sets.allSatisfy { $0.kg == nil }) } }
        for p in parsed {
            if existingKeys.contains(p.key) { report.skipped += 1; continue }
            let s = Session(title: p.title, workoutID: nil, startedAt: p.start, source: "hevy")
            s.endedAt = p.end; s.isDraft = false; s.hevyKey = p.key; s.note = p.notes
            context.insert(s)
            for (i, ex) in p.exercises.enumerated() {
                let bodyweight = ex.sets.allSatisfy { $0.kg == nil }
                let e = resolve(ex.name, bodyweight: bodyweight)
                let se = SessionExercise(order: i, exerciseID: e.id, exerciseName: e.source == "custom" ? e.name : ex.name)
                se.note = ex.notes
                se.session = s
                context.insert(se)
                for st in ex.sets {
                    let log = SetLog(index: st.index, type: st.type, kg: st.kg, reps: st.reps, seconds: st.seconds, done: true)
                    log.distanceKm = st.distanceKm
                    log.exercise = se; context.insert(log)
                }
            }
            report.imported += 1
        }
        try context.save()
        if report.imported > 0 { reconstruct(context: context, report: &report) }
        try context.save()
        return report
    }

    /// Titles used ≥3× become Workouts (slots from the last 6 sessions); those used ≥3× in the last 120 days form the routine loop.
    static func reconstruct(context: ModelContext, report: inout Report) {
        let sessions = ((try? context.fetch(FetchDescriptor<Session>())) ?? []).filter { !$0.isDraft }.sorted { $0.startedAt < $1.startedAt }
        guard let latest = sessions.last?.startedAt else { return }
        let existing = (try? context.fetch(FetchDescriptor<Workout>())) ?? []
        var byName: [String: Workout] = Dictionary(existing.map { ($0.name, $0) }, uniquingKeysWith: { a, _ in a })
        let byTitle = Dictionary(grouping: sessions, by: \.title)

        for (title, ss) in byTitle where ss.count >= 3 {
            let w = byName[title] ?? { let w = Workout(name: title); context.insert(w); byName[title] = w; report.workoutsCreated += 1; return w }()
            if w.slots.isEmpty {
                for slot in slotsFrom(sessions: Array(ss.suffix(6))) { slot.workout = w; context.insert(slot) }
            }
            for s in ss where s.workoutID == nil { s.workoutID = w.id }
        }
        // Import rebuilds WORKOUTS (above) but never a routine: the loop is built by the user on the Workouts screen.
    }

    static func slotsFrom(sessions ss: [Session]) -> [WorkoutSlot] {
        var pos: [String: [Int]] = [:], nsets: [String: [Int]] = [:], reps: [String: [Int]] = [:], names: [String: String] = [:]
        for s in ss {
            for (p, se) in s.orderedExercises.enumerated() {
                pos[se.exerciseID, default: []].append(p); nsets[se.exerciseID, default: []].append(se.sets.count)
                reps[se.exerciseID, default: []] += se.sets.compactMap(\.reps); names[se.exerciseID] = se.exerciseName
            }
        }
        let keep = pos.filter { Double($0.value.count) >= Double(ss.count) / 2 }.keys
            .sorted { Double(pos[$0]!.reduce(0, +)) / Double(pos[$0]!.count) < Double(pos[$1]!.reduce(0, +)) / Double(pos[$1]!.count) }
        return keep.prefix(8).enumerated().map { i, id in
            let rs = reps[id]!.sorted(); let ns = nsets[id]!.sorted()
            return WorkoutSlot(order: i, exerciseID: id, exerciseName: names[id] ?? "", sets: ns[ns.count / 2], repLo: rs.isEmpty ? 8 : rs[rs.count / 4], repHi: rs.isEmpty ? 12 : rs[(3 * rs.count) / 4])
        }
    }
}
