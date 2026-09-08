import SwiftUI
import Observation
import AuthenticationServices
import CryptoKit
import Supabase

/// Sign in with Apple, plus an email code as the fallback that works on a free
/// developer team. The screens read `phase` and nothing else.
@MainActor @Observable final class AuthState {
    enum Phase: Equatable {
        case restoring                          // looking for a stored session at launch
        case signedOut
        case loading                            // an attempt is in flight
        case awaitingCode(email: String)        // code sent, waiting for the six digits
        case signedIn(name: String?, since: Date)
    }

    private(set) var phase: Phase = .restoring
    private(set) var offline = false            // login caption swaps to "No connection. Try again."
    private(set) var codeError = false          // wrong or expired code

    private let mock: Bool
    private var appleSignIn: AppleSignIn?        // strong ref: ASAuthorizationController does not keep one
    private var currentNonce: String?

    init() {
        let args = CommandLine.arguments
        mock = args.contains("--mock-auth")
        if mock {
            offline = args.contains("--auth-offline")
            phase = (offline || args.contains("--signed-out")) ? .signedOut : Self.mockAccount
            return
        }
        // Debug only. The simulator points at the local stack, where the only sign-in the UI
        // offers (Apple, Google) cannot complete — so testing anything that needs a real
        // auth.uid(), like a sync push, needs a password path that does not exist in the app.
        #if DEBUG
        if let i = args.firstIndex(of: "--dev-signin"), i + 2 < args.count {
            let email = args[i + 1], password = args[i + 2]
            Task {
                do {
                    let session = try await Supa.client.auth.signIn(email: email, password: password)
                    phase = Self.signedIn(from: session.user)
                } catch { phase = .signedOut }
            }
            return
        }
        #endif
        Task { await restore() }
    }

    var isSignedIn: Bool { if case .signedIn = phase { return true }; return false }
    var account: (name: String?, since: Date)? {
        if case let .signedIn(name, since) = phase { return (name, since) }
        return nil
    }

    // ── session ──────────────────────────────────────────────────────────────

    /// A stored session survives relaunch; the SDK refreshes it if it has expired.
    private func restore() async {
        do { phase = Self.signedIn(from: try await Supa.client.auth.session.user) }
        catch { phase = .signedOut }
    }

    private static func signedIn(from user: User) -> Phase {
        let meta = user.userMetadata
        let name = (meta["full_name"] ?? meta["name"])?.stringValue?
            .trimmingCharacters(in: .whitespaces)
        return .signedIn(name: (name?.isEmpty ?? true) ? nil : name, since: user.createdAt)
    }

    func signOut() {
        phase = .signedOut
        guard !mock else { return }
        Task { try? await Supa.client.auth.signOut() }
    }

    // ── Sign in with Apple ───────────────────────────────────────────────────

