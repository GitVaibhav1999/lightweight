import XCTest
import SwiftData
@testable import LightWeight

@MainActor
final class CoachTests: XCTestCase {
    func testChangeNumbersExempt() {
        let store = AppStore(inMemory: true)
        let ctx = #"{"cycles":[{"cycle":27,"vol":"9,120"}],"topSets":["Row 70×12"]}"#
        // action numbers are NEW by design — must pass; claims must be payload-verbatim
        let ok = CoachRead(headline: "Held at 9,120 volume", body: "Row top set stayed 70×12 across the block.",
                           actions: [CoachAction(type: "weight", exercise: "Row", from: "70", to: "72.5", label: "row 70 → 72.5", reason: "top of range")])
        XCTAssertNotNil(store.readValidated(ok, ctx: ctx))
        let bad = CoachRead(headline: "You hit 12,340 volume", body: "Solid.", actions: nil)
        XCTAssertNil(store.readValidated(bad, ctx: ctx))
        // whitelist: review types pass through, junk filtered
        let acts = CoachRead(headline: "Held", body: "Flat.", actions: [
            CoachAction(type: "repRange", exercise: "Row", from: "8-12", to: "6-10", label: "x", reason: nil),
            CoachAction(type: "explode", exercise: "x", from: nil, to: nil, label: "no", reason: nil)])
        XCTAssertEqual(store.readValidated(acts, ctx: nil)?.actions?.count, 1)
    }

    func testCyclesCountOnlySinceRoutineBuilt() throws {
        let store = AppStore(inMemory: true)
        let w = Workout(name: "Legs"); store.context.insert(w)
        let r = Routine(name: "My routine", isActive: true); store.context.insert(r)
        let e = RoutineEntry(order: 0, workoutID: w.id); e.routine = r; store.context.insert(e)
        for i in 0..<3 {   // imported history predating the routine
            let s = Session(title: "Legs", workoutID: w.id, startedAt: Date(timeIntervalSinceNow: Double(-i - 1) * 86400), source: "hevy")
            s.isDraft = false; store.context.insert(s)
        }
        try store.context.save(); store.reload()
        let fresh = store.cycleChunks()
        XCTAssertTrue(fresh.past.isEmpty, "pre-routine history must not form cycles")
        XCTAssertTrue(fresh.current.isEmpty)
        XCTAssertEqual(store.cycleVolumes().current, 0)
        r.pointer = 2   // two sessions tracked since the routine was built
        XCTAssertEqual(store.cycleChunks().current.count, 2)
    }
}

@MainActor
final class HevyImportFidelityTests: XCTestCase {
    /// The parser always read these; the importer dropped them on the floor.
    func testImportCarriesNotesAndDistance() throws {
        let csv = """
        "title","start_time","end_time","description","exercise_title","superset_id","exercise_notes","set_index","set_type","weight_kg","reps","distance_km","duration_seconds","rpe"
        "Legs","1 Apr 2023, 20:34","1 Apr 2023, 21:30","felt strong","Squat (Barbell)","","knees ok",0,"normal",100,5,,,
        "Legs","1 Apr 2023, 20:34","1 Apr 2023, 21:30","felt strong","Squat (Barbell)","","knees ok",1,"normal",100,5,,,
        "Legs","1 Apr 2023, 20:34","1 Apr 2023, 21:30","felt strong","Farmer Walk","","heavy",0,"normal",40,,0.25,60,
        """
        let store = AppStore(inMemory: true)
        let report = try HevyImporter.importCSV(csv, into: store.context)
        XCTAssertEqual(report.imported, 1)

        let all = ((try? store.context.fetch(FetchDescriptor<Session>())) ?? [])
        let s = try XCTUnwrap(all.first { $0.hevyKey == "Legs|1 Apr 2023, 20:34" })
        XCTAssertEqual(s.note, "felt strong", "session description must survive the import")

        let squat = try XCTUnwrap(s.orderedExercises.first { $0.exerciseName.contains("Squat") })
        XCTAssertEqual(squat.note, "knees ok", "exercise notes must survive the import")

        let walk = try XCTUnwrap(s.orderedExercises.first { $0.exerciseName.contains("Farmer") })
        XCTAssertEqual(walk.orderedSets.first?.distanceKm, 0.25, "distance must survive the import")
        XCTAssertNil(squat.orderedSets.first?.distanceKm, "a lift has no distance")
    }

