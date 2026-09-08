import SwiftUI

enum FocusMode {
    static let key = "session.focus"
    static let `default` = true          // a new install opens its first session one set at a time
}

/// The switch that swaps the table for focus mode. Per user, not per session.
struct FocusSwitch: View {
    @Binding var on: Bool
    var body: some View {
        Button {
            UISelectionFeedbackGenerator().selectionChanged()
            on.toggle()
        } label: {
            Group {
                if on {
                    Text("FOCUS").font(LWFont.mono(9.5, semibold: true)).tracking(9.5 * 0.16)
                        .foregroundStyle(LW.inkOnAccent)
                } else {
                    SingleSetGlyph()
                }
            }
            .padding(.horizontal, 13).frame(height: 30)
            .background {
                if on { Capsule().fill(LW.accent) } else { Capsule().strokeBorder(LW.ink(0.22), lineWidth: 1) }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("session.focus")
        .accessibilityLabel("Focus mode")
        .accessibilityValue(on ? "on" : "off")
    }
}

/// OFF glyph: the one live row between two dimmed ones.
private struct SingleSetGlyph: View {
    var body: some View {
        VStack(spacing: 3) {
            Capsule().fill(LW.ink(0.4)).frame(width: 16, height: 2)
            RoundedRectangle(cornerRadius: 1.5).fill(LW.ink).frame(width: 16, height: 5)
            Capsule().fill(LW.ink(0.4)).frame(width: 16, height: 2)
        }
    }
}

/// 6a/6b/6d — one set at a time. A second view over the same session: every write lands in the
/// store the table writes to, so the switch is lossless in both directions.
struct FocusSessionView: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(FocusMode.key) private var focusOn = FocusMode.default
    let session: Session

    @State private var cursor = 0
    @State private var restingOn: Int? = nil       // the row the countdown belongs to; nil = set state
    @State private var showDial = false
    @State private var best: BestFlash?
    @State private var kgDraft: Double?            // uncommitted drag value
    @State private var kgText = ""
    @State private var editingKg = false
    @State private var dragBase: Double?
    @State private var dragTicks = 0
    @FocusState private var kgFieldUp: Bool

    private let gutter: CGFloat = 11               // on top of Screen's 10 → the frame's 21pt margin
    private let railBand: CGFloat = 24             // right inset that keeps the body clear of the rail

    struct BestFlash: Equatable {
        let exercise: String, line: String, prev: String
    }

    // MARK: rows
    private var rows: [(se: SessionExercise, set: SetLog)] {
        session.orderedExercises.flatMap { se in se.orderedSets.map { (se: se, set: $0) } }
    }
    private var at: Int { min(max(0, cursor), max(0, rows.count - 1)) }
    /// During rest the header names the set you just checked, not the one the rail has moved to.
    private var headline: Int { restingOn ?? at }
    private var skippedBehind: Int { rows.prefix(at).filter { !$0.set.done }.count }

    var body: some View {
        if rows.isEmpty { empty } else { content }
    }

    private var empty: some View {
        Screen {
            VStack(spacing: 16) {
                Text("No sets in this session").font(LWFont.mono(12)).foregroundStyle(LW.ink(0.5))
                OutlinePill(title: "Use the table") { focusOn = false }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var content: some View {
        let row = rows[at]
        return Screen {
            ZStack {
                VStack(spacing: 0) {
                    header(rows[min(headline, rows.count - 1)])
                    if restingOn == nil { setBlock(row) } else { restBlock }
                    footer
                }
                .padding(.horizontal, gutter)
                .opacity(showDial ? 0.22 : 1).blur(radius: showDial ? 1 : 0)
                .allowsHitTesting(!showDial)
                .overlay(alignment: .trailing) { rail.padding(.trailing, 10) }
                .animation(.easeInOut(duration: 0.2), value: restingOn == nil)
                if showDial { dial }
                if let b = best {
                    FocusNewBest(flash: b, reduceMotion: reduceMotion) { best = nil }
                        .zIndex(20)
                }
            }
        }
        .gesture(DragGesture(minimumDistance: 24).onEnded { g in       // vertical swipe anywhere: down = previous
            guard abs(g.translation.height) > abs(g.translation.width), abs(g.translation.height) > 40 else { return }
            move(g.translation.height > 0 ? -1 : 1)
        })
        // a clock already running means the rest state, even on a fresh entry — the timer is the store's, not this view's
        .onAppear { cursor = opening; if store.restAnchor != nil { restingOn = max(0, cursor - 1) }; park() }
        .onChange(of: at) { _, _ in park() }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("focus.screen")
    }

    private func park() {
        guard !rows.isEmpty else { return }
        store.focusRowID = AppStore.rowID(rows[at].se, rows[at].set)
    }

    /// Where focus opens: the set the table was parked on, else the first one still to do.
    private var opening: Int {
        if let id = store.focusRowID, let i = rows.firstIndex(where: { AppStore.rowID($0.se, $0.set) == id }) { return i }
        return rows.firstIndex { !$0.set.done } ?? max(0, rows.count - 1)
    }

    // MARK: header
    private func header(_ row: (se: SessionExercise, set: SetLog)) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 0) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 10) {
                        Button { router.pop() } label: {          // minimise only — never ends the session
                            Icon(kind: .chevronDown, size: 18, color: LW.ink(0.6))
                                .frame(width: 30, height: 30).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                        .accessibilityIdentifier("session.minimize").accessibilityLabel("Minimize")
                        .offset(x: -6)
                        TimelineView(.periodic(from: .now, by: 1)) { ctx in
                            let t = max(0, Int(ctx.date.timeIntervalSince(session.startedAt)))
                            Text("\(Fmt.title(session.title)) · \(String(format: "%d:%02d", t / 60, t % 60))")
                                .font(LWFont.mono(10)).tracking(1.4).foregroundStyle(LW.ink(0.58))
                                .lineLimit(1).minimumScaleFactor(0.7)
                        }
                        .offset(x: -12)
                    }
                    Text(row.se.exerciseName.uppercased())
                        .font(LWFont.archivo(26, weight: 900, width: 85)).tracking(-0.2)
                        .foregroundStyle(LW.ink).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 0) {
                        Text("SET ").foregroundStyle(LW.ink(0.58))
                        Text("\(row.set.index + 1)").foregroundStyle(LW.accent)
                        Text(" OF \(row.se.sets.count)").foregroundStyle(LW.ink(0.58))
                    }
                    .font(LWFont.mono(10)).tracking(1.8)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("focus.set")
                    .accessibilityLabel("Set \(row.set.index + 1) of \(row.se.sets.count)")
                }
                Spacer(minLength: 8)
                FocusSwitch(on: $focusOn)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
    }

