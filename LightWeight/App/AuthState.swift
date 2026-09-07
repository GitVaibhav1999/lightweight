import SwiftUI
import Observation

/// Mock Sign in with Apple. The screens only ever read `phase`, so the real pass swaps the two
/// stubs below — `signIn()` for an ASAuthorizationController round-trip, `init` for a restored
/// session — and nothing above this file changes.
@MainActor @Observable final class AuthState {
    enum Phase: Equatable { case signedOut, loading, signedIn(name: String?, since: Date) }

    private(set) var phase: Phase
    private(set) var offline: Bool          // login caption swaps to "No connection. Try again."

    /// Signed in unless `--signed-out`: the login screen must not stand between the suite and Home.
    init() {
        let args = CommandLine.arguments
        let down = args.contains("--auth-offline")
        offline = down
        phase = (down || args.contains("--signed-out")) ? .signedOut : Self.mockAccount
    }

    var isSignedIn: Bool { if case .signedIn = phase { return true }; return false }
    var account: (name: String?, since: Date)? {
        if case let .signedIn(name, since) = phase { return (name, since) }
        return nil
    }

    /// Stub: the credential sheet takes about this long, and a cancel lands back on signedOut with no toast.
    func signIn() {
        guard phase != .loading else { return }
        phase = .loading
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
            self.phase = self.offline ? .signedOut : Self.mockAccount
        }
    }

    func signOut() { phase = .signedOut }

    private static let mockAccount = Phase.signedIn(name: "Aman", since: DateComponents(calendar: .current, year: 2026, month: 8, day: 1).date ?? .now)
}
