import SwiftUI

// MARK: - SessionView
//
// The main content area for one session.
// Scrollable list of OutputBlocks + BreadcrumbBar + SmartInputBar.

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

            // Output scroll
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(session.blocks) { block in
                            OutputBlockView(block: block)
                                .id(block.id)

                            Divider()
                                .background(Color.mosaicBorder.opacity(0.4))
                        }

                        // Approval card inline at bottom
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
                    withAnimation {
                        proxy.scrollTo("bottom", anchor: .bottom)
                    }
                }
                .onChange(of: showApproval) { shown in
                    if shown {
                        withAnimation {
                            proxy.scrollTo("approval", anchor: .bottom)
                        }
                    }
                }
            }
            .background(Color.mosaicBg)

            // Smart input bar
            SmartInputBar(
                text: $session.pendingCommand,
                onSend: { cmd in
                    Task { await session.send(cmd) }
                },
                onNeedsApproval: { cmd, tier in
                    approvalCommand = cmd
                    approvalTier = tier
                    showApproval = true
                }
            )
        }
        .background(Color.mosaicBg)
    }
}
