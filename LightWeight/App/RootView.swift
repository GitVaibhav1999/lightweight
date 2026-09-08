import SwiftUI

struct RootView: View {
    @Environment(AppStore.self) private var store
    @State private var router = Router()
    @State private var auth = AuthState()
    @AppStorage("appearance.mode") private var appearanceMode = "system"
    private var appearanceScheme: ColorScheme? { appearanceMode == "light" ? .light : appearanceMode == "dark" ? .dark : nil }

    var body: some View {
        @Bindable var router = router
        ZStack {
            ZStack(alignment: .top) {
                PagerView()
                    .safeAreaInset(edge: .bottom) { Color.clear.frame(height: 56) }   // the nav row is part of every page's safe area
                PageHeader(page: router.page, edit: router.page == .workouts ? $router.workoutsEditing : nil)
                    .padding(.horizontal, LW.screenPad)
                    .padding(.top, LW.topPad)
                    .padding(.bottom, 10)
            }
            .background(LW.bg)
            .ignoresSafeArea(.container, edges: [.top, .bottom])
            .overlay(alignment: .bottomTrailing) {
                if router.stack.isEmpty {
                    NavBar().padding(.bottom, 4).transition(.opacity.combined(with: .offset(y: 8)))
                }
            }
            .overlay {
                if router.stack.isEmpty, router.page == .home { StartLayer() }
            }
            if let top = router.stack.last {
                screen(top).id(top).transition(transition(top)).zIndex(10)
            }
            if let name = router.splash { SplashView(workoutName: name).transition(.opacity).zIndex(50) }
            if let fid = router.finishSplash, let fs = store.anySession(fid) {
                FinishSplash(session: fs).transition(.opacity).zIndex(60)
            }
            if !auth.isSignedIn { LoginView().transition(.opacity).zIndex(70) }
        }
        .sheet(isPresented: $router.startSheet) { StartSheet().environment(router) }
        .environment(router)
        .environment(auth)
        .preferredColorScheme(appearanceScheme)
        .background(LW.bg.ignoresSafeArea())
        .onAppear(perform: applyDebugScreen)
        .onAppear(perform: applyAppearance)
        .onChange(of: appearanceMode) { _, _ in applyAppearance() }
        .onOpenURL { url in
            switch url.host ?? url.absoluteString {
            case "calendar": router.stack = []; router.page = .calendar
            case "start": router.stack = []; router.page = .home
            default: break
            }
        }
    }

    @ViewBuilder private func screen(_ r: Route) -> some View {
        switch r {
        case .session(let id): ActiveSessionView(sessionID: id)
        case .summary(let id): SummaryView(sessionID: id)
        case .exercise(let id): ExerciseDetailView(exerciseID: id)
        case .workoutEdit(let id): WorkoutEditView(workoutID: id)
        case .picker(let t): ExercisePickerView(target: t)
        case .account: AccountView()
        }
    }

    /// The account page is the one screen that arrives from the side, not from underneath.
    private func transition(_ r: Route) -> AnyTransition {
        r == .account ? .move(edge: .leading) : .opacity.combined(with: .offset(y: 6))
    }

    /// §4 override at the UIKit window level — dynamic UIColors and the status bar follow the trait, not just the SwiftUI environment.
    private func applyAppearance() {
        let style: UIUserInterfaceStyle = appearanceMode == "light" ? .light : appearanceMode == "dark" ? .dark : .unspecified
        for case let ws as UIWindowScene in UIApplication.shared.connectedScenes {
            for w in ws.windows { w.overrideUserInterfaceStyle = style }
        }
    }

