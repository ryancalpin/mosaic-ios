import SwiftUI

// MARK: - SessionView

@MainActor
struct SessionView: View {
    @ObservedObject var session: Session
    @Environment(AppSettings.self) private var settings
    @State private var approvalCommand: String? = nil
    @State private var approvalTier: SafetyTier = .safe
    @State private var showApproval = false
    @State private var showFirstNativeRenderBanner = false
    @State private var showWorkflows = false

    private var connInfo: ConnectionInfo { session.connection.connectionInfo }

    var body: some View {
        VStack(spacing: 0) {
            BreadcrumbBar(
                username:  connInfo.username,
                hostname:  connInfo.hostname,
                directory: session.currentDirectory,
                branch:    session.currentBranch,
                ahead:     session.aheadCount,
                isTUIMode: session.isTUIMode
            )
            .overlay(alignment: .trailing) {
                if !session.isTUIMode {
                    Button {
                        showWorkflows = true
                    } label: {
                        Image(systemName: "list.bullet.rectangle")
                            .font(.system(size: 13, weight: .regular))
                            .foregroundColor(.mosaicTextSec)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }

            // GeometryReader gives TerminalViewBridge real dimensions so
            // the SSH server receives correct cols/rows for vim, htop, etc.
            GeometryReader { geo in
                if session.isTUIMode {
                    // TUI layout: full-screen SwiftTerm, passthrough input
                    ZStack {
                        TerminalViewBridge(session: session, size: geo.size, isTUIMode: true)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                } else {
                    // Normal layout: hidden terminal + output blocks + banner
                    ZStack(alignment: .topLeading) {
                        // SwiftTerm — hidden via opacity, but full-sized so it reports
                        // correct terminal dimensions. allowsHitTesting(false) keeps it
                        // from intercepting touches meant for the scroll view.
                        TerminalViewBridge(session: session, size: geo.size, isTUIMode: false)
                            .opacity(0)
                            .allowsHitTesting(false)

                        ScrollViewReader { proxy in
                            ScrollView {
                                VStack(alignment: .leading, spacing: 0) {
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
                            // Keyboard shortcut scroll notifications
                            .onReceive(NotificationCenter.default.publisher(for: .mosaicScrollToTop)) { _ in
                                guard let firstID = session.blocks.first?.id else { return }
                                withAnimation { proxy.scrollTo(firstID, anchor: .top) }
                            }
                            .onReceive(NotificationCenter.default.publisher(for: .mosaicScrollToBottom)) { _ in
                                withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
                            }
                        }
                        .background(Color.mosaicBg)

                        if showFirstNativeRenderBanner {
                            FirstNativeRenderBanner {
                                showFirstNativeRenderBanner = false
                                settings.hasSeenFirstNativeRender = true
                            }
                            .transition(.opacity)
                        }
                    }
                }
            }
            .animation(.easeInOut(duration: 0.2), value: session.isTUIMode)
            .onReceive(NotificationCenter.default.publisher(for: .mosaicFirstNativeRender)) { _ in
                guard !settings.hasSeenFirstNativeRender else { return }
                withAnimation { showFirstNativeRenderBanner = true }
            }

            if session.isTUIMode {
                TUIControlBar { data in
                    Task { try? await session.connection.sendData(data) }
                }
            } else {
                SmartInputBar(
                    text: $session.pendingCommand,
                    hostname: connInfo.hostname,
                    onSend: { cmd in
                        session.pendingCommand = ""
                        Task { await session.send(cmd) }
                    },
                    onNeedsApproval: { cmd, tier in
                        approvalCommand = cmd
                        approvalTier    = tier
                        showApproval    = true
                    }
                )
            }
        }
        .sheet(isPresented: $showWorkflows) {
            WorkflowListView { workflow in
                showWorkflows = false
                Task { await session.runWorkflow(workflow) }
            }
        }
        .background(Color.mosaicBg)
        .userActivity("com.mosaic.session", isActive: true) { activity in
            activity.title = "Terminal — \(connInfo.username)@\(connInfo.hostname)"
            activity.addUserInfoEntries(from: [
                "connectionID": session.connection.id.uuidString
            ])
            activity.isEligibleForHandoff = true
            activity.isEligibleForSearch  = false
        }
    }
}
