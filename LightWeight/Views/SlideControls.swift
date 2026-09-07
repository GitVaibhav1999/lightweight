import SwiftUI

/// "SLIDE TO START · LEGS" — the lightning slider from the board. Effects scale with drag progress.
/// Toggles child opacity on a fixed period — the board's `ovFlick` steps(2) animation.
/// Stable view identity matters here: these sit inside the slider's gesture view, and swapping structure mid-drag cancels the DragGesture.
struct Flicker<Content: View>: View {
    let period: Double
    var active = true
    @ViewBuilder let content: () -> Content
    var body: some View {
        TimelineView(.animation(minimumInterval: period, paused: !active)) { ctx in
            content().opacity(!active || Int(ctx.date.timeIntervalSinceReferenceDate / period) % 2 == 0 ? 1 : 0.15)
        }
    }
}

struct Jitter: ViewModifier {
    let active: Bool; let speed: Double
    func body(content: Content) -> some View {
        TimelineView(.animation(minimumInterval: speed, paused: !active)) { ctx in
            let k = active ? Int(ctx.date.timeIntervalSinceReferenceDate / speed) % 4 : 0
            let off: [(CGFloat, CGFloat)] = [(0, 0), (1.4, -1), (-1.2, 1), (1, 1.2)]
            content.offset(x: off[k].0, y: off[k].1)
        }
    }
}

/// "SLIDE TO FINISH" — glass track, sage fill with inverted label, arrow thumb.
struct SlideToFinish: View {
    var unchecked: () -> Int = { 0 }      // Session Updates §3: >0 arms a second-slide confirmation
    let onComplete: () -> Void
    @State private var p: CGFloat = 0
    @State private var dragging = false
    @State private var done = false
    @State private var armed = false
    @State private var disarm: DispatchWorkItem?
    private static let armedKnob = lwDyn(lwHex(0xC7D584), lwHex(0x3C4433))
    var body: some View {
        GeometryReader { g in
            let w = g.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(armed ? AnyShapeStyle(LW.accent(0.14)) : AnyShapeStyle(.clear)).glassEffect(.regular.interactive(), in: Capsule())
                    .overlay { if armed { Capsule().strokeBorder(LW.accent(0.55), lineWidth: 1) } }
                    .shadow(color: LW.shadow(0.5), radius: 13, y: 10)
                if armed {
                    VStack(spacing: 2) {
                        Text("SLIDE AGAIN TO FINISH").font(LWFont.mono(12, semibold: true)).tracking(1.1).foregroundStyle(Self.armedKnob)
                        Text("\(unchecked()) unchecked set\(unchecked() == 1 ? "" : "s") will be dropped").font(LWFont.mono(9.5)).foregroundStyle(LW.ink(0.45))
                    }.frame(maxWidth: .infinity)
                } else {
                    Text(done ? "DONE" : "SLIDE TO FINISH").font(LWFont.body(13.5, weight: 700)).tracking(1.1).foregroundStyle(LW.accent).frame(maxWidth: .infinity)
                }
                Capsule().fill(LW.accent).frame(width: (w - 62) * p + 52).padding(3)
                    .overlay(alignment: .leading) {
                        Text(done ? "DONE" : (armed ? "" : "SLIDE TO FINISH")).font(LWFont.body(13.5, weight: 700)).tracking(1.1).foregroundStyle(LW.inkOnAccent)
                            .frame(width: w).clipped()
                    }.clipShape(Capsule())
                Circle().fill(armed ? Self.armedKnob : LW.accent).frame(width: 48, height: 48)
                    .overlay { if armed { Icon(kind: .check, size: 16, color: LW.inkOnAccent, weight: 2.6) } else { Icon(kind: .arrowRight, size: 16, color: LW.inkOnAccent, weight: 2.4) } }
                    .shadow(color: LW.shadow(0.35), radius: 5, y: 2)
                    .offset(x: (w - 56) * p + 4)
            }
            .frame(height: 56)
            .animation(dragging ? nil : .timingCurve(0.2, 0.9, 0.2, 1, duration: 0.4), value: p)
            .animation(.easeOut(duration: 0.3), value: armed)
            .contentShape(Capsule())
            .accessibilityElement(children: .ignore).accessibilityIdentifier("slide.finish")
            .accessibilityLabel(armed ? "Slide again to finish" : "Slide to finish")
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { v in guard !done else { return }; dragging = true; p = max(0, min(1, (v.location.x - 28) / (w - 56))) }
                .onEnded { _ in
                    guard !done else { return }
                    dragging = false
                    if p >= 0.9 {
                        if unchecked() > 0, !armed {
                            armed = true; p = 0
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            disarm?.cancel()
                            let work = DispatchWorkItem { withAnimation { armed = false } }
                            disarm = work
                            DispatchQueue.main.asyncAfter(deadline: .now() + 6, execute: work)   // 6s idle → disarm (3s cut off reading the two-line warning)
                        } else {
                            disarm?.cancel()
                            p = 1; done = true; UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { onComplete() }
                        }
                    } else { p = 0 }
                })
        }.frame(height: 56)
    }
}

