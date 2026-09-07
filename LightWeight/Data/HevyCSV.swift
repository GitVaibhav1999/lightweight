import Foundation

/// Pure parser for Hevy's "Export data" CSV. One row per set; sessions keyed by (title, start_time).
enum HevyCSV {
    struct Set { var index: Int; var type: String; var kg: Double?; var reps: Int?; var seconds: Int?; var rpe: Double? }
    struct Exercise { var name: String; var supersetID: String?; var notes: String?; var sets: [Set] }
    struct Session { var title: String; var start: Date; var end: Date; var key: String; var notes: String?; var exercises: [Exercise] }

    static let dateFormatter: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "d MMM yyyy, HH:mm"; return f
    }()

    static func parse(_ text: String) -> [Session] {
        let rows = parseCSV(text)
        guard let header = rows.first else { return [] }
        let col = Dictionary(uniqueKeysWithValues: header.enumerated().map { ($1, $0) })
        func f(_ r: [String], _ name: String) -> String { col[name].flatMap { $0 < r.count ? r[$0] : nil } ?? "" }

        var order: [String] = []
        var sessions: [String: Session] = [:]
        var exOrder: [String: [String]] = [:]
        var exercises: [String: [String: Exercise]] = [:]
        for r in rows.dropFirst() where r.count >= 10 {
            let title = f(r, "title"), startS = f(r, "start_time")
            let key = title + "|" + startS
            guard let start = dateFormatter.date(from: startS) else { continue }
            if sessions[key] == nil {
                order.append(key)
                let end = dateFormatter.date(from: f(r, "end_time")) ?? start
                sessions[key] = Session(title: title, start: start, end: end, key: key, notes: f(r, "description").isEmpty ? nil : f(r, "description"), exercises: [])
            }
            let name = f(r, "exercise_title")
            if exercises[key]?[name] == nil {
                exOrder[key, default: []].append(name)
                exercises[key, default: [:]][name] = Exercise(name: name, supersetID: f(r, "superset_id").isEmpty ? nil : f(r, "superset_id"), notes: f(r, "exercise_notes").isEmpty ? nil : f(r, "exercise_notes"), sets: [])
            }
            exercises[key]![name]!.sets.append(Set(index: Int(f(r, "set_index")) ?? 0, type: f(r, "set_type").isEmpty ? "normal" : f(r, "set_type"),
                                                 kg: Double(f(r, "weight_kg")), reps: Int(f(r, "reps")), seconds: Int(f(r, "duration_seconds")), rpe: Double(f(r, "rpe"))))
        }
        return order.map { k in
            var s = sessions[k]!
            s.exercises = (exOrder[k] ?? []).map { n in var e = exercises[k]![n]!; e.sets.sort { $0.index < $1.index }; return e }
            return s
        }.sorted { $0.start < $1.start }
    }

    /// Minimal RFC 4180 reader. Works on unicode scalars so "\r\n" is two characters, not one grapheme.
    static func parseCSV(_ text: String) -> [[String]] {
        var rows: [[String]] = [], row: [String] = [], field = "", inQuotes = false
        let scalars = Array(text.unicodeScalars)
        var i = 0
        func endRow() { row.append(field); field = ""; if row.contains(where: { !$0.isEmpty }) { rows.append(row) }; row = [] }
        while i < scalars.count {
            let c = scalars[i]
            if inQuotes {
                if c == "\"" {
                    if i + 1 < scalars.count, scalars[i + 1] == "\"" { field.unicodeScalars.append("\""); i += 2; continue }
                    inQuotes = false; i += 1; continue
                }
                field.unicodeScalars.append(c); i += 1
            } else {
                switch c {
                case "\"": inQuotes = true
                case ",": row.append(field); field = ""
                case "\r": break
                case "\n": endRow()
                default: field.unicodeScalars.append(c)
                }
                i += 1
            }
        }
        if !field.isEmpty || !row.isEmpty { endRow() }
        return rows
    }
}
