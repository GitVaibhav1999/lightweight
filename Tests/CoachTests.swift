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

    /// Two Push sessions inside one week is a workout with two slots, never two workouts:
    /// reconstruction groups by title, so the recurrence lands as sessions of the same template.
    func testARecurringTitleRebuildsAsOneWorkout() throws {
        let head = #""title","start_time","end_time","description","exercise_title","superset_id","exercise_notes","set_index","set_type","weight_kg","reps","distance_km","duration_seconds","rpe""#
        var rows = [head]
        for (title, day) in [("Push", 1), ("Legs", 2), ("Push", 4), ("Push", 8), ("Legs", 9), ("Push", 11), ("Legs", 15)] {
            let ex = title == "Push" ? "Bench Press (Barbell)" : "Squat (Barbell)"
            rows.append("\"\(title)\",\"\(day) Apr 2023, 10:00\",\"\(day) Apr 2023, 11:00\",\"\",\"\(ex)\",\"\",\"\",0,\"normal\",60,8,,,")
        }
        let store = AppStore(inMemory: true)
        let report = try HevyImporter.importCSV(rows.joined(separator: "\n"), into: store.context)
        XCTAssertEqual(report.imported, 7)

        let keys = Set([1, 4, 8, 11].map { "Push|\($0) Apr 2023, 10:00" })
        let pushSessions = (try store.context.fetch(FetchDescriptor<Session>())).filter { keys.contains($0.hevyKey ?? "") }
        XCTAssertEqual(pushSessions.count, 4)
        XCTAssertEqual(Set(pushSessions.compactMap(\.workoutID)).count, 1,
                       "a title that recurs twice a week rebuilds as one workout with two turns, not two workouts")
    }

    /// The identity a Hevy session gets must survive a wipe, or a re-imported push collides
    /// with rows the server already holds under their old ids (hevy_key is unique per user).
    func testSessionIDIsStableAcrossAWipe() throws {
        let csv = """
        "title","start_time","end_time","description","exercise_title","superset_id","exercise_notes","set_index","set_type","weight_kg","reps","distance_km","duration_seconds","rpe"
        "Legs","1 Apr 2023, 20:34","1 Apr 2023, 21:30","","Squat (Barbell)","","",0,"normal",100,5,,,
        """
        func idAfterFreshImport() throws -> UUID {
            let store = AppStore(inMemory: true)          // a brand new store, as after a reinstall
            _ = try HevyImporter.importCSV(csv, into: store.context)
            let all = ((try? store.context.fetch(FetchDescriptor<Session>())) ?? [])
            return try XCTUnwrap(all.first { $0.hevyKey == "Legs|1 Apr 2023, 20:34" }).id
        }
        XCTAssertEqual(try idAfterFreshImport(), try idAfterFreshImport(),
                       "the same export must yield the same id on any device")
        XCTAssertEqual(HevyImporter.stableID("Legs|1 Apr 2023, 20:34"), try idAfterFreshImport())
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
        store.addToRoutine(a); store.addToRoutine(b); store.addToRoutine(b)   // a workout may take a second slot
        let actives = (try store.context.fetch(FetchDescriptor<Routine>())).filter(\.isActive)
        XCTAssertEqual(actives.count, 1, "one active routine, however many slots")
        XCTAssertEqual(actives.first?.orderedEntries.count, 3)
        XCTAssertEqual(Set(actives.first?.orderedEntries.map(\.workoutID) ?? []).count, 2, "the third slot is not a third workout")
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
    func testDeletingAWorkoutTheLoopUsesIsRefused() throws {
        let store = AppStore(inMemory: true)
        let a = Workout(name: "Legs"), b = Workout(name: "Push"), c = Workout(name: "Back")
        for w in [a, b, c] { store.context.insert(w); store.addToRoutine(w) }
        store.finish(store.startSession(from: a))           // pointer -> 1

        XCTAssertTrue(store.routineUses(b))
        XCTAssertFalse(store.deleteWorkout(b), "a workout the loop points at must not be deletable")

        let r = try XCTUnwrap(store.activeRoutine())
        XCTAssertEqual(r.orderedEntries.count, 3, "the loop must be untouched by a refused delete")
        XCTAssertEqual(r.pointer, 1, "and so must the pointer")
    }

    /// Removing the slot first is the supported route, and then the loop repairs itself.
    func testRemovingTheSlotThenDeletingRepairsTheLoop() throws {
        let store = AppStore(inMemory: true)
        let a = Workout(name: "Legs"), b = Workout(name: "Push"), c = Workout(name: "Back")
        for w in [a, b, c] { store.context.insert(w); store.addToRoutine(w) }
        store.finish(store.startSession(from: a))           // pointer -> 1

        let r = try XCTUnwrap(store.activeRoutine())
        let slot = try XCTUnwrap(r.orderedEntries.first { $0.workoutID == b.id })
        store.context.delete(slot)
        for (i, e) in r.orderedEntries.filter({ $0 !== slot }).enumerated() { e.order = i }
        r.pointer = 0
        try? store.context.save(); store.dataTick += 1

        XCTAssertTrue(store.deleteWorkout(b), "out of the loop, it deletes")
        let after = try XCTUnwrap(store.activeRoutine())
        XCTAssertEqual(after.orderedEntries.count, 2)
        XCTAssertEqual(after.orderedEntries.map(\.order), [0, 1], "order closes its gap")
        XCTAssertFalse(after.orderedEntries.contains { $0.workoutID == b.id })
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

    /// push · pull · push: one workout, two slots, and the loop still walks them in order.
    func testARepeatedWorkoutTakesTwoSlots() throws {
        let store = AppStore(inMemory: true)
        let push = Workout(name: "Push"), pull = Workout(name: "Pull")
        store.context.insert(push); store.context.insert(pull)
        store.addToRoutine(push); store.addToRoutine(pull); store.addToRoutine(push)

        let slots = store.routineSlots()
        XCTAssertEqual(slots.map(\.name), ["Push", "Pull", "Push"])
        XCTAssertEqual(slots.map(\.occurrence), [1, 1, 2], "occurrences number in slot order")
        XCTAssertEqual(slots.map(\.repeated), [true, false, true])
        XCTAssertEqual(slots[0].alsoFills, [3]); XCTAssertEqual(slots[2].alsoFills, [1])
        XCTAssertTrue(store.routineHasRepeats())
        XCTAssertEqual(Set(slots.map(\.workoutID)).count, 2, "two slots, one workout entity")

        store.finish(store.startSession(from: push))                       // slot 1
        XCTAssertEqual(store.activeRoutine()?.pointer, 1)
        store.finish(store.startSession(from: pull))                       // slot 2
        XCTAssertEqual(store.nextWorkout()?.id, push.id, "slot 3 is push's second turn")
        store.finish(store.startSession(from: push))                       // slot 3
        // the bug this pins: advancing by workout id lands on slot 1 and rewinds the cycle
        XCTAssertEqual(store.activeRoutine()?.pointer, 0, "the loop wraps from slot 3, not back to slot 2")
        XCTAssertEqual(store.activeRoutine()?.cyclesCompleted, 1)
    }

    func testPointerFollowsItsSlotThroughAReorder() throws {
        let store = AppStore(inMemory: true)
        let push = Workout(name: "Push"), pull = Workout(name: "Pull"), legs = Workout(name: "Legs")
        for w in [push, pull, legs] { store.context.insert(w) }
        for w in [push, pull, push, legs] { store.addToRoutine(w) }
        let r = try XCTUnwrap(store.activeRoutine())
        r.pointer = 2                                                      // push's SECOND slot
        let pointed = r.orderedEntries[2]

        store.moveSlot(from: 0, to: 3)                                     // the first push goes to the end

        XCTAssertEqual(r.orderedEntries.map(\.order), [0, 1, 2, 3], "order closes up")
        XCTAssertEqual(store.routineSlots().map(\.name), ["Pull", "Push", "Legs", "Push"])
        XCTAssertTrue(r.orderedEntries[r.pointer] === pointed, "the pointer keeps its own slot, not the first with that workout")
        XCTAssertEqual(r.pointer, 1)
    }

    func testRemovingThePointersSlotTakesWhateverStandsThere() throws {
        let store = AppStore(inMemory: true)
        let push = Workout(name: "Push"), pull = Workout(name: "Pull"), legs = Workout(name: "Legs")
        for w in [push, pull, legs] { store.context.insert(w); store.addToRoutine(w) }
        let r = try XCTUnwrap(store.activeRoutine())
        r.pointer = 1                                                      // standing on Pull

        store.removeSlot(r.orderedEntries[1])                              // its own slot goes

        XCTAssertEqual(store.routineSlots().map(\.name), ["Push", "Legs"])
        XCTAssertEqual(r.pointer, 1, "the slot now at that index takes over")
        XCTAssertEqual(store.nextWorkout()?.id, legs.id)
        XCTAssertNotNil(store.workout(pull.id), "losing its last slot must not delete the workout")

        store.removeSlot(r.orderedEntries[1])                              // the last slot, and the pointer's
        XCTAssertEqual(r.pointer, 0, "past the end it wraps to slot 1")
        XCTAssertFalse(store.removeSlot(r.orderedEntries[0]), "a routine never empties: one slot is the floor")
    }

    func testANoRepeatRoutineCarriesNoOrdinals() throws {
        let store = AppStore(inMemory: true)
        for n in ["Legs", "Push 1", "Back", "Shoulders"] {
            let w = Workout(name: n); store.context.insert(w); store.addToRoutine(w)
        }
        XCTAssertFalse(store.routineHasRepeats(), "no workout takes two turns")
        for s in store.routineSlots() {
            XCTAssertFalse(s.repeated); XCTAssertEqual(s.occurrence, 1); XCTAssertTrue(s.alsoFills.isEmpty)
        }
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
