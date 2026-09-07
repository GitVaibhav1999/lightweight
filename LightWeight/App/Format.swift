import Foundation

enum Fmt {
    static func kg(_ v: Double?) -> String {
        guard let v else { return "BW" }
        return v == v.rounded() ? String(format: "%.0f", v) : String(format: "%.2f", v).replacingOccurrences(of: #"\.?0+$"#, with: "", options: .regularExpression)
    }
    static func set(_ kg: Double?, _ reps: Int) -> String { "\(Self.kg(kg)) × \(reps)" }
    static func e1rm(_ v: Double) -> String { v == v.rounded() ? String(format: "%.0f", v) : String(format: "%.1f", v) }
    private static let intFormatter: NumberFormatter = { let f = NumberFormatter(); f.numberStyle = .decimal; f.maximumFractionDigits = 0; return f }()
    static func int(_ v: Double) -> String { intFormatter.string(from: NSNumber(value: v)) ?? "0" }
    static func index(_ v: Double) -> String { String(format: "%.2f", v) }
    static func pct(_ v: Double) -> String { String(format: "%@%.0f%%", v >= 0 ? "+" : "", v) }
    nonisolated(unsafe) private static var dateFormatters: [String: DateFormatter] = [:]
    static func date(_ d: Date, _ format: String) -> String {
        if let f = dateFormatters[format] { return f.string(from: d) }
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = format; dateFormatters[format] = f
        return f.string(from: d)
    }
    static func relative(_ d: Date, today: Date) -> String {
        let n = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: d), to: Calendar.current.startOfDay(for: today)).day ?? 0
        return n <= 0 ? "Today" : n == 1 ? "1 day" : "\(n) days"
    }
    /// "Lateral Raise (Dumbbell)" → "Lateral raise" — the card lists what you are about to do.
    static func shortExercise(_ s: String) -> String {
        let base = s.components(separatedBy: " (").first ?? s
        return base.prefix(1).uppercased() + base.dropFirst().lowercased()
    }
    /// Compact relative day for the home list: "today" · "4 d ago".
    static func ago(_ d: Date, today: Date) -> String {
        let n = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: d), to: Calendar.current.startOfDay(for: today)).day ?? 0
        return n <= 0 ? "today" : "\(n) d ago"
    }
    /// Display form of a workout name: uppercase, "and" → "&" like the board.
    static func title(_ s: String) -> String { s.replacingOccurrences(of: " and ", with: " & ").uppercased() }
    static func hoursMinutes(_ minutes: Int) -> String { "\(minutes / 60) h \(minutes % 60) m" }
}
