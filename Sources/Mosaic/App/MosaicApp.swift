import SwiftUI
import SwiftData

@main
struct MosaicApp: App {
    let container: ModelContainer

    init() {
        do {
            let cloudConfig = ModelConfiguration("cloud", schema: Schema([Connection.self]),     cloudKitDatabase: .automatic)
            let localConfig = ModelConfiguration("local", schema: Schema([CommandHistory.self, CustomRenderer.self]), cloudKitDatabase: .none)
            container = try ModelContainer(for: Connection.self, CommandHistory.self, CustomRenderer.self, configurations: cloudConfig, localConfig)
            injectTestSSHKeyIfNeeded(container: container)
            let ctx = ModelContext(container)
            Task { @MainActor in
                RendererRegistry.shared.registerCustomRenderers(from: ctx)
            }
        } catch {
            fatalError("Failed to create model container: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .modelContainer(container)
                .environment(AppSettings.shared)
                .onAppear { NotificationManager.shared.requestPermission() }
                .onContinueUserActivity("com.mosaic.session") { activity in
                    guard
                        let idString = activity.userInfo?["connectionID"] as? String,
                        let uuid = UUID(uuidString: idString)
                    else { return }

                    let ctx = ModelContext(container)
                    let descriptor = FetchDescriptor<Connection>(
                        predicate: #Predicate { $0.id == uuid }
                    )
                    guard let connection = try? ctx.fetch(descriptor).first else { return }

                    Task { @MainActor in
                        _ = await SessionManager.shared.openSessionThrowing(for: connection)
                    }
                }
        }
    }

    // DEBUG ONLY — injects a localhost SSH-key connection for T-SSH-4 testing
    private func injectTestSSHKeyIfNeeded(container: ModelContainer) {
        let ctx = ModelContext(container)
        let existing = try? ctx.fetch(FetchDescriptor<Connection>())
        guard (existing ?? []).filter({ $0.name == "localhost-key" }).isEmpty else { return }
        let conn = Connection(name: "localhost-key", hostname: "localhost", port: 22, username: "ryancalpin", transport: .ssh)
        let key = """
-----BEGIN PRIVATE KEY-----
MIGHAgEAMBMGByqGSM49AgEGCCqGSM49AwEHBG0wawIBAQQgAwDpRUradu5M7wd2
O1Mt1YiaX8zZyjahtz59y+41SwOhRANCAAS4UPkYWWLKuyR/Xrch51Yn0a2/RIWC
wUbV26+Hkoe4GurZdHk6k8AcHhTFq9BZAgIwQ0WGh6A4h6ZtPqH45nGv
-----END PRIVATE KEY-----
"""
        KeychainHelper.savePrivateKey(key, connectionID: conn.id.uuidString)
        ctx.insert(conn)
        try? ctx.save()
    }
}
