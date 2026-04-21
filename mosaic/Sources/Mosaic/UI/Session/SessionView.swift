import SwiftUI

// MARK: - SessionView
//
// Layout: BreadcrumbBar → [ScrollView of OutputBlocks | TerminalView] → SmartInputBar
//
// TerminalViewBridge is always present in the hierarchy (zero-size overlay).
// It processes all SSH bytes through SwiftTerm's VT100 engine regardless
// of whether we're showing native or raw output — per spec "Never bypass SwiftTerm."

struct SessionView: View {
    @ObservedObject var session: Session
    @State private var approvalCommand: String? = nil
    @State private var approvalTier: SafetyTier = .safe
    @State private var showApproval = false

    private var connInfo: ConnectionInfo { session.connection.connectionInfo }

    var body: some View {
        VStack(spacing: 0) {
            // Breadcrumb
            BreadcrumbBar(
                username:  connInfo.username,
                hostname:  connInfo.hostname,
                directory: session.currentDirectory,
                branch:    session.currentBranch,
                ahead:     session.aheadCount
            )

            // Main content area
            ZStack(alignment: .topLeading) {
                // SwiftTerm — always processing, zero-size when not shown directly.
                // In Phase 1 it runs as the VT100 back-end.
                // Phase 2+: show it full-screen when no renderer matches.
                TerminalViewBridge(session: session)
                    .frame(width: 0, height: 0)
                    .opacity(0)

                // Output blocks scroll
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(session.blocks) { block in
                                OutputBlockView(block: block)
                                    .id(block.id)
                                Divider()
                                    .background(Color.mosaicBorder.opacity(0.4))
                            }

                            if showApproval, let cmd = approvalCommand {
                                ApprovalCardView(
                                    command: cmd,
                                    tier: approvalTier,
                                    onConfirm: {
                                        showApproval = false
                                        Task { await session.send(cmd) }
                                    },
                                    onCancel: {
                                        showApproval = false
                                        approvalCommand = nil
                                    }
                                )
                                .padding(14)
                                .id("approval")
                            }

                            Color.clear.frame(height: 8).id("bottom")
                        }
                    }
                    .onChange(of: session.blocks.count) { _ in
                        withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
                    }
                    .onChange(of: showApproval) { shown in
                        if shown {
                            withAnimation { proxy.scrollTo("approval", anchor: .bottom) }
                        }
                    }
                }
                .background(Color.mosaicBg)
            }

            // Smart input bar
            SmartInputBar(
                text: $session.pendingCommand,
                onSend: { cmd in
                    Task { await session.send(cmd) }
                },
                onNeedsApproval: { cmd, tier in
                    approvalCommand = cmd
                    approvalTier    = tier
                    showApproval    = true
                }
            )
        }
        .background(Color.mosaicBg)
    }
}
