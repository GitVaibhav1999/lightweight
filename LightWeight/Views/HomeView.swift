import SwiftUI
import SwiftData

/// S1 — routine-first Home: the loop is the hero, one card per workout in it, dual slider below.
struct HomeView: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router

    var body: some View {
        let routine = store.activeRoutine()
        let entries = routine?.orderedEntries ?? []
        let next = store.nextWorkout()
        let others = store.workouts().count - entries.count
        let _ = store.coachTick
        let _ = store.dataTick
        Screen(top: 102, underBar: true) {
            VStack(spacing: 0) {
                HeaderScroll(page: .home) {
                    VStack(alignment: .leading, spacing: 0) {
                        if let routine, !entries.isEmpty {
                            RoutineHero(routine: routine, next: next).padding(.top, 6)
                            if let read = store.insightRead("cycle-\(routine.cyclesCompleted)") {
                                CoachReadPanel(read: read, key: "cycle-\(routine.cyclesCompleted)", caption: store.insightCaption(),
                                               aid: "coach.insight", onReview: { router.show(.workouts) }).padding(.top, 14)
                            } else if store.coachFailed.contains("cycle-\(routine.cyclesCompleted)") {
                                Button { store.retryCycleInsight() } label: {
                                    HStack(spacing: 8) {
                                        CoachMark9c(size: 14)
                                        Text("insight failed: \(store.coachFailReason["cycle-\(routine.cyclesCompleted)"] ?? "unknown") · tap to retry")
                                            .font(LWFont.mono(10.5)).foregroundStyle(LW.ink(0.5)).lineLimit(1).minimumScaleFactor(0.7)
                                        Spacer()
                                    }.padding(.horizontal, 12).frame(height: 40)
                                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(AIMist.base.opacity(0.3), lineWidth: 1))
                                    .contentShape(Rectangle())
                                }.buttonStyle(.plain).accessibilityIdentifier("coach.insight.error").padding(.top, 14)
                            } else if store.coachPending.contains("cycle-\(routine.cyclesCompleted)") {
                                Group {
                                    if let streamed = store.coachStream["cycle-\(routine.cyclesCompleted)"], !streamed.isEmpty {
                                        CoachWritingPanel(cycle: routine.cyclesCompleted, text: streamed, caption: store.insightCaption())
                                    } else {
                                        CoachInsightLoading(cycle: routine.cyclesCompleted,
                                                            status: store.coachStatus["cycle-\(routine.cyclesCompleted)"] ?? "reading sessions…",
                                                            caption: store.insightCaption())
                                    }
                                }
                                .padding(.top, 14).transition(.opacity)
                            } else if routine.cyclesCompleted > 0 {
                                Button { store.ensureCycleInsight() } label: {
                                    HStack(spacing: 9) {
                                        CoachMark9c(size: 15)
                                        Text("CYCLE \(routine.cyclesCompleted) REPORT").font(LWFont.mono(10)).tracking(1.4).foregroundStyle(LW.ink(0.65))
                                        Spacer()
                                        Text("tap to generate").font(LWFont.mono(9.5)).foregroundStyle(AIMist.base)
                                        Icon(kind: .chevronDown, size: 12, color: LW.ink(0.4), weight: 2)
                                    }.padding(.horizontal, 13).frame(height: 40)
                                    .background(AIPanelBackground(alpha: 0.6))
                                    .contentShape(Rectangle())
                                }.buttonStyle(.plain).accessibilityIdentifier("coach.insight.ask").padding(.top, 14)
                            }
                            if let card = store.liveSession().flatMap({ store.workout($0.workoutID) }) ?? next {
                                NextUpCard(workout: card).padding(.top, 16)
                            }
                        } else {
                            EmptyHome().padding(.top, 4)
                        }
                        if !entries.isEmpty { Text("This cycle").lwLabel(10, tracking: 0.16, color: LW.ink(0.35)).padding(.top, 22).padding(.bottom, 2) }
                        ForEach(Array(entries.enumerated()), id: \.element.persistentModelID) { i, e in
                            if let w = store.workout(e.workoutID) {
                                WorkoutCard(workout: w, isNext: w.id == next?.id, pending: i > (routine?.pointer ?? 0))
                            }
                        }
                        if !entries.isEmpty { Hairline() }
                        if others > 0, !entries.isEmpty {
                            Button { router.show(.workouts) } label: {
                                Text("+ \(others) more workout\(others == 1 ? "" : "s") →")
                                    .font(LWFont.mono(11)).foregroundStyle(LW.ink(0.4))
                                    .frame(maxWidth: .infinity, alignment: .leading).frame(height: 40).contentShape(Rectangle())
                            }.buttonStyle(.plain)
                        }
                        Color.clear.frame(height: 64)
                    }
                }                .padding(.top, 0)
            }
        }
    }

    /// Loop order starting at the pointer (next first).
    private func rotated(_ entries: [RoutineEntry], _ r: Routine?) -> [RoutineEntry] {
        guard let r, !entries.isEmpty else { return entries }
        let p = r.pointer % entries.count
        return Array(entries[p...] + entries[..<p])
    }
}

