import AppIntents

struct MosaicShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: OpenServerIntent(),
            phrases: [
                "Open a server in \(.applicationName)",
                "Connect to a server in \(.applicationName)",
                "SSH to a server with \(.applicationName)"
            ],
            shortTitle: "Open Server",
            systemImageName: "terminal"
        )
    }
}
