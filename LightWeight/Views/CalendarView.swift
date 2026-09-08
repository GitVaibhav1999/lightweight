import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// S8 — month view of what actually happened, Hevy import, pinned workout progression.
struct CalendarView: View {
    @Environment(AppStore.self) private var store
    @State private var month: Date = .now
    @State private var importing = false

    /// Split into children on purpose. When the month grid, the year strip, the pinned
    /// charts and 470 history rows all live in one body, any state touch re-evaluates the
    /// lot — tapping 6M/YEAR/ALL rebuilt the whole page. Each part now owns its own state,
    /// so a change reaches only what it affects. The pager renders this page twice, which
    /// doubles whatever is left.
    /// DEBUG bisect: tap the month title to cycle which sections render, so the section
    /// responsible for the scroll cost can be identified in one install instead of one
    /// build per hypothesis. Five reasoned fixes did not find it; this will.
    @AppStorage("cal.only") private var only = 0
    private var modes: [String] { ["all", "no history", "no charts", "no strip", "grid only"] }

    var body: some View {
        let _ = store.dataTick
        Screen(top: 102, underBar: true) {
            VStack(alignment: .leading, spacing: 0) {
                HeaderScroll(page: .calendar) {
                    VStack(alignment: .leading, spacing: 0) {
                        MonthHeading(month: month)
                        #if DEBUG
                        Button { only = (only + 1) % modes.count } label: {
                            Text("§ \(modes[only])").font(LWFont.mono(9)).tracking(1)
                                .foregroundStyle(LW.accent).padding(.vertical, 4)
                                .contentShape(Rectangle())
                        }.buttonStyle(.plain).accessibilityIdentifier("cal.bisect")
                        #endif
                        if only < 3 {
                            YearStrip(weeks: 53, cell: 5.2, radius: 1.7, rowGap: 2.6, fadeTo: 0.26)
                                .environment(store)
                                .padding(.top, 16)
                                .accessibilityIdentifier("year.strip")
                        }
                        MonthGrid(month: month).padding(.top, 16)
                        ImportReceipt()
                        if only < 2 { PinnedProgression() }
                        if only < 1 { AllHistory().padding(.top, 22) }
                        if store.finishedSessions().isEmpty { EmptyCalendarCard { importing = true } }
                        Color.clear.frame(height: 90)
                    }
                }.padding(.top, 4)
            }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.commaSeparatedText, .plainText, .data]) { result in
            guard case .success(let url) = result else { return }
            let ok = url.startAccessingSecurityScopedResource(); defer { if ok { url.stopAccessingSecurityScopedResource() } }
            if let text = try? String(contentsOf: url, encoding: .utf8) { store.importHevy(text: text) }
        }
        .onAppear { month = store.finishedSessions().last?.startedAt ?? store.today }
    }
}

/// Month name and the month's totals.
private struct MonthHeading: View {
    @Environment(AppStore.self) private var store
    let month: Date
    var body: some View {
        let cal = Calendar(identifier: .iso8601)
        let start = cal.dateInterval(of: .month, for: month)!.start
        let sessions = store.finishedSessions().filter { cal.isDate($0.startedAt, equalTo: start, toGranularity: .month) }
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(Fmt.date(start, "MMMM yyyy").uppercased()).font(LWFont.display(28, width: 88)).tracking(-0.6)
                Spacer()
            }.padding(.top, 18)
            Text("\(sessions.count) sessions · \(Fmt.hoursMinutes(sessions.reduce(0) { $0 + $1.durationMinutes }))")
                .font(LWFont.mono(11)).foregroundStyle(LW.ink(0.45)).padding(.top, 2)
        }
    }
}

/// Weekday letters plus the day cells for one month.
private struct MonthGrid: View {
    @Environment(AppStore.self) private var store
    let month: Date
    var body: some View {
        let cal = Calendar(identifier: .iso8601)
        let start = cal.dateInterval(of: .month, for: month)!.start
        let days = cal.range(of: .day, in: .month, for: start)!.count
        let lead = (cal.component(.weekday, from: start) + 5) % 7      // Monday-first
        let trained = Set(store.finishedSessions()
            .filter { cal.isDate($0.startedAt, equalTo: start, toGranularity: .month) }
            .map { cal.component(.day, from: $0.startedAt) })
        let todayDay = cal.isDate(store.today, equalTo: start, toGranularity: .month) ? cal.component(.day, from: store.today) : -1
        let cols = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)
        VStack(alignment: .leading, spacing: 0) {
            LazyVGrid(columns: cols, spacing: 0) {
                ForEach(Array("MTWTFSS".enumerated()), id: \.offset) { _, c in
                    Text(String(c)).font(LWFont.mono(9.5)).foregroundStyle(LW.ink(0.3))
                }
            }
            LazyVGrid(columns: cols, spacing: 3) {
                ForEach(-max(lead, 0)..<0, id: \.self) { _ in Color.clear.frame(height: 21) }
                ForEach(1...days, id: \.self) { d in
                    HStack(spacing: 3) {
                        Text("\(d)").font(LWFont.mono(11))
                            .foregroundStyle(d == todayDay ? LW.accent : trained.contains(d) ? LW.ink(0.9) : LW.ink(0.45))
                        Circle().fill(trained.contains(d) ? LW.accent : .clear).frame(width: 4, height: 4)
                    }
                    .frame(height: 21).frame(maxWidth: .infinity)
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(d == todayDay ? LW.accent : .clear, lineWidth: 1))
                }
            }.padding(.top, 4)
        }
    }
}

