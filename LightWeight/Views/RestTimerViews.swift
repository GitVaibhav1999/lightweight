import SwiftUI

/// Session V2 — the rest-timer mark ("ra"): pause bars inside a ticked dial.
/// 24×24 design viewBox: tick ring r9.5 (pathLength 48, dash 0.5/1.5), two 2.6×8.8 r1.3 bars.
struct RAMark: View {
    var size: CGFloat
    var color: Color
    var pause = true                 // running = pause bars · idle = play, so the chip states its action
    var body: some View {
        let s = size / 24
        let unit = (2 * CGFloat.pi * 9.5 * s) / 48
        ZStack {
            Circle().stroke(color, style: StrokeStyle(lineWidth: 1.6 * s, dash: [0.5 * unit, 1.5 * unit]))
                .frame(width: 19 * s, height: 19 * s)
            if pause {
                HStack(spacing: 2.6 * s) {
                    RoundedRectangle(cornerRadius: 1.3 * s).frame(width: 2.6 * s, height: 8.8 * s)
                    RoundedRectangle(cornerRadius: 1.3 * s).frame(width: 2.6 * s, height: 8.8 * s)
                }.foregroundStyle(color)
            } else {
                Path { p in
                    p.move(to: CGPoint(x: 9.4 * s, y: 7.2 * s)); p.addLine(to: CGPoint(x: 16 * s, y: 12 * s))
                    p.addLine(to: CGPoint(x: 9.4 * s, y: 16.8 * s)); p.closeSubpath()
                }.fill(color).frame(width: size, height: size)
            }
        }.frame(width: size, height: size)
    }
}

private let restSolid = Color(red: 0xAD / 255, green: 0xBA / 255, blue: 0x5E / 255)
private let restBright = Color(red: 0xC7 / 255, green: 0xD5 / 255, blue: 0x84 / 255)
func restClock(_ t: TimeInterval) -> String { String(format: "%d:%02d", Int(t) / 60, Int(t) % 60) }

/// Header chip — one global timer. Idle outline → running solid → 1s bright flip at 0:00.
struct RestChip: View {
    @Environment(AppStore.self) private var store
    @Binding var showDial: Bool
    /// Idle reads the armed preset — "REST 1:30" — or plain REST in count-up mode.
    private var idleLabel: String { store.restPreset > 0 ? "REST \(restClock(store.restPreset))" : "REST" }
    var body: some View {
        if store.restAnchor == nil { chip(nil) }
        else if store.restScreenUp { chip(store.restDisplay(at: .now)) }   // the rest screen covers it — don't tick behind it
        else { TimelineView(.periodic(from: .now, by: 1)) { ctx in chip(store.restDisplay(at: ctx.date)) } }
    }

    @ViewBuilder private func chip(_ t: TimeInterval?) -> some View {
        Group {
            let running = t != nil
            let solid = running || showDial
            HStack(spacing: 5) {
                RAMark(size: 15, color: solid || store.restFlash ? .black : LW.accent, pause: running)
                Text(store.restFlash ? "0:00" : t.map(restClock) ?? idleLabel)
                    .font(LWFont.mono(11, semibold: running)).tracking(running ? 0 : 0.8)
                    .foregroundStyle(solid || store.restFlash ? .black : LW.accent)
            }
            .frame(width: 96, height: 28)          // never changes width
            .background {
                if store.restFlash { Capsule().fill(restBright) }
                else if solid { Capsule().fill(restSolid) }
                else { Capsule().fill(LW.accent(0.14)).overlay(Capsule().strokeBorder(LW.accent(0.4), lineWidth: 1)) }
            }
            .contentShape(Capsule())
            .onTapGesture {
                guard !showDial else { return }         // release after the hold must not cancel
                running ? store.cancelRest() : store.startRest()
            }
            .simultaneousGesture(LongPressGesture(minimumDuration: 0.35).onEnded { _ in
                guard !running else { return }            // the dial is locked while the clock runs
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                withAnimation(.easeOut(duration: 0.2)) { showDial = true }
            })
            .accessibilityIdentifier("rest.chip")
            .accessibilityLabel(t.map(restClock) ?? "REST")
        }
    }
}

/// Hold the chip → the dial. 48-tick ring, draggable pointer in 15 s steps, release = save preset + arm.
struct RestDial: View {
    @Environment(AppStore.self) private var store
    var close: () -> Void
    @State private var target: TimeInterval = 90
    @State private var dragTick = -1
    private let full: TimeInterval = 180   // full revolution = 3:00 (1:30 → pointer at bottom centre)

