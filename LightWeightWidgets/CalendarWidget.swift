import WidgetKit
import SwiftUI
import CoreText

// MARK: mode-proof palette (Widget Handoff §3)
private struct Mode {
    let scheme: ColorScheme
    let rendering: WidgetRenderingMode
    var tinted: Bool { rendering != .fullColor }
    var ink: Color { tinted ? .white : scheme == .dark ? Color(red: 0xE7/255, green: 0xE5/255, blue: 0xD7/255) : Color(red: 0x1C/255, green: 0x1A/255, blue: 0x14/255) }
    var accent: Color { tinted ? .white : scheme == .dark ? Color(red: 0xAD/255, green: 0xBA/255, blue: 0x5E/255) : Color(red: 0x56/255, green: 0x60/255, blue: 0x49/255) }
    var trainedFill: Color { tinted ? .white.opacity(0.85) : accent }
    var onFill: Color { tinted ? .black : scheme == .dark ? Color(red: 0x14/255, green: 0x16/255, blue: 0x04/255) : Color(red: 0xF3/255, green: 0xEF/255, blue: 0xE7/255) }
    var bestFill: LinearGradient {
        if tinted { return LinearGradient(colors: [.white, .white], startPoint: .top, endPoint: .bottom) }
        return scheme == .dark
            ? LinearGradient(colors: [Color(red: 0xC7/255, green: 0xD5/255, blue: 0x84/255), Color(red: 0xAD/255, green: 0xBA/255, blue: 0x5E/255)], startPoint: .topLeading, endPoint: .bottomTrailing)
            : LinearGradient(colors: [Color(red: 0x6E/255, green: 0x7A/255, blue: 0x5E/255), Color(red: 0x4A/255, green: 0x53/255, blue: 0x40/255)], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

private func mono(_ size: CGFloat, semibold: Bool = false) -> Font { .custom(semibold ? "IBMPlexMono-SemiBold" : "IBMPlexMono-Regular", size: size) }
private func archivo(_ size: CGFloat, weight: CGFloat = 900, width: CGFloat = 85) -> Font {
    let attrs: [CFString: Any] = [kCTFontFamilyNameAttribute: "Archivo",
        kCTFontVariationAttribute: [NSNumber(value: 0x77676874 as UInt32): weight, NSNumber(value: 0x77647468 as UInt32): width] as CFDictionary]
    return Font(CTFontCreateWithFontDescriptor(CTFontDescriptorCreateWithAttributes(attrs as CFDictionary), size, nil))
}

// MARK: data
private struct CalEntry: TimelineEntry { let date: Date; let snap: WidgetSnapshot? }

private struct CalProvider: TimelineProvider {
    private func snapshotData() -> WidgetSnapshot? {
        guard let ud = UserDefaults(suiteName: WidgetStore.suite),
              let data = ud.data(forKey: WidgetStore.key) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }
    func placeholder(in context: Context) -> CalEntry { CalEntry(date: .now, snap: snapshotData()) }
    func getSnapshot(in context: Context, completion: @escaping (CalEntry) -> Void) { completion(CalEntry(date: .now, snap: snapshotData())) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<CalEntry>) -> Void) {
        let midnight = Calendar.current.startOfDay(for: .now).addingTimeInterval(86_400)
        completion(Timeline(entries: [CalEntry(date: .now, snap: snapshotData())], policy: .after(midnight)))
    }
}

// MARK: pieces
private struct WidgetLogoMark: View {   // the app's LogoMark, inlined (widget target is self-contained)
    var width: CGFloat = 16
    var color: Color
    var body: some View {
        let s = width / 32
        ZStack(alignment: .topLeading) {
            ForEach([(0.5, 5.0, 2.5, 8.0), (4.5, 2.0, 3.0, 14.0), (24.5, 2.0, 3.0, 14.0), (29.0, 5.0, 2.5, 8.0)], id: \.0) { x, y, w, h in
                RoundedRectangle(cornerRadius: s).fill(color).frame(width: w * s, height: h * s).offset(x: x * s, y: y * s)
            }
            Path { p in
                let pts: [(CGFloat, CGFloat)] = [(7.5, 10), (13, 6.5), (16, 11), (19.5, 6.5), (24.5, 10)]
                p.move(to: CGPoint(x: pts[0].0 * s, y: pts[0].1 * s)); for q in pts.dropFirst() { p.addLine(to: CGPoint(x: q.0 * s, y: q.1 * s)) }
            }.stroke(color, style: StrokeStyle(lineWidth: 2.4 * s, lineCap: .round, lineJoin: .round))
        }
        .frame(width: width, height: 18 * s, alignment: .topLeading)
    }
}

private struct DayCell: View {
    let day: Int
    let state: DayState
    let m: Mode
    enum DayState { case rest, trained, best, today, adjacent }
    var body: some View {
        ZStack {
            switch state {
            case .trained:
                RoundedRectangle(cornerRadius: 5.5).fill(m.trainedFill).frame(width: 15, height: 15)
                Text("\(day)").font(mono(8.5, semibold: true)).foregroundStyle(m.onFill)
            case .best:
                RoundedRectangle(cornerRadius: 5.5).fill(m.bestFill).frame(width: 15, height: 15)
                Text("\(day)").font(mono(8.5, semibold: true)).foregroundStyle(m.onFill)
                Image(systemName: "arrow.up.right").font(.system(size: 6, weight: .bold)).foregroundStyle(m.accent)
                    .offset(x: 8.5, y: -8.5)
            case .today:
                RoundedRectangle(cornerRadius: 5.5).strokeBorder(m.accent, lineWidth: 1).frame(width: 15, height: 15)
                Text("\(day)").font(mono(8.5)).foregroundStyle(m.ink.opacity(0.9))
            case .adjacent:
                Color.clear   // competitor-clean: no leading/trailing month numbers
            case .rest:
                Text("\(day)").font(mono(9)).foregroundStyle(m.ink.opacity(0.45))
            }
        }.frame(maxWidth: .infinity, minHeight: 20)
    }
}

private struct MonthGrid: View {
    let entry: CalEntry
    let m: Mode
    var body: some View {
        let cal = Calendar.current
        let start = cal.dateInterval(of: .month, for: entry.date)!.start
        let days = cal.range(of: .day, in: .month, for: start)!.count
        let lead = (cal.component(.weekday, from: start) + 5) % 7          // Monday-start
        let today = cal.component(.day, from: entry.date)
        let trained = Dictionary(uniqueKeysWithValues: (entry.snap?.days ?? []).map { ($0.epochDay, $0) })
        let firstEpoch = Int(cal.startOfDay(for: start).timeIntervalSince1970 / 86_400)
        let prevDays = cal.range(of: .day, in: .month, for: cal.date(byAdding: .month, value: -1, to: start)!)!.count
        let rows = Int(ceil(Double(lead + days) / 7))
        VStack(spacing: 3.5) {
            HStack(spacing: 0) {
                ForEach(Array("MTWTFSS".enumerated()), id: \.offset) { _, c in
                    Text(String(c)).font(mono(7.5)).foregroundStyle(m.ink.opacity(0.3)).frame(maxWidth: .infinity)
                }
            }
            ForEach(0..<rows, id: \.self) { r in
                HStack(spacing: 0) {
                    ForEach(0..<7, id: \.self) { c in
                        let i = r * 7 + c
                        if i < lead { DayCell(day: prevDays - lead + 1 + i, state: .adjacent, m: m) }
                        else if i - lead < days {
                            let d = i - lead + 1
                            let e = trained[firstEpoch + d - 1]
                            DayCell(day: d, state: e?.best == true ? .best : e != nil ? .trained : d == today ? .today : .rest, m: m)
                        } else { DayCell(day: i - lead - days + 1, state: .adjacent, m: m) }
                    }
                }
            }
        }
    }
}

private func monthStats(_ entry: CalEntry) -> (count: Int, minutes: Int) {
    let cal = Calendar.current
    let start = cal.dateInterval(of: .month, for: entry.date)!.start
    let firstEpoch = Int(cal.startOfDay(for: start).timeIntervalSince1970 / 86_400)
    let days = (entry.snap?.days ?? []).filter { $0.epochDay >= firstEpoch }
    return (days.reduce(0) { $0 + $1.sessions }, days.reduce(0) { $0 + $1.minutes })
}

// MARK: sizes
private struct SmallView: View {
    let entry: CalEntry; let m: Mode
    var body: some View {
        let stats = monthStats(entry)
        VStack(spacing: 4) {
            HStack(spacing: 5) {
                WidgetLogoMark(color: m.accent)
                Text(entry.date.formatted(.dateTime.month(.abbreviated)).uppercased()).font(mono(9)).foregroundStyle(m.ink.opacity(0.5))
                Spacer()
                (Text("\(stats.count)").foregroundStyle(m.accent) + Text(" workouts").foregroundStyle(m.ink.opacity(0.45))).font(mono(9, semibold: true))
            }
            MonthGrid(entry: entry, m: m)
        }
    }
}

private struct MediumView: View {
    let entry: CalEntry; let m: Mode
    var body: some View {
        let stats = monthStats(entry)
        HStack(spacing: 12) {
            VStack(spacing: 4) {
                HStack(spacing: 5) {
                    WidgetLogoMark(color: m.accent)
                    Text(entry.date.formatted(.dateTime.month(.wide)).uppercased()).font(mono(9)).foregroundStyle(m.ink.opacity(0.5))
                    Spacer()
                }
                MonthGrid(entry: entry, m: m)
            }.frame(width: 150)
            Rectangle().fill(m.ink.opacity(0.12)).frame(width: 0.7)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(stats.count)").font(archivo(36)).foregroundStyle(m.ink)
                Text("workouts · \(stats.minutes / 60)h \(stats.minutes % 60)m").font(mono(9)).foregroundStyle(m.ink.opacity(0.45))
                Spacer(minLength: 4)
                if let next = entry.snap?.nextUp {
                    Link(destination: URL(string: "lightweight://start")!) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("NEXT UP").font(mono(8, semibold: true)).tracking(0.8).foregroundStyle(m.ink.opacity(0.4))
                            Text(next.uppercased()).font(archivo(20)).foregroundStyle(m.accent).lineLimit(1).minimumScaleFactor(0.6)
                            if let d = entry.snap?.nextUpLastDays {
                                Text("last done \(d) day\(d == 1 ? "" : "s") ago").font(mono(8.5)).foregroundStyle(m.ink.opacity(0.4))
                            }
                        }
                    }
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct CalendarWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "CalendarWidget", provider: CalProvider()) { entry in
            CalendarWidgetView(entry: entry)
                .widgetURL(URL(string: "lightweight://calendar"))
        }
        .configurationDisplayName("Training Calendar")
        .description("Trained days, PR days, and what's next.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

private struct CalendarWidgetView: View {
    let entry: CalEntry
    @Environment(\.colorScheme) private var scheme
    @Environment(\.widgetRenderingMode) private var rendering
    @Environment(\.widgetFamily) private var family
    var body: some View {
        let m = Mode(scheme: scheme, rendering: rendering)
        Group { if family == .systemMedium { MediumView(entry: entry, m: m) } else { SmallView(entry: entry, m: m) } }
            .containerBackground(for: .widget) {
                (scheme == .dark ? Color.black : Color(red: 0xF3/255, green: 0xEF/255, blue: 0xE7/255))
            }
    }
}


// MARK: - Year strip widget (Year View Handoff §4) — systemMedium only
struct YearStripWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "YearWidget", provider: CalProvider()) { entry in
            YearWidgetView(entry: entry)
                .widgetURL(URL(string: "lightweight://calendar"))
        }
        .configurationDisplayName("Training Year")
        .description("26-week training strip with your week streak.")
        .supportedFamilies([.systemMedium])
    }
}

private struct YearWidgetView: View {
    let entry: CalEntry
    @Environment(\.colorScheme) private var scheme
    @Environment(\.widgetRenderingMode) private var rendering
    private static var iso: Calendar { var c = Calendar(identifier: .iso8601); c.firstWeekday = 2; return c }
    var body: some View {
        let m = Mode(scheme: scheme, rendering: rendering)
        let weeks = 26
        let cal = Self.iso
        let thisWeek = cal.dateInterval(of: .weekOfYear, for: entry.date)!.start
        let dayMap = Dictionary(uniqueKeysWithValues: (entry.snap?.days ?? []).map { ($0.epochDay, $0.best) })
        let todayEpoch = Int(cal.startOfDay(for: entry.date).timeIntervalSince1970 / 86_400)
        let best = m.tinted ? Color.white : (scheme == .dark ? Color(red: 0xCD/255, green: 0xE9/255, blue: 0xA9/255) : Color(red: 0x3C/255, green: 0x44/255, blue: 0x33/255))
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                WidgetLogoMark(width: 18, color: m.accent)
                (Text("\(entry.snap?.streak ?? 0)").foregroundStyle(m.accent) + Text(" WEEK STREAK").foregroundStyle(m.ink.opacity(0.4)))
                    .font(mono(11, semibold: true)).tracking(1.3)
                Spacer()
            }
            GeometryReader { g in
                let cell: CGFloat = 9, rowGap: CGFloat = 2.4
                let gap = max(0, (g.size.width - CGFloat(weeks) * cell) / CGFloat(weeks - 1))
                HStack(spacing: gap) {
                    ForEach(0..<weeks, id: \.self) { c in
                        let weekStart = cal.date(byAdding: .weekOfYear, value: c - weeks + 1, to: thisWeek)!
                        VStack(spacing: rowGap) {
                            ForEach(0..<7, id: \.self) { r in
                                let day = cal.date(byAdding: .day, value: r, to: weekStart)!
                                let e = Int(cal.startOfDay(for: day).timeIntervalSince1970 / 86_400)
                                let ramp = 0.5 + 0.42 * Double(c) / Double(weeks - 1)
                                ZStack {
                                    if let isBest = dayMap[e] {
                                        RoundedRectangle(cornerRadius: 2.8).fill(isBest ? AnyShapeStyle(best) : AnyShapeStyle(m.trainedFill.opacity(ramp)))
                                    } else {
                                        RoundedRectangle(cornerRadius: 2.8).fill(m.ink.opacity(e > todayEpoch ? 0.04 : 0.06))
                                    }
                                    if e == todayEpoch { RoundedRectangle(cornerRadius: 2.8).strokeBorder(m.accent, lineWidth: 1.1) }
                                }.frame(width: cell, height: cell)
                            }
                        }
                    }
                }
                .frame(height: cell * 7 + rowGap * 6)
                .frame(maxHeight: .infinity, alignment: .center)
                .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.18), .init(color: .black, location: 1)],
                                     startPoint: .leading, endPoint: .trailing))
            }
        }
        .containerBackground(for: .widget) {
            ZStack {
                scheme == .dark ? Color(red: 0x0A/255, green: 0x0A/255, blue: 0x0A/255) : Color(red: 0xF3/255, green: 0xEF/255, blue: 0xE7/255)
                RadialGradient(colors: [m.accent.opacity(0.12), .clear], center: UnitPoint(x: 0.5, y: -0.1), startRadius: 0, endRadius: 220)
            }
        }
    }
}

