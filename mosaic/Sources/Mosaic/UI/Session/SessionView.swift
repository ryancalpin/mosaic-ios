import SwiftUI

// MARK: - SessionView

@MainActor
struct SessionView: View {
    @ObservedObject var session: Session
    @State private var approvalCommand: String? = nil
    @State private var approvalTier: SafetyTier = .safe
    @State private var showApproval = false

    private var connInfo: ConnectionInfo { session.connection.connectionInfo }

    var body: some View {
        VStack(spacing: 0) {
            BreadcrumbBar(
                username:  connInfo.username,
                hostname:  connInfo.hostname,
                directory: session.currentDirectory,
                branch:    session.currentBranch,
                ahead:     session.aheadCount
            )

            // GeometryReader gives TerminalViewBridge real dimensions so
            // the SSH server receives correct cols/rows for vim, htop, etc.
            GeometryReader { geo in
                ZStack(alignment: .topLeading) {
                    // SwiftTerm — hidden via opacity, but full-sized so it reports
                    // correct terminal dimensions. allowsHitTesting(false) keeps it
                    // from intercepting touches meant for the scroll view.
                    TerminalViewBridge(session: session, size: geo.size)
                        .opacity(0)
                        .allowsHitTesting(false)

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
                                            approvalCommand = nil
                                            session.pendingCommand = ""
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
                        // Scroll on new block appended
                        .onChange(of: session.blocks.count) {
                            withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
                        }
                        // Scroll while output streams into the active block
                        .onChange(of: session.blocks.last?.rawOutput) {
                            proxy.scrollTo("bottom", anchor: .bottom)
                        }
                        .onChange(of: showApproval) {
                            if showApproval {
                                withAnimation { proxy.scrollTo("approval", anchor: .bottom) }
                            }
                        }
                    }
                    .background(Color.mosaicBg)
                }
            }

            SmartInputBar(
                text: $session.pendingCommand,
                onSend: { cmd in
                    session.pendingCommand = ""
                    Task {
                        do { try await session.send(cmd) }
                        catch { session.pendingCommand = cmd }  // restore on send failure so user can retry
                    }
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
