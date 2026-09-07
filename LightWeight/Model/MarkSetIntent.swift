import AppIntents

/// Lock-screen "mark next set" button. LiveActivityIntent runs in the APP process,
/// so the store is reachable; the widget target compiles only the stub (LW_WIDGET).
struct MarkSetIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Mark next set done"
    func perform() async throws -> some IntentResult {
        #if !LW_WIDGET
        await AppStore.shared?.markNextSetFromIntent()
        #endif
        return .result()
    }
}