/// "Hevy split · cycle 27 · 3/4 done" + segment bars + index trend + last/best/next-beat numbers.
struct RoutineHero: View {
    @Environment(AppStore.self) private var store
    let routine: Routine
    let next: Workout?

    var body: some View {
        let progress = store.routineProgress()
        let vols = store.cycleVolumes()
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(vols.closed && routine.cyclesCompleted > 0 ? "\(routine.name) · cycle \(routine.cyclesCompleted) closed" : "\(routine.name) · cycle \(progress?.cycle ?? 1)").lwLabel(10, tracking: 0.16, color: LW.ink(0.4))
                Spacer()
                Text("\(progress?.done ?? 0) OF \(progress?.total ?? 0) DONE").font(LWFont.mono(10)).tracking(1).foregroundStyle(LW.accent)
            }
            HStack(spacing: 5) {
                ForEach(0..<(progress?.total ?? 0), id: \.self) { i in
                    Capsule().fill(i < (progress?.done ?? 0) ? LW.accent : LW.ink(0.1))   // done · next (outlined) · remaining track
                        .overlay(Capsule().strokeBorder(i == progress?.done ? LW.accent(0.6) : .clear, lineWidth: 1))
                        .frame(height: 2.5)
                }
            }
            if vols.current > 0 || vols.prevBest != nil {
            HStack(alignment: .top) {
                stat(grouped(vols.current), "CYCLE VOL", accent: true, align: .leading)
                Spacer(minLength: 12)
                stat(vols.prevBest.map { grouped($0) } ?? "—", "CYCLE BEST", accent: false, align: .trailing)
            }.padding(.top, 8)
            }
        }
        .accessibilityElement(children: .contain).accessibilityIdentifier("routine.hero")
    }
    private func stat(_ v: String, _ l: String, accent: Bool, align: HorizontalAlignment) -> some View {
        VStack(alignment: align, spacing: 2) {
            Text(v).font(LWFont.mono(15, semibold: true)).foregroundStyle(accent ? LW.accent : LW.ink)
                .lineLimit(1).minimumScaleFactor(0.6)
            Text(l).font(LWFont.mono(9)).tracking(1.2).foregroundStyle(LW.ink(0.3))
        }
    }
    private func grouped(_ v: Double) -> String {
        let f = NumberFormatter(); f.numberStyle = .decimal; f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: v)) ?? "0"
    }
}

