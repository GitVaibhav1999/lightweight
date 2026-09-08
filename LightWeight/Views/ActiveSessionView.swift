import SwiftUI
import SwiftData

extension AppStore {
    func session(_ id: UUID) -> Session? {
        if let s = finishedSessions().first(where: { $0.id == id }) { return s }
        return (try? context.fetch(FetchDescriptor<Session>(predicate: #Predicate { $0.id == id })))?.first
    }
    func bestSet(_ exerciseID: String) -> (Double?, Int)? { analysis.exerciseHistory[exerciseID]?.max { $0.e1rm < $1.e1rm }.map { ($0.kg, $0.reps) } }
}

/// S2 — full-screen logging. No rest timer, no chrome: last time's numbers prefilled, you repeat or beat them.
struct ActiveSessionView: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router
    let sessionID: UUID
    @State private var confirmDiscard = false
    @State private var showDial = false
    @AppStorage(FocusMode.key) private var focusOn = FocusMode.default
    private var restUp: Bool { store.restScreenUp && store.restAnchor != nil }

    var body: some View {
        if let s = store.session(sessionID) {
            if focusOn { FocusSessionView(session: s) } else { content(s) }
        } else { Screen { Text("Session not found").foregroundStyle(LW.ink(0.5)) } }
    }

    private func content(_ s: Session) -> some View {
        Screen {
            ZStack {
            VStack(spacing: 0) {
                HStack {
                    Button { router.pop() } label: { Icon(kind: .chevronDown, size: 18, color: LW.ink(0.6)).frame(width: 44, height: 36).contentShape(Rectangle()) }.buttonStyle(.plain).offset(x: -12)
                        .accessibilityIdentifier("session.minimize").accessibilityLabel("Minimize")
                        .simultaneousGesture(LongPressGesture(minimumDuration: 0.6).onEnded { _ in confirmDiscard = true })
                        .frame(width: 84, alignment: .leading)
                    Spacer()
                    HStack(spacing: 8) {
                        Text(Fmt.title(s.title)).font(LWFont.heading(17, width: 90)).tracking(0.3).lineLimit(1).minimumScaleFactor(0.7)
                        TimelineView(.periodic(from: .now, by: 1)) { ctx in
                            let t = Int(ctx.date.timeIntervalSince(s.startedAt)); Text(String(format: "%d:%02d", t / 60, t % 60)).font(LWFont.mono(12)).foregroundStyle(LW.ink(0.45))
                        }
                    }
                    Spacer()
                    HStack(spacing: 8) {
                        RestChip(showDial: $showDial)
                        FocusSwitch(on: $focusOn)
                    }
                }.frame(height: 30)
                SessionProgressBar(session: s).padding(.top, 12)
                ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 20) {
                        ForEach(s.orderedExercises, id: \.persistentModelID) { se in SessionExerciseBlock(se: se) }
                        OutlinePill(title: "+ Add exercise") { router.push(.picker(.session(s.id))) }
                        Color.clear.frame(height: 120)  // scroll room so the last rows clear the floating slider
                    }.padding(.horizontal, 9)
                }
                .padding(.horizontal, -9).padding(.top, 12)
                .onAppear {                                  // arriving from focus mode: land on the set it was parked on
                    guard let row = store.focusRowID else { return }
                    DispatchQueue.main.async { proxy.scrollTo(row, anchor: .center) }
                }
                }
                                .overlay(alignment: .bottom) {
                    SlideToFinish(unchecked: { s.exercises.flatMap(\.sets).filter { !$0.done }.count }) {
                        store.finish(s); router.finishSplash = s.id                 // cover first
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { router.present(.summary(s.id)) }
                    }.padding(.horizontal, 9).padding(.bottom, 20)
                }
            }
            .opacity(showDial ? 0.22 : (restUp ? 0.85 : 1)).blur(radius: showDial ? 1 : (restUp ? 3 : 0))
            .allowsHitTesting(!showDial && !restUp)
            if showDial {
                Color.black.opacity(0.001).ignoresSafeArea()
                    .onTapGesture { withAnimation(.easeOut(duration: 0.2)) { showDial = false } }
                RestDial { withAnimation(.easeOut(duration: 0.2)) { showDial = false } }
                    .transition(.scale(scale: 0.92).combined(with: .opacity))
                    .gesture(DragGesture(minimumDistance: 30).onEnded { g in      // swipe down dismisses
                        if g.translation.height > 30 { withAnimation(.easeOut(duration: 0.2)) { showDial = false } }
                    })
            }
            if restUp {
                RestScreen(session: s) { withAnimation(.easeOut(duration: 0.22)) { store.restScreenUp = false } }
                    .transition(.opacity)
            }
            }
        }
        .confirmationDialog("Discard this session?", isPresented: $confirmDiscard) {
            Button("Discard session", role: .destructive) { store.discard(s); router.home() }
            Button("Keep going", role: .cancel) {}
        }
    }
}

