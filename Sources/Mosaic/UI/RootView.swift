// Sources/Mosaic/UI/RootView.swift
import SwiftUI

@MainActor
struct RootView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(\.horizontalSizeClass) private var sizeClass
    @ObservedObject private var manager = SessionManager.shared
    @State private var showConnectionSheet = false
    @State private var showSettingsSheet = false
    @State private var connectionError: String? = nil
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var showAITab  = false
    @State private var aiSession: AISession? = nil

    var body: some View {
        Group {
            if sizeClass == .regular {
                iPadLayout
            } else {
                iPhoneLayout
            }
        }
        .preferredColorScheme(settings.theme.colorScheme)
        .environment(\.terminalFontSize,    settings.terminalFontSize)
        .environment(\.outputDensity,       settings.outputDensity)
        .environment(\.showNativeRenderers, settings.showNativeRenderers)
        .environment(\.showTimestamps,      settings.showTimestamps)
        .sheet(isPresented: $showSettingsSheet) {
            SettingsSheet()
        }
        .sheet(isPresented: $showConnectionSheet) {
            ConnectionSheet { connection in
                Task {
                    if let err = await manager.openSessionThrowing(for: connection) {
                        connectionError = (err as any Error).localizedDescription
                    }
                }
            }
            .environment(AppSettings.shared)
        }
        .alert("Connection Error", isPresented: Binding(
            get: { connectionError != nil },
            set: { if !$0 { connectionError = nil } }
        )) {
            Button("OK") { connectionError = nil }
        } message: {
            Text(connectionError ?? "")
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: NSNotification.Name.NSPersistentStoreRemoteChange
            )
        ) { _ in
            // @Query views update automatically when CloudKit pushes arrive.
            // This is the hook point for any imperative state refresh in the future.
        }
    }

    private func getOrCreateAISession(for session: Session) -> AISession {
        if let existing = aiSession { return existing }
        let ai = AISession(mirroring: session, apiKey: settings.claudeApiKey)
        aiSession = ai
        return ai
    }

    private var iPadLayout: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(
                manager: manager,
                onAddTab:   { showConnectionSheet = true },
                onSettings: { showSettingsSheet = true }
            )
            .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 320)
        } detail: {
            if let session = manager.activeSession {
                SessionView(session: session)
                    .id(session.id)
            } else {
                EmptyStateView(onConnect: { showConnectionSheet = true })
            }
        }
        .navigationSplitViewStyle(.balanced)
    }

    private var iPhoneLayout: some View {
        ZStack {
            Color.mosaicBg.ignoresSafeArea()
            VStack(spacing: 0) {
                if !manager.sessions.isEmpty {
                    TabBarView(
                        manager:      manager,
                        onAddTab:     { showConnectionSheet = true },
                        onSettings:   { showSettingsSheet = true },
                        onToggleAI:   {
                            showAITab.toggle()
                            if !showAITab {
                                let s = aiSession
                                aiSession = nil
                                Task { await s?.disconnect() }
                            }
                        },
                        isAITabActive: showAITab
                    )
                }
                if showAITab, let session = manager.activeSession {
                    AITabView(aiSession: getOrCreateAISession(for: session), manualSession: session)
                        .id(session.id)
                } else if let session = manager.activeSession {
                    SessionView(session: session)
                        .id(session.id)
                } else {
                    EmptyStateView(onConnect: { showConnectionSheet = true })
                        .overlay(alignment: .topTrailing) {
                            Button { showSettingsSheet = true } label: {
                                Image(systemName: "gearshape")
                                    .font(.system(size: 15))
                                    .foregroundStyle(Color.mosaicTextSec)
                                    .frame(width: 44, height: 44)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .padding(8)
                        }
                }
            }
        }
    }
}
