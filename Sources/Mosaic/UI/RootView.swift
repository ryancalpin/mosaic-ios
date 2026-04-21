import SwiftUI

// MARK: - RootView
//
// Top-level layout: tab bar → breadcrumb → session content.
// Manages the connection sheet and session switching.

@MainActor
struct RootView: View {
    @ObservedObject private var manager = SessionManager.shared
    @State private var showConnectionSheet = false
    @State private var showSettingsSheet = false
    @State private var connectionError: String? = nil

    var body: some View {
        ZStack {
            Color.mosaicBg.ignoresSafeArea()

            VStack(spacing: 0) {
                // Tab bar (always visible)
                if !manager.sessions.isEmpty {
                    TabBarView(manager: manager, onAddTab: {
                        showConnectionSheet = true
                    }, onSettings: {
                        showSettingsSheet = true
                    })
                }

                // Content
                if let session = manager.activeSession {
                    SessionView(session: session)
                        .id(session.id)
                } else {
                    EmptyStateView(onConnect: {
                        showConnectionSheet = true
                    })
                }
            }
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showSettingsSheet) {
            SettingsSheet()
                .environment(AppSettings.shared)
        }
        .sheet(isPresented: $showConnectionSheet) {
            ConnectionSheet { connection in
                Task {
                    if let err = await manager.openSessionThrowing(for: connection) {
                        connectionError = (err as any Error).localizedDescription
                    }
                }
            }
        }
        .alert("Connection Error", isPresented: Binding(
            get: { connectionError != nil },
            set: { if !$0 { connectionError = nil } }
        )) {
            Button("OK") { connectionError = nil }
        } message: {
            Text(connectionError ?? "")
        }
    }
}
