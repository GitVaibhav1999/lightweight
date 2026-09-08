import SwiftUI

/// S3 — the payoff: records, verdict per exercise, workout progression, back to Home.
struct SummaryView: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router
    let sessionID: UUID
    @State private var yearly = false

    @State private var editing = false
    var body: some View {
        if let s = store.session(sessionID) { content(s) } else { Screen { Text("Session not found").foregroundStyle(LW.ink(0.5)) } }
    }

    private func content(_ s: Session) -> some View {
        let r = store.result(s)
        let series = progression(s)
        return Screen(top: 62) {
            VStack(alignment: .leading, spacing: 0) {
                ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("Session complete").lwLabel(10, tracking: 0.16, color: LW.accent)
                    Spacer()
                    Button { withAnimation(.easeOut(duration: 0.2)) { editing.toggle() } } label: {
                        Image(systemName: editing ? "checkmark" : "pencil")
                            .font(.system(size: 14, weight: .semibold)).foregroundStyle(editing ? LW.inkOnAccent : LW.accent)
                            .frame(width: 34, height: 30)
                            .background { if editing { Capsule().fill(LW.accent) } }
                            .glassEffect(.regular.interactive(), in: Capsule())
                            .contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityIdentifier("summary.edit")
                        .onChange(of: editing) { was, now in if was, !now { store.saveSessionEdit(s) } }
                }
                Text(Fmt.title(s.title)).font(LWFont.display(46, width: 85)).tracking(-1.4).lineLimit(1).minimumScaleFactor(0.6).padding(.top, 6)
                HStack(spacing: 10) {
                    Text(Fmt.date(s.startedAt, "EEE d MMM · HH:mm")).font(LWFont.mono(11)).foregroundStyle(LW.ink(0.45))
                    if s.edited { Text("EDITED").font(LWFont.mono(9)).tracking(1).foregroundStyle(LW.ink(0.4)) }
                    VerdictBadge(state: r?.state)
                    if let d = r?.delta { Text("\(Fmt.pct(d)) vs last").font(LWFont.mono(11)).foregroundStyle(LW.ink(0.35)) }
                    else if r != nil { Text("new mix · no verdict").font(LWFont.mono(11)).foregroundStyle(LW.ink(0.35)) }
                }.padding(.top, 6)
                HStack(alignment: .top, spacing: 8) {
                    stat("Duration") { Text("\(s.durationMinutes)").font(LWFont.mono(21, semibold: true)) + Text(" min").font(LWFont.mono(12)).foregroundStyle(LW.ink(0.45)) }
                    stat("All-time best") { HStack(spacing: 5) { Icon(kind: .arrowUp, size: 14, color: LW.accent, weight: 2); Text("\(r?.prs.count ?? 0)").font(LWFont.mono(21, semibold: true)).foregroundStyle(LW.accent) } }
                    stat("Went up") { Text("\(r?.upCount ?? 0)").font(LWFont.mono(21, semibold: true)) + Text(" / \(s.exercises.count)").font(LWFont.mono(12)).foregroundStyle(LW.ink(0.45)) }
                }.padding(.top, 22)
                CoachPanel(session: s).padding(.top, 16)
                HStack {
                    Text("Workout progression").lwLabel(10, tracking: 0.14)
                    Spacer()
                    RangeToggle(yearly: $yearly)
                }.padding(.top, 18)
                ChartCard(title: s.title, subtitle: "session volume", delta: series.delta, values: series.values, left: series.left, right: series.right, caption: series.caption).padding(.top, 10)
                if editing {
                    VStack(alignment: .leading, spacing: 20) {
                        ForEach(s.orderedExercises, id: \.persistentModelID) { se in SessionExerciseBlock(se: se) }
                    }.padding(.top, 20)
                } else {
                VStack(spacing: 0) {
                    ForEach(s.orderedExercises, id: \.persistentModelID) { se in
                        Button { router.push(.exercise(se.exerciseID)) } label: {
                            HStack(spacing: 10) {
                                Text(se.exerciseName).font(LWFont.body(13.5)).lineLimit(1); Spacer()
                                Text(Engine.topSet(se.orderedSets.map { SetInput(kg: $0.kg, reps: $0.reps, isWarmup: $0.type == "warmup") }).map { Fmt.set($0.kg, $0.reps) } ?? "—").font(LWFont.mono(12)).foregroundStyle(LW.ink(0.5))
                                VerdictIcon(verdict: r?.exerciseVerdicts[se.exerciseID])
                            }.frame(height: 44).overlay(alignment: .top) { Hairline() }.contentShape(Rectangle())
                        }.buttonStyle(.plain)
                    }
                    Hairline()
                }.padding(.top, 20)
                }
                Color.clear.frame(height: 20)
                }
                }
                Spacer(minLength: 10)
                VStack(spacing: 10) {
                    HStack(spacing: 0) { Text("NEXT · ").foregroundStyle(LW.ink(0.45)); Text(Fmt.title(store.nextWorkout()?.name ?? "—")).foregroundStyle(LW.accent); Text(nextSlot).foregroundStyle(LW.ink(0.45)) }
                        .font(LWFont.mono(11)).lineLimit(1).minimumScaleFactor(0.8).frame(maxWidth: .infinity)
                    Button { router.home() } label: {
                        Text("DONE").font(LWFont.body(15, weight: 800)).tracking(1).foregroundStyle(.black).frame(maxWidth: .infinity).frame(height: 56)
                            .background(Capsule().fill(LW.accent)).shadow(color: LW.accent(0.3), radius: 12, y: 8)
                    }.buttonStyle(.plain).accessibilityIdentifier("summary.done").padding(.bottom, 28)
                }
            }
        }
    }

    /// " · SLOT 5 OF 6" — the loop already advanced, so the pointer IS the next slot.
    private var nextSlot: String {
        guard let p = store.routineProgress() else { return " · loop advanced" }
        return " · \(store.routineHasRepeats() ? "SLOT " : "")\(min(p.done + 1, p.total)) OF \(p.total)"
    }

    private func stat<V: View>(_ label: String, @ViewBuilder _ value: () -> V) -> some View {
        VStack(alignment: .leading, spacing: 2) { value(); Text(label).lwLabel(9.5, tracking: 0.12) }.frame(maxWidth: .infinity, alignment: .leading)
    }

    struct Series { var values: [Double]; var delta: String; var left: String; var right: String; var caption: String }
    private func progression(_ s: Session) -> Series {
        let all = store.analysis.volumeSeries(group: s.groupKey).filter { $0.date <= s.startedAt }
        let since = Calendar.current.date(byAdding: yearly ? .year : .month, value: -1, to: s.startedAt)!
        let pts = all.filter { $0.date >= since }
        let vals = pts.map(\.volume)
        let delta = (vals.first.flatMap { f in vals.last.map { l in f > 0 ? Fmt.pct((l - f) / f * 100) : "" } }) ?? ""
        return Series(values: vals, delta: delta, left: pts.first.map { Fmt.date($0.date, yearly ? "MMM yy" : "d MMM") } ?? "", right: pts.last.map { Fmt.date($0.date, yearly ? "MMM yy" : "d MMM") } ?? "",
                      caption: "\(pts.count) sessions · \(yearly ? "12 mo" : Fmt.date(s.startedAt, "MMM"))")
    }
}