/// 10a — the next workout is the page's centre of gravity: what it is, what it costs, one START.
struct NextUpCard: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router
    let workout: Workout
    var body: some View {
        let s = store.workoutStats(workout.id)
        let sets = workout.orderedSlots.reduce(0) { $0 + $1.sets }
        let live = store.liveSession()
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text(live == nil ? "NEXT UP" : "IN PROGRESS").font(LWFont.mono(10)).tracking(1.8).foregroundStyle(LW.accent)
                Spacer()
                Button { router.push(.workoutEdit(workout.id)) } label: {
                    Icon(kind: .more, size: 18, color: LW.ink(0.35), weight: 2.4)
                        .frame(width: 36, height: 26).contentShape(Rectangle())
                }.buttonStyle(.plain)
                .accessibilityIdentifier("next.more").accessibilityLabel("Edit \(workout.name)")
            }
            Text(Fmt.title(workout.name))
                .font(LWFont.display(23, width: 85)).tracking(-0.6)
                .lineLimit(2).minimumScaleFactor(0.6).fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)
                .background(GeometryReader { g in Color.clear
                    .onAppear { router.heroNameFrame = g.frame(in: .global) }
                    .onChange(of: g.frame(in: .global)) { _, f in router.heroNameFrame = f } })
            Text(meta(s, sets)).font(LWFont.mono(10.5)).foregroundStyle(LW.ink(0.42))
                .lineLimit(1).minimumScaleFactor(0.7).padding(.top, 8)
            Text(exerciseLine).font(LWFont.mono(10.5)).foregroundStyle(LW.ink(0.5))
                .lineLimit(2).fixedSize(horizontal: false, vertical: true).padding(.top, 6)
            if let live {                                     // same box, now the way back in
                Button { router.present(.session(live.id)) } label: {
                    HStack(spacing: 10) {
                        PulseDot(size: 6)
                        Text("Resume").font(LWFont.heading(20, width: 92)).tracking(-0.2).foregroundStyle(LW.accent)
                        Spacer(minLength: 8)
                        LiveTimer(since: live.startedAt, size: 12)
                        Text("\(Int((AppStore.progress(live) * 100).rounded()))%")
                            .font(LWFont.mono(12, semibold: true)).foregroundStyle(LW.accent)
                    }
                    .padding(.horizontal, 15)
                    .frame(maxWidth: .infinity).frame(height: 48)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(LW.accent(0.55), lineWidth: 1.2))
                    .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }.buttonStyle(.plain).padding(.top, 13)
                .accessibilityIdentifier("home.resume").accessibilityLabel("Resume \(workout.name)")
            } else {
                Button { router.startRequest = workout.id } label: {
                    HStack(spacing: 9) {
                        BoltShape().fill(LW.inkOnAccent).frame(width: 13, height: 18)
                        Text("Start").font(LWFont.heading(20, width: 92)).tracking(-0.2).foregroundStyle(LW.inkOnAccent)
                    }
                    .frame(maxWidth: .infinity).frame(height: 48)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(LW.accent))
                    .shadow(color: LW.accent(0.35), radius: 12, y: 2)        // a glow, kept inside the card
                }.buttonStyle(.plain).padding(.top, 13)
                .accessibilityIdentifier("home.start").accessibilityLabel("Start \(workout.name)")
            }
        }
        .padding(13)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(LinearGradient(colors: [LW.accent(0.14), LW.accent(0.05)], startPoint: .top, endPoint: .bottom)))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(LW.accent(0.4), lineWidth: 1))
        .accessibilityElement(children: .contain).accessibilityIdentifier("next.card")
    }
    /// "Lateral raise · Overhead press · Bicep curl · +2"
    private var exerciseLine: String {
        let names = workout.orderedSlots.map { Fmt.shortExercise($0.exerciseName) }
        let head = names.prefix(3).joined(separator: " · ")
        return names.count > 3 ? head + " · +\(names.count - 3)" : head
    }
    private func meta(_ s: AppStore.WorkoutStats, _ sets: Int) -> String {
        var t = "\(workout.orderedSlots.count) EX · \(sets) SETS"
        if s.lastVolume > 0 { t += " · last \(Fmt.int(s.lastVolume)) kg" }
        if let d = s.lastDate { t += " · \(Fmt.ago(d, today: store.today))" }
        return t
    }
}

/// The board's 300×96 hero chart: dashed BEST line, area, faint line, sage end dot. No y labels.
struct RoutineChart: View {
    let values: [Double]
    let best: Double
    var body: some View {
        GeometryReader { g in
            let lo = (values.min() ?? 0), hi = max(values.max() ?? 1, best)
            let span = max(hi - lo, 0.001)
            let pts = values.enumerated().map { i, v in
                CGPoint(x: CGFloat(i) * g.size.width / CGFloat(max(values.count - 1, 1)),
                        y: 14 + (1 - CGFloat((v - lo) / span)) * (g.size.height - 22))
            }
            let bestY = 14 + (1 - CGFloat((best - lo) / span)) * (g.size.height - 22)
            ZStack(alignment: .topLeading) {
                Path { p in p.move(to: CGPoint(x: 0, y: bestY)); p.addLine(to: CGPoint(x: g.size.width, y: bestY)) }
                    .stroke(LW.accent(0.35), style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
                Text("BEST \(Fmt.index(best))").font(LWFont.mono(8.5)).foregroundStyle(LW.accent(0.7)).offset(y: bestY - 12)
                if pts.count > 1 {
                    Path { p in p.move(to: CGPoint(x: pts[0].x, y: g.size.height)); p.addLine(to: pts[0]); for q in pts.dropFirst() { p.addLine(to: q) }; p.addLine(to: CGPoint(x: pts.last!.x, y: g.size.height)); p.closeSubpath() }
                        .fill(LW.accent(0.08))
                    Path { p in p.move(to: pts[0]); for q in pts.dropFirst() { p.addLine(to: q) } }
                        .stroke(LW.ink(0.35), style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))
                }
                if let e = pts.last { Circle().fill(LW.accent).frame(width: 7, height: 7).position(e) }
            }
        }
        .frame(height: 96)
    }
}

