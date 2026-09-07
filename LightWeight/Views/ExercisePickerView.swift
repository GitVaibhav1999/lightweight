import SwiftUI
import SwiftData

/// S7 — search + target/equipment chips over the 1,312-exercise library and your own.
struct ExercisePickerView: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router
    let target: PickerTarget
    @State private var query = ""
    @State private var targetChip: String? = nil
    @State private var equipChip: String? = nil
    @State private var creating = false
    @State private var customName = ""
    @State private var customBodyweight = false

    private var targetName: String {
        switch target { case .workout(let id): return store.workout(id)?.name ?? "workout"; case .session(let id): return store.session(id)?.title ?? "session" }
    }
    private var dominantTarget: String? {
        let ids: [String]
        switch target { case .workout(let id): ids = store.workout(id)?.slots.map(\.exerciseID) ?? []; case .session(let id): ids = store.session(id)?.exercises.map(\.exerciseID) ?? [] }
        let counts = Dictionary(grouping: ids.compactMap { store.exercise($0)?.target }.filter { $0 != "custom" }, by: { $0 }).mapValues(\.count)
        return counts.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }.first?.key
    }

    var body: some View {
        let all = store.allExercises()
        let mine = all.filter { store.analysis.exerciseHistory[$0.id] != nil }.sorted { (store.analysis.exerciseHistory[$0.id]?.last?.date ?? .distantPast) > (store.analysis.exerciseHistory[$1.id]?.last?.date ?? .distantPast) }
        let filtered = all.filter(matches)
        let mineFiltered = mine.filter(matches)
        let chipTargets = ["All"] + ([targetChip, dominantTarget].compactMap { $0 } + ["upper back", "lats", "biceps", "pectorals", "delts", "quads", "hamstrings", "glutes", "triceps", "abs", "calves"]).uniqued().prefix(6)
        Screen {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Button { router.pop() } label: { Text("Cancel").font(LWFont.body(13)).foregroundStyle(LW.ink(0.6)) }.buttonStyle(.plain).accessibilityIdentifier("picker.cancel")
                    Spacer(); Text("Add to \(targetName)").font(LWFont.body(15, weight: 700)); Spacer(); Color.clear.frame(width: 40)
                }.frame(height: 28)
                HStack(spacing: 8) {
                    Icon(kind: .search, size: 15, color: LW.ink(0.4), weight: 2)
                    TextField("", text: $query, prompt: Text("Search \(Fmt.int(Double(all.count))) exercises").foregroundStyle(LW.ink(0.4))).font(LWFont.body(13)).foregroundStyle(LW.ink).accessibilityIdentifier("picker.search")
                }.padding(.horizontal, 12).frame(height: 40).background(RoundedRectangle(cornerRadius: 12).fill(LW.ink(0.08))).padding(.top, 14)
                chips(Array(chipTargets), selected: targetChip ?? "All") { targetChip = $0 == "All" ? nil : $0 }.padding(.top, 12)
                chips(["barbell", "cable", "dumbbell", "machine", "body weight", "kettlebell"], selected: equipChip ?? "") { equipChip = equipChip == $0 ? nil : $0 }.padding(.top, 6)
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 2) {
                        if !mineFiltered.isEmpty {
                            Text("In your workouts").lwLabel(10, tracking: 0.14).padding(.top, 16)
                            ForEach(mineFiltered.prefix(6), id: \.id) { e in row(e, sub: mineSub(e), accentPlus: true) }
                        }
                        Text("All · \(targetChip ?? "everything") · \(filtered.count)").lwLabel(10, tracking: 0.14).padding(.top, 14)
                        ForEach(filtered.prefix(60), id: \.id) { e in row(e, sub: "\(e.target) · \(e.equipment)", accentPlus: false) }
                        Color.clear.frame(height: 110)
                    }
                }
            }
        }
        .overlay(alignment: .bottom) {
            VStack(spacing: 8) {
                OutlinePill(title: "Create custom exercise") { customName = query; creating = true }
                Text("Thumbnails © Gym visual — gymvisual.com").font(LWFont.mono(9)).foregroundStyle(LW.ink(0.25))
            }.padding(.horizontal, LW.screenPad).padding(.bottom, LW.screenPad)
            .background(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.5)], startPoint: .top, endPoint: .bottom).frame(height: 170).allowsHitTesting(false), alignment: .bottom)
        }
        .onAppear { if targetChip == nil { targetChip = dominantTarget } }
        .alert("Custom exercise", isPresented: $creating) {
            TextField("Name", text: $customName)
            Button("Bodyweight") { create(bodyweight: true) }
            Button("Weighted") { create(bodyweight: false) }
            Button("Cancel", role: .cancel) {}
        } message: { Text("Added to your library and to \(targetName).") }
    }

    /// Typing searches the whole library; the target chip only narrows browsing.
    private func matches(_ e: Exercise) -> Bool {
        (query.isEmpty || e.name.localizedCaseInsensitiveContains(query))
        && (targetChip == nil || !query.isEmpty || e.target == targetChip)
        && (equipChip == nil || (equipChip == "machine" ? e.equipment.contains("machine") : e.equipment == equipChip))
    }
    private func mineSub(_ e: Exercise) -> String {
        let w = store.workouts().first { $0.slots.contains { $0.exerciseID == e.id } }?.name
        let last = store.analysis.exerciseHistory[e.id]?.last.map { Fmt.set($0.kg, $0.reps) } ?? ""
        return [w.map { "in \($0)" }, last.isEmpty ? nil : "last \(last)"].compactMap { $0 }.joined(separator: " · ")
    }
    private func chips(_ items: [String], selected: String, tap: @escaping (String) -> Void) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(items, id: \.self) { t in
                    Button { tap(t) } label: {
                        Text(t).font(LWFont.mono(10.5)).foregroundStyle(t == selected ? LW.accent : LW.ink(0.5)).padding(.horizontal, 11).frame(height: 28)
                            .overlay(Capsule().strokeBorder(t == selected ? LW.accent : LW.ink(0.25), lineWidth: 1)).contentShape(Capsule())
                    }.buttonStyle(.plain)
                }
            }
        }
    }
    private func row(_ e: Exercise, sub: String, accentPlus: Bool) -> some View {
        Button { add(e) } label: {
            HStack(spacing: 12) {
                ExerciseThumb(exercise: e, size: 38)
                VStack(alignment: .leading, spacing: 1) { Text(e.name).font(LWFont.body(13.5)).lineLimit(1); Text(sub).font(LWFont.mono(10.5)).foregroundStyle(LW.ink(0.4)).lineLimit(1) }
                Spacer(); Text("+").font(LWFont.body(18)).foregroundStyle(accentPlus ? LW.accent : LW.ink(0.35))
            }.frame(height: 52).overlay(alignment: .bottom) { Hairline() }.contentShape(Rectangle())
        }.buttonStyle(.plain)
    }
    private func add(_ e: Exercise) {
        switch target {
        case .workout(let id):
            guard let w = store.workout(id) else { return }
            let s = WorkoutSlot(order: w.slots.count, exerciseID: e.id, exerciseName: e.name, sets: 3, repLo: 8, repHi: 12); s.workout = w; store.context.insert(s)
        case .session(let id):
            guard let s = store.session(id) else { return }
            store.addExercise(to: s, exerciseID: e.id, name: e.name)
        }
        try? store.context.save(); router.pop()
    }
    private func create(bodyweight: Bool) {
        let name = customName.trimmingCharacters(in: .whitespaces); guard !name.isEmpty else { return }
        let e = Exercise(id: "custom-" + UUID().uuidString, name: name, bodyPart: "", target: "custom", equipment: "", loadType: bodyweight ? "bodyweight+reps" : "weight+reps", source: "custom")
        store.context.insert(e); try? store.context.save(); store.reload(); add(e)
    }
}

extension Array where Element: Hashable {
    func uniqued() -> [Element] { var seen = Set<Element>(); return filter { seen.insert($0).inserted } }
}
