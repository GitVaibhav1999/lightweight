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

    /// The simulator shares the Mac's loopback, so it uses the local stack. A device
    /// cannot: Google will only redirect an OAuth callback to https (localhost is the
    /// one exception), and a plain-http LAN address cannot be registered with Google
    /// at all. So a device — debug or release — talks to the hosted project.
    static var url: URL {
        #if DEBUG && targetEnvironment(simulator)
        URL(string: "http://127.0.0.1:54321")!
        #else
        URL(string: "https://\(projectRef).supabase.co")!
        #endif
    }

    /// Not a secret: it only names the project. Every table is default-deny under RLS,
    /// so this key alone reads nothing without a user's JWT.
    static var anonKey: String {
        #if DEBUG && targetEnvironment(simulator)
        // Fixed local demo key, identical on every machine and published by Supabase.
        "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0"
        #else
        "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Indiam53aGVmb3RzbGtqeHJ2cmdtIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODg3NzUyODAsImV4cCI6MjEwNDM1MTI4MH0.J1rBJeMXdl0QVAmYiod-QUoagngdbDG0NHkrHjVoxKg"
        #endif
    }

    static let projectRef = "wbjnwhefotslkjxrvrgm"
}
