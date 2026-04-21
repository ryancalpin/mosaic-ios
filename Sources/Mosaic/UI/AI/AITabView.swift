import SwiftUI

// MARK: - AITabView

@MainActor
struct AITabView: View {
    @ObservedObject var aiSession:  AISession
    let manualSession: Session
    @Environment(AppSettings.self) private var settings

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            messageList
            Divider().background(Color.mosaicBorder)
            inputBar
        }
        .background(Color.mosaicBg)
        .task { await aiSession.connect() }
    }

    private var headerBar: some View {
        HStack {
            Text("✦ AI")
                .font(.custom("JetBrains Mono", size: 13).weight(.bold))
                .foregroundStyle(Color.mosaicAccent)
            Spacer()
            StatusDot(state: aiSession.connectionState)
            Text(manualSession.connection.connectionInfo.hostname)
                .font(.custom("JetBrains Mono", size: 10))
                .foregroundStyle(Color.mosaicTextSec)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color.mosaicSurface1)
        .overlay(Rectangle().fill(Color.mosaicBorder).frame(height: 0.5), alignment: .bottom)
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if aiSession.messages.isEmpty {
                        AIEmptyState()
                    }
                    ForEach(aiSession.messages) { msg in
                        AIMessageView(message: msg)
                            .id(msg.id)
                    }
                    if aiSession.isThinking {
                        ThinkingIndicator()
                    }
                    if let cmd = aiSession.pendingCommand {
                        ApprovalCardView(
                            command: cmd,
                            tier:    aiSession.pendingTier,
                            onConfirm: {
                                Task { await aiSession.executeApproved(cmd) }
                            },
                            onCancel: {
                                aiSession.pendingCommand = nil
                            }
                        )
                        .padding(.horizontal, 14)
                        .id("approval")
                    }
                    Color.clear.frame(height: 8).id("bottom")
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
            .onChange(of: aiSession.messages.count) {
                withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
            }
            .onChange(of: aiSession.pendingCommand) {
                withAnimation { proxy.scrollTo("approval", anchor: .bottom) }
            }
        }
    }

    private var inputBar: some View {
        HStack(spacing: 10) {
            TextField("", text: $aiSession.inputText,
                prompt: Text("ask anything…")
                    .font(.custom("JetBrains Mono", size: 13))
                    .foregroundStyle(Color.mosaicTextSec.opacity(0.5))
            )
            .font(.custom("JetBrains Mono", size: 13))
            .foregroundStyle(Color.mosaicTextPri)
            .tint(.mosaicAccent)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .onSubmit { sendMessage() }

            Button { sendMessage() } label: {
                Image(systemName: "arrow.up")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(aiSession.inputText.isEmpty ? Color.mosaicTextMut : .black)
                    .frame(width: 44, height: 44)
                    .background(
                        Circle()
                            .fill(aiSession.inputText.isEmpty ? Color.mosaicSurface2 : Color.mosaicAccent)
                            .frame(width: 30, height: 30)
                    )
            }
            .buttonStyle(.plain)
            .disabled(aiSession.inputText.isEmpty)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.mosaicSurface1)
    }

    private func sendMessage() {
        let input = aiSession.inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { return }
        aiSession.inputText = ""
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        Task { await aiSession.submit(userInput: input, from: manualSession) }
    }
}

// MARK: - AIMessageView

struct AIMessageView: View {
    let message: AIMessage

    var body: some View {
        switch message.role {
        case .user:
            HStack {
                Spacer()
                Text(message.text)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.mosaicTextPri)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.mosaicAccent.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }

        case .thinking:
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .foregroundStyle(Color.mosaicAccent)
                    .font(.system(size: 10))
                Text(message.text)
                    .font(.custom("JetBrains Mono", size: 10))
                    .foregroundStyle(Color.mosaicTextSec)
                    .italic()
            }

        case .result:
            VStack(alignment: .leading, spacing: 6) {
                if let result = message.rendererResult,
                   case .native(let renderer, let data, _) = result {
                    NativeBadge(label: renderer.badgeLabel, showingRaw: .constant(false))
                    renderer.view(for: data)
                } else {
                    Text(message.text)
                        .font(.custom("JetBrains Mono", size: 12))
                        .foregroundStyle(Color.mosaicTextPri)
                        .textSelection(.enabled)
                }
            }

        case .error:
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(Color.mosaicRed)
                Text(message.text)
                    .font(.custom("JetBrains Mono", size: 11))
                    .foregroundStyle(Color.mosaicRed)
            }
        }
    }
}

// MARK: - ThinkingIndicator

struct ThinkingIndicator: View {
    @State private var dots = ""
    @State private var timer: Timer? = nil

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "sparkles")
                .foregroundStyle(Color.mosaicAccent)
                .font(.system(size: 10))
            Text("Thinking\(dots)")
                .font(.custom("JetBrains Mono", size: 10))
                .foregroundStyle(Color.mosaicTextSec)
                .italic()
        }
        .onAppear {
            timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
                DispatchQueue.main.async {
                    dots = dots.count < 3 ? dots + "." : ""
                }
            }
        }
        .onDisappear {
            timer?.invalidate()
            timer = nil
        }
    }
}

// MARK: - AIEmptyState

struct AIEmptyState: View {
    var body: some View {
        VStack(spacing: 16) {
            Text("✦")
                .font(.system(size: 40))
                .foregroundStyle(Color.mosaicAccent)
            Text("Ask me anything")
                .font(.custom("JetBrains Mono", size: 14))
                .foregroundStyle(Color.mosaicTextSec)
            VStack(alignment: .leading, spacing: 8) {
                ForEach(["show me disk usage",
                         "which containers are running?",
                         "tail the app log"], id: \.self) { example in
                    Text("› \(example)")
                        .font(.custom("JetBrains Mono", size: 11))
                        .foregroundStyle(Color.mosaicTextMut)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }
}