// MARK: — week widget: seven dots, today ringed, "3 / 7 THIS WEEK"

struct WeekWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "WeekWidget", provider: CalProvider()) { entry in
            WeekWidgetView(entry: entry)
                .widgetURL(URL(string: "lightweight://calendar"))
        }
        .configurationDisplayName("This Week")
        .description("The seven days behind you, and how many you trained.")
        .supportedFamilies([.systemSmall])
    }
}

private struct WeekWidgetView: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.widgetRenderingMode) private var rendering
    let entry: CalEntry

    /// Monday-first week containing today.
    private var week: [(letter: String, trained: Bool, isToday: Bool)] {
        var cal = Calendar.current
        cal.firstWeekday = 2
        let today = cal.startOfDay(for: .now)
        let start = cal.dateInterval(of: .weekOfYear, for: today)?.start ?? today
        let trainedDays = Set((entry.snap?.days ?? []).filter { $0.sessions > 0 }.map(\.epochDay))
        return (0..<7).map { i in
            let d = cal.date(byAdding: .day, value: i, to: start) ?? start
            let epoch = Int(cal.startOfDay(for: d).timeIntervalSince1970 / 86_400)
            return (["M", "T", "W", "T", "F", "S", "S"][i], trainedDays.contains(epoch), cal.isDate(d, inSameDayAs: today))
        }
    }

    var body: some View {
        let m = Mode(scheme: scheme, rendering: rendering)
        let days = week
        let done = days.filter(\.trained).count
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 7) {
                WidgetLogoMark(width: 18, color: m.accent)
                Text("7D").font(mono(11)).foregroundStyle(m.ink.opacity(0.5))
            }
            Spacer(minLength: 0)
            HStack(spacing: 0) {
                ForEach(Array(days.enumerated()), id: \.offset) { _, d in
                    VStack(spacing: 7) {
                        ZStack {
                            if d.trained { Circle().fill(m.trainedFill) }
                            else if d.isToday { Circle().strokeBorder(m.accent, lineWidth: 1.8) }
                            else { Circle().fill(m.ink.opacity(0.14)) }
                        }
                        .frame(width: 15, height: 15)
                        Text(d.letter).font(mono(9.5))
                            .foregroundStyle(d.isToday ? m.accent : m.ink.opacity(0.35))
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            Spacer(minLength: 0)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(done)").font(archivo(34)).foregroundStyle(m.accent)
                Text("/ 7 THIS WEEK").font(mono(11)).tracking(0.6).foregroundStyle(m.ink.opacity(0.45))
            }
        }
        .padding(.vertical, 2)
        .containerBackground(for: .widget) {
            (scheme == .dark ? Color.black : Color(red: 0xF3/255, green: 0xEF/255, blue: 0xE7/255))
        }
    }
}