struct SessionExerciseBlock: View {
    @Environment(AppStore.self) private var store
    let se: SessionExercise
    @State private var newSetIndex: Int? = nil
    var body: some View {
        let prev = store.lastSessionSets(exerciseID: se.exerciseID)
        let best = store.bestSet(se.exerciseID)
        VStack(alignment: .leading, spacing: 6) {
            Text(se.exerciseName.uppercased()).font(LWFont.heading(19, width: 90)).tracking(-0.2)
            HStack(spacing: 4) { Text("Best").font(LWFont.mono(11)).foregroundStyle(LW.ink(0.45)); Text(best.map { Fmt.set($0.0, $0.1) } ?? "—").font(LWFont.mono(11)).foregroundStyle(LW.ink(0.8)) }
            HStack(spacing: 8) {
                Text("#").frame(width: 20, alignment: .leading); Text("Prev").frame(width: 66, alignment: .leading)
                Text("kg").frame(maxWidth: .infinity, alignment: .leading); Text("Reps").frame(maxWidth: .infinity, alignment: .leading); Color.clear.frame(width: 44)
            }.lwLabel(9.5, tracking: 0.1).frame(height: 20).padding(.top, 4)
            ForEach(se.orderedSets, id: \.persistentModelID) { st in
                SetRow(set: st, exerciseID: se.exerciseID, prev: st.index < prev.count ? prev[st.index] : nil, justAdded: st.index == newSetIndex)
                    .transition(.asymmetric(insertion: .move(edge: .top).combined(with: .opacity), removal: .opacity))
                    .id(AppStore.rowID(se, st))            // focus mode's scroll target
            }
            AddSetRow(se: se) { newSetIndex = $0 }
        }
    }
}

/// Full-width dashed "+ set" per exercise. Insert slides down; the row flashes "SET N ADDED" for 1s.
struct AddSetRow: View {
    @Environment(AppStore.self) private var store
    let se: SessionExercise
    var added: (Int) -> Void
    @State private var flashSet: Int? = nil
    var body: some View {
        Button {
            var idx = 0
            withAnimation(.easeOut(duration: 0.25)) { idx = store.addSet(to: se); added(idx) }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            flashSet = idx + 1
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { flashSet = nil }
        } label: {
            Text(flashSet.map { "SET \($0) ADDED" } ?? "+ set")
                .font(LWFont.mono(11)).tracking(0.8)
                .foregroundStyle(flashSet != nil ? LW.accent : LW.ink(0.45))
                .frame(maxWidth: .infinity).frame(height: 40)
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(LW.ink(0.25), style: StrokeStyle(lineWidth: 1, dash: [4, 4])))
                .contentShape(Rectangle())
        }.buttonStyle(.plain)
        .accessibilityIdentifier("set.add")
    }
}

struct SetRow: View {
    @Environment(AppStore.self) private var store
    @Bindable var set: SetLog
    let exerciseID: String
    let prev: (Double?, Int)?
    var justAdded = false
    @State private var kgText = ""
    @State private var repsText = ""
    @State private var addWash: Double = 0
    @State private var kgDragBase: Double? = nil
    @State private var kgDragTicks = 0
    @State private var showCoachPopover = false
    /// Session Updates §1: "kg|was|reason" when the coach adjusted this field (first session after acceptance).
    private var coachMark: (kg: String, was: String, reason: String)? {
        guard let sid = set.exercise?.session?.id,
              let raw = UserDefaults.standard.string(forKey: "coach.smark.\(sid.uuidString).\(exerciseID)") else { return nil }
        let parts = raw.components(separatedBy: "|")
        return (parts.first ?? "", parts.count > 1 ? parts[1] : "", parts.count > 2 ? parts[2] : "")
    }