    func signIn() {
        guard phase != .loading else { return }
        phase = .loading
        guard !mock else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
                self.phase = self.offline ? .signedOut : Self.mockAccount
            }
            return
        }
        // Apple signs the nonce's hash into the token; Supabase re-derives it from the
        // raw value we send, which is what stops a stolen token being replayed.
        let raw = Self.nonce()
        currentNonce = raw
        let signIn = AppleSignIn { [weak self] result in
            Task { @MainActor in await self?.finishApple(result) }
        }
        appleSignIn = signIn
        signIn.start(nonceHash: Self.sha256(raw))
    }

    private func finishApple(_ result: Result<String, Error>) async {
        defer { appleSignIn = nil }
        guard case let .success(idToken) = result, let raw = currentNonce else {
            phase = .signedOut                   // cancel is silent, per the handoff
            return
        }
        do {
            let session = try await Supa.client.auth.signInWithIdToken(
                credentials: .init(provider: .apple, idToken: idToken, nonce: raw))
            phase = Self.signedIn(from: session.user)
        } catch {
            offline = true
            phase = .signedOut
        }
    }

    // ── Sign in with Google ──────────────────────────────────────────────────

    /// OAuth, not an Apple capability, so this works on a free developer team and
    /// on a real device today. The SDK opens an ASWebAuthenticationSession, Google
    /// redirects to Supabase's callback, and Supabase bounces back to lightweight://
    /// with the session already exchanged.
    func signInWithGoogle() {
        guard phase != .loading else { return }
        phase = .loading
        guard !mock else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
                self.phase = self.offline ? .signedOut : Self.mockAccount
            }
            return
        }
        Task {
            do {
                let session = try await Supa.client.auth.signInWithOAuth(
                    provider: .google,
                    redirectTo: URL(string: "lightweight://auth-callback"))
                phase = Self.signedIn(from: session.user)
            } catch is CancellationError {
                phase = .signedOut                   // dismissed the sheet
            } catch {
                // ASWebAuthenticationSession reports a user cancel as an error too.
                offline = !Self.isUserCancel(error)
                phase = .signedOut
            }
        }
    }

    private static func isUserCancel(_ error: Error) -> Bool {
        let ns = error as NSError
        return ns.domain == ASWebAuthenticationSessionErrorDomain
            && ns.code == ASWebAuthenticationSessionError.canceledLogin.rawValue
    }

    // ── email code ───────────────────────────────────────────────────────────

    func sendCode(to email: String) {
        let address = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard address.contains("@"), phase != .loading else { return }
        phase = .loading
        guard !mock else { phase = .awaitingCode(email: address); return }
        Task {
            do {
                try await Supa.client.auth.signInWithOTP(email: address)
                phase = .awaitingCode(email: address)
            } catch {
                offline = true
                phase = .signedOut
            }
        }
    }

    func verifyCode(_ code: String) {
        guard case let .awaitingCode(email) = phase else { return }
        let digits = code.filter(\.isNumber)
        guard digits.count == 6 else { return }
        codeError = false
        guard !mock else { phase = Self.mockAccount; return }
        Task {
            do {
                let session = try await Supa.client.auth.verifyOTP(
                    email: email, token: digits, type: .email)
                phase = Self.signedIn(from: session.user)
            } catch {
                codeError = true                 // stay on the code screen so it can be retyped
            }
        }
    }

    /// Back out of the code screen without losing the typed address on the next try.
    func cancelCode() { if case .awaitingCode = phase { phase = .signedOut; codeError = false } }

    // ── nonce ────────────────────────────────────────────────────────────────

    private static func nonce(_ length: Int = 32) -> String {
        let chars = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        return String((0..<length).map { _ in chars[Int.random(in: 0..<chars.count)] })
    }

    private static func sha256(_ s: String) -> String {
        SHA256.hash(data: Data(s.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private static let mockAccount = Phase.signedIn(
        name: "Aman",
        since: DateComponents(calendar: .current, year: 2026, month: 8, day: 1).date ?? .now)
}

/// ASAuthorizationController needs an NSObject delegate and a presentation anchor.
private final class AppleSignIn: NSObject, ASAuthorizationControllerDelegate,
                                 ASAuthorizationControllerPresentationContextProviding {
    private let done: (Result<String, Error>) -> Void
    init(done: @escaping (Result<String, Error>) -> Void) { self.done = done }

    func start(nonceHash: String) {
        let request = ASAuthorizationAppleIDProvider().createRequest()
        // .email is not optional: GoTrue rejects the user outright when the project
        // has email_optional = false and Apple returns no address.
        request.requestedScopes = [.fullName, .email]
        request.nonce = nonceHash
        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self
        controller.performRequests()
    }

    func authorizationController(controller: ASAuthorizationController,
                                 didCompleteWithAuthorization auth: ASAuthorization) {
        guard let cred = auth.credential as? ASAuthorizationAppleIDCredential,
              let data = cred.identityToken, let token = String(data: data, encoding: .utf8)
        else { return done(.failure(URLError(.badServerResponse))) }
        done(.success(token))
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        done(.failure(error))
    }

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow }.first ?? ASPresentationAnchor()
    }
}
