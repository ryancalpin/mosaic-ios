import SwiftUI
import SwiftData

@MainActor
struct SmartInputBar: View {
    @Binding var text: String
    let hostname: String
    let onSend: (String) -> Void
    let onNeedsApproval: (String, SafetyTier) -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(\.terminalFontSize) private var fontSize

    @StateObject private var completionProvider = CompletionProvider(matcher: nil)
    @State private var historyMatcher: HistoryMatcher? = nil
    @State private var ccEnabled: Bool = true
    @State private var ghostSuffix: String? = nil

    var body: some View {
        VStack(spacing: 0) {
            if !completionProvider.items.isEmpty {
                CompletionDropdownView(items: completionProvider.items) { selected in
                    text = selected
                    completionProvider.update(for: selected)
                    ghostSuffix = nil
                }
                .padding(.bottom, 4)
                .animation(.easeInOut(duration: 0.15), value: completionProvider.items.isEmpty)
            }

            Divider().background(Color.mosaicBorder)

            HStack(spacing: 10) {
                Button {
                    ccEnabled.toggle()
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: ccEnabled ? "checkmark.circle.fill" : "checkmark.circle").font(.system(size: 10))
                        Text("CC").font(.custom("JetBrains Mono", size: 8).weight(.bold)).kerning(0.4)
                    }
                    .foregroundColor(ccEnabled ? .mosaicAccent : .mosaicTextSec)
                    .padding(.horizontal, 7).padding(.vertical, 4)
                    .background(ccEnabled ? Color.mosaicAccent.opacity(0.12) : Color.mosaicSurface2)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(ccEnabled ? Color.mosaicAccent.opacity(0.4) : Color.mosaicBorder, lineWidth: 0.5))
                    .frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .animation(.easeInOut(duration: 0.15), value: ccEnabled)

                GhostTextField(
                    text: $text,
                    placeholder: "command",
                    fontSize: fontSize,
                    ghostSuffix: ccEnabled ? ghostSuffix : nil,
                    onAcceptGhost: {
                        if let suffix = ghostSuffix, ccEnabled {
                            text += suffix; ghostSuffix = nil; completionProvider.update(for: text)
                        }
                    },
                    onSubmit: { submit() }
                )

                Button { } label: {
                    Image(systemName: "mic").font(.system(size: 15)).foregroundColor(.mosaicTextSec).frame(width: 44, height: 44).contentShape(Rectangle())
                }.buttonStyle(.plain)

                Button { submit() } label: {
                    Image(systemName: "arrow.up").font(.system(size: 13, weight: .semibold))
                        .foregroundColor(text.isEmpty ? .mosaicTextMut : .black)
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(text.isEmpty ? Color.mosaicSurface2 : Color.mosaicGreen).frame(width: 30, height: 30))
                }
                .buttonStyle(.plain).disabled(text.isEmpty).animation(.easeInOut(duration: 0.15), value: text.isEmpty)
            }
            .padding(.horizontal, 12).padding(.vertical, 10).background(Color.mosaicSurface1)
        }
        .background(Color.mosaicSurface1)
        .onAppear {
            let matcher = HistoryMatcher(context: modelContext)
            historyMatcher = matcher
            completionProvider.setup(matcher: matcher)
        }
        .onChange(of: text) { _, newValue in
            guard ccEnabled else { return }
            ghostSuffix = historyMatcher?.ghostSuffix(for: newValue)
            completionProvider.update(for: newValue)
            guard newValue.hasSuffix(" ") else { return }
            if let corrected = TypoCorrector.shared.correct(newValue), corrected != newValue {
                text = corrected
            }
        }
    }

    private func submit() {
        let cmd = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cmd.isEmpty else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        historyMatcher?.save(command: cmd, hostname: hostname)
        text = ""
        ghostSuffix = nil
        completionProvider.items = []
        let tier = SafetyClassifier.shared.classify(cmd)
        switch tier {
        case .safe: onSend(cmd)
        case .tier1, .tier2, .tier3: onNeedsApproval(cmd, tier)
        }
    }
}