    var body: some View {
        let pr = set.isPR && set.done
        HStack(spacing: 8) {
            ZStack {
                Circle().fill(LW.accent).frame(width: 20, height: 20).opacity(addWash)
                Text("\(set.index + 1)").foregroundStyle(addWash > 0.5 ? Color.black : LW.ink(0.45))
            }.frame(width: 20, alignment: .leading)
            Text(prev.map { Fmt.set($0.0, $0.1) } ?? "—").frame(width: 66, alignment: .leading).lineLimit(1).minimumScaleFactor(0.8)
            field($kgText, placeholder: Fmt.kg(set.kg), pr: pr) { set.kg = Double($0) }
                .overlay {
                    if let _ = coachMark {
                        RoundedRectangle(cornerRadius: 8).strokeBorder(LinearGradient(stops: [
                            .init(color: Color(red: 0x9F/255, green: 0xD0/255, blue: 0xE4/255), location: 0),
                            .init(color: Color(red: 0x65/255, green: 0xAA/255, blue: 0xC2/255), location: 0.55),
                            .init(color: Color(red: 0x4E/255, green: 0x86/255, blue: 0xA0/255), location: 1)],
                            startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
                    }
                }
                .overlay(alignment: .trailing) {
                    if let m = coachMark {
                        Button { showCoachPopover = true } label: {
                            CoachMark9c(size: 12).frame(width: 24, height: 24).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                        .popover(isPresented: $showCoachPopover) {
                            let typedOver = !kgText.isEmpty && kgText != m.kg
                            VStack(alignment: .leading, spacing: 8) {
                                Text(typedOver ? "coach \(m.kg) · you \(kgText)" : "coach set \(m.kg) kg · was \(m.was)")
                                    .font(LWFont.mono(11)).foregroundStyle(LW.ink(0.85))
                                if !m.reason.isEmpty { Text(m.reason).font(LWFont.mono(9.5)).foregroundStyle(LW.ink(0.5)) }
                                Button {
                                    if let was = Double(m.was.components(separatedBy: " ").first ?? "") { set.kg = was; kgText = Fmt.kg(was) }
                                    if let sid = set.exercise?.session?.id { UserDefaults.standard.removeObject(forKey: "coach.smark.\(sid.uuidString).\(exerciseID)") }
                                    showCoachPopover = false
                                } label: {
                                    Text("revert").font(LWFont.mono(10.5)).foregroundStyle(AIMist.base)
                                        .padding(.horizontal, 12).frame(height: 26)
                                        .overlay(Capsule().strokeBorder(AIMist.base.opacity(0.5), lineWidth: 1))
                                }.buttonStyle(.plain)
                            }
                            .padding(12).presentationCompactAdaptation(.popover)
                        }
                    }
                }
                .accessibilityIdentifier("set.kg.\(set.index)")
                .simultaneousGesture(
                    DragGesture(minimumDistance: 12)
                        .onChanged { g in                                     // horizontal swipe = ±2.5 kg per tick
                            if kgDragBase == nil { kgDragBase = Double(kgText) ?? set.kg ?? prev?.0 ?? 0; kgDragTicks = 0 }
                            let t = Int(g.translation.width / 18)
                            if t != kgDragTicks {
                                kgDragTicks = t
                                kgText = Fmt.kg(max(0, (kgDragBase ?? 0) + Double(t) * 2.5))
                                UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.6)
                            }
                        }
                        .onEnded { _ in kgDragBase = nil; kgDragTicks = 0 }
                )
            repsCluster(pr: pr)
            Button(action: toggle) {
                ZStack {
                    Circle().fill(set.done ? LW.accent : .clear).overlay(Circle().strokeBorder(LW.ink(set.done ? 0 : 0.3), lineWidth: 1))
                        .frame(width: 34, height: 34)
                    if set.done { Icon(kind: .check, size: 14, color: .black, weight: 3) }
                }.frame(width: 44, height: 44).contentShape(Rectangle())
            }.buttonStyle(.plain).frame(width: 44).accessibilityIdentifier("set.check.\(set.index)").accessibilityLabel(set.done ? "done" : "todo")
        }
        .font(LWFont.mono(13)).foregroundStyle(LW.ink(0.45))
        .frame(height: 46)
        .background {
            if pr { RoundedRectangle(cornerRadius: 10).fill(LW.accent(0.14)) }
            else if addWash > 0.01 { RoundedRectangle(cornerRadius: 10).fill(LW.accent(0.10)).opacity(addWash).padding(.horizontal, -9) }
        }
        .overlay(alignment: .bottom) { Rectangle().fill(LW.ink(0.1)).frame(height: 0.5) }
        .overlay(alignment: .topTrailing) {
            if pr {
                HStack(spacing: 4) { Icon(kind: .arrowUp, size: 9, color: .black, weight: 2.2); Text("BEST · \(Fmt.e1rm(Engine.e1rm(kg: set.kg, reps: set.reps ?? 0)))") }
                    .font(LWFont.mono(9.5, semibold: true)).tracking(0.8).foregroundStyle(.black)
                    .padding(.horizontal, 7).padding(.vertical, 1.5).background(RoundedRectangle(cornerRadius: 5).fill(LW.accent))
                    .offset(x: -44, y: -8)
            }
        }
        .onAppear {
            kgText = set.kg.map(Fmt.kg) ?? ""; repsText = set.reps.map(String.init) ?? ""
            if justAdded { addWash = 1; withAnimation(.easeOut(duration: 0.9).delay(0.15)) { addWash = 0 } }
        }
    }

    /// Session V2: −/+ steppers flank the reps value; tap the number for the keyboard.
    private func repsCluster(pr: Bool) -> some View {
        HStack(spacing: 0) {
            stepBtn("−", id: "set.reps.minus.\(set.index)") { bumpReps(-1) }
            TextField("", text: $repsText, prompt: Text(set.reps.map(String.init) ?? "").foregroundStyle(LW.ink(0.35)))
                .keyboardType(.numberPad).font(LWFont.mono(13, semibold: pr))
                .multilineTextAlignment(.center)
                .foregroundStyle(pr ? LW.accent : (set.done ? LW.ink : LW.ink(0.35)))
                .onChange(of: repsText) { _, v in set.reps = Int(v) }
                .accessibilityIdentifier("set.reps.\(set.index)")
            stepBtn("+", id: "set.reps.plus.\(set.index)") { bumpReps(+1) }
        }
        .frame(height: 36).frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 8).fill(LW.ink(set.done ? 0.1 : 0.06)))
    }
    private func stepBtn(_ sym: String, id: String, _ act: @escaping () -> Void) -> some View {
        Button(action: act) {
            Text(sym).font(LWFont.mono(14)).foregroundStyle(LW.ink(0.5))
                .frame(width: 26, height: 36).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityIdentifier(id)
    }
    private func bumpReps(_ d: Int) {
        let v = max(0, (Int(repsText) ?? set.reps ?? prev?.1 ?? 0) + d)
        repsText = String(v)                            // onChange commits + solidifies the ghost
        UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.6)
    }

