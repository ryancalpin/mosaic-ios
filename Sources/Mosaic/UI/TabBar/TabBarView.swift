import SwiftUI

// MARK: - TabBarView
//
// Horizontal scrolling tab strip at the top.
// Each tab: status dot + server name + protocol badge.
// Active tab has accent underline. "+" opens connection sheet.

@MainActor
struct TabBarView: View {
    @ObservedObject var manager: SessionManager
    let onAddTab: () -> Void
    let onSettings: () -> Void
    let onToggleAI:    () -> Void
    let isAITabActive: Bool

    var body: some View {
        HStack(spacing: 0) {
            // Scrollable tabs + add button
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(manager.sessions) { session in
                        TabItemView(
                            session: session,
                            isActive: manager.activeSessionID == session.id,
                            onSelect: { manager.activate(session) },
                            onClose:  { manager.closeSession(session) }
                        )
                    }

                    // Add tab button
                    Button {
                        onAddTab()
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.mosaicTextSec)
                            .frame(width: 44, height: tabBarHeight)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.leading, 4)
                }
                .padding(.horizontal, 8)
            }

            // AI button — pinned between scroll area and separator
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                onToggleAI()
            } label: {
                HStack(spacing: 3) {
                    Text("✦")
                        .font(.system(size: 11, weight: .semibold))
                    Text("AI")
                        .font(.custom("JetBrains Mono", size: 9).weight(.bold))
                }
                .foregroundColor(isAITabActive ? .mosaicAccent : .mosaicTextSec)
                .frame(width: 48, height: tabBarHeight)
                .contentShape(Rectangle())
                .overlay(
                    Rectangle()
                        .fill(isAITabActive ? Color.mosaicAccent : .clear)
                        .frame(height: 2),
                    alignment: .bottom
                )
            }
            .buttonStyle(.plain)

            // Gear — pinned at trailing edge, outside the scroll view
            Rectangle()
                .fill(Color.mosaicBorder)
                .frame(width: 0.5, height: 20)

            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                onSettings()
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(.mosaicTextSec)
                    .frame(width: 44, height: tabBarHeight)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .frame(height: tabBarHeight)
        .background(Color.mosaicSurface1)
        .overlay(
            Rectangle()
                .fill(Color.mosaicBorder)
                .frame(height: 0.5),
            alignment: .bottom
        )
    }
}

private let tabBarHeight: CGFloat = 44

// MARK: - TabItemView

@MainActor
struct TabItemView: View {
    @ObservedObject var session: Session
    let isActive: Bool
    let onSelect: () -> Void
    let onClose: () -> Void

    private var connInfo: ConnectionInfo { session.connection.connectionInfo }
    private var connState: ConnectionState { session.connectionState }

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 6) {
                // Status dot
                StatusDot(state: connState)

                // Server name
                Text(connInfo.hostname)
                    .font(.custom("JetBrains Mono", size: 10.5))
                    .foregroundColor(isActive ? .mosaicTextPri : .mosaicTextSec)
                    .lineLimit(1)

                // Protocol badge
                ProtocolBadge(transport: connInfo.transport, isRoaming: connState == .roaming)

                // Close button (only on active tab)
                if isActive {
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundColor(.mosaicTextSec)
                            .frame(width: 16, height: 16)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .frame(height: tabBarHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(
            // Active underline
            Rectangle()
                .fill(isActive ? Color.mosaicAccent : .clear)
                .frame(height: 2),
            alignment: .bottom
        )
    }
}

// MARK: - StatusDot

struct StatusDot: View {
    let state: ConnectionState

    private var color: Color {
        switch state {
        case .connected:    return .mosaicGreen
        case .roaming:      return .mosaicYellow
        case .connecting:   return .mosaicAccent
        case .disconnected: return .mosaicTextMut
        case .error:        return .mosaicRed
        }
    }

    @State private var pulsing = false

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 6, height: 6)
            .scaleEffect(pulsing ? 1.3 : 1.0)
            .opacity(pulsing ? 0.6 : 1.0)
            .onAppear { setPulsing(state == .connected) }
            .onChange(of: state) { setPulsing(state == .connected) }
    }

    private func setPulsing(_ shouldPulse: Bool) {
        if shouldPulse {
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                pulsing = true
            }
        } else {
            // Use an explicit easing (not .default spring) to reliably cancel the repeatForever
            withAnimation(.easeInOut(duration: 0.2)) { pulsing = false }
        }
    }
}

// MARK: - ProtocolBadge

struct ProtocolBadge: View {
    let transport: TransportProtocol
    let isRoaming: Bool

    private var label: String {
        isRoaming ? "↻ ROAMING" : transport.rawValue
    }

    private var color: Color {
        isRoaming ? .mosaicYellow : (transport == .mosh ? .mosaicPurple : .mosaicBlue)
    }

    var body: some View {
        Text(label)
            .font(.custom("JetBrains Mono", size: 7.5).weight(.bold))
            .kerning(0.3)
            .foregroundColor(color)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(color.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 3))
    }
}
