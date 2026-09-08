import SwiftUI
import SwiftData

/// S5 — WORKOUTS: the active routine loop, then every workout.
struct WorkoutsView: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router
    @State private var pendingDelete: UUID?
    @State private var drag: ReorderState?
    private var editing: Bool { router.workoutsEditing }

    var body: some View {
        @Bindable var router = router
        let _ = store.dataTick
        let routine = store.activeRoutine()
        let entries = routine?.orderedEntries ?? []
        let slots = store.routineSlots()
        let pointer = entries.isEmpty ? 0 : (routine?.pointer ?? 0) % entries.count
        let all = store.workouts().map { ($0, store.sessionCount(workoutID: $0.id)) }.sorted { ((store.isPinned($0.0.id) ? 1 : 0), $0.1) > ((store.isPinned($1.0.id) ? 1 : 0), $1.1) }
        Screen(top: 102, underBar: true) {
            VStack(alignment: .leading, spacing: 0) {
                HeaderScroll(page: .workouts, edit: $router.workoutsEditing) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("WORKOUTS").font(LWFont.display(34, width: 85)).tracking(-0.7).padding(.top, 6).accessibilityIdentifier("page.workouts")
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(entries.isEmpty ? "Routine" : "Routine · \(entries.count) slots").lwLabel(10, tracking: 0.14, color: LW.accent); Spacer()
                            Text(editing ? "drag to reorder · − removes" : "\(routine?.name ?? "No routine") · repeats in order").font(LWFont.mono(11)).foregroundStyle(LW.ink(0.45))
                        }.padding(.top, 16)
                        if entries.isEmpty { EmptyRoutineSlots() }
                        VStack(spacing: 0) {
                            ForEach(slots) { s in
                                if let w = store.workout(s.workoutID) {
                                    let i = s.index
                                    HStack(spacing: 10) {
                                        if editing { ReorderHandle(index: i, count: slots.count, rowHeight: 46, drag: $drag) { from, to in store.moveSlot(from: from, to: to) } }
                                        Text("\(i + 1)").font(LWFont.mono(10)).foregroundStyle(i == pointer ? LW.accent : LW.ink(0.4)).frame(width: 12, alignment: .leading)
                                        Button { router.push(.workoutEdit(w.id)) } label: { Text(w.name).font(LWFont.body(14)).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle()) }.buttonStyle(.plain).accessibilityIdentifier("routine.row")
                                        if store.liveSession()?.workoutID == s.workoutID { Text("● LIVE").font(LWFont.mono(9.5)).tracking(1).foregroundStyle(LW.accent) }
                                        // where else this workout takes a turn — absent when it takes only one
                                        if s.repeated { Text("also \(s.alsoFills.map(String.init).joined(separator: ", "))").font(LWFont.mono(9)).foregroundStyle(LW.ink(0.35)).accessibilityIdentifier("routine.also.\(i)") }
                                        Text("\(w.slots.count) ex").font(LWFont.mono(11)).foregroundStyle(LW.ink(0.45))
                                        if editing { Button { store.removeSlot(s.entry) } label: { Icon(kind: .minusCircle, size: 14, color: LW.ink(0.35), weight: 1.7).frame(width: 28, height: 28).contentShape(Rectangle()) }.buttonStyle(.plain).accessibilityIdentifier("routine.remove.\(i)") }
                                    }.frame(height: 46)
                                    .background { if i == pointer { RoundedRectangle(cornerRadius: 10, style: .continuous).fill(LW.accent(0.06)).padding(.horizontal, -8) } }
                                    .overlay(alignment: .bottom) { if i != pointer, i + 1 != pointer { Hairline() } }
                                    .reorderOffset(index: i, drag: drag, rowHeight: 46)
                                }
                            }
                            if editing, !entries.isEmpty {
                                HStack(spacing: 12) {
                                    Button { router.slotPicker = true } label: {
                                        Text("+ Add slot").font(LWFont.body(14, weight: 600)).foregroundStyle(LW.accent)
                                            .frame(height: 44).contentShape(Rectangle())
                                    }.buttonStyle(.plain).accessibilityIdentifier("slot.add")
                                    if store.routineHasRepeats() { Text("any workout, again is fine").font(LWFont.mono(9)).foregroundStyle(LW.ink(0.3)) }
                                    Spacer()
                                }
                            }
                        }.padding(.top, 4)

                        HStack(alignment: .firstTextBaseline, spacing: 14) {
                            Text("All workouts").lwLabel(10, tracking: 0.14); Spacer()
                            // the nav's + is gone, so the start sheet (and its empty session) lives here now
                            Button { router.startSheet = true } label: { Text("Empty session").font(LWFont.mono(11)).foregroundStyle(LW.ink(0.5)) }
                                .buttonStyle(.plain).accessibilityIdentifier("workouts.empty.session")
                            Button { let w = Workout(name: "New workout"); store.context.insert(w); try? store.context.save(); store.dataTick += 1; router.push(.workoutEdit(w.id)) } label: { Text("+ New workout").font(LWFont.mono(11)).foregroundStyle(LW.accent) }.buttonStyle(.plain)
                        }.padding(.top, 22)
                        if all.isEmpty {
                            EmptyWorkoutsCard { let w = Workout(name: "New workout"); store.context.insert(w); try? store.context.save(); store.dataTick += 1; router.push(.workoutEdit(w.id)) }
                        }
                        VStack(spacing: 0) {
                            ForEach(all, id: \.0.id) { w, n in
                                HStack(spacing: 12) {
                                    Button { router.push(.workoutEdit(w.id)) } label: { Text(w.name).font(LWFont.body(13.5)).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle()) }.buttonStyle(.plain)
                                    Text("\(n)×").font(LWFont.mono(11)).foregroundStyle(LW.ink(0.45))
                                    if editing {                       // already in the loop? another slot is fine
                                        Button { add(w, to: routine) } label: {
                                            ZStack {
                                                Circle().strokeBorder(LW.accent(0.6), lineWidth: 1.2).frame(width: 24, height: 24)
                                                Text("+").font(LWFont.body(14, weight: 700)).foregroundStyle(LW.accent).offset(y: -0.5)
                                            }.frame(width: 30, height: 30).contentShape(Rectangle())
                                        }.buttonStyle(.plain).accessibilityIdentifier("loop.add.\(w.name)").accessibilityLabel("Add \(w.name) to routine")
                                    }
                                    if editing {
                                        Button { store.togglePin(w.id) } label: {
                                            Image(systemName: store.isPinned(w.id) ? "pin.fill" : "pin")
                                                .font(.system(size: 12, weight: .semibold))
                                                .foregroundStyle(store.isPinned(w.id) ? LW.accent : LW.ink(0.35))
                                                .frame(width: 28, height: 28).contentShape(Rectangle())
                                        }.buttonStyle(.plain).accessibilityIdentifier("pin.\(w.name)").accessibilityValue(store.isPinned(w.id) ? "pinned" : "unpinned")
                                        Button { withAnimation(.easeOut(duration: 0.18)) { pendingDelete = pendingDelete == w.id ? nil : w.id } } label: { Icon(kind: .trash, size: 14, color: pendingDelete == w.id ? LW.ink(0.7) : LW.ink(0.35), weight: 1.7).frame(width: 28, height: 28).contentShape(Rectangle()) }.buttonStyle(.plain).accessibilityIdentifier("delete.\(w.name)")
                                        if pendingDelete == w.id {
                                            Button { withAnimation(.easeOut(duration: 0.15)) { delete(w, routine); pendingDelete = nil } } label: {
                                                Text("Delete").font(LWFont.body(13, weight: 700)).foregroundStyle(.white)
                                                    .padding(.horizontal, 14).frame(height: 34)
                                                    .background(RoundedRectangle(cornerRadius: 12).fill(Color(red: 0.88, green: 0.32, blue: 0.28)))
                                                    .contentShape(Rectangle())
                                            }.buttonStyle(.plain).accessibilityIdentifier("delete.confirm").transition(.move(edge: .trailing).combined(with: .opacity))
                                        }
                                    } else {
                                        Text("›").foregroundStyle(LW.ink(0.3))
                                    }
                                }.frame(height: 46).overlay(alignment: .bottom) { Hairline() }
                            }
                        }.padding(.top, 4)
                        Color.clear.frame(height: 90)
                    }
                }.padding(.top, 2)
            }
        }
        .overlay {
            if editing {
                LinearGradient(colors: [LW.accent(0.06), .clear], startPoint: .top, endPoint: .bottom)
                    .frame(height: 120).frame(maxHeight: .infinity, alignment: .top)
                    .ignoresSafeArea().allowsHitTesting(false)
            }
        }
        .sheet(isPresented: $router.slotPicker) { SlotPickerSheet().environment(store).environment(router) }
    }
    private func add(_ w: Workout, to r: Routine?) { store.addToRoutine(w) }
    private func delete(_ w: Workout, _ r: Routine?) { store.deleteWorkout(w) }
}