    private func field(_ text: Binding<String>, placeholder: String, pr: Bool, commit: @escaping (String) -> Void) -> some View {
        TextField("", text: text, prompt: Text(placeholder).foregroundStyle(LW.ink(0.35)))
            .onReceive(NotificationCenter.default.publisher(for: UITextField.textDidBeginEditingNotification)) { note in
                (note.object as? UITextField)?.selectAll(nil)   // tap a number -> whole value selected, typing replaces it
            }
            .keyboardType(.decimalPad).font(LWFont.mono(13, semibold: pr))
            .foregroundStyle(pr ? LW.accent : (set.done ? LW.ink : LW.ink(0.35)))
            .padding(.horizontal, 9).frame(height: 30).frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 8).fill(LW.ink(set.done ? 0.1 : 0.06)))
            .onChange(of: text.wrappedValue) { _, v in commit(v) }
    }

    /// ✓ with nothing typed accepts the prefilled (last-time) values. The reward moment fires if the set beats the all-time best.
    private func toggle() {
        if !set.done {
            store.check(set, exerciseID: exerciseID, prev: prev)
            kgText = set.kg.map(Fmt.kg) ?? ""; repsText = set.reps.map(String.init) ?? ""
            if set.isPR { UINotificationFeedbackGenerator().notificationOccurred(.success) } else { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
        } else { store.uncheck(set) }
    }
}


/// The design's session "loading" bar: 3 pt track, sage fill, live percent of sets checked.
struct SessionProgressBar: View {
    let session: Session
    var body: some View {
        let p = AppStore.progress(session)
        HStack(spacing: 10) {
            GeometryReader { g in
                Capsule().fill(LW.ink(0.1))
                    .overlay(alignment: .leading) { Capsule().fill(LW.accent).frame(width: max(g.size.width * p, p > 0 ? 6 : 0)) }
            }
            .frame(height: 3)
            .animation(.timingCurve(0.2, 0.9, 0.2, 1, duration: 0.4), value: p)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier("session.progress")
        .accessibilityLabel("\(Int((p * 100).rounded()))%")
    }
}