    /// Re-import is a no-op, so the notes are not duplicated or wiped on a second run.
    func testReimportIsIdempotent() throws {
        let csv = """
        "title","start_time","end_time","description","exercise_title","superset_id","exercise_notes","set_index","set_type","weight_kg","reps","distance_km","duration_seconds","rpe"
        "Legs","1 Apr 2023, 20:34","1 Apr 2023, 21:30","felt strong","Squat (Barbell)","","knees ok",0,"normal",100,5,,,
        """
        let store = AppStore(inMemory: true)
        _ = try HevyImporter.importCSV(csv, into: store.context)
        let second = try HevyImporter.importCSV(csv, into: store.context)
        XCTAssertEqual(second.imported, 0)
        XCTAssertEqual(second.skipped, 1)
        let matching = ((try? store.context.fetch(FetchDescriptor<Session>())) ?? [])
            .filter { $0.hevyKey == "Legs|1 Apr 2023, 20:34" }
        XCTAssertEqual(matching.count, 1, "a second import must not duplicate the session")
    }
}

@MainActor
final class RoutineFlowTests: XCTestCase {
    func testAddToRoutineNeverDuplicatesActives() throws {
        let store = AppStore(inMemory: true)
        let a = Workout(name: "Legs"), b = Workout(name: "Push")
        store.context.insert(a); store.context.insert(b)
        store.addToRoutine(a); store.addToRoutine(b); store.addToRoutine(b)   // double-tap must be idempotent
        let actives = (try store.context.fetch(FetchDescriptor<Routine>())).filter(\.isActive)
        XCTAssertEqual(actives.count, 1)
        XCTAssertEqual(actives.first?.orderedEntries.count, 2)
    }
    func testFinishAdvancesLoopPointer() throws {
        let store = AppStore(inMemory: true)
        let a = Workout(name: "Legs"), b = Workout(name: "Push")
        store.context.insert(a); store.context.insert(b)
        store.addToRoutine(a); store.addToRoutine(b)
        let s1 = store.startSession(from: a)
        store.finish(s1)
        XCTAssertEqual(store.activeRoutine()?.pointer, 1, "finishing slot 1 must queue slot 2")
        XCTAssertEqual(store.nextWorkout()?.id, b.id)
        let s2 = store.startSession(from: b)
        store.finish(s2)
        XCTAssertEqual(store.activeRoutine()?.pointer, 0, "loop must wrap")
        XCTAssertEqual(store.activeRoutine()?.cyclesCompleted, 1)
    }
    func testDeletingALoopWorkoutRepairsTheLoop() throws {
        let store = AppStore(inMemory: true)
        let a = Workout(name: "Legs"), b = Workout(name: "Push"), c = Workout(name: "Back")
        for w in [a, b, c] { store.context.insert(w); store.addToRoutine(w) }
        store.finish(store.startSession(from: a))           // pointer -> 1
        XCTAssertEqual(store.activeRoutine()?.pointer, 1)

        store.deleteWorkout(b)                               // delete the one it is pointing at

        let r = try XCTUnwrap(store.activeRoutine())
        XCTAssertEqual(r.orderedEntries.count, 2, "the deleted workout's entry must go with it")
        XCTAssertEqual(r.orderedEntries.map(\.order), [0, 1], "order must close its gap, not keep a hole")
        XCTAssertFalse(r.orderedEntries.contains { $0.workoutID == b.id })
        XCTAssertEqual(r.pointer, 0, "a part-finished cycle whose composition changed is not that cycle")
        // the bug: a stale pointer indexes a surviving entry and serves the wrong workout
        XCTAssertEqual(store.nextWorkout()?.id, a.id)
        let p = try XCTUnwrap(store.routineProgress())
        XCTAssertLessThanOrEqual(p.done, p.total, "progress must never report a place past the end")
    }

    func testDeletingAWorkoutOutsideTheLoopLeavesThePointer() throws {
        let store = AppStore(inMemory: true)
        let a = Workout(name: "Legs"), b = Workout(name: "Push"), loose = Workout(name: "Arms")
        for w in [a, b] { store.context.insert(w); store.addToRoutine(w) }
        store.context.insert(loose)                          // never added to the routine
        store.finish(store.startSession(from: a))            // pointer -> 1

        store.deleteWorkout(loose)

        XCTAssertEqual(store.activeRoutine()?.pointer, 1, "deleting an unrelated workout must not reset the cycle")
        XCTAssertEqual(store.nextWorkout()?.id, b.id)
    }

    func testDuplicateActivesHealOnReload() throws {
        let store = AppStore(inMemory: true)
        let w = Workout(name: "Legs"); store.context.insert(w)
        let r1 = Routine(name: "A", isActive: true); store.context.insert(r1)
        let e = RoutineEntry(order: 0, workoutID: w.id); e.routine = r1; store.context.insert(e)
        let r2 = Routine(name: "B", isActive: true); store.context.insert(r2)
        try store.context.save()
        store.reload()
        let actives = (try store.context.fetch(FetchDescriptor<Routine>())).filter(\.isActive)
        XCTAssertEqual(actives.count, 1)
        XCTAssertEqual(actives.first?.name, "A", "the fullest loop survives")
    }
}
