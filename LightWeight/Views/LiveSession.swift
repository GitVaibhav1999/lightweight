import SwiftUI

/// Elapsed mm:ss for a live session.
struct LiveTimer: View {
    let since: Date
    var size: CGFloat = 11
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            let t = max(0, Int(ctx.date.timeIntervalSince(since)))
            Text(String(format: "%d:%02d", t / 60, t % 60)).font(LWFont.mono(size)).foregroundStyle(LW.ink(0.5))
        }
    }
}

/// The floating liquid-glass pill shown on every non-Home page while a session is live.
struct LivePill: View {
    @Environment(Router.self) private var router
    let session: Session
    var body: some View {
        let p = AppStore.progress(session)
        Button { router.present(.session(session.id)) } label: {
            HStack(spacing: 6) {
                PulseDot(size: 6)
                HStack(spacing: 5) {
                    Text("\(Int((p * 100).rounded()))%").font(LWFont.mono(10.5, semibold: true)).foregroundStyle(LW.accent)
                    LiveTimer(since: session.startedAt, size: 10)
                }.lineLimit(1).minimumScaleFactor(0.7)
                Spacer(minLength: 0)
                Circle().fill(LW.accent).frame(width: 34, height: 34)
                    .overlay(Icon(kind: .chevronUp, size: 13, color: LW.inkOnAccent, weight: 2.2))
            }
            .padding(.leading, 10).padding(.trailing, 5)
            .frame(maxWidth: .infinity).frame(height: 48)
            .lwGlass(Capsule(), rim: 0.18)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("live.pill").accessibilityLabel("Resume \(session.title)")
    }
}
