import Foundation

// MARK: - Inputs (plain structs so the engine is testable without SwiftData)

struct SetInput { var kg: Double?; var reps: Int?; var isWarmup: Bool = false; var done: Bool = true }
struct ExerciseInput { var exerciseID: String; var name: String; var sets: [SetInput] }
struct SessionInput {
    var id: UUID
    var groupKey: String        // same-workout grouping
    var title: String
    var start: Date
    var end: Date?
    var exercises: [ExerciseInput]
}

// MARK: - Outputs

enum Verdict: String { case up = "UP", down = "DOWN", held = "HELD" }
enum SessionState: String { case up = "UP", down = "DOWN", held = "HELD", stalled = "STALLED", best = "BEST" }
/// Per exercise, vs. its previous appearance. `best` = went up and set an all-time e1RM record.
enum ExerciseVerdict { case best, up, held, down }

struct PR: Equatable { let exerciseID: String; let setIndex: Int; let kg: Double?; let reps: Int; let e1rm: Double }

struct ExerciseSessionPoint {
    let sessionID: UUID; let date: Date
    let kg: Double?; let reps: Int; let e1rm: Double; let volume: Double
    var verdict: ExerciseVerdict?
}

struct SessionResult {
    let sessionID: UUID
    let groupKey: String
    let date: Date
    var verdict: Verdict?
    var state: SessionState?
    var delta: Double?          // mean % change of top-set e1RM over common exercises
    var index: Double?          // workout index (mean e1RM / baseline)
    var prs: [PR] = []
    var common = 0, of = 0
    var exerciseVerdicts: [String: ExerciseVerdict] = [:]
    var volume: Double = 0
    var upCount: Int { exerciseVerdicts.values.filter { $0 == .up || $0 == .best }.count }
    var bestCount: Int { exerciseVerdicts.values.filter { $0 == .best }.count }
}

struct Analysis {
    var results: [UUID: SessionResult] = [:]
    var ordered: [SessionResult] = []                       // chronological
    var exerciseHistory: [String: [ExerciseSessionPoint]] = [:]
    var bestE1RM: [String: Double] = [:]
    var sessionsPerGroup: [String: [SessionResult]] = [:]
}

// MARK: - Engine (PRD §6; mirrors scripts/verdict.py)

enum Engine {
    static let band = 1.0            // % — within it is HELD
    static let minCommon = 2
    static let minCoverage = 0.5
    static let stallWindow = 3
    static let prMinPrior = 3
    static let baselineN = 3

    /// Epley; bodyweight -> reps. Direction-only use, so its inaccuracy at high reps doesn't matter.
    static func e1rm(kg: Double?, reps: Int) -> Double {
        if let kg, kg > 0 { return kg * (1 + Double(reps) / 30) }
        return Double(reps)
    }

    static func topSet(_ sets: [SetInput]) -> (kg: Double?, reps: Int, e1rm: Double)? {
        let work = sets.filter { !$0.isWarmup && $0.done && ($0.reps ?? 0) > 0 }
        guard let best = work.max(by: { e1rm(kg: $0.kg, reps: $0.reps!) < e1rm(kg: $1.kg, reps: $1.reps!) }) else { return nil }
        return (best.kg, best.reps!, e1rm(kg: best.kg, reps: best.reps!))
    }

    static func volume(_ sets: [SetInput]) -> Double {
        sets.filter { !$0.isWarmup && $0.done }.reduce(0) { $0 + ($1.kg ?? 0) * Double($1.reps ?? 0) }
    }

    static func verdict(forDelta d: Double) -> Verdict { d > band ? .up : d < -band ? .down : .held }