/// The receipt shown after an import, absent otherwise.
private struct ImportReceipt: View {
    @Environment(AppStore.self) private var store
    var body: some View {
        if let r = store.importReport {
            Text("Import review · \(r.imported) imported · \(r.skipped) already there · \(r.customCreated.count) custom")
                .font(LWFont.mono(10.5)).foregroundStyle(LW.ink(0.45))
                .padding(EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12))
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(LW.ink(0.25), style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
                .padding(.top, 12)
        }
    }
}

/// Pinned workout charts. Owns its own range so changing it cannot invalidate the rest
/// of the page — that alone was rebuilding the grid, the strip and every history row.
private struct PinnedProgression: View {
    @Environment(AppStore.self) private var store
    @State private var pinMonths: Int? = 12   // 6M / YEAR (default) / ALL (nil)
    var body: some View {
        let pinned = store.pinnedWorkouts()
        if !pinned.isEmpty {
            HStack {
                Text("Progression").lwLabel(10, tracking: 0.14)
                Spacer()
                HStack(spacing: 0) {
                    ForEach([("6M", 6), ("YEAR", 12), ("ALL", nil)], id: \.0) { label, m in
                        Button { pinMonths = m } label: {
                            Text(label).font(LWFont.mono(9)).tracking(0.6)
                                .foregroundStyle(pinMonths == m ? LW.inkOnAccent : LW.ink(0.5))
                                .padding(.horizontal, 9).frame(height: 22)
                                .background(Capsule().fill(pinMonths == m ? LW.accent : .clear))
                                .contentShape(Capsule())
                        }.buttonStyle(.plain)
                    }
                }.background(Capsule().fill(LW.ink(0.08)))
            }.padding(.top, 22)
            let pairs: [[Workout]] = stride(from: 0, to: pinned.count, by: 2).map { Array(pinned[$0..<min($0 + 2, pinned.count)]) }
            ForEach(Array(pairs.enumerated()), id: \.offset) { _, rowWs in
                HStack(alignment: .top, spacing: 10) {
                    ForEach(rowWs, id: \.id) { w in
                        let s = series(for: w, months: pinMonths)
                        ChartCard(chartHeight: 72, valueFormat: { String(format: "%.2f", $0) }, title: w.name,
                                  subtitle: "index", delta: s.delta, values: s.values, left: s.left, right: s.right, caption: s.caption)
                    }
                }.padding(.top, 10)
            }
        } else if !store.finishedSessions().isEmpty {
            Text("pin workouts on the Workouts page to chart them here")
                .font(LWFont.mono(10)).foregroundStyle(LW.ink(0.3)).padding(.top, 22)
        }
    }

    private func series(for w: Workout, months: Int?) -> SummaryView.Series {
        let all = store.analysis.indexSeries(group: w.id.uuidString)
        let ref = all.last?.date ?? store.today
        let pts = months.map { m in
            let since = Calendar.current.date(byAdding: .month, value: -m, to: ref)!
            return all.filter { $0.date >= since }
        } ?? all
        let vals = pts.map(\.index)
        let delta = (vals.first.flatMap { f in vals.last.map { l in f > 0 ? Fmt.pct((l - f) / f * 100) : "" } }) ?? ""
        return SummaryView.Series(values: vals, delta: delta, left: pts.first.map { Fmt.date($0.date, "MMM yy") } ?? "", right: pts.last.map { Fmt.date($0.date, "MMM yy") } ?? "", caption: "\(pts.count) sessions · \(months.map { "\($0) mo" } ?? "all time")")
    }
}

