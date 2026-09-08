import SwiftUI

/// The splash glow: an S = 0.34 bloom pinned below the bottom edge that only breathes.
/// Shared with the login screen — same stops, same scale, same ground.
struct SplashBloom: View {
    static let ground = Color(lwHex(0x0B0C07))
    static let bright = Color(lwHex(0xC7D584))
    var breathing: Bool
    var body: some View {
        GeometryReader { g in
            EllipticalGradient(
                stops: [.init(color: Self.bright.opacity(0.34), location: 0),
                        .init(color: LW.accent(0.20), location: 0.32),
                        .init(color: LW.accent(0.07), location: 0.58),
                        .init(color: .clear, location: 0.76)],
                center: .center, startRadiusFraction: 0, endRadiusFraction: 0.5)
            .frame(width: g.size.width * 1.4, height: g.size.height * 0.62)
            .position(x: g.size.width / 2, y: g.size.height * 1.12)
        }
        .ignoresSafeArea()
        .scaleEffect(breathing ? 1.06 : 1.0, anchor: .bottom)
        .opacity(breathing ? 1.0 : 0.72)
    }
}

/// Start splash (Start Splash.dc.html). Glow rises and breathes at the bottom, the name scales
/// 1.07 → 1, the meta follows 60ms later, and the exercise list steps up one line at a time.
/// Holds a beat, then cross-dissolves into the session.
struct StartLayer: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var shown = false        // cross-dissolve in and out
    @State private var risen = false        // bloom lift + name settle
    @State private var breathing = false    // the glow's slow breath
    @State private var reel = 0             // which exercise the list is showing
    @State private var launching = false
    @State private var flew = false         // false = the name still sits where the card had it
    @State private var nameFrame: CGRect = .zero

    private let ground = SplashBloom.ground
    private let bright = SplashBloom.bright
    private let line: CGFloat = 18

    var body: some View {
        ZStack {
            if let w = router.startRequest.flatMap({ store.workout($0) }) {
                ground.ignoresSafeArea()
                bloom
                Rectangle()                                   // hairline along the very bottom
                    .fill(LinearGradient(colors: [.clear, bright.opacity(0.55), .clear], startPoint: .leading, endPoint: .trailing))
                    .opacity(breathing ? 0.9 : 0.45)
                    .frame(height: 2)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .ignoresSafeArea()
                copy(w)
            }
        }
        .opacity(shown ? 1 : 0)
        .allowsHitTesting(false)
        .onChange(of: router.startRequest) { _, req in
            guard let id = req, let w = store.workout(id), !launching else { return }
            launch(workout: w)
        }
    }

    /// Sits at the bottom edge, rises once, then only breathes — it never travels up the screen.
    private var bloom: some View {
        SplashBloom(breathing: breathing)
            .offset(y: risen ? 0 : 90)
            .opacity(risen ? 1 : 0)
    }

    private func copy(_ w: Workout) -> some View {
        let names = w.orderedSlots.map { $0.exerciseName.uppercased() }
        return GeometryReader { g in
            VStack(alignment: .leading, spacing: 9) {
                Text(eyebrow).font(LWFont.mono(10)).tracking(2.6).foregroundStyle(LW.ink(0.5))
                Text(Fmt.title(w.name))
                    .font(LWFont.display(48, width: 82)).tracking(-1.4)
                    .lineLimit(2).minimumScaleFactor(0.5).fixedSize(horizontal: false, vertical: true)
                    .foregroundStyle(LW.ink)
                    .background(GeometryReader { p in Color.clear
                        .onAppear { nameFrame = p.frame(in: .global) }
                        .onChange(of: p.frame(in: .global)) { _, f in nameFrame = f } })
                    .scaleEffect(flew ? 1 : heroScale, anchor: .topLeading)
                    .offset(x: flew ? 0 : heroOffset.width, y: flew ? 0 : heroOffset.height)
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(w.orderedSlots.count) EX · \(w.orderedSlots.reduce(0) { $0 + $1.sets }) SETS")
                        .font(LWFont.mono(11)).tracking(1.5).foregroundStyle(bright)
                    exerciseReel(names).padding(.top, 2)
                }
            }
            .opacity(risen ? 1 : 0)
            .animation(.easeOut(duration: 0.34).delay(0.08), value: risen)   // ground leads, copy follows
            .padding(.horizontal, 24)
            .frame(width: g.size.width, alignment: .leading)
            .position(x: g.size.width / 2, y: g.size.height * 0.46)
        }
    }

    /// A one-line window the list steps through, fading out at the right edge.
    private func exerciseReel(_ names: [String]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(names.enumerated()), id: \.offset) { _, n in
                Text(n).font(LWFont.mono(10.5)).tracking(1.05)
                    .foregroundStyle(LW.ink(0.55)).lineLimit(1).fixedSize()
                    .frame(height: line, alignment: .leading)
            }
        }
        .offset(y: -line * CGFloat(reel))
        .frame(height: line, alignment: .top)
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipped()
        .mask(LinearGradient(stops: [.init(color: .black, location: 0.78), .init(color: .clear, location: 1)],
                             startPoint: .leading, endPoint: .trailing))
    }

    /// The card's name box vs the splash's — the delta the name travels on the way in.
    private var heroScale: CGFloat {
        let card = router.heroNameFrame
        guard card.height > 1, nameFrame.height > 1 else { return 1.07 }
        return max(0.3, min(1, card.height / nameFrame.height))
    }
    private var heroOffset: CGSize {
        let card = router.heroNameFrame
        guard card.width > 1, nameFrame.width > 1 else { return .zero }
        return CGSize(width: card.minX - nameFrame.minX, height: card.minY - nameFrame.minY)
    }

    /// The slot about to be trained, not the count behind it: "CYCLE 93 · 4 OF 6".
    private var eyebrow: String {
        guard let p = store.routineProgress() else { return "NEXT UP" }
        return "CYCLE \(p.cycle) · \(min(p.done + 1, p.total)) OF \(p.total)"
    }

    /// ~3.2s door to door: 0.12s takeover · rise · hold with the reel stepping · 0.34s dissolve.
    private func launch(workout: Workout) {
        launching = true
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()          // you pressed start
        withAnimation(.easeInOut(duration: 0.3)) { shown = true }          // a dissolve, not a cut
        withAnimation(reduceMotion ? .easeOut(duration: 0.22) : .timingCurve(0.2, 0.9, 0.25, 1, duration: 0.34)) { risen = true }
        withAnimation(reduceMotion ? .easeOut(duration: 0.22) : .timingCurve(0.25, 0.9, 0.3, 1, duration: 0.42)) { flew = true }
        if !reduceMotion {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
                UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.5)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.36) {
                withAnimation(.easeInOut(duration: 1.9).repeatForever(autoreverses: true)) { breathing = true }
            }
            let steps = max(0, workout.orderedSlots.count - 1)
            for i in 1...max(1, steps) where i <= steps {                  // one line at a time: glide, then hold
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6 + 1.2 * Double(i - 1)) {
                    guard launching else { return }
                    withAnimation(.timingCurve(0.45, 0, 0.25, 1, duration: 0.5)) { reel = i }
                }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.42) {     // ground is opaque by now: the card can flip unseen
            let s = store.startSession(from: workout)
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.18) { router.present(.session(s.id)) }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.8) {
            withAnimation(.easeInOut(duration: 0.34)) { shown = false }    // cross-dissolve into the session
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.2) {
            var t = Transaction(); t.disablesAnimations = true
            withTransaction(t) { risen = false; breathing = false; reel = 0; flew = false }
            launching = false; router.startRequest = nil
        }
    }
}