/// One workout of the loop: NAME · sparkline · when — verdict arrows · "3/6 up · vol · best".
struct WorkoutCard: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router
    let workout: Workout
    let isNext: Bool
    var pending = false            // later in the loop than the next workout — dimmed, not yet earned
    var body: some View {
        let s = store.workoutStats(workout.id)
        let series = (store.analysis.sessionsPerGroup[workout.id.uuidString] ?? []).map(\.volume)
        Button { if let last = s.last { router.push(.summary(last.id)) } } label: {
            VStack(alignment: .leading, spacing: 5) {
                Hairline()
                HStack(spacing: 7) {
                    Text(Fmt.title(workout.name)).font(LWFont.heading(15, width: 88)).tracking(-0.1)
                        .foregroundStyle(pending ? LW.ink(0.55) : LW.ink)
                        .lineLimit(1).minimumScaleFactor(0.62)
                    if let r = s.lastResult, let last = s.last { VerdictIcon(verdict: overall(r, last), size: 13) }
                    Spacer(minLength: 8)
                    Sparkline(values: series, lastIsBest: s.lastResult?.state == .best)
                }.padding(.top, 12)
                Text(sub(s)).font(LWFont.mono(10)).foregroundStyle(store.liveSession()?.workoutID == workout.id ? LW.accent : LW.ink(0.35))
                    .lineLimit(1).minimumScaleFactor(0.8).padding(.bottom, 14)
            }.contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("workout.card").accessibilityLabel(workout.name)
    }
    /// "5 EX · 2 d ago" — what it costs and when you last did it.
    private func sub(_ s: AppStore.WorkoutStats) -> String {
        let ex = "\(workout.orderedSlots.count) EX"
        if store.liveSession()?.workoutID == workout.id { return "\(ex) · live now" }
        guard let d = s.lastDate else { return "\(ex) · no sessions yet" }
        return "\(ex) · \(Fmt.ago(d, today: store.today))"
    }
    /// One arrow for the whole workout: up if anything moved, down only if nothing did.
    /// A workout's best is the workout's own record — its index beating the best that group
    /// has ever posted — not "one lift PR'd". Those are different claims, and reading the
    /// second as the first lit almost every session, which is how the accent lost its meaning.
    /// A single PR inside an otherwise ordinary session is an up here; the lift keeps its own
    /// best on the summary and exercise pages, where the claim is about that lift.
    private func overall(_ r: SessionResult, _ last: Session) -> ExerciseVerdict {
        if r.state == .best { return .best }
        let vs = last.orderedExercises.compactMap { r.exerciseVerdicts[$0.exerciseID] }
        if vs.contains(.up) || vs.contains(.best) { return .up }
        return vs.contains(.down) && !vs.contains(.held) ? .down : .held
    }
    private func summary(_ r: SessionResult, _ s: AppStore.WorkoutStats, count: Int) -> String {
        var t = "\(r.upCount) / \(count) up"
        if r.bestCount > 0 { t += " · \(r.bestCount) best" }
        if s.lastVolume > 0 { t += " · vol \(Fmt.int(s.lastVolume))" }
        if s.bestVolume > 0 { t += " · best \(Fmt.int(s.bestVolume))" }
        return t
    }
}