/// Every session, newest first, grouped by month — the design's "All history · 470 sessions".
struct AllHistory: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router
    /// A LazyVStack only defers the *body* of a row. Each row here owns a swipe gesture and
    /// its own state, and 470 of those is enough to stall the scroll on device. Render a page
    /// at a time and grow when the reader reaches the end.
    @State private var shown = pageSize
    private static let pageSize = 50

    var body: some View {
        let sessions = store.sessionsNewestFirst()
        let visible = sessions.prefix(shown)
        // Calendar.current builds a calendar on each access; this ran once per row.
        let cal = Calendar.current
        VStack(alignment: .leading, spacing: 0) {
            Text("All history · \(sessions.count) sessions").lwLabel(10, tracking: 0.14).padding(.bottom, 4)
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(Array(visible.enumerated()), id: \.element.id) { i, s in
                    if i == 0 || !cal.isDate(s.startedAt, equalTo: sessions[i - 1].startedAt, toGranularity: .month) {
                        Text(Fmt.date(s.startedAt, "MMMM yyyy") + " ↓").font(LWFont.mono(10)).foregroundStyle(LW.ink(0.3)).frame(height: 34, alignment: .bottomLeading).padding(.bottom, 4)
                    }
                    SwipeDeleteRow(onTap: { router.push(.summary(s.id)) }, onDelete: { store.deleteSession(s) }) {
                        HStack(spacing: 12) {
                            Text(s.title).font(LWFont.body(13.5)).foregroundStyle(LW.ink).lineLimit(1)
                            if s.edited { Text("EDITED").font(LWFont.mono(8.5)).tracking(0.8).foregroundStyle(LW.ink(0.4)) }
                            Spacer()
                            Text(Fmt.date(s.startedAt, "EEE d MMM")); Text("\(s.durationMinutes) min")
                            // Accent is earned here too: this row draws its own arrow rather
                            // than going through VerdictIcon, so it kept accenting every up.
                            let st = store.result(s)?.state
                            if st == .best {
                                Icon(kind: .arrowUp, size: 12, color: LW.accentBright, weight: 2)
                                    .shadow(color: LW.accentBright.opacity(0.7), radius: 4)
                            } else if st == .up {
                                Icon(kind: .arrowUp, size: 12, color: LW.ink(0.7), weight: 2)
                            } else { Color.clear.frame(width: 12, height: 12) }
                        }.font(LWFont.mono(11)).foregroundStyle(LW.ink(0.45)).frame(height: 42).overlay(alignment: .top) { Hairline() }.contentShape(Rectangle())
                    }
                }
                if shown < sessions.count {
                    // onAppear and onChange both fire for rows sitting in SwiftUI's off-screen
                    // render buffer, so either one cascaded the window to the end in a single
                    // pass. onScrollVisibilityChange fires on actual visibility inside the
                    // scroll view, so growing pushes the skeleton back out of view and it
                    // settles — which is what makes auto-load work without running away.
                    HistorySkeleton(rows: min(3, sessions.count - shown))
                        .onScrollVisibilityChange(threshold: 0.15) { visible in
                            guard visible else { return }
                            shown = min(shown + Self.pageSize, sessions.count)
                        }
                        .accessibilityIdentifier("history.more")
                        .accessibilityLabel("Loading older sessions")
                }
            }
        }
    }
}


/// Placeholder in the shape of the rows it precedes, so the list does not jump when they
/// arrive. Breathes rather than shimmers — a moving highlight over a long list is noise.
struct HistorySkeleton: View {
    var rows: Int
    @State private var dim = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        VStack(spacing: 0) {
            ForEach(0..<max(1, rows), id: \.self) { _ in
                HStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: 3).frame(width: 96, height: 9)
                    Spacer()
                    RoundedRectangle(cornerRadius: 3).frame(width: 62, height: 8)
                    RoundedRectangle(cornerRadius: 3).frame(width: 34, height: 8)
                }
                .foregroundStyle(LW.ink(dim ? 0.05 : 0.11))
                .frame(height: 42)
                .overlay(alignment: .top) { Hairline() }
            }
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.85).repeatForever(autoreverses: true)) { dim = true }
        }
    }
}

/// Swipe a row left to reveal Delete. The row and the button live in ONE strip that slides,
/// so the button is genuinely where it looks — an offset overlay never took the taps reliably.
struct SwipeDeleteRow<Content: View>: View {
    @Environment(Router.self) private var router
    var onTap: () -> Void
    var onDelete: () -> Void
    @ViewBuilder var content: Content
    @State private var open = false
    @State private var drag: CGFloat = 0
    @State private var sideways = false
    @State private var swiped = false
    private let reveal: CGFloat = 98

