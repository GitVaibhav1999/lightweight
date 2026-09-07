import Foundation
import ActivityKit

/// Live Activity contract shared by the app and the widget extension.
struct WorkoutActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var progress: Double     // 0…1 of working sets done
        var startedAt: Date      // timer base
        var nextExercise: String?   // next unchecked set — nil when everything is done
        var nextDetail: String?     // "SET 2 · 80 KG × 8"
        // Session Updates §2 — lockscreen banner
        var exercise: String?       // current set's exercise, uppercase
        var kg: String?             // primary numbers, prefilled
        var reps: String?
        var setNo: Int?
        var setTotal: Int?
        var isNextExercise: Bool?   // upcoming set starts a different exercise -> "NEXT ·" prefix
        var logged: Bool?           // sage full-surface flash after the tick
        var restEndsAt: Date? = nil // Session V2: rest countdown target — headline swaps to "0:42 · NEXT kg × reps"
    }
    var workoutName: String
}
