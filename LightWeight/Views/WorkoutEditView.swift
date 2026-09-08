import SwiftUI
import SwiftData

/// S6 — slots, not exercises: exercise · sets · rep range. Tap a row for the glass sheet.
struct WorkoutEditView: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router
    let workoutID: UUID
    @State private var selected: WorkoutSlot?
    @State private var renaming = false
    @State private var drag: ReorderState?
    @State private var newName = ""

    var body: some View {
        if let w = store.workout(workoutID) { content(w) } else { Screen { Text("Workout not found").foregroundStyle(LW.ink(0.5)) } }
    }

    private func content(_ w: Workout) -> some View {
        @Bindable var w = w
        let inLoop = store.activeRoutine()?.entries.contains { $0.workoutID == w.id } ?? false
        let mins = medianMinutes(w)
        return Screen {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Button { save(); router.pop() } label: { HStack(spacing: 4) { Icon(kind: .chevronLeft, size: 16, color: LW.ink(0.6)); Text("Routines").font(LWFont.body(13)).foregroundStyle(LW.ink(0.6)) }.frame(height: 36).contentShape(Rectangle()) }.buttonStyle(.plain).offset(x: -4).accessibilityIdentifier("edit.back")
                    Spacer()
                    if router.workoutsEditing {
                        Button { save(); router.pop() } label: { Text("Save").font(LWFont.body(13, weight: 600)).foregroundStyle(LW.accent) }
                            .buttonStyle(.plain).accessibilityIdentifier("edit.save")
                    }
                }.frame(height: 28)
                Button { newName = w.name; renaming = true } label: {
                    Text(Fmt.title(w.name)).font(LWFont.display(24, width: 88)).tracking(-0.4)
                        .lineLimit(2).minimumScaleFactor(0.65).multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                        .overlay(alignment: .bottom) { Rectangle().fill(LW.ink(0.3)).frame(height: 1).mask(DashMask()).offset(y: 2) }
                }.buttonStyle(.plain).padding(.top, 14)
                .alert("Rename workout", isPresented: $renaming) { TextField("Name", text: $newName); Button("Save") { if !newName.isEmpty { w.name = newName; save() } }; Button("Cancel", role: .cancel) {} }
                Text("\(w.slots.count) exercises · ~\(mins) min\(inLoop ? " · in loop" : "")").font(LWFont.mono(11)).foregroundStyle(LW.ink(0.45)).padding(.top, 4)
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        let slots = w.orderedSlots
                        ForEach(Array(slots.enumerated()), id: \.element.persistentModelID) { i, slot in
                            HStack(spacing: 10) {
                                ReorderHandle(index: i, count: slots.count, rowHeight: 44, drag: $drag) { from, to in
                                    var ss = w.orderedSlots; let s = ss.remove(at: from); ss.insert(s, at: to); for (j, x) in ss.enumerated() { x.order = j }; save()
                                }
                            Button { selected = slot } label: {
                                HStack(spacing: 10) {
                                    Text(slot.exerciseName).font(LWFont.body(13.5)).frame(maxWidth: .infinity, alignment: .leading)
                                    Text("\(slot.sets) × \(slot.repLo)–\(slot.repHi)").font(LWFont.mono(11)).foregroundStyle(LW.ink(0.45))
                                    Text("›").foregroundStyle(LW.ink(0.3))
                                }.frame(height: 44).contentShape(Rectangle())
                            }.buttonStyle(.plain)
                            }.frame(height: 44).overlay(alignment: .bottom) { Hairline() }.reorderOffset(index: i, drag: drag, rowHeight: 44)
                        }
                        if router.workoutsEditing {
                            OutlinePill(title: "+ Add exercise") { router.push(.picker(.workout(w.id))) }.padding(.top, 14)
                        }
                        Color.clear.frame(height: 180)
                    }
                }.padding(.top, 12)
            }
        }
        .overlay(alignment: .bottom) {
            if !router.workoutsEditing, selected == nil {
                Button {
                    let s = store.startSession(from: w)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { router.present(.session(s.id)) }
                } label: {
                    Text("Start").font(LWFont.heading(20, width: 92)).tracking(-0.2).foregroundStyle(LW.inkOnAccent)
                        .frame(maxWidth: .infinity).frame(height: 48)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(LW.accent))
                }.buttonStyle(.plain)
                .padding(.horizontal, LW.screenPad).padding(.bottom, 18)
                .accessibilityIdentifier("workout.start").accessibilityLabel("Start \(w.name)")
            }
        }
        .overlay(alignment: .bottom) { if let s = selected { slotSheet(s, w) } }
        .onAppear { if CommandLine.arguments.contains("--demo-sheet") { selected = w.orderedSlots.first } }
    }

    private func slotSheet(_ s: WorkoutSlot, _ w: Workout) -> some View {
        VStack(spacing: 12) {
            Capsule().fill(LW.ink(0.3)).frame(width: 36, height: 4)
            HStack { Text(s.exerciseName).font(LWFont.body(15, weight: 700)); Spacer()
                Button { store.context.delete(s); reindex(w); selected = nil; store.workoutEdited(w) } label: { Text("Remove").font(LWFont.body(12)).foregroundStyle(LW.ink(0.5)) }.buttonStyle(.plain) }
            HStack(spacing: 10) {
                stepper("Sets", "\(s.sets)") { s.sets = max(1, s.sets - 1) } plus: { s.sets = min(10, s.sets + 1) }
                stepper("Rep range", "\(s.repLo)–\(s.repHi)") { s.repLo = max(1, s.repLo - 1); s.repHi = max(s.repLo, s.repHi - 1) } plus: { s.repLo += 1; s.repHi += 1 }
            }
        }
        .padding(EdgeInsets(top: 14, leading: 22, bottom: 40, trailing: 22))
        .frame(maxWidth: .infinity)
        .glassEffect(.regular, in: UnevenRoundedRectangle(topLeadingRadius: 24, topTrailingRadius: 24))
        .overlay(alignment: .top) { Rectangle().fill(LW.ink(0.16)).frame(height: 0.5) }
        .shadow(color: .black.opacity(0.5), radius: 20, y: -14)
        .onTapGesture {}
        .ignoresSafeArea()
    }
    private func stepper(_ label: String, _ value: String, minus: @escaping () -> Void, plus: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label).lwLabel(9.5, tracking: 0.12, color: LW.ink(0.35))
            HStack {
                Button(action: { minus(); if let w = store.workout(workoutID) { store.workoutEdited(w) } }) { Text("−").foregroundStyle(LW.ink(0.5)).frame(width: 26, height: 26).background(Circle().fill(LW.ink(0.08))) }.buttonStyle(.plain)
                Spacer(); Text(value).font(LWFont.mono(13)); Spacer()
                Button(action: { plus(); if let w = store.workout(workoutID) { store.workoutEdited(w) } }) { Text("+").foregroundStyle(LW.accent).frame(width: 26, height: 26).background(Circle().fill(LW.accent(0.15))) }.buttonStyle(.plain)
            }.padding(.horizontal, 5).frame(height: 36).background(RoundedRectangle(cornerRadius: 9).fill(LW.ink(0.1)))
        }.frame(maxWidth: .infinity)
    }
    private func reindex(_ w: Workout) { for (i, s) in w.orderedSlots.enumerated() { s.order = i } }
    private func save() { if let w = store.workout(workoutID) { store.workoutEdited(w) } }
    private func medianMinutes(_ w: Workout) -> Int {
        let m = store.finishedSessions().filter { $0.workoutID == w.id }.map(\.durationMinutes).sorted()
        return m.isEmpty ? max(10, w.slots.reduce(0) { $0 + $1.sets } * 3) : m[m.count / 2]
    }
}

struct DashMask: View {
    var body: some View { GeometryReader { g in HStack(spacing: 3) { ForEach(0..<Int(g.size.width / 6), id: \.self) { _ in Rectangle().frame(width: 3) } } } }
}
