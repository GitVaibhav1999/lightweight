import SwiftUI

/// S4 — "am I progressing on this lift" in one glance.
struct ExerciseDetailView: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router
    let exerciseID: String

    var body: some View {
        let ex = store.exercise(exerciseID)
        let st = store.analysis.exerciseStats(exerciseID)
        let hist = st?.history.suffix(12) ?? []
        Screen {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Button { router.pop() } label: { Icon(kind: .chevronLeft, size: 18, color: LW.ink(0.6)).frame(width: 44, height: 36).contentShape(Rectangle()) }.buttonStyle(.plain).offset(x: -12).accessibilityIdentifier("exercise.back")
                    Spacer(); Text("Edit").font(LWFont.mono(11)).foregroundStyle(LW.ink(0.45))
                }.frame(height: 28)
                HStack(alignment: .top, spacing: 12) {
                    Text((ex?.name ?? exerciseID).uppercased()).font(LWFont.display(28, width: 88)).tracking(-0.6).lineLimit(2)
                    Spacer(minLength: 0)
                    ExerciseThumb(exercise: ex, size: 56)
                }.padding(.top, 14)
                Text(ex.map { "\($0.target) · \($0.equipment.isEmpty ? "custom" : $0.equipment)" } ?? "").font(LWFont.mono(11)).foregroundStyle(LW.ink(0.45)).padding(.top, 4)
                HStack(spacing: 8) {
                    VerdictIcon(verdict: st?.lastVerdict, size: 14)
                    Text(streakText(st)).font(LWFont.mono(11)).foregroundStyle(LW.accent)
                    Spacer()
                    Text("best e1RM \(Fmt.e1rm(st?.best ?? 0))").font(LWFont.mono(11)).foregroundStyle(LW.ink(0.35))
                }.padding(.top, 8)
                ProgressionChart(values: hist.map(\.e1rm), labelLeft: hist.first.map { Fmt.date($0.date, "d MMM") } ?? "", labelRight: hist.last.map { Fmt.date($0.date, "d MMM") } ?? "", caption: "\(hist.count) sessions · e1RM", format: { Fmt.e1rm($0) })
                    .padding(EdgeInsets(top: 14, leading: 14, bottom: 8, trailing: 14))
                    .lwGlass(RoundedRectangle(cornerRadius: 20), tint: LW.ink(0.05), rim: 0.12, shadow: false)
                    .padding(.top, 16)
                HStack(alignment: .top, spacing: 8) {
                    stat(Fmt.e1rm(st?.best ?? 0), "Best e1RM"); stat(Fmt.e1rm(st?.last ?? 0), "Last")
                    stat(st?.delta30.map(Fmt.pct) ?? "—", "Δ 30 days", accent: (st?.delta30 ?? 0) > 0)
                }.padding(.top, 16)
                VStack(spacing: 0) {
                    ForEach(Array(hist.reversed().prefix(5).enumerated()), id: \.offset) { _, p in
                        HStack(spacing: 12) {
                            Text(Fmt.date(p.date, "d MMM")).foregroundStyle(LW.ink(0.45)); Spacer()
                            Text(Fmt.set(p.kg, p.reps)); Text(Fmt.e1rm(p.e1rm)).foregroundStyle(LW.ink(0.45)); VerdictIcon(verdict: p.verdict)
                        }.font(LWFont.mono(12)).frame(height: 40).overlay(alignment: .top) { Hairline() }
                    }
                    Hairline()
                }.padding(.top, 14)
                Spacer()
            }
        }
    }
    private func stat(_ v: String, _ l: String, accent: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 2) { Text(v).font(LWFont.mono(20, semibold: true)).foregroundStyle(accent ? LW.accent : LW.ink); Text(l).lwLabel(9.5, tracking: 0.12) }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private func streakText(_ st: Analysis.ExerciseStats?) -> String {
        guard let st else { return "no history" }
        return st.streak > 0 ? "up ×\(st.streak)" : (st.lastVerdict == .held ? "held" : st.lastVerdict == .down ? "down" : "—")
    }
}