    static func run(_ input: [SessionInput]) -> Analysis {
        var a = Analysis()
        let sessions = input.sorted { $0.start < $1.start }
        var baseline: [String: Double] = [:], firsts: [String: [Double]] = [:]
        var prBest: [String: Double] = [:], seen: [String: Int] = [:]
        var lastByGroup: [String: [String: Double]] = [:]     // group -> exerciseID -> top e1RM
        var recent: [String: [Verdict]] = [:]
        var bestIndex: [String: Double] = [:]

        for s in sessions {
            var cur: [String: Double] = [:]
            var r = SessionResult(sessionID: s.id, groupKey: s.groupKey, date: s.start)
            for ex in s.exercises {
                guard let top = topSet(ex.sets) else { continue }
                cur[ex.exerciseID] = top.e1rm
                r.volume += volume(ex.sets)
                // baseline for the workout index
                if baseline[ex.exerciseID] == nil {
                    firsts[ex.exerciseID, default: []].append(top.e1rm)
                    if firsts[ex.exerciseID]!.count == baselineN { baseline[ex.exerciseID] = median(firsts[ex.exerciseID]!) }
                }
                // per-set PRs
                var b = prBest[ex.exerciseID] ?? 0
                var gotPR = false
                for (i, st) in ex.sets.enumerated() where !st.isWarmup && st.done && (st.reps ?? 0) > 0 {
                    let v = e1rm(kg: st.kg, reps: st.reps!)
                    if v > b {
                        if (seen[ex.exerciseID] ?? 0) >= prMinPrior { r.prs.append(PR(exerciseID: ex.exerciseID, setIndex: i, kg: st.kg, reps: st.reps!, e1rm: v)); gotPR = true }
                        b = v
                    }
                }
                prBest[ex.exerciseID] = b
                seen[ex.exerciseID, default: 0] += 1
                // per-exercise verdict vs previous appearance
                var pv: ExerciseVerdict? = nil
                if let prev = a.exerciseHistory[ex.exerciseID]?.last {
                    pv = top.e1rm > prev.e1rm ? .up : top.e1rm < prev.e1rm ? .down : .held
                    if gotPR && pv == .up { pv = .best }
                }
                if let pv { r.exerciseVerdicts[ex.exerciseID] = pv }
                a.exerciseHistory[ex.exerciseID, default: []].append(ExerciseSessionPoint(sessionID: s.id, date: s.start, kg: top.kg, reps: top.reps, e1rm: top.e1rm, volume: volume(ex.sets), verdict: pv))
            }
            r.of = cur.count
            if let prev = lastByGroup[s.groupKey] {
                let common = cur.keys.filter { prev[$0] != nil }
                r.common = common.count
                if common.count >= minCommon && Double(common.count) >= minCoverage * Double(cur.count) {
                    let d = common.reduce(0.0) { $0 + (cur[$1]! - prev[$1]!) / prev[$1]! } / Double(common.count) * 100
                    r.delta = d
                    r.verdict = verdict(forDelta: d)
                }
            }
            let idxEx = cur.keys.filter { baseline[$0] != nil }
            if idxEx.count >= 2 { r.index = idxEx.reduce(0.0) { $0 + cur[$1]! / baseline[$1]! } / Double(idxEx.count) }
            if let v = r.verdict {
                var h = recent[s.groupKey, default: []]; h.append(v)
                var state = SessionState(rawValue: v.rawValue)!
                if h.count >= stallWindow && !h.suffix(stallWindow).contains(.up) { state = .stalled }
                if let idx = r.index, idx > (bestIndex[s.groupKey] ?? 0), v != .down { state = .best }
                r.state = state
                recent[s.groupKey] = Array(h.suffix(10))
            }
            if let idx = r.index { bestIndex[s.groupKey] = max(bestIndex[s.groupKey] ?? 0, idx) }
            lastByGroup[s.groupKey] = cur
            a.results[s.id] = r
            a.ordered.append(r)
            a.sessionsPerGroup[s.groupKey, default: []].append(r)
        }
        a.bestE1RM = prBest
        return a
    }

    static func median(_ xs: [Double]) -> Double {
        let s = xs.sorted(); let n = s.count
        return n % 2 == 1 ? s[n / 2] : (s[n / 2 - 1] + s[n / 2]) / 2
    }
}

// MARK: - Derived stats for screens

extension Analysis {
    struct ExerciseStats {
        var best: Double; var last: Double; var delta30: Double?          // Δ vs. the latest point ≥30 days before the last
        var streak: Int; var history: [ExerciseSessionPoint]               // chronological
        var lastVerdict: ExerciseVerdict?
    }

    func exerciseStats(_ id: String) -> ExerciseStats? {
        guard let h = exerciseHistory[id], let last = h.last else { return nil }
        var streak = 0
        for p in h.reversed() { if p.verdict == .up || p.verdict == .best { streak += 1 } else { break } }
        let ref = h.last { last.date.timeIntervalSince($0.date) >= 30 * 86400 }
        let d30 = ref.map { (last.e1rm - $0.e1rm) / $0.e1rm * 100 }
        return ExerciseStats(best: h.map(\.e1rm).max() ?? last.e1rm, last: last.e1rm, delta30: d30, streak: streak, history: h, lastVerdict: last.verdict)
    }

    /// Session volumes for a workout group, chronological. Zero-volume sessions (bodyweight-only) are not
    /// meaningful in a tonnage chart and would plunge it to zero, so they're skipped.
    func indexSeries(group: String, since: Date? = nil) -> [(date: Date, index: Double)] {
        (sessionsPerGroup[group] ?? []).compactMap { r in r.index.flatMap { (since == nil || r.date >= since!) ? (r.date, $0) : nil } }
    }
    func volumeSeries(group: String, since: Date? = nil) -> [(date: Date, volume: Double)] {
        (sessionsPerGroup[group] ?? []).filter { $0.volume > 0 && (since == nil || $0.date >= since!) }.map { ($0.date, $0.volume) }
    }
}
