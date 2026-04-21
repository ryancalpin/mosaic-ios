import SwiftUI
import SwiftData

@main
struct MosaicApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
                .modelContainer(for: [Connection.self])
                .onAppear {
                    // RendererRegistry bootstraps itself on first access
                    _ = RendererRegistry.shared
                }
        }
    }
}
