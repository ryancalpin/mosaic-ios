import SwiftUI

// MARK: - SmartInputBar
//
// Bottom input bar for the session view.
// Phase 1: basic command input + send button + UI-only CodeCorrect pill + mic placeholder.

@MainActor
struct SmartInputBar: View {
    @Binding var text: String
    let onSend: (String) -> Void
    let onNeedsApproval: (String, SafetyTier) -> Void

    @FocusState private var isFocused: Bool
    @Environment(\.terminalFontSize) private var fontSize

    var body: some View {
        VStack(spacing: 0) {
            Divider().background(Color.mosaicBorder)

            HStack(spacing: 10) {
                // Code-correct pill (Phase 1: UI only)
                Button {
                    // Phase 2: toggle CodeCorrect
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle")
                            .font(.system(size: 10))
                        Text("CC")
                            .font(.custom("JetBrains Mono", size: 8).weight(.bold))
                            .kerning(0.4)
                    }
                    .foregroundColor(.mosaicTextSec)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(Color.mosaicSurface2)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.mosaicBorder, lineWidth: 0.5))
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                // Text field
                TextField("", text: $text, prompt:
                    Text("command")
                        .font(.custom("JetBrains Mono", size: fontSize))
                        .foregroundColor(Color.mosaicTextSec.opacity(0.5))
                )
                .font(.custom("JetBrains Mono", size: fontSize))
                .foregroundColor(.mosaicTextPri)
                .tint(.mosaicAccent)
                .focused($isFocused)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .onSubmit { submit() }

                // Mic (Phase 1: placeholder)
                Button {
                    // Phase 2: voice input
                } label: {
                    Image(systemName: "mic")
                        .font(.system(size: 15))
                        .foregroundColor(.mosaicTextSec)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                // Send button
                Button { submit() } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(text.isEmpty ? .mosaicTextMut : .black)
                        .frame(width: 44, height: 44)
                        .background(
                            Circle()
                                .fill(text.isEmpty ? Color.mosaicSurface2 : Color.mosaicGreen)
                                .frame(width: 30, height: 30)
                        )
                }
                .buttonStyle(.plain)
                .disabled(text.isEmpty)
                .animation(.easeInOut(duration: 0.15), value: text.isEmpty)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color.mosaicSurface1)
        }
    }

    private func submit() {
        let cmd = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cmd.isEmpty else { return }

        UIImpactFeedbackGenerator(style: .light).impactOccurred()

        let tier = SafetyClassifier.shared.classify(cmd)
        switch tier {
        case .safe:
            onSend(cmd)
        case .tier3:
            onNeedsApproval(cmd, tier)
        case .tier1, .tier2:
            onNeedsApproval(cmd, tier)
        }
        isFocused = true
    }
}