/// The start transition: sage radial, bolt on the right, "NEXT IN LOOP / LEGS", rocks lifting.
struct SplashView: View {
    let workoutName: String
    @State private var appeared = false
    var body: some View {
        ZStack {
            RadialGradient(colors: [LW.accent(0.28), LW.bg.opacity(0.92)], center: UnitPoint(x: 0.5, y: 0.45), startRadius: 0, endRadius: 380).background(LW.bg)
            GeometryReader { g in
                ForEach(0..<6, id: \.self) { i in
                    Rock(seed: i).offset(x: g.size.width * [0.14, 0.30, 0.47, 0.63, 0.78, 0.88][i], y: g.size.height * [0.70, 0.80, 0.74, 0.82, 0.72, 0.84][i] + (appeared ? -34 : 26)).opacity(appeared ? 0.85 : 0)
                }
            }
            LinearGradient(colors: [.clear, LW.accent(0.38)], startPoint: .top, endPoint: .bottom).frame(height: 130).frame(maxHeight: .infinity, alignment: .bottom)
            VStack(spacing: 8) {
                Text("Next in loop").lwLabel(10, tracking: 0.18, color: LW.accent)
                Text(Fmt.title(workoutName)).font(LWFont.display(64, width: 85)).tracking(-1.9).lineLimit(1).minimumScaleFactor(0.5).padding(.horizontal, 24).foregroundStyle(LW.accentPale).shadow(color: LW.accent(0.8), radius: 30)
            }
            LW.accentPale.opacity(appeared ? 0 : 0.9).allowsHitTesting(false)
        }
        .ignoresSafeArea()
        .onAppear { withAnimation(.easeOut(duration: 0.4)) { appeared = true } }
    }
    struct Rock: View {
        let seed: Int
        var body: some View {
            Path { p in p.move(to: CGPoint(x: 2, y: 0)); p.addLine(to: CGPoint(x: 12, y: 3)); p.addLine(to: CGPoint(x: 10, y: 11)); p.addLine(to: CGPoint(x: 0, y: 8)); p.closeSubpath() }
                .fill(LinearGradient(colors: [Color(red: 0.23, green: 0.24, blue: 0.19), Color(red: 0.14, green: 0.15, blue: 0.11)], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 12, height: 11).rotationEffect(.degrees(Double(seed % 2 == 0 ? 14 : -12)))
        }
    }
}

/// Start Bar v2 debris trail: rising earth particles in the knob's wake.
/// TimelineView keeps identity stable inside the slider's gesture view; paused below 15% charge.
struct DebrisTrail: View {
    let charge: CGFloat
    private static let seeds: [(x: CGFloat, size: CGFloat, dur: Double, delay: Double, sage: Bool, op: Double)] = [
        (0.06, 2, 0.82, 0.05, true, 0.45), (0.14, 3, 1.05, 0.32, false, 1), (0.22, 2, 0.75, 0.58, true, 0.35),
        (0.31, 2, 0.98, 0.12, true, 0.55), (0.39, 3, 1.10, 0.44, false, 1), (0.48, 2, 0.86, 0.66, true, 0.4),
        (0.56, 2, 0.79, 0.22, false, 1),  (0.64, 3, 1.02, 0.50, true, 0.5), (0.72, 2, 0.90, 0.08, true, 0.38),
        (0.80, 2, 1.08, 0.38, false, 1),  (0.88, 3, 0.77, 0.62, true, 0.52), (0.94, 2, 0.95, 0.18, true, 0.42),
    ]
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: charge < 0.15)) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            GeometryReader { g in
                ForEach(0..<Self.seeds.count, id: \.self) { i in
                    let s = Self.seeds[i]
                    let phase = ((t + s.delay) / s.dur).truncatingRemainder(dividingBy: 1)
                    Rectangle()
                        .fill(s.sage ? LW.accent(s.op) : Color(red: 0x56 / 255, green: 0x60 / 255, blue: 0x49 / 255))
                        .frame(width: s.size, height: s.size)
                        .position(x: g.size.width * s.x, y: 46 - 18 * phase)
                        .opacity(phase < 0.15 ? Double(phase) / 0.15 * 0.9 : max(0, 0.9 * (1 - (Double(phase) - 0.15) / 0.85)))
                }
            }
        }
        .allowsHitTesting(false).accessibilityHidden(true)
    }
}
