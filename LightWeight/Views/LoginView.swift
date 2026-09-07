import SwiftUI

/// Login, frame 2b — "the loop". A headline, then the routine segments and the last
/// cycle-over-cycle gain lifted straight off Home, so the first screen argues for the
/// app before asking for anything. Always dark: these are the literal splash tokens,
/// not the trait-driven ones.
struct LoginView: View {
    @Environment(AuthState.self) private var auth
    @Environment(AppStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false
    @State private var breathing = false
    @State private var pending: Provider?          // which row spins; both disable together

    private enum Provider { case apple, google }

    private let ground = SplashBloom.ground
    private let ink = Color(lwHex(0xE7E5D7))
    private let action = Color(lwHex(0xADBA5E))
    private let pad: CGFloat = 24

    var body: some View {
        ZStack {
            ground.ignoresSafeArea()
            SplashBloom(breathing: breathing)
            VStack(alignment: .leading, spacing: 0) {
                wordmark
                headline.padding(.top, 26)
                if let p = store.routineProgress() { segments(p).padding(.top, 34) }
                proof.padding(.top, 22)
                Spacer(minLength: 24)
                providers
            }
            .padding(.horizontal, pad)
            .padding(.top, 10)
            .padding(.bottom, 26)
        }
        .opacity(shown ? 1 : 0)
        .onAppear(perform: raise)
        .accessibilityElement(children: .contain).accessibilityIdentifier("login")
    }

    private var wordmark: some View {
        HStack(spacing: 10) {
            LogoMark(width: 26, color: action)
            Text("LIGHT WEIGHT").font(LWFont.mono(10)).tracking(2.2).foregroundStyle(ink.opacity(0.6))
        }
        .accessibilityElement(children: .ignore).accessibilityLabel("Light Weight")
    }

    /// 0.9 line-height: each line sits in a box shorter than the font's natural leading.
    private var headline: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(["Same loop.", "Heavier", "every time."], id: \.self) { line in
                Text(line)
                    .font(LWFont.display(40, width: 84)).tracking(-1.5)
                    .foregroundStyle(ink)
                    .frame(height: 40 * 0.9, alignment: .leading)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
    }

    /// The same done / next / remaining reading RoutineHero uses, at hairline weight.
    private func segments(_ p: (done: Int, total: Int, cycle: Int)) -> some View {
        // First word only: the columns are a quarter of the screen and "Shoulders and
        // Arms" shrinks to nothing in one. The head of a workout name identifies it.
        let names = (store.activeRoutine()?.orderedEntries ?? [])
            .compactMap { store.workout($0.workoutID)?.name
                .split(separator: " ").first.map(String.init)?.uppercased() }
        return HStack(alignment: .top, spacing: 8) {
            ForEach(Array(names.prefix(6).enumerated()), id: \.offset) { i, name in
                VStack(alignment: .leading, spacing: 7) {
                    Capsule()
                        .fill(i < p.done ? action : ink.opacity(0.12))
                        .frame(height: 3)
                    Text(name)
                        .font(LWFont.mono(8.5)).tracking(1.1)
                        .foregroundStyle(i == p.done ? action : ink.opacity(i < p.done ? 0.7 : 0.3))
                        .lineLimit(1).truncationMode(.tail)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Cycle \(p.cycle), \(p.done) of \(p.total) done")
    }

    /// Hidden until a workout has been repeated — there is no cycle-over-cycle number
    /// before the loop has come round once, and a fabricated one would be worse than none.
    @ViewBuilder private var proof: some View {
        if let p = store.cycleProof() {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(p.pct >= 0 ? "+\(String(format: "%.1f", p.pct))%" : "\(String(format: "%.1f", p.pct))%")
                    .font(LWFont.mono(26, semibold: true)).tracking(-0.5)
                    .foregroundStyle(p.pct >= 0 ? action : ink.opacity(0.75))
                Text("CYCLE OVER CYCLE · \(p.workout.uppercased()) e1RM")
                    .font(LWFont.mono(9)).tracking(1.1)
                    .foregroundStyle(ink.opacity(0.45))
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
        }
    }

    private var providers: some View {
        VStack(spacing: 12) {
            apple
            google
            Text(auth.offline ? "No connection. Try again."
                              : "No email, no password. Just an ID to keep your lifts.")
                .font(LWFont.mono(9.5)).tracking(0.5).lineSpacing(3)
                .foregroundStyle(ink.opacity(auth.offline ? 0.75 : 0.5))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 12).padding(.top, 4)
                .accessibilityIdentifier("login.caption")
        }
    }

    /// Both rows share one content width so the two glyphs land on the same x. Centring
    /// each row independently would stagger them, since the labels differ in width.
    private func providerRow<I: View>(_ icon: I, _ title: String, spinning: Bool, tint: Color) -> some View {
        HStack(spacing: 9) {
            if spinning {
                ProgressView().controlSize(.small).tint(tint)
            } else {
                icon.frame(width: 20, height: 20)
                Text(title).font(LWFont.archivo(15, weight: 700))
            }
        }
        .frame(width: 196, alignment: spinning ? .center : .leading)
    }

    private var apple: some View {
        let loading = auth.phase == .loading
        return Button { pending = .apple; auth.signIn() } label: {
            providerRow(
                // the leaf makes the mark read high in its box; a point down optically centres it
                Image(systemName: "applelogo").font(.system(size: 17)).offset(y: -1),
                "Continue with Apple", spinning: loading && pending == .apple, tint: ground)
            .foregroundStyle(ground)
            .frame(maxWidth: .infinity).frame(height: 52)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(ink))
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain).disabled(loading)
        .accessibilityIdentifier("login.apple").accessibilityLabel("Continue with Apple")
    }

    private var google: some View {
        let loading = auth.phase == .loading
        return Button { pending = .google; auth.signInWithGoogle() } label: {
            providerRow(GoogleG(size: 18), "Continue with Google",
                        spinning: loading && pending == .google, tint: ink)
            .foregroundStyle(ink.opacity(0.9))
            .frame(maxWidth: .infinity).frame(height: 52)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(ink.opacity(0.22), lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain).disabled(loading)
        .accessibilityIdentifier("login.google").accessibilityLabel("Continue with Google")
    }

    /// Reduce motion: the glow fades in and holds — no breath.
    private func raise() {
        withAnimation(.easeOut(duration: 0.4)) { shown = true }
        guard !reduceMotion else { return }
        withAnimation(.easeInOut(duration: 3.5).repeatForever(autoreverses: true)) { breathing = true }
    }
}

/// Google's mark, drawn rather than bundled: a four-arc ring plus the crossbar.
/// Brand colours are fixed values by definition, so they are not theme tokens.
private struct GoogleG: View {
    var size: CGFloat

    var body: some View {
        Canvas { ctx, s in
            let c = CGPoint(x: s.width / 2, y: s.height / 2)
            let outer = min(s.width, s.height) / 2
            let weight = outer * 0.44          // the ring must stay open: the hole is the letter
            let r = outer - weight / 2

            func arc(_ from: Double, _ to: Double, _ hex: UInt32) {
                var p = Path()
                p.addArc(center: c, radius: r, startAngle: .degrees(from), endAngle: .degrees(to), clockwise: false)
                ctx.stroke(p, with: .color(Color(lwHex(hex))), style: StrokeStyle(lineWidth: weight, lineCap: .butt))
            }
            arc(206, 337, 0xEA4335)                 // red, over the top
            arc(337, 404, 0x4285F4)                 // blue, the right flank
            arc(44, 132, 0x34A853)                  // green, the bottom
            arc(132, 206, 0xFBBC05)                 // yellow, the left

            // the crossbar: same weight as the ring, from the centre out to the right edge
            var bar = Path()
            bar.addRect(CGRect(x: c.x, y: c.y - weight / 2, width: outer, height: weight))
            ctx.fill(bar, with: .color(Color(lwHex(0x4285F4))))
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