struct RangeToggle: View {
    @Binding var yearly: Bool
    var body: some View {
        HStack(spacing: 2) { seg("MONTH", !yearly) { yearly = false }; seg("YEAR", yearly) { yearly = true } }
            .padding(2).background(Capsule().fill(LW.ink(0.08)))
    }
    private func seg(_ t: String, _ on: Bool, _ a: @escaping () -> Void) -> some View {
        Button(action: a) { Text(t).font(LWFont.mono(10)).tracking(0.8).foregroundStyle(on ? LW.accent : LW.ink(0.45)).padding(.horizontal, 12).padding(.vertical, 3).background(Capsule().fill(on ? LW.accent(0.18) : .clear)).contentShape(Capsule()) }.buttonStyle(.plain)
    }
}

/// Glass gradient card wrapping a ProgressionChart, with the "Name · metric   +9%" header.
struct ChartCard: View {
    var chartHeight: CGFloat? = nil
    var valueFormat: ((Double) -> String)? = nil
    private var chartView: ProgressionChart {
        var c = ProgressionChart(values: values, labelLeft: left, labelRight: right, caption: caption, fixedHeight: chartHeight)
        if let f = valueFormat { c.format = f }
        return c
    }
    let title: String; let subtitle: String; let delta: String
    let values: [Double]; let left: String; let right: String; let caption: String
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                (Text(title).font(LWFont.body(13.5, weight: 700)) + Text(" · \(subtitle)").font(LWFont.mono(10)).foregroundStyle(LW.ink(0.35))).lineLimit(1)
                Spacer(); Text(delta).font(LWFont.mono(11)).foregroundStyle(LW.accent)
            }
            chartView
        }
        .padding(EdgeInsets(top: 12, leading: 14, bottom: 8, trailing: 14))
        .background(RoundedRectangle(cornerRadius: 18).fill(LinearGradient(colors: [LW.ink(0.08), LW.ink(0.02)], startPoint: .topLeading, endPoint: .bottomTrailing)))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(LW.ink(0.12), lineWidth: 0.5))
    }
}
