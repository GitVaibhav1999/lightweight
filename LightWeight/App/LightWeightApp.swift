import SwiftUI
import SwiftData

@main
struct LightWeightApp: App {
    @State private var store = AppStore(inMemory: CommandLine.arguments.contains("--empty-demo"))
    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .modelContainer(store.container)
        }
    }
}
