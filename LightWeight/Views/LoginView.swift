import SwiftUI

/// Login (acct-login.jpg): the start splash's ground and glow, the mark and name at 38 % of the
/// screen, one filled Sign in with Apple at the bottom. Always dark — the colours are the literal
/// splash tokens, not the trait-driven ones.
struct LoginView: View {
    @Environment(AuthState.self) private var auth
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false
    @State private var breathing = false

    private let ground = SplashBloom.ground
    private let ink = Color(lwHex(0xE7E5D7))
    private let action = Color(lwHex(0xADBA5E))

    var body: some View {
        ZStack {
            ground.ignoresSafeArea()
            SplashBloom(breathing: breathing)
            Rectangle()                                   // hairline along the very bottom
                .fill(LinearGradient(colors: [.clear, SplashBloom.bright.opacity(0.55), .clear], startPoint: .leading, endPoint: .trailing))
                .opacity(breathing ? 0.9 : 0.45)
                .frame(height: 2)
                .frame(maxHeight: .infinity, alignment: .bottom)
                .ignoresSafeArea()
            mark
            bottom
        }
        .opacity(shown ? 1 : 0)
        .onAppear(perform: raise)
        .accessibilityElement(children: .contain).accessibilityIdentifier("login")
    }

    private var mark: some View {
        GeometryReader { g in
            VStack(spacing: 0) {
                LogoMark(width: 64, color: action)
                VStack(spacing: 0) { nameLine("LIGHT"); nameLine("WEIGHT") }.padding(.top, 16)
            }
            .frame(width: g.size.width)
            .padding(.top, g.size.height * 0.38)
        }
        .ignoresSafeArea()
        .accessibilityElement(children: .ignore).accessibilityLabel("Light Weight")
    }

    /// 0.92 line-height: each line sits in a box shorter than the font's natural leading.
    private func nameLine(_ s: String) -> some View {
        Text(s).font(LWFont.display(34, width: 82)).tracking(-1.02).foregroundStyle(ink).frame(height: 34 * 0.92)
    }

    private var bottom: some View {
        VStack(spacing: 10) {
            // future providers stack here as 44pt outlined rows; Apple stays the filled primary below them
            apple
            Text(auth.offline ? "No connection. Try again." : "Only your Apple ID. No email, no password.")
                .font(LWFont.mono(9.5)).tracking(0.76)
                .foregroundStyle(ink.opacity(auth.offline ? 0.75 : 0.58))
                .multilineTextAlignment(.center).padding(.top, 4)
                .accessibilityIdentifier("login.caption")
        }
        .padding(.horizontal, 20)
        .frame(maxHeight: .infinity, alignment: .bottom)
        .padding(.bottom, 26)
    }

    private var apple: some View {
        let loading = auth.phase == .loading
        return Button { auth.signIn() } label: {
            HStack(spacing: 9) {
                if loading {
                    ProgressView().controlSize(.small).tint(ground)      // the label colour on an ink fill is the ground
                } else {
                    Image(systemName: "applelogo").font(.system(size: 17)).frame(width: 17, height: 20)
                    Text("Sign in with Apple").font(LWFont.archivo(15, weight: 700))
                }
            }
            .foregroundStyle(ground)
            .frame(maxWidth: .infinity).frame(height: 52)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(ink))
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain).disabled(loading)
        .accessibilityIdentifier("login.apple").accessibilityLabel("Sign in with Apple")
    }

    /// Reduce motion: the glow fades in and holds — no breath.
    private func raise() {
        withAnimation(.easeOut(duration: 0.4)) { shown = true }
        guard !reduceMotion else { return }
        withAnimation(.easeInOut(duration: 3.5).repeatForever(autoreverses: true)) { breathing = true }
    }
}
