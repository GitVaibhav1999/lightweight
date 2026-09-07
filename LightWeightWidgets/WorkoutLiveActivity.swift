import ActivityKit
import WidgetKit
import SwiftUI

private let sage = Color(red: 0xAD / 255, green: 0xBA / 255, blue: 0x5E / 255)   // court action green

/// timerInterval text reports a huge intrinsic width and stretches the island — always hard-bound it.
private func timer(_ state: WorkoutActivityAttributes.ContentState, size: CGFloat, width: CGFloat, weight: Font.Weight = .semibold) -> some View {
    Text(timerInterval: state.startedAt...state.startedAt.addingTimeInterval(43_200), countsDown: false)
        .font(.system(size: size, weight: weight, design: .monospaced)).foregroundStyle(.white.opacity(0.55))
        .monospacedDigit().minimumScaleFactor(0.6).lineLimit(1)
        .multilineTextAlignment(.trailing).frame(width: width)
}
private func pct(_ state: WorkoutActivityAttributes.ContentState, size: CGFloat) -> some View {
    Text("\(Int((state.progress * 100).rounded()))%")
        .font(.system(size: size, weight: .semibold, design: .monospaced)).foregroundStyle(sage)
}
private func bar(_ state: WorkoutActivityAttributes.ContentState) -> some View {
    GeometryReader { g in
        ZStack(alignment: .leading) {
            Capsule().fill(.white.opacity(0.14))
            Capsule().fill(sage).frame(width: max(3, g.size.width * state.progress))
        }
    }.frame(height: 3)
}

/// The mark-next-set control: greyed (unselected) until tapped — mirrors the in-app set circles.
private func markButton() -> some View {
    Button(intent: MarkSetIntent()) {
        ZStack {
            Circle().strokeBorder(.white.opacity(0.35), lineWidth: 1.5).frame(width: 32, height: 32)
            Image(systemName: "checkmark").font(.system(size: 13, weight: .black)).foregroundStyle(.white.opacity(0.5))
        }
    }.buttonStyle(.plain)
}

@main
struct LightWeightWidgetBundle: WidgetBundle {
    var body: some Widget {
        WorkoutLiveActivity()
        CalendarWidget()
        WeekWidget()
        YearStripWidget()
    }
}

struct WorkoutLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WorkoutActivityAttributes.self) { context in
            // Lock screen / banner — Session Updates §2: ready → logged flash → next
            let logged = context.state.logged ?? false
            let ink: Color = logged ? .black : .white
            VStack(spacing: 10) {
                HStack(spacing: 8) {
                    Circle().fill(logged ? .black : sage).frame(width: 7, height: 7)
                    Text(context.attributes.workoutName.uppercased())
                        .font(.system(size: 11, weight: .heavy)).foregroundStyle(ink).lineLimit(1)
                    Group {
                        if let rest = context.state.restEndsAt, rest > context.state.startedAt {
                            (Text(timerInterval: context.state.startedAt...rest, countsDown: true)
                             + Text(" · NEXT \(context.state.kg ?? "—") × \(context.state.reps ?? "—")"))
                        } else {
                            (Text("\(Int((context.state.progress * 100).rounded()))% · ")
                             + Text(timerInterval: context.state.startedAt...context.state.startedAt.addingTimeInterval(43_200), countsDown: false))
                        }
                    }
                        .font(.system(size: 11, design: .monospaced)).foregroundStyle(ink.opacity(0.4))
                        .lineLimit(1).minimumScaleFactor(0.7)
                    Spacer()
                    if logged {
                        Text("LOGGED").font(.system(size: 11, weight: .heavy, design: .monospaced)).foregroundStyle(ink)
                    } else if let n = context.state.setNo, let m = context.state.setTotal {
                        Text("SET \(n)/\(m)").font(.system(size: 11, design: .monospaced)).foregroundStyle(ink.opacity(0.55))
                    }
                }
                HStack(alignment: .center, spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(context.state.kg ?? "—").font(.system(size: logged ? 24 : 20, weight: .semibold, design: .monospaced)).foregroundStyle(ink)
                            Text("×").font(.system(size: 14, design: .monospaced)).foregroundStyle(ink.opacity(0.4))
                            Text(context.state.reps ?? "—").font(.system(size: logged ? 24 : 20, weight: .semibold, design: .monospaced)).foregroundStyle(ink)
                        }
                        Text(((context.state.isNextExercise ?? false) ? "NEXT · " : "") + (context.state.exercise ?? ""))
                            .font(.system(size: 10, design: .monospaced)).foregroundStyle(ink.opacity(0.4)).lineLimit(1)
                    }
                    Spacer()
                    Button(intent: MarkSetIntent()) {
                        ZStack {
                            if logged {
                                Circle().fill(.black).frame(width: 44, height: 44)
                                Image(systemName: "checkmark").font(.system(size: 16, weight: .black)).foregroundStyle(sage)
                            } else {
                                Circle().strokeBorder(.white.opacity(0.35), lineWidth: 1.5).frame(width: 44, height: 44)
                                Image(systemName: "checkmark").font(.system(size: 15, weight: .black)).foregroundStyle(.white.opacity(0.5))
                            }
                        }
                    }.buttonStyle(.plain)
                }
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(ink.opacity(0.12))
                        Capsule().fill(logged ? .black : sage).frame(width: max(3, g.size.width * context.state.progress))
                    }
                }.frame(height: 3)
            }
            .padding(.horizontal, 16).padding(.vertical, 13)
            .activityBackgroundTint(logged ? sage : Color(red: 60/255, green: 64/255, blue: 45/255).opacity(0.55))
            .activitySystemActionForegroundColor(logged ? .black : sage)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 8) {
                        Circle().fill(sage).frame(width: 7, height: 7)
                        Text(context.attributes.workoutName.uppercased())
                            .font(.system(size: 14, weight: .heavy)).foregroundStyle(.white).lineLimit(1)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) { timer(context.state, size: 14, width: 56) }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 10) {
                        HStack(spacing: 10) { pct(context.state, size: 11); bar(context.state) }
                        if let ex = context.state.nextExercise {
                            HStack(spacing: 10) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("NEXT · " + ex).font(.system(size: 12, weight: .heavy)).foregroundStyle(.white).lineLimit(1)
                                    if let d = context.state.nextDetail {
                                        Text(d).font(.system(size: 10, design: .monospaced)).foregroundStyle(.white.opacity(0.55))
                                    }
                                }
                                Spacer()
                                markButton()
                            }
                        }
                    }.padding(.top, 4)
                }
            } compactLeading: {
                pct(context.state, size: 12).frame(width: 34)
            } compactTrailing: {
                timer(context.state, size: 12, width: 34)
            } minimal: {
                Text("\(Int((context.state.progress * 100).rounded()))%")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced)).foregroundStyle(sage)
            }
            .keylineTint(sage)
        }
    }
}
