import SwiftUI
import UniformTypeIdentifiers

/// Account (acct-page.jpg): who you are, the two numbers Home already shows, appearance, data,
/// sign out. Comes in over the pager from the left; a leading drag takes it back out the same way.
struct AccountView: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router
    @Environment(AuthState.self) private var auth
    @AppStorage("appearance.mode") private var appearanceMode = "system"
    @State private var confirmSignOut = false
    @State private var picking = false
    @State private var syncing = false
    @State private var syncNote: String?
    @State private var lastImport = UserDefaults.standard.object(forKey: "hevy.lastImport") as? Date
    @State private var dragX: CGFloat = 0

    var body: some View {
        Screen {
            VStack(alignment: .leading, spacing: 0) {
                nav
                identity.padding(.top, 26)
                facts.padding(.top, 22)
                label("APPEARANCE").padding(.top, 26).padding(.bottom, 10)
                segment
                label("DATA").padding(.top, 26)
                dataRows
                Spacer(minLength: 24)
                signOut
                footer.padding(.top, 14)
            }
            .padding(.horizontal, 10)                  // 20pt margins, with the screen's own 10
            .padding(.bottom, safeBottom + 22)
        }
        .offset(x: dragX)
        .gesture(DragGesture(minimumDistance: 12)
            .onChanged { v in dragX = min(0, v.translation.width) }
            .onEnded { v in
                if v.translation.width + v.velocity.width * 0.2 < -90 { router.closeAccount() }
                else { withAnimation(.easeOut(duration: 0.2)) { dragX = 0 } }
            })
        .accessibilityElement(children: .contain).accessibilityIdentifier("account")
    }

    private var nav: some View {
        ZStack {
            Text("ACCOUNT").font(LWFont.mono(10)).tracking(2.2).foregroundStyle(LW.ink(0.58))
            HStack {
                Button { router.closeAccount() } label: {
                    Icon(kind: .chevronLeft, size: 24, color: LW.ink(0.7), weight: 2)
                        .frame(width: 44, height: 36).contentShape(Rectangle())
                }.buttonStyle(.plain).offset(x: -12)
                .accessibilityIdentifier("account.back").accessibilityLabel("Back")
                Spacer()
            }
        }.frame(height: 28)
    }

    private var identity: some View {
        let name = auth.account?.name
        let since = auth.account.map { "since \(Fmt.date($0.since, "MMM yyyy"))" } ?? ""
        return HStack(spacing: 13) {
            Text(name.map { $0.prefix(1).uppercased() } ?? "·")
                .font(LWFont.archivo(19, weight: 800)).foregroundStyle(LW.accent)
                .frame(width: 52, height: 52)
                .background(Circle().fill(LW.accent(0.16)))
                .overlay(Circle().strokeBorder(LW.accent(0.4), lineWidth: 1))
            VStack(alignment: .leading, spacing: 3) {
                Text(name ?? "Apple ID").font(LWFont.archivo(19, weight: 800)).foregroundStyle(LW.ink)
                    .lineLimit(1).minimumScaleFactor(0.7)
                Text(name == nil ? since : "Apple ID · \(since)")     // no name granted: the line above already says it
                    .font(LWFont.mono(10.5)).foregroundStyle(LW.ink(0.58))
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine).accessibilityIdentifier("account.identity")
    }

    private var facts: some View {
        HStack(spacing: 10) {
            tile("\(store.finishedSessions().count)", "SESSIONS", id: "account.sessions", accent: false)
            tile("\(store.weekStreak())", "WEEK STREAK", id: "account.streak", accent: true)
        }
    }

    private func tile(_ value: String, _ name: String, id: String, accent: Bool) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value).font(LWFont.mono(20, semibold: true)).foregroundStyle(accent ? LW.accent : LW.ink)
                .lineLimit(1).minimumScaleFactor(0.6)
            Text(name).font(LWFont.mono(8.5)).tracking(1.02).foregroundStyle(LW.ink(0.58))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12).padding(.vertical, 11)
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(LW.ink(0.12), lineWidth: 1))
        .accessibilityElement(children: .combine).accessibilityIdentifier(id)
    }

    private var segment: some View {
        HStack(spacing: 0) {
            ForEach(["dark", "light", "system"], id: \.self) { mode in
                Button { pick(mode) } label: {
                    Text(mode.uppercased()).font(LWFont.mono(11, semibold: true)).tracking(1.3)
                        .foregroundStyle(appearanceMode == mode ? LW.bg : LW.ink(0.6))
                        .frame(maxWidth: .infinity).frame(height: 34)
                        .background { if appearanceMode == mode { RoundedRectangle(cornerRadius: 10, style: .continuous).fill(LW.ink) } }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("account.appearance.\(mode)")
                .accessibilityAddTraits(appearanceMode == mode ? [.isSelected] : [])
            }
        }
        .padding(3)
        .frame(height: 40)
        .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(LW.ink(0.06)))
        .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).strokeBorder(LW.ink(0.1), lineWidth: 1))
        .accessibilityElement(children: .contain)
    }

    /// Debug only. Sync is push-only and unfinished; shipping a half-duplex sync button to
    /// users would imply their data is safe on the server, which it is not yet.
    @ViewBuilder private var syncRow: some View {
        #if DEBUG
        Button {
            syncing = true
            Task {
                do { let r = try await Sync.pushAll(store); syncNote = r.summary }
                catch { syncNote = error.localizedDescription }
                syncing = false
            }
        } label: {
            HStack(spacing: 10) {
                Text("Push to Postgres").font(LWFont.body(14)).foregroundStyle(LW.ink)
                Spacer(minLength: 8)
                Text(syncing ? "pushing…" : (syncNote ?? "debug"))
                    .font(LWFont.mono(10)).foregroundStyle(LW.ink(0.58)).lineLimit(1)
                Icon(kind: .chevronRight, size: 14, color: LW.ink(0.4), weight: 1.8)
            }
            .frame(height: 48).contentShape(Rectangle())
        }
        .buttonStyle(.plain).disabled(syncing)
        .overlay(alignment: .bottom) { Hairline() }
        .accessibilityIdentifier("account.sync").accessibilityLabel("Push to Postgres")
        #endif
    }

    private var dataRows: some View {
        VStack(spacing: 0) {
        syncRow
        Button { picking = true } label: {
            HStack(spacing: 10) {
                Text("Import from Hevy").font(LWFont.body(14)).foregroundStyle(LW.ink)
                Spacer(minLength: 8)
                Text(lastImport.map { "last \(Fmt.date($0, "d MMM"))" } ?? "never")
                    .font(LWFont.mono(10)).foregroundStyle(LW.ink(0.58))
                Icon(kind: .chevronRight, size: 14, color: LW.ink(0.4), weight: 1.8)
            }
            .frame(height: 48).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) { Hairline() }
        .accessibilityIdentifier("account.import").accessibilityLabel("Import from Hevy")
        .fileImporter(isPresented: $picking, allowedContentTypes: [.commaSeparatedText, .plainText]) { result in
            guard case let .success(url) = result, url.startAccessingSecurityScopedResource() else { return }
            defer { url.stopAccessingSecurityScopedResource() }
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { return }
            store.importHevy(text: text)
            lastImport = .now
            UserDefaults.standard.set(lastImport, forKey: "hevy.lastImport")
        }
        }
    }

    private var signOut: some View {
        Button { confirmSignOut = true } label: {
            Text("Sign out").font(LWFont.archivo(14, weight: 600)).foregroundStyle(LW.ink(0.85))
                .frame(maxWidth: .infinity).frame(height: 44)
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(LW.ink(0.22), lineWidth: 1))
                .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain).accessibilityIdentifier("account.signout")
        .alert("Sign out?", isPresented: $confirmSignOut) {
            Button("Sign out", role: .destructive) { router.home(); auth.signOut() }
            Button("Cancel", role: .cancel) {}
        } message: { Text("Your sessions stay on this phone.") }
    }

    private var footer: some View {
        HStack(spacing: 5) {
            Text("v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0")")
            Text("·")
            legal("Privacy", id: "account.privacy")
            Text("·")
            legal("Terms", id: "account.terms")
        }
        .font(LWFont.mono(9)).tracking(0.9).foregroundStyle(LW.ink(0.58))
        .frame(maxWidth: .infinity)
    }

    /// The pages themselves land with the real sign-in pass.
    private func legal(_ title: String, id: String) -> some View {
        Button {} label: { Text(title).underline() }
            .buttonStyle(.plain).accessibilityIdentifier(id)
    }

    private func label(_ t: String) -> some View {
        Text(t).font(LWFont.mono(9)).tracking(1.98).foregroundStyle(LW.ink(0.58))
    }

    private func pick(_ mode: String) {
        UISelectionFeedbackGenerator().selectionChanged()
        withAnimation(.easeOut(duration: 0.2)) { appearanceMode = mode }
    }

    /// `Screen` runs full-bleed, so the footer has to clear the home indicator itself.
    private var safeBottom: CGFloat {
        UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow?.safeAreaInsets.bottom }.first ?? 0
    }
}