/// The one fixed header: page icon · date · week dots (→ calendar), hairline underneath.
/// It never scrolls or swipes — only the icon changes with the page.
struct PageHeader: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router
    @AppStorage("appearance.mode") private var appearanceMode = "system"
    @Environment(\.colorScheme) private var scheme
    let page: Page
    var edit: Binding<Bool>? = nil     // when set, the page icon becomes the edit toggle
    @State private var pressing = false
    @State private var flipped = false  // this touch already flipped the theme — don't also open Account
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                HStack(spacing: 9) {
                    if let edit {
                        EditTrigger(editing: edit)
                    } else {
                        icon.frame(width: 24, height: 20).id(page).transition(.opacity)
                            .background { RoundedRectangle(cornerRadius: 10, style: .continuous)   // tint overflows: the header keeps its layout
                                .fill(LW.accent(pressing ? 0.12 : 0)).frame(width: 44, height: 32) }
                            .contentShape(Rectangle().inset(by: -10))
                            .accessibilityIdentifier(page == .home ? "home.logo" : "header.icon.\(page)")
                            .accessibilityLabel("Account")
                            .accessibilityValue(page == .home ? appearanceMode : "")
                            .accessibilityAddTraits(.isButton)
                            .accessibilityAction { router.openAccount() }
                            .gesture(markGesture)
                    }
                    if let edit, edit.wrappedValue {
                        Text("EDITING · TAP ✓ WHEN DONE").lwLabel(11, tracking: 0.12, color: LW.accent)
                    } else if page == .calendar {
                        (Text("\(store.weekStreak())").foregroundStyle(LW.accent)
                         + Text(" WEEK STREAK").foregroundStyle(LW.ink(0.45)))
                            .font(LWFont.mono(11)).tracking(1.3).textCase(.uppercase)
                            .accessibilityIdentifier("calendar.streak")
                    } else {
                        Text(Fmt.date(store.today, "EEE d MMM")).lwLabel(11, tracking: 0.12, color: LW.ink(0.45))
                    }
                }
                Spacer()
                Button { router.show(.calendar) } label: {          // the week reads the same on every page
                    HStack(spacing: 8) {
                        Text("7D").font(LWFont.mono(9, semibold: true)).tracking(1.0).foregroundStyle(LW.ink(0.35))
                        WeekDots(trained: trainedLast7())
                    }.contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityIdentifier("home.week")
            }.frame(height: 26)
        }
        .animation(.easeOut(duration: 0.2), value: page)
        .accessibilityElement(children: .contain).accessibilityIdentifier("header.\(page)")
    }
    /// Tap opens Account, hold still flips the theme — one gesture so the hold never also taps.
    private var markGesture: some Gesture {
        LongPressGesture(minimumDuration: 0.4)
            .onEnded { _ in
                guard page == .home else { return }
                flipped = true
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                let darkNow = appearanceMode == "dark" || (appearanceMode == "system" && scheme == .dark)
                ThemeFlip.run(to: darkNow ? "light" : "dark")   // reveal spreads from the logo
            }
            .simultaneously(with: DragGesture(minimumDistance: 0)
                .onChanged { _ in pressing = true }
                .onEnded { v in
                    pressing = false
                    if !flipped, abs(v.translation.width) < 10, abs(v.translation.height) < 10 {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        router.openAccount()
                    }
                    flipped = false
                })
    }

    @ViewBuilder private var icon: some View {
        switch page {
        case .home: LogoMark(width: 24)
        case .workouts: Icon(kind: .list, size: 20, color: LW.accent)
        case .calendar: Icon(kind: .calendar, size: 19, color: LW.accent)
        }
    }
    /// Rolling last-7-days window; index 6 = today (rightmost dot).
    private func trainedLast7() -> Set<Int> {
        let cal = Calendar.current
        let today = cal.startOfDay(for: store.today)
        return Set(store.finishedSessions().compactMap { s in
            let d = cal.dateComponents([.day], from: cal.startOfDay(for: s.startedAt), to: today).day ?? 99
            return (0...6).contains(d) ? 6 - d : nil })
    }
}

/// Last 7 days: filled = trained, outline = missed; rightmost = today, ringed thin white.
struct WeekDots: View {
    let trained: Set<Int>
    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<7, id: \.self) { i in
                Group {
                    if trained.contains(i) { Circle().fill(LW.accent) }
                    else { Circle().strokeBorder(LW.ink(0.28), lineWidth: 1) }
                }
                .frame(width: 5, height: 5)
                .overlay { if i == 6 { Circle().strokeBorder(LW.ink(0.85), lineWidth: 1).frame(width: 11, height: 11) } }
            }
        }.padding(.vertical, 6)
    }
}
