import XCTest
@testable import LightWeight

/// Pins the Swift engine to scripts/verdict.py on the real Hevy export (HEVY_CSV env or the repo default).
final class EngineTests: XCTestCase {
    static let csvPath = ProcessInfo.processInfo.environment["HEVY_CSV"]
        ?? URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent(".cache/hevy/workout_data.csv").path

    func loadSessions() throws -> [SessionInput] {
        let text = try String(contentsOfFile: Self.csvPath, encoding: .utf8)
        return HevyCSV.parse(text).map { p in
            SessionInput(id: UUID(), groupKey: p.title, title: p.title, start: p.start, end: p.end,
                         exercises: p.exercises.map { ExerciseInput(exerciseID: $0.name, name: $0.name, sets: $0.sets.map { SetInput(kg: $0.kg, reps: $0.reps, isWarmup: $0.type == "warmup") }) })
        }
    }

    func testParseCounts() throws {
        let s = try loadSessions()
        XCTAssertEqual(s.count, 470)
        XCTAssertEqual(s.reduce(0) { $0 + $1.exercises.reduce(0) { $0 + $1.sets.count } }, 6078)
    }

    func testVerdictDistributionMatchesPython() throws {
        let a = Engine.run(try loadSessions())
        let f = ISO8601DateFormatter(); f.formatOptions = [.withFullDate]
        let since = f.date(from: "2025-08-27")!
        let yr = a.ordered.filter { $0.date >= since }
        XCTAssertEqual(yr.count, 186)
        func n(_ st: SessionState?) -> Int { yr.filter { $0.state == st }.count }
        XCTAssertEqual(n(.up), 89); XCTAssertEqual(n(.down), 29); XCTAssertEqual(n(.held), 31)
        XCTAssertEqual(n(.stalled), 10); XCTAssertEqual(n(.best), 14); XCTAssertEqual(n(nil), 13)
    }

    func testE1RM() {
        XCTAssertEqual(Engine.e1rm(kg: 100, reps: 5), 100 * (1 + 5.0 / 30), accuracy: 0.001)
        XCTAssertEqual(Engine.e1rm(kg: nil, reps: 9), 9)
    }
}