    /// `--screen s0…s8` mirrors the design board's `?screen=` so every frame can be screenshotted directly.
    /// `--focus on|off` pins which live-session view opens, since the switch is a sticky user preference.
    private func applyDebugScreen() {
        #if DEBUG
        let args = CommandLine.arguments
        if let f = args.firstIndex(of: "--focus"), f + 1 < args.count {
            UserDefaults.standard.set(args[f + 1] == "on", forKey: FocusMode.key)
        }
        guard let i = args.firstIndex(of: "--screen"), i + 1 < args.count else { return }
        let next = store.nextWorkout(); let last = store.sessionsNewestFirst().first
        switch args[i + 1] {
        case "s0": router.startSheet = true
        case "s2": if let s = store.draftSession() ?? next.map({ store.startSession(from: $0) }) { router.stack = [.session(s.id)] }
        case "s3": if let last { router.stack = [.summary(last.id)] }
        case "s4": if let id = last?.orderedExercises.first?.exerciseID { router.stack = [.exercise(id)] }
        case "s5": router.page = .workouts
        case "s6": if let next { router.page = .workouts; router.stack = [.workoutEdit(next.id)] }
        case "s7": if let next { router.page = .workouts; router.stack = [.workoutEdit(next.id), .picker(.workout(next.id))] }
        case "s8": router.page = .calendar
        case "s9": router.stack = [.account]
        default: break
        }
        #endif
    }
}

/// Telegram-style theme switch: freeze the old look in a snapshot, flip the window style underneath,
/// then erase the snapshot through a circle growing from the top-left logo.
enum ThemeFlip {
    static func run(to mode: String) {
        let style: UIUserInterfaceStyle = mode == "light" ? .light : mode == "dark" ? .dark : .unspecified
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        guard let ws = scenes.first, let window = ws.keyWindow ?? ws.windows.first,
              !UIAccessibility.isReduceMotionEnabled,
              let snap = window.snapshotView(afterScreenUpdates: false) else {
            UserDefaults.standard.set(mode, forKey: "appearance.mode")
            scenes.flatMap(\.windows).forEach { $0.overrideUserInterfaceStyle = style }
            return
        }
        window.addSubview(snap)
        UserDefaults.standard.set(mode, forKey: "appearance.mode")
        scenes.flatMap(\.windows).forEach { $0.overrideUserInterfaceStyle = style }

        let origin = CGPoint(x: LW.screenPad + 14, y: window.safeAreaInsets.top + 16)   // the logo
        let b = window.bounds
        let endR = hypot(max(origin.x, b.width - origin.x), max(origin.y, b.height - origin.y)) + 40
        func holed(_ r: CGFloat) -> CGPath {
            let p = UIBezierPath(rect: b)
            p.append(UIBezierPath(ovalIn: CGRect(x: origin.x - r, y: origin.y - r, width: 2 * r, height: 2 * r)))
            return p.cgPath
        }
        let mask = CAShapeLayer()
        mask.fillRule = .evenOdd
        mask.path = holed(endR)
        snap.layer.mask = mask
        let anim = CABasicAnimation(keyPath: "path")
        anim.fromValue = holed(0.1); anim.toValue = holed(endR)
        anim.duration = 0.55
        anim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        CATransaction.begin()
        CATransaction.setCompletionBlock { snap.removeFromSuperview() }
        mask.add(anim, forKey: "reveal")
        CATransaction.commit()
    }
}

