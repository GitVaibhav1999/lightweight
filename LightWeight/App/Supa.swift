import Foundation
import Supabase

/// The Supabase client. One instance, resolved against whichever backend this
/// build can actually reach.
///
/// The anon key is not a secret — it only identifies the project. Every table is
/// fenced by row level security, so a caller holding it can still read nothing
/// until they present a user's JWT. The service_role key, which does bypass RLS,
/// never leaves the server.
enum Supa {
    static let client = SupabaseClient(supabaseURL: url, supabaseKey: anonKey)

    /// Simulator shares the Mac's loopback; a phone does not, so it needs the LAN
    /// address. Release talks to the hosted project over https.
    static var url: URL {
        #if DEBUG
        #if targetEnvironment(simulator)
        URL(string: "http://127.0.0.1:54321")!
        #else
        URL(string: "http://\(devHost):54321")!
        #endif
        #else
        URL(string: "https://\(projectRef).supabase.co")!
        #endif
    }

    static var anonKey: String {
        #if DEBUG
        // Fixed local demo key, identical on every machine and published by Supabase.
        "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0"
        #else
        Bundle.main.object(forInfoDictionaryKey: "SUPABASE_ANON_KEY") as? String ?? ""
        #endif
    }

    static let projectRef = "wbjnwhefotslkjxrvrgm"

    /// The Mac running `supabase start`. Overridable without a rebuild so a
    /// changed DHCP lease doesn't mean re-signing the app.
    static var devHost: String {
        UserDefaults.standard.string(forKey: "supa.devHost") ?? "192.168.101.84"
    }
}
