import Foundation

/// App ↔ widget bridge: compact month-calendar snapshot in the App Group store.
enum WidgetStore {
    static let suite = "group.com.vaibhavgautam.lightweight"
    static let key = "widget.snapshot"
}

struct WidgetDay: Codable {
    var epochDay: Int          // days since 1970, local calendar
    var sessions: Int
    var minutes: Int
    var best: Bool
}

struct WidgetSnapshot: Codable {
    var days: [WidgetDay]      // rolling year (53 ISO weeks), one entry per trained day
    var streak: Int?           // consecutive training weeks, current week counts once it has a session
    var nextUp: String?
    var nextUpLastDays: Int?   // days since that workout was last done
    var updated: Date
}