/// 3b — bottom navigation: glass pill with the three pages, plus the detached start circle.
/// The active tab expands into a solid sage lozenge; it is the page indicator (no page dots).
struct NavBar: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router
    @State private var innerW: CGFloat = 0       // width of the three cells, for finger → position maths
    @State private var fingerX: CGFloat?         // live finger position; nil = settled on the current page
    @State private var lastCell = -1             // last cell the finger crossed, for the tick
    private let order: [Page] = [.home, .workouts, .calendar]

    var body: some View {
        let cell = innerW / CGFloat(order.count)
        let restX = cell * (CGFloat(order.firstIndex(of: router.page) ?? 0) + 0.5)
        let x = fingerX.map { min(innerW - cell / 2, max(cell / 2, $0)) } ?? restX      // glides with the finger
        let lit = cell > 0 ? min(order.count - 1, max(0, Int(x / cell))) : 0

        HStack(spacing: 12) {
            ZStack(alignment: .leading) {
                if cell > 0 {
                    Capsule().fill(.clear)
                        .glassEffect(.regular.interactive(), in: Capsule())
                        .frame(width: cell - 4, height: 40)
                        .offset(x: x - (cell - 4) / 2)
                }
                HStack(spacing: 0) {
                    ForEach(Array(order.enumerated()), id: \.element) { i, p in tab(p, lit: i == lit) }
                }
            }
            .padding(4)
            .frame(maxWidth: .infinity).frame(height: 48)
            .lwGlass(Capsule(), rim: 0)          // glass owns its rim; a stroke on top doubles up when pressed
            .background { GeometryReader { g in Color.clear
                .onAppear { innerW = g.size.width - 8 }
                .onChange(of: g.size.width) { _, w in innerW = w - 8 } } }
            .coordinateSpace(name: "navbar")
            .simultaneousGesture(                      // press and glide: the indicator tracks the finger 1:1
                DragGesture(minimumDistance: 6, coordinateSpace: .named("navbar"))
                    .onChanged { v in
                        guard innerW > 0 else { return }
                        fingerX = v.location.x - 4                       // inside the bar's 4pt padding
                        let now = cellIndex(fingerX!)
                        if now != lastCell { lastCell = now; UISelectionFeedbackGenerator().selectionChanged() }
                    }
                    .onEnded { _ in
                        if let fx = fingerX {
                            let landed = order[cellIndex(fx)]
                            if landed != router.page { router.show(landed) }
                        }
                        lastCell = -1
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.8)) { fingerX = nil }
                    }
            )
        }
        .containerRelativeFrame(.horizontal) { w, _ in w * 0.5 - 15 }   // right half of the bottom row
        .padding(.trailing, LW.screenPad)
        .animation(.spring(response: 0.34, dampingFraction: 0.82), value: router.page)
    }

    /// Which third a finger position falls in — recomputed live, never captured from a stale body pass.
    private func cellIndex(_ x: CGFloat) -> Int {
        guard innerW > 0 else { return 0 }
        return min(order.count - 1, max(0, Int(min(innerW - 1, max(0, x)) / (innerW / CGFloat(order.count)))))
    }

    @ViewBuilder private func tab(_ p: Page, lit: Bool) -> some View {
        Button { router.show(p) } label: {
            glyph(p, color: lit ? LW.accent : LW.ink(0.62))
                .frame(height: 40).frame(maxWidth: .infinity)
                .contentShape(Rectangle())
        }.buttonStyle(.plain)
        .accessibilityIdentifier("nav.tab.\(p)")
    }
    @ViewBuilder private func glyph(_ p: Page, color: Color) -> some View {
        switch p {
        case .home: Icon(kind: .home, size: 19, color: color)
        case .workouts: Icon(kind: .list, size: 18, color: color)
        case .calendar: Icon(kind: .calendar, size: 18, color: color)
        }
    }
}