/// "+ Add slot": every workout, pickable. One already in the loop simply takes another slot —
/// that is the loop working, not a duplicate, so nothing warns and nothing is disabled.
struct SlotPickerSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router
    var body: some View {
        let slots = store.routineSlots()
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                Text("ADD A SLOT").font(LWFont.display(24, width: 85)).tracking(-0.4).padding(.top, 22)
                Text("ANY WORKOUT · AGAIN IS FINE").font(LWFont.mono(10)).tracking(1.4)
                    .foregroundStyle(LW.ink(0.4)).padding(.top, 4).padding(.bottom, 10)
                ForEach(store.workouts(), id: \.id) { w in
                    let fills = slots.filter { $0.workoutID == w.id }.map { $0.index + 1 }
                    Button {
                        store.addToRoutine(w); router.slotPicker = false
                    } label: {
                        HStack(spacing: 10) {
                            Text(Fmt.title(w.name)).font(LWFont.heading(17, width: 90)).tracking(-0.2)
                                .lineLimit(1).minimumScaleFactor(0.6)
                            Spacer(minLength: 8)
                            if !fills.isEmpty {
                                Text("slot \(fills.map(String.init).joined(separator: ", "))").font(LWFont.mono(10)).foregroundStyle(LW.ink(0.38))
                            }
                            Text("\(w.slots.count) ex").font(LWFont.mono(10)).foregroundStyle(LW.ink(0.38))
                        }
                        .padding(.vertical, 14).contentShape(Rectangle())
                        .overlay(alignment: .bottom) { Hairline() }
                    }.buttonStyle(.plain).accessibilityIdentifier("slot.pick.\(w.name)")
                }
                Color.clear.frame(height: 24)
            }
            .padding(.horizontal, LW.screenPad)
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(LW.bg)
        .accessibilityElement(children: .contain).accessibilityIdentifier("slot.picker")
    }
}