    // MARK: set state (6a)
    private func setBlock(_ row: (se: SessionExercise, set: SetLog)) -> some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: 18)          // fixed above, flexible below: the weight rides just under the header
            weight(row.set)
            coachSlot(row.se).frame(height: 24).padding(.top, 22)
            Spacer(minLength: 12)
            reps(row.set)
            Spacer(minLength: 16)
            action(row)
        }
        .padding(.trailing, railBand)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .transition(.opacity)
    }

    private func weight(_ set: SetLog) -> some View {
        let shown = editingKg ? kgText : Fmt.kg(kgDraft ?? set.kg)
        // the number is fixed-size so the rule and KG can hug it — so it must be sized to fit, never clipped.
        // Archivo 900/76 % runs ~0.5 em per digit, the point a little under half that; 250pt is the narrowest gutter.
        let units = shown.reduce(0.0) { $0 + ($1 == "." ? 0.45 : 1) }
        let big = LWFont.archivo(min(136, 500 / max(1, units)), weight: 900, width: 76)
        return HStack(spacing: 0) {
            nudge(set, up: false)
            Text(shown.isEmpty ? "0" : shown)
                .font(big).foregroundStyle(LW.ink).lineLimit(1).fixedSize()
                .opacity(editingKg ? 0 : 1)
                // labelled before the overlays go on, or the element swallows the field and the keypad is unreachable
                .accessibilityIdentifier("focus.weight")
                .accessibilityLabel("Weight")
                .accessibilityValue("\(Fmt.kg(kgDraft ?? set.kg)) kg")
                .overlay {
                    TextField("", text: $kgText)
                        .font(big).foregroundStyle(LW.ink).multilineTextAlignment(.center)
                        .keyboardType(.decimalPad).focused($kgFieldUp)
                        .opacity(editingKg ? 1 : 0).allowsHitTesting(editingKg)
                        .accessibilityIdentifier("focus.weight.field")
                }
                .overlay(alignment: Alignment(horizontal: .center, vertical: .lastTextBaseline)) {
                    Rectangle().fill(LW.ink(0.16)).frame(height: 2).offset(y: 14).accessibilityHidden(true)
                }
                .overlay(alignment: Alignment(horizontal: .trailing, vertical: .lastTextBaseline)) {
                    Text("KG").font(LWFont.mono(11)).tracking(11 * 0.22).foregroundStyle(LW.ink(0.58))
                        .fixedSize().alignmentGuide(.trailing) { _ in -8 }.accessibilityHidden(true)
                }
                .contentShape(Rectangle())
                .onTapGesture { kgText = Fmt.kg(set.kg); editingKg = true; kgFieldUp = true }
                .gesture(weightDrag(set))
            nudge(set, up: true)
        }
        .onChange(of: kgFieldUp) { _, up in if !up, editingKg { commitKeypad(set) } }
        .toolbar {
            if editingKg {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { commitKeypad(set) }.accessibilityIdentifier("focus.weight.done")
                }
            }
        }
    }

    /// The chevrons hint the drag and take a tap: one unit either way, same 2.5 kg step.
    private func nudge(_ set: SetLog, up: Bool) -> some View {
        Button {
            store.setWeight(set, max(0, (((set.kg ?? 0) + (up ? 2.5 : -2.5)) / 2.5).rounded() * 2.5))
            UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.6)
        } label: {
            FocusChevron(right: up).stroke(LW.ink(0.3), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                .frame(width: 12, height: 20)
                .frame(width: 44, height: 44)          // the glyph stays 12×20; the target is a finger
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain).frame(maxWidth: .infinity)
        .accessibilityIdentifier(up ? "focus.weight.up" : "focus.weight.down")
        .accessibilityLabel(up ? "Heavier" : "Lighter")
    }

    /// ±2.5 kg per 28pt with a tick per step; the model only hears about it on release.
    private func weightDrag(_ set: SetLog) -> some Gesture {
        DragGesture(minimumDistance: 10)
            .onChanged { g in
                guard !editingKg else { return }
                if dragBase == nil { dragBase = set.kg ?? 0; dragTicks = 0 }
                let t = Int(g.translation.width / 28)
                if t != dragTicks {
                    dragTicks = t
                    UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.6)
                }
                kgDraft = max(0, (((dragBase ?? 0) + Double(t) * 2.5) / 2.5).rounded() * 2.5)
            }
            .onEnded { _ in
                if let v = kgDraft { store.setWeight(set, v) }
                kgDraft = nil; dragBase = nil; dragTicks = 0
            }
    }

    private func commitKeypad(_ set: SetLog) {
        if let v = Double(kgText.replacingOccurrences(of: ",", with: ".")) { store.setWeight(set, max(0, v)) }
        editingKg = false; kgFieldUp = false
    }

    @ViewBuilder private func coachSlot(_ se: SessionExercise) -> some View {
        if let m = coachMark(se) { FocusCoachChip(was: m.was, now: m.now) } else { Color.clear }
    }

    /// Session Updates §1 — "kg|was|reason", the same key the table row reads.
    private func coachMark(_ se: SessionExercise) -> (was: String, now: String)? {
        guard let raw = UserDefaults.standard.string(forKey: "coach.smark.\(session.id.uuidString).\(se.exerciseID)") else { return nil }
        let parts = raw.components(separatedBy: "|")
        guard parts.count > 1 else { return nil }
        let num = { (s: String) in s.components(separatedBy: " ").first ?? s }
        return (num(parts[1]), num(parts[0]))
    }

    private func reps(_ set: SetLog) -> some View {
        HStack(spacing: 0) {
            stepper("−", id: "focus.reps.minus") { bumpReps(set, -1) }
            Spacer(minLength: 0)
            VStack(spacing: 4) {
                Text("\(set.reps ?? 0)")
                    .font(LWFont.archivo(92, weight: 900, width: 76)).foregroundStyle(LW.ink)
                Text("REPS").font(LWFont.mono(10)).tracking(2.4).foregroundStyle(LW.ink(0.58))
            }
            .accessibilityElement(children: .ignore)
            .accessibilityIdentifier("focus.reps")
            .accessibilityLabel("\(set.reps ?? 0) reps")
            Spacer(minLength: 0)
            stepper("+", id: "focus.reps.plus") { bumpReps(set, 1) }
        }
    }

    private func stepper(_ sym: String, id: String, _ act: @escaping () -> Void) -> some View {
        Button(action: act) {
            Text(sym).font(LWFont.body(26, weight: 300)).foregroundStyle(LW.ink(0.6))
                .frame(width: 60, height: 60)
                .overlay(Circle().strokeBorder(LW.ink(0.2), lineWidth: 1))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id).accessibilityLabel(sym == "+" ? "One more rep" : "One fewer rep")
    }

    private func bumpReps(_ set: SetLog, _ d: Int) {
        store.setReps(set, (set.reps ?? 0) + d)
        UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.6)
    }

    /// The 64pt slot: check, or the finish knob once there is nothing after this set.
    @ViewBuilder private func action(_ row: (se: SessionExercise, set: SetLog)) -> some View {
        if at == rows.count - 1 {
            SlideToFinish(unchecked: { skippedBehind },
                          title: skippedBehind > 0 ? "FINISH · \(skippedBehind) SKIPPED" : "MARK & FINISH") {
                store.check(row.set, exerciseID: row.se.exerciseID, prev: prevSet(row))
                finish()
            }
            .frame(height: 64)
        } else {
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                check(row)
            } label: {
                RoundedRectangle(cornerRadius: 20, style: .continuous).fill(LW.accentBright)
                    .frame(height: 64)
                    .overlay { Icon(kind: .check, size: 28, color: LW.inkOnAccent, weight: 3) }
                    .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("focus.check").accessibilityLabel("Log this set")
        }
    }

    // MARK: rest state (6b)
    private var restBlock: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: 18)
            countdown
            Spacer(minLength: 12)
            nextUp
            Spacer(minLength: 16)
            Button { endRest() } label: {
                HStack(spacing: 10) {
                    Text("SKIP REST").font(LWFont.archivo(15, weight: 800, width: 100)).tracking(0.6)
                    Icon(kind: .arrowRight, size: 15, color: LW.ink, weight: 2)
                }
                .foregroundStyle(LW.ink)
                .frame(maxWidth: .infinity).frame(height: 64)
                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(LW.ink(0.22), lineWidth: 1))
                .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("focus.skip").accessibilityLabel("Skip rest")
        }
        .padding(.trailing, railBand)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .transition(.opacity)
    }

    private var countdown: some View {
        VStack(spacing: 14) {
            Text("REST").font(LWFont.mono(10)).tracking(2.4).foregroundStyle(LW.accent)
            TimelineView(.periodic(from: .now, by: 0.5)) { ctx in
                let t = store.restDisplay(at: ctx.date) ?? 0
                VStack(spacing: 16) {
                    Text(restClock(t))
                        .font(LWFont.mono(104, semibold: true)).tracking(-5.2)
                        .foregroundStyle(LW.accentBright).monospacedDigit()
                        .lineLimit(1).minimumScaleFactor(0.5)
                    Capsule().fill(LW.ink(0.12)).frame(width: 180, height: 3)
                        .overlay(alignment: .leading) { Capsule().fill(LW.accent).frame(width: 180 * left(t), height: 3) }
                }
                // count-up mode never reaches zero — only an armed countdown flips the screen back
                .onChange(of: store.restAnchor == nil || (store.restDuration != nil && t <= 0)) { _, over in
                    if over { endRest(alarm: true) }
                }
            }
        }
        // the press must survive the timeline's rebuilds, so it lives outside them
        .overlay {
            Color.clear.contentShape(Rectangle())
                .onLongPressGesture(minimumDuration: 0.4) {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    withAnimation(.easeOut(duration: 0.2)) { showDial = true }
                }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier("focus.rest").accessibilityLabel("Resting")
    }

    /// It depletes: full bar at the start of the rest, empty at 0:00.
    private func left(_ remaining: TimeInterval) -> CGFloat {
        guard let d = store.restDuration, d > 0 else { return 0 }
        return min(1, max(0, CGFloat(remaining / d)))
    }

    private var nextUp: some View {
        let row = rows[at]
        let showsNext = at != (restingOn ?? at)
        return VStack(spacing: 12) {
            Text(showsNext ? "NEXT · SET \(row.set.index + 1) OF \(row.se.sets.count)" : "LAST SET LOGGED")
                .font(LWFont.mono(9.5)).tracking(9.5 * 0.22).foregroundStyle(LW.ink(0.58))
            HStack(alignment: .lastTextBaseline, spacing: 5) {
                Text(Fmt.kg(row.set.kg)).font(LWFont.archivo(44, weight: 900, width: 76)).foregroundStyle(LW.ink)
                Text("kg").font(LWFont.mono(13)).foregroundStyle(LW.ink(0.5)).padding(.trailing, 6)
                Text("×").font(LWFont.archivo(44, weight: 900, width: 76)).foregroundStyle(LW.accent)
                Text("\(row.set.reps ?? 0)").font(LWFont.archivo(44, weight: 900, width: 76)).foregroundStyle(LW.ink)
            }
            if let m = coachMark(row.se) { FocusCoachChip(was: m.was, now: m.now) }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .overlay(alignment: .top) { Rectangle().fill(LW.ink(0.1)).frame(height: 1) }
        .overlay(alignment: .bottom) { Rectangle().fill(LW.ink(0.1)).frame(height: 1) }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("focus.next.target")
    }

    // MARK: footer + rail
    private var footer: some View {
        HStack {
            Button { move(-1) } label: {
                Text("‹ PREV").font(LWFont.mono(9.5)).tracking(0.95).foregroundStyle(LW.ink(0.45))
                    .frame(height: 34).padding(.trailing, 24).contentShape(Rectangle())
            }.buttonStyle(.plain)
            .accessibilityIdentifier("focus.prev").accessibilityLabel("Previous set")
            Spacer()
            Button { move(1) } label: {
                Text("NEXT ›").font(LWFont.mono(9.5)).tracking(0.95).foregroundStyle(LW.ink(0.45))
                    .frame(height: 34).padding(.leading, 24).contentShape(Rectangle())
            }.buttonStyle(.plain)
            .accessibilityIdentifier("focus.next").accessibilityLabel("Next set")
        }
        .padding(.top, 12).padding(.bottom, 22).padding(.trailing, railBand)   // clear of the home indicator
        .accessibilityElement(children: .contain)
    }

    private var rail: some View {
        VStack(spacing: 10) {
            ForEach(session.orderedExercises, id: \.persistentModelID) { se in
                VStack(spacing: 1) {
                    ForEach(se.orderedSets, id: \.persistentModelID) { st in
                        railDot(se, st)
                    }
                }
            }
        }
        .frame(width: 14)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("focus.rail")
    }

    private func railDot(_ se: SessionExercise, _ st: SetLog) -> some View {
        let i = rows.firstIndex { $0.se === se && $0.set === st } ?? 0
        let current = i == at
        return Button { jump(to: i) } label: {
            Group {
                if current {
                    Capsule().fill(LW.accentBright).frame(width: 5, height: 18)
                } else if st.done {
                    Circle().fill(LW.accent).frame(width: 5, height: 5)
                } else if st.skipped {
                    ZStack {
                        Circle().strokeBorder(LW.ink(0.5), lineWidth: 1).frame(width: 6, height: 6)
                        Rectangle().fill(LW.ink(0.5)).frame(width: 8, height: 1).rotationEffect(.degrees(-45))
                    }
                } else {
                    Circle().fill(LW.ink(0.16)).frame(width: 5, height: 5)
                }
            }
            .frame(width: 14, height: (current ? 18 : 6) + 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("focus.rail.\(i)")
        .accessibilityLabel("\(se.exerciseName) set \(st.index + 1)")
        .accessibilityValue(current ? "current" : st.done ? "done" : st.skipped ? "skipped" : "to do")
    }

    private var dial: some View {
        ZStack {
            Color.black.opacity(0.001).ignoresSafeArea()
                .onTapGesture { withAnimation(.easeOut(duration: 0.2)) { showDial = false } }
            RestDial { withAnimation(.easeOut(duration: 0.2)) { showDial = false } }
                .transition(.scale(scale: 0.92).combined(with: .opacity))
        }
    }

    // MARK: moves
    private func prevSet(_ row: (se: SessionExercise, set: SetLog)) -> (Double?, Int)? {
        let last = store.lastSessionSets(exerciseID: row.se.exerciseID)
        return row.set.index < last.count ? last[row.set.index] : nil
    }

    /// Everything left behind on the way forward is a skip; going back marks nothing.
    private func jump(to i: Int) {
        let target = min(max(0, i), rows.count - 1)
        guard target != at else { return }
        if target > at { for r in rows[at..<target] { store.markSkipped(r.set) } }
        withAnimation(.easeOut(duration: 0.18)) { cursor = target; restingOn = nil }
    }
    private func move(_ d: Int) { jump(to: at + d) }

    private func check(_ row: (se: SessionExercise, set: SetLog)) {
        store.check(row.set, exerciseID: row.se.exerciseID, prev: prevSet(row))
        let flash = store.newBest(exerciseID: row.se.exerciseID, kg: row.set.kg, reps: row.set.reps ?? 0)
        store.startRest()
        store.restScreenUp = false                 // focus IS the rest screen — the table's overlay must not stack on it
        let here = at
        withAnimation(.easeOut(duration: 0.2)) {
            restingOn = here
            cursor = min(here + 1, rows.count - 1)
        }
        let once = "\(session.id.uuidString)|\(row.se.exerciseID)"
        guard let f = flash, !store.focusRewarded.contains(once) else { return }
        store.focusRewarded.insert(once)
        best = BestFlash(exercise: row.se.exerciseName.uppercased(),
                         line: "\(Fmt.kg(row.set.kg)) × \(row.set.reps ?? 0) · e1RM \(Fmt.e1rm(f.e1rm))",
                         prev: "prev \(Fmt.e1rm(f.prev))\(f.date.map { " · \(Fmt.date($0, "d MMM"))" } ?? "") · " + String(format: "%+.1f%%", f.pct))
    }

    private func endRest(alarm: Bool = false) {
        guard restingOn != nil else { return }
        store.cancelRest()
        if alarm { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
        withAnimation(.easeOut(duration: 0.2)) { restingOn = nil }
    }

    private func finish() {
        store.cancelRest()                       // a running clock at the end just stops
        store.focusRowID = nil
        store.finish(session)
        router.finishSplash = session.id
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { router.present(.summary(session.id)) }
    }
}

/// 6d's blunt vertical arrow — the app's diagonal arrowUp reads as a trend, not a record.
private struct FocusUpArrow: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let i: CGFloat = 4
        p.move(to: CGPoint(x: r.midX, y: r.maxY - i)); p.addLine(to: CGPoint(x: r.midX, y: r.minY + i))
        p.move(to: CGPoint(x: r.minX + i, y: r.minY + r.height * 0.34))
        p.addLine(to: CGPoint(x: r.midX, y: r.minY + i))
        p.addLine(to: CGPoint(x: r.maxX - i, y: r.minY + r.height * 0.34))
        return p
    }
}

/// 12×20 hint chevron — the drag affordance either side of the weight.
private struct FocusChevron: Shape {
    let right: Bool
    func path(in r: CGRect) -> Path {
        var p = Path()
        let inset: CGFloat = 1
        p.move(to: CGPoint(x: right ? r.minX + inset : r.maxX - inset, y: r.minY + inset))
        p.addLine(to: CGPoint(x: right ? r.maxX - inset : r.minX + inset, y: r.midY))
        p.addLine(to: CGPoint(x: right ? r.minX + inset : r.maxX - inset, y: r.maxY - inset))
        return p
    }
}

/// The one thing allowed in the slot under the weight: what the coach moved, and from where.
private struct FocusCoachChip: View {
    let was: String, now: String
    private static let border = LinearGradient(stops: [
        .init(color: Color(lwHex(0xC0B6E8)), location: 0),
        .init(color: Color(lwHex(0x8FB8C9, 0.5)), location: 0.4),
        .init(color: Color(lwHex(0xA6C48A, 0.35)), location: 0.75),
        .init(color: Color(lwHex(0xA6C48A)), location: 1)], startPoint: .topLeading, endPoint: .bottomTrailing)
    var body: some View {
        HStack(spacing: 8) {
            CoachMark9c(size: 12).frame(width: 12, height: 12)
            Text("COACH").font(LWFont.mono(10, semibold: true)).tracking(1.4).foregroundStyle(Color(lwHex(0x9FC0CC)))
            Text("\(was) → \(now)").font(LWFont.mono(10, semibold: true)).tracking(1).foregroundStyle(Color(lwHex(0xC0B6E8)))
        }
        .padding(.horizontal, 12).frame(height: 24)
        .background(Capsule().fill(Color(lwHex(0x0A0B0C))))
        .overlay(Capsule().strokeBorder(Self.border, lineWidth: 2))
        .shadow(color: Color(lwHex(0x8FB8C9, 0.22)), radius: 8, y: 4)
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier("focus.coach")
        .accessibilityLabel("Coach moved this to \(now) from \(was)")
    }
}

/// 6d — the reward. An overlay, never a screen: the rest clock keeps running underneath it.
private struct FocusNewBest: View {
    let flash: FocusSessionView.BestFlash
    let reduceMotion: Bool
    let dismiss: () -> Void
    @State private var up = false
    @State private var landed = false
    @State private var rings = false
    private let flood = Color(lwHex(0xC7D584))

    var body: some View {
        GeometryReader { g in
            ZStack {
                flood.opacity(0.94).ignoresSafeArea()
                    .offset(y: reduceMotion ? 0 : (up ? 0 : g.size.height))
                    .opacity(reduceMotion ? (up ? 1 : 0) : 1)
                VStack(spacing: 0) {
                    Spacer(minLength: 0); Spacer(minLength: 0)     // the block rides low, the way the frame reads
                    ZStack {
                        if !reduceMotion {
                            ForEach(0..<2, id: \.self) { i in
                                Circle().strokeBorder(LW.inkOnAccent.opacity(rings ? 0 : 0.5), lineWidth: 2)
                                    .frame(width: 72, height: 72)
                                    .scaleEffect(rings ? 2.6 : 0.4)
                                    .animation(.easeOut(duration: 1.4).delay(0.5 + Double(i) * 0.35).repeatForever(autoreverses: false), value: rings)
                            }
                        }
                        FocusUpArrow().stroke(LW.inkOnAccent, style: StrokeStyle(lineWidth: 7, lineCap: .round, lineJoin: .round))
                            .frame(width: 52, height: 72)
                    }
                    .frame(width: 100, height: 100)
                    .modifier(Land(landed: landed, delay: 0.5, off: reduceMotion))
                    Text("NEW BEST")
                        .font(LWFont.archivo(64, weight: 900, width: 78)).tracking(-1.4)
                        .foregroundStyle(LW.inkOnAccent).multilineTextAlignment(.center)
                        .lineLimit(2).minimumScaleFactor(0.6).padding(.top, 6)
                        .modifier(Land(landed: landed, delay: 0.65, off: reduceMotion))
                    Text(flash.exercise)
                        .font(LWFont.mono(11, semibold: true)).tracking(11 * 0.22)
                        .foregroundStyle(LW.inkOnAccent).multilineTextAlignment(.center)
                        .padding(.top, 18)
                        .modifier(Land(landed: landed, delay: 0.8, off: reduceMotion))
                    Text(flash.line)
                        .font(LWFont.mono(12, semibold: true)).foregroundStyle(LW.inkOnAccent).padding(.top, 14)
                        .modifier(Land(landed: landed, delay: 0.95, off: reduceMotion))
                    Text(flash.prev)
                        .font(LWFont.mono(10.5)).foregroundStyle(LW.inkOnAccent.opacity(0.7)).padding(.top, 6)
                        .modifier(Land(landed: landed, delay: 1.1, off: reduceMotion))
                    Spacer(minLength: 24)
                    Text("TAP TO DISMISS")
                        .font(LWFont.mono(10)).tracking(2).foregroundStyle(LW.inkOnAccent.opacity(0.55))
                        .padding(.bottom, 30)
                        .modifier(Land(landed: landed, delay: 1.1, off: reduceMotion))
                }
                .padding(.horizontal, 24)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .contentShape(Rectangle())
            .onTapGesture { close() }
        }
        .ignoresSafeArea()
        .padding(.horizontal, -LW.screenPad)             // full bleed: out through the page's gutters
        .onAppear {
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()     // fires on the flood, not the tap
            withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .timingCurve(0.2, 0.9, 0.25, 1, duration: 0.3).delay(0.1)) { up = true }
            landed = true; rings = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.6) { if up { close() } }   // 2.5s after the last line lands
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("focus.newbest")
        .accessibilityAddTraits(.isModal)
    }

    private func close() {
        withAnimation(.easeIn(duration: 0.45)) { up = false }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { dismiss() }
    }

    /// Staggered arrival — one modifier so every line reads the same way.
    private struct Land: ViewModifier {
        let landed: Bool, delay: Double, off: Bool
        func body(content: Content) -> some View {
            content.opacity(landed ? 1 : 0).offset(y: landed || off ? 0 : 14)
                .animation(.easeOut(duration: 0.32).delay(off ? 0 : delay), value: landed)
        }
    }
}