/// The + circle asks: start a pre-saved workout, or a fresh one.
struct StartSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router
    var body: some View {
        let next = store.nextWorkout()
        let cycle = (store.activeRoutine()?.orderedEntries ?? []).compactMap { store.workout($0.workoutID) }
        let others = store.workouts().filter { w in !cycle.contains { $0.id == w.id } }
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                Text("START A WORKOUT").font(LWFont.display(24, width: 85)).tracking(-0.4).padding(.top, 22)
                Text("PICK ONE · OR EMPTY SESSION").font(LWFont.mono(10)).tracking(1.4)
                    .foregroundStyle(LW.ink(0.4)).padding(.top, 4).padding(.bottom, 10)
                ForEach(cycle, id: \.id) { w in row(w, isNext: w.id == next?.id, sessions: nil) }
                if !others.isEmpty {
                    Text("Other workouts").lwLabel(10, tracking: 0.16, color: LW.ink(0.35)).padding(.top, 20).padding(.bottom, 2)
                    ForEach(others, id: \.id) { w in row(w, isNext: false, sessions: (store.analysis.sessionsPerGroup[w.id.uuidString] ?? []).count) }
                }
                Button {
                    router.startSheet = false
                    let s = store.startSession(from: nil); store.markLive(s)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { router.present(.session(s.id)) }
                } label: {
                    HStack(spacing: 10) {
                        Text("+").font(LWFont.body(19, weight: 500)).foregroundStyle(LW.accent)
                        Text("EMPTY SESSION").font(LWFont.mono(13, semibold: true)).tracking(1.6).foregroundStyle(LW.accent)
                    }
                    .frame(maxWidth: .infinity).frame(height: 62)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(LW.accent(0.5), style: StrokeStyle(lineWidth: 1, dash: [5, 4])))
                    .contentShape(Rectangle())
                }.buttonStyle(.plain).padding(.top, 22).accessibilityIdentifier("start.fresh")
                Text("add exercises as you go · save as a workout after")
                    .font(LWFont.mono(10)).foregroundStyle(LW.ink(0.32))
                    .frame(maxWidth: .infinity).padding(.top, 8).padding(.bottom, 24)
            }
            .padding(.horizontal, LW.screenPad)
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(LW.bg)
    }

    /// One pickable workout: name over its cost, START on the right — filled for the next one.
    @ViewBuilder private func row(_ w: Workout, isNext: Bool, sessions: Int?) -> some View {
        let s = store.workoutStats(w.id)
        let sets = w.orderedSlots.reduce(0) { $0 + $1.sets }
        HStack(spacing: 10) {
            Button {                                            // the name opens the workout; only the pill starts it
                router.startSheet = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { router.push(.workoutEdit(w.id)) }
            } label: {
                VStack(alignment: .leading, spacing: 3) {
                    Text(Fmt.title(w.name)).font(LWFont.heading(17, width: 90)).tracking(-0.2).lineLimit(1).minimumScaleFactor(0.6)
                    Text(meta(w, s, sets: sets, isNext: isNext, sessions: sessions))
                        .font(LWFont.mono(10)).foregroundStyle(LW.ink(0.38)).lineLimit(1).minimumScaleFactor(0.7)
                }
                .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityIdentifier("start.open")
            Spacer(minLength: 8)
            Button {
                router.startSheet = false
                let ses = store.startSession(from: w)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { router.present(.session(ses.id)) }
            } label: {
                Text("START").font(LWFont.mono(11, semibold: true)).tracking(1.6)
                    .foregroundStyle(isNext ? LW.inkOnAccent : LW.ink(0.7))
                    .frame(width: 82, height: 32)                // both variants identical width
                    .background {
                        if isNext { Capsule().fill(LW.accent) } else { Capsule().strokeBorder(LW.ink(0.22), lineWidth: 1) }
                    }
                    .contentShape(Capsule())
            }.buttonStyle(.plain)
            .accessibilityIdentifier("start.workout").accessibilityLabel("Start \(w.name)")
        }
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) { Hairline() }
    }

    private func meta(_ w: Workout, _ s: AppStore.WorkoutStats, sets: Int, isNext: Bool, sessions: Int?) -> String {
        var t = "\(w.orderedSlots.count) EX · \(sets) SETS"
        if let n = sessions { return "\(w.orderedSlots.count) EX · \(n) SESSION\(n == 1 ? "" : "S")" }
        if s.lastVolume > 0 { t += " · last \(Fmt.int(s.lastVolume)) kg" }
        if let d = s.lastDate { t += " · \(Fmt.ago(d, today: store.today))" }
        return t
    }
}

/// Home · Workouts · Calendar as one horizontal paging scroll view.
struct PagerView: View {
    @Environment(Router.self) private var router
    // The scroll position starts nil and is set after first layout — binding it straight to router.page
    // gets dropped on cold launch (LazyHStack lays out at page 0 = Fresh before the position applies).
    @State private var pos: Page? = nil
    var body: some View {
        GeometryReader { g in
            ScrollView(.horizontal) {
                LazyHStack(spacing: 0) {
                    HomeView().frame(width: g.size.width, height: g.size.height).id(Page.home)
                    WorkoutsView().frame(width: g.size.width, height: g.size.height).id(Page.workouts)
                    CalendarView().frame(width: g.size.width, height: g.size.height).id(Page.calendar)
                }.scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: $pos)
            .scrollDisabled(router.pagingLocked)
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize)
        }
        .ignoresSafeArea(edges: .top)
        .onAppear { pos = router.page }
        .onChange(of: router.page) { _, p in if pos != p { pos = p } }
        .onChange(of: pos) { _, p in if let p, router.page != p { router.page = p } }
    }
}