    var body: some View {
        let x = min(0, max(-reveal, (open ? -reveal : 0) + drag))
        // No GeometryReader. One per row forces a layout pass per row and defeats SwiftUI's
        // sizing shortcuts; at 50 rows — doubled by the pager — that was measurable in the
        // trace alongside the per-row gestures. Negative trailing padding hangs the Delete
        // button off the right edge instead of measuring the width to place it.
        Group {
            HStack(spacing: 0) {
                content
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if open || swiped { withAnimation(.easeOut(duration: 0.2)) { open = false } } else { onTap() }
                    }
                Button {
                    UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
                    withAnimation(.easeOut(duration: 0.2)) { open = false; drag = 0 }
                    onDelete()
                } label: {
                    Text("Delete").font(LWFont.body(13, weight: 700)).foregroundStyle(.white)
                        .padding(.horizontal, 14).frame(height: 34)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color(red: 0.88, green: 0.32, blue: 0.28)))
                        .frame(width: reveal, alignment: .trailing)
                        .contentShape(Rectangle())
                }.buttonStyle(.plain)
                .accessibilityIdentifier("history.delete")
            }
            .padding(.trailing, -reveal)
            .offset(x: x)
            .simultaneousGesture(
                DragGesture(minimumDistance: 6)
                    .onChanged { v in
                        if !sideways {
                            guard abs(v.translation.width) > 8 || abs(v.translation.height) > 8 else { return }
                            sideways = abs(v.translation.width) > abs(v.translation.height)
                            if sideways { router.pagingLocked = true }
                        }
                        if sideways { drag = v.translation.width; swiped = true }
                    }
                    .onEnded { v in
                        let settled = (open ? -reveal : 0) + (sideways ? v.translation.width : 0)
                        router.pagingLocked = false
                        sideways = false
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) { open = settled < -reveal / 2; drag = 0 }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { swiped = false }
                    }
            )
        }
        .frame(height: 42)
        .clipped()
        .accessibilityIdentifier("history.row")
    }
}

/// Year View §2 — GitHub-graph training strip: one column per ISO week, Mon-top, oldest left.
struct YearStrip: View {
    @Environment(AppStore.self) private var store
    var weeks: Int
    var cell: CGFloat
    var radius: CGFloat
    var rowGap: CGFloat
    var fadeTo: Double
    private static let bestFill = lwDyn(lwHex(0xC7D584), lwHex(0x3C4433))
    private static var iso: Calendar { var c = Calendar(identifier: .iso8601); c.firstWeekday = 2; return c }
    /// epochDay -> did any session that day set a record. Rebuilt only when the data
    /// changes: it costs a startOfDay per session, and the strip's body re-evaluates on
    /// every layout pass, including while scrolling.
    @State private var dayState: [Int: Bool] = [:]
    @State private var builtFor = -1

    /// A week is 7 days, always. Once the first column's epoch day is known every other
    /// cell is arithmetic — the old code asked Calendar for 371 dates and 371 startOfDays
    /// on each pass, which is what made the strip expensive rather than the session count.
    private func rebuild() {
        let cal = Self.iso
        dayState = Dictionary(
            store.finishedSessions().map { s in
                (Int(cal.startOfDay(for: s.startedAt).timeIntervalSince1970 / 86_400),
                 store.result(s)?.state == .best)
            }, uniquingKeysWith: { $0 || $1 })
        builtFor = store.dataTick
    }

    var body: some View {
        let cal = Self.iso
        let thisWeek = cal.dateInterval(of: .weekOfYear, for: store.today)!.start
        let firstEpoch = Int(cal.startOfDay(for: thisWeek).timeIntervalSince1970 / 86_400) - (weeks - 1) * 7
        let todayEpoch = Int(cal.startOfDay(for: store.today).timeIntervalSince1970 / 86_400)
        GeometryReader { g in
            let gap = max(0, (g.size.width - CGFloat(weeks) * cell) / CGFloat(weeks - 1))
            HStack(spacing: gap) {
                ForEach(0..<weeks, id: \.self) { c in
                    VStack(spacing: rowGap) {
                        ForEach(0..<7, id: \.self) { r in
                            let e = firstEpoch + c * 7 + r
                            let ramp = 0.5 + 0.42 * Double(c) / Double(weeks - 1)
                            ZStack {
                                if let best = dayState[e] {
                                    RoundedRectangle(cornerRadius: radius).fill(best ? AnyShapeStyle(Self.bestFill) : AnyShapeStyle(LW.accent(ramp)))
                                } else {
                                    RoundedRectangle(cornerRadius: radius).fill(LW.ink(e > todayEpoch ? 0.04 : 0.06))
                                }
                                if e == todayEpoch { RoundedRectangle(cornerRadius: radius).strokeBorder(LW.accent, lineWidth: 1.1) }
                            }.frame(width: cell, height: cell)
                        }
                    }
                }
            }
            .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: fadeTo), .init(color: .black, location: 1)],
                                 startPoint: .leading, endPoint: .trailing))
        }
        .frame(height: cell * 7 + rowGap * 6)
        .onAppear { if builtFor != store.dataTick { rebuild() } }
        .onChange(of: store.dataTick) { _, _ in rebuild() }
    }
}
