import SwiftUI

/// Finish splash (Finish Splash.dc.html). Plates build, RACKED lands, the PR chip pops with a
/// shine and a pulsing ring, totals fade in. It also masks the engine re-run: `settleFinish()`
/// happens behind it, so the summary is ready by the time it dissolves.
struct FinishSplash: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let session: Session

    @State private var shown = true         // opaque from frame one: it is covering a screen swap
    @State private var go = false           // drives the staged build
    @State private var breathing = false
    @State private var ring = false
    @State private var gleam = false
    @State private var started = false

    private let ground = Color(lwHex(0x0B0C07))
    private let bright = Color(lwHex(0xC7D584))

    private var prCount: Int { session.exercises.flatMap(\.sets).filter { $0.isPR && $0.done }.count }
    private var volume: Double {
        session.exercises.flatMap(\.sets).filter { $0.done && $0.type != "warmup" }
            .reduce(0) { $0 + ($1.kg ?? 0) * Double($1.reps ?? 0) }
    }
    private var setCounts: (done: Int, total: Int) {
        let all = session.exercises.flatMap(\.sets).filter { $0.type != "warmup" }
        return (all.filter(\.done).count, all.count)
    }

    var body: some View {
        ZStack {
            ground.ignoresSafeArea()
            bloom
            Rectangle()
                .fill(LinearGradient(colors: [.clear, bright.opacity(0.55), .clear], startPoint: .leading, endPoint: .trailing))
                .opacity(breathing ? 0.9 : 0.45)
                .frame(height: 2).frame(maxHeight: .infinity, alignment: .bottom).ignoresSafeArea()
            VStack(spacing: 24) {
                plates
                VStack(spacing: 10) {
                    Text("RACKED")
                        .font(LWFont.display(44, width: 82)).tracking(-1.3).foregroundStyle(LW.ink)
                        .scaleEffect(go ? 1 : 1.07).opacity(go ? 1 : 0)
                        .animation(.timingCurve(0.2, 0.9, 0.25, 1, duration: 0.5).delay(0.28), value: go)
                    if prCount > 0 { prChip }
                    totals.padding(.top, 4)
                }
            }
            .padding(.horizontal, 22)
        }
        .opacity(shown ? 1 : 0)
        .allowsHitTesting(false)
        .onAppear { play() }
    }

    private var bloom: some View {
        GeometryReader { g in
            EllipticalGradient(
                stops: [.init(color: bright.opacity(0.44), location: 0),
                        .init(color: LW.accent(0.26), location: 0.32),
                        .init(color: LW.accent(0.07), location: 0.58),
                        .init(color: .clear, location: 0.76)],
                center: .center, startRadiusFraction: 0, endRadiusFraction: 0.5)
            .frame(width: g.size.width * 1.4, height: g.size.height * 0.62)
            .position(x: g.size.width / 2, y: g.size.height * 1.12)
        }
        .ignoresSafeArea()
        .scaleEffect(breathing ? 1.06 : 1.0, anchor: .bottom)
        .opacity(breathing ? 1.0 : 0.72)
        .offset(y: go ? 0 : 90)
        .opacity(go ? 1 : 0)
        .animation(.easeOut(duration: 0.7), value: go)
    }

    /// Three plates growing up off the floor, 60ms apart.
    private var plates: some View {
        HStack(alignment: .bottom, spacing: 8) {
            plate(height: 46, color: LW.accent, delay: 0.16)
            plate(height: 74, color: bright, delay: 0.06)
            plate(height: 60, color: LW.accent, delay: 0.26)
        }
        .frame(height: 104, alignment: .bottom)
    }

    private func plate(height: CGFloat, color: Color, delay: Double) -> some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous).fill(color)
            .frame(width: 34, height: height)
            .overlay(alignment: .top) {
                Circle().fill(ground.opacity(0.4)).frame(width: 9, height: 9).padding(.top, 7)
            }
            .scaleEffect(x: 1, y: go ? 1 : 0.2, anchor: .bottom)
            .offset(y: go ? 0 : 24)
            .opacity(go ? 1 : 0)
            .animation(.timingCurve(0.2, 0.9, 0.25, 1, duration: 0.6).delay(delay), value: go)
    }

    /// The reward: a pill that pops, gleams once, and keeps a ring pulsing out of it.
    private var prChip: some View {
        ZStack {
            Capsule().strokeBorder(bright, lineWidth: 1.5)
                .frame(width: 74, height: 34)
                .scaleEffect(ring ? 1.7 : 0.85).opacity(ring ? 0 : 0.6)
            HStack(spacing: 7) {
                Text("\(prCount)").font(LWFont.mono(14, semibold: true)).foregroundStyle(LW.inkOnAccent)
                Text("PR").font(LWFont.mono(10.5, semibold: true)).tracking(1.9).foregroundStyle(LW.inkOnAccent)
            }
            .padding(.horizontal, 16).frame(height: 34)
            .background(Capsule().fill(bright))
            .overlay {
                Capsule().fill(LinearGradient(colors: [.clear, .white.opacity(0.65), .clear], startPoint: .leading, endPoint: .trailing))
                    .frame(width: 28).rotationEffect(.degrees(-18))
                    .offset(x: gleam ? 70 : -70).opacity(gleam ? 0 : 0.85)
                    .clipShape(Capsule())
            }
            .scaleEffect(go ? 1 : 0.4).opacity(go ? 1 : 0)
            .animation(.spring(response: 0.42, dampingFraction: 0.55).delay(0.42), value: go)
        }
    }

    private var totals: some View {
        HStack(spacing: 10) {
            Text("\(Fmt.int(volume)) KG").font(LWFont.mono(11)).tracking(1.1).foregroundStyle(LW.ink(0.75))
            Circle().fill(LW.ink(0.35)).frame(width: 3, height: 3)
            Text("\(setCounts.done) / \(setCounts.total) SETS").font(LWFont.mono(11)).tracking(1.1).foregroundStyle(LW.ink(0.75))
        }
        .opacity(go ? 1 : 0)
        .animation(.easeOut(duration: 0.5).delay(0.56), value: go)
    }

    /// Plays, settles the engine behind the hold, then hands over to the summary.
    private func play() {
        guard !started else { return }
        started = true
        go = true
        if !reduceMotion {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.52) {
                withAnimation(.easeOut(duration: 1.4).repeatForever(autoreverses: false)) { ring = true }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.72) {
                withAnimation(.easeOut(duration: 1.0)) { gleam = true }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                withAnimation(.easeInOut(duration: 1.9).repeatForever(autoreverses: true)) { breathing = true }
            }
        }
        // the animation has landed — take the engine hit here, where nothing is moving
        let t0 = Date()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.25) {
            store.settleFinish()
            // hold at least as long as the start splash (2.8s), so the engine time hides INSIDE
            // the window instead of extending it and the two splashes feel the same length
            let wait = max(0, 2.8 - Date().timeIntervalSince(t0))
            DispatchQueue.main.asyncAfter(deadline: .now() + wait) {
                withAnimation(.easeInOut(duration: 0.36)) { shown = false }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { router.finishSplash = nil }
            }
        }
    }
}
