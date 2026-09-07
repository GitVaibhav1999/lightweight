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
        let loopIDs = Set(entries.map(\.workoutID))
        let all = store.workouts().map { ($0, store.sessionCount(workoutID: $0.id)) }.sorted { ((store.isPinned($0.0.id) ? 1 : 0), $0.1) > ((store.isPinned($1.0.id) ? 1 : 0), $1.1) }
        Screen(top: 102, underBar: true) {
            VStack(alignment: .leading, spacing: 0) {
                HeaderScroll(page: .workouts, edit: $router.workoutsEditing) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("WORKOUTS").font(LWFont.display(34, width: 85)).tracking(-0.7).padding(.top, 6).accessibilityIdentifier("page.workouts")
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text("Routine").lwLabel(10, tracking: 0.14, color: LW.accent); Spacer()
                            Text(editing ? "drag to reorder · − removes" : "\(routine?.name ?? "No routine") · repeats in order").font(LWFont.mono(11)).foregroundStyle(LW.ink(0.45))
                        }.padding(.top, 16)
                        if entries.isEmpty { EmptyRoutineSlots() }
                        VStack(spacing: 0) {
                            ForEach(Array(entries.enumerated()), id: \.element.persistentModelID) { i, e in
                                if let w = store.workout(e.workoutID) {
                                    HStack(spacing: 10) {
                                        if editing { ReorderHandle(index: i, count: entries.count, rowHeight: 48, drag: $drag) { from, to in move(routine, from: from, to: to) } }
                                        Text("\(i + 1)").font(LWFont.mono(11)).foregroundStyle(LW.ink(0.3)).frame(width: 12, alignment: .leading)
                                        Button { router.push(.workoutEdit(w.id)) } label: { Text(w.name).font(LWFont.body(14)).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle()) }.buttonStyle(.plain).accessibilityIdentifier("routine.row")
                                        if store.liveSession()?.workoutID == e.workoutID { Text("● LIVE").font(LWFont.mono(9.5)).tracking(1).foregroundStyle(LW.accent) }
                                        else if i == (routine?.pointer ?? 0) % max(entries.count, 1) { Text("● NEXT").font(LWFont.mono(9.5)).tracking(1).foregroundStyle(LW.accent) }
                                        Text("\(w.slots.count) ex").font(LWFont.mono(11)).foregroundStyle(LW.ink(0.45))
                                        if editing { Button { remove(e, from: routine) } label: { Icon(kind: .minusCircle, size: 14, color: LW.ink(0.35), weight: 1.7).frame(width: 28, height: 28).contentShape(Rectangle()) }.buttonStyle(.plain).accessibilityIdentifier("routine.remove.\(i)") }
                                    }.frame(height: 48).overlay(alignment: .bottom) { Hairline() }
                                    .reorderOffset(index: i, drag: drag, rowHeight: 48)
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
                                    if editing, !loopIDs.contains(w.id) {
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
    }
    /// Reorder the loop; the pointer follows the workout it was on.
    private func move(_ r: Routine?, from: Int, to: Int) {
        guard let r else { return }
        var es = r.orderedEntries; let pointed = es.indices.contains(r.pointer) ? es[r.pointer].workoutID : nil
        let e = es.remove(at: from); es.insert(e, at: to)
        for (i, x) in es.enumerated() { x.order = i }
        if let pointed, let i = es.firstIndex(where: { $0.workoutID == pointed }) { r.pointer = i }
        try? store.context.save(); store.dataTick += 1
    }
    private func remove(_ e: RoutineEntry, from r: Routine?) {
        guard let r else { return }
        store.context.delete(e)
        for (i, x) in r.orderedEntries.filter({ $0 !== e }).enumerated() { x.order = i }
        r.pointer = 0; try? store.context.save(); store.dataTick += 1
    }
    private func add(_ w: Workout, to r: Routine?) { store.addToRoutine(w) }
    private func delete(_ w: Workout, _ r: Routine?) {
        for e in r?.entries.filter({ $0.workoutID == w.id }) ?? [] { store.context.delete(e) }
        store.context.delete(w); try? store.context.save(); store.dataTick += 1
    }
}