    // gesture lives OUTSIDE any TimelineView — timeline rebuilds cancel an in-flight drag
    var body: some View {
        let unit = (2 * CGFloat.pi * 88) / 96
        let dash = StrokeStyle(lineWidth: 12, dash: [0.55 * unit, 1.45 * unit])
        ZStack {
            Circle().stroke(LW.ink(0.16), style: dash).frame(width: 176, height: 176)
            TimelineView(.periodic(from: .now, by: 0.5)) { ctx in
                let frac: CGFloat = store.restAnchor.map { min(1, ctx.date.timeIntervalSince($0) / full) }
                    ?? min(1, target / full)
                Circle().trim(from: 0, to: frac).stroke(restSolid, style: dash)
                    .rotationEffect(.degrees(-90)).frame(width: 176, height: 176)
            }
            DialPointer().fill(restBright).frame(width: 12, height: 9)
                .offset(y: -103)
                .rotationEffect(.degrees(target / full * 360))
            ZStack {
                Circle().fill(Color(red: 0x10 / 255, green: 0x12 / 255, blue: 0x08 / 255))
                VStack(spacing: 2) {
                    Text("REST").font(LWFont.mono(9)).tracking(1.2).foregroundStyle(.white.opacity(0.45))
                    TimelineView(.periodic(from: .now, by: 0.5)) { ctx in
                        Text(restClock(store.restDisplay(at: ctx.date) ?? target))
                            .font(LWFont.mono(26, semibold: true)).foregroundStyle(restBright)
                    }
                    Text(target > 0 ? "of \(restClock(target))" : "count-up")
                        .font(LWFont.mono(8.5)).foregroundStyle(.white.opacity(0.4))
                }
            }
            .frame(width: 116, height: 116)
            .contentShape(Circle())
            .onTapGesture {                              // set the preset and put the dial away — does not start it
                store.restPreset = target
                close()
            }
        }
        .frame(width: 236, height: 236)
        .padding(24)
        .lwGlass(RoundedRectangle(cornerRadius: 24), rim: 0.2)
        .shadow(color: .black.opacity(0.45), radius: 30, y: 12)
        .contentShape(Rectangle())                     // whole card drags — tick gaps must not fall through
        .gesture(
            DragGesture(minimumDistance: 4)
                .onChanged { g in
                    let c = CGPoint(x: 142, y: 142)
                    let dx = g.location.x - c.x, dy = g.location.y - c.y
                    guard hypot(dx, dy) > 58 else { return }        // center disc = close, not drag
                    var ang = atan2(dx, -dy); if ang < 0 { ang += 2 * .pi }
                    var secs = (Double(ang) / (2 * .pi) * full / 15).rounded() * 15
                    if secs >= full { secs = 0 }
                    if Int(secs) != dragTick {
                        dragTick = Int(secs); target = secs
                        UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.6)
                    }
                }
                .onEnded { _ in
                    guard dragTick >= 0 else { return }
                    dragTick = -1
                    store.restPreset = target                        // release = save the preset, nothing more
                }
        )
        .onAppear { target = store.restPreset }
        .accessibilityIdentifier("rest.dial")
    }
}

private struct DialPointer: Shape {   // apex points inward (down when at 12)
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY)); p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        p.addLine(to: CGPoint(x: r.midX, y: r.maxY)); p.closeSubpath()
        return p
    }
}

/// 11a — the rest screen. Glass over the live session, no controls: the session stays readable
/// behind it, any tap drops back to it, and the clock keeps running in the header chip.
struct RestScreen: View {
    @Environment(AppStore.self) private var store
    let session: Session
    var close: () -> Void

    var body: some View {
        GeometryReader { g in
            ZStack {
                Rectangle().fill(.ultraThinMaterial).opacity(0.45).ignoresSafeArea()
                Rectangle().fill(Color(red: 9 / 255, green: 10 / 255, blue: 6 / 255).opacity(0.72)).ignoresSafeArea()
                VStack(spacing: 0) {
                    Color.clear.frame(height: g.size.height * 0.28)
                    Text("REST").font(LWFont.mono(10)).tracking(2.8).foregroundStyle(LW.ink(0.45))
                    TimelineView(.periodic(from: .now, by: 0.5)) { ctx in
                        let t = store.restDisplay(at: ctx.date) ?? 0
                        VStack(spacing: 18) {
                            Text(restClock(t)).font(LWFont.mono(72, semibold: true))
                                .foregroundStyle(LW.ink).monospacedDigit()
                            Capsule().fill(LW.ink(0.18))
                                .overlay(alignment: .leading) { Capsule().fill(LW.accent).frame(width: 220 * elapsed(t)) }
                                .frame(width: 220, height: 3)
                        }
                        .padding(.top, 12)
                    }
                    Spacer(minLength: 0)
                    if let (ex, set) = nextUp() {
                        Text(set).font(LWFont.mono(12)).tracking(0.6).foregroundStyle(LW.accent)
                        Text(ex).font(LWFont.mono(10.5)).tracking(1.2).foregroundStyle(LW.ink(0.4)).padding(.top, 6)
                    }
                    Button { close() } label: {
                        Text("Continue").font(LWFont.heading(19, width: 92)).foregroundStyle(LW.inkOnAccent)
                            .frame(maxWidth: .infinity).frame(height: 56)
                            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(LW.accent))
                    }.buttonStyle(.plain)
                    .padding(.horizontal, 14).padding(.top, 26).padding(.bottom, 30)
                    .accessibilityIdentifier("rest.continue").accessibilityLabel("Back to the session")
                }
                .frame(maxWidth: .infinity)
            }
        }
        .ignoresSafeArea()
        .padding(.horizontal, -LW.screenPad)            // full bleed: escape the page's gutters
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("rest.screen")
    }

    /// Fraction of the armed duration already spent (count-up mode fills nothing).
    private func elapsed(_ remaining: TimeInterval) -> CGFloat {
        guard let d = store.restDuration, d > 0 else { return 0 }
        return min(1, max(0, CGFloat((d - remaining) / d)))
    }

    /// "NEXT · 72.5 × 12" over "BENT OVER ROW · SET 3".
    private func nextUp() -> (String, String)? {
        for se in session.orderedExercises {
            if let st = se.orderedSets.first(where: { !$0.done && $0.type != "warmup" }) {
                let load = st.kg.map(Fmt.kg) ?? "BW"
                let reps = (st.reps ?? 0) > 0 ? " × \(st.reps!)" : ""
                return ("\(se.exerciseName.uppercased()) · SET \(st.index + 1)", "NEXT · \(load)\(reps)")
            }
        }
        return nil
    }
}
