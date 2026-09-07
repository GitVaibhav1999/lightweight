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
