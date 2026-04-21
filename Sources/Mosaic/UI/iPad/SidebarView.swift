// Sources/Mosaic/UI/iPad/SidebarView.swift
import SwiftUI

@MainActor
struct SidebarView: View {
    @ObservedObject var manager: SessionManager
    let onAddTab: () -> Void
    let onSettings: () -> Void

    var body: some View {
        List(manager.sessions, selection: Binding<UUID?>(
            get: { manager.activeSessionID },
            set: { manager.activeSessionID = $0 }
        )) { session in
            SidebarRow(session: session, onClose: { manager.closeSession(session) })
                .tag(session.id as UUID?)
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(Color.mosaicSurface1)
        .overlay {
            if manager.sessions.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "server.rack")
                        .font(.system(size: 36))
                        .foregroundStyle(Color.mosaicTextSec)
                    Text("No sessions")
                        .font(.custom("JetBrains Mono", size: 12))
                        .foregroundStyle(Color.mosaicTextSec)
                }
            }
        }
        .navigationTitle("Mosaic")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { onSettings() } label: {
                    Image(systemName: "gearshape")
                        .foregroundStyle(Color.mosaicTextSec)
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { onAddTab() } label: {
                    Image(systemName: "plus")
                        .foregroundStyle(Color.mosaicAccent)
                }
            }
        }
    }
}

@MainActor
private struct SidebarRow: View {
    @ObservedObject var session: Session
    let onClose: () -> Void

    private var connInfo: ConnectionInfo { session.connection.connectionInfo }
    private var connState: ConnectionState { session.connectionState }

    var body: some View {
        HStack(spacing: 10) {
            StatusDot(state: connState)

            VStack(alignment: .leading, spacing: 2) {
                Text(connInfo.hostname)
                    .font(.custom("JetBrains Mono", size: 11).weight(.semibold))
                    .foregroundStyle(Color.mosaicTextPri)
                    .lineLimit(1)
                Text(connInfo.username)
                    .font(.custom("JetBrains Mono", size: 9))
                    .foregroundStyle(Color.mosaicTextSec)
            }

            Spacer()

            ProtocolBadge(transport: connInfo.transport, isRoaming: connState == .roaming)

            Button { onClose() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Color.mosaicTextSec)
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}
