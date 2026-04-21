import SwiftUI

// MARK: - OutputBlockView

struct OutputBlockView: View {
    @ObservedObject var block: OutputBlock

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Command line
            HStack(spacing: 6) {
                Text("›")
                    .font(.custom("JetBrains Mono", size: 12).weight(.bold))
                    .foregroundColor(.mosaicAccent)
                Text(block.displayCommand)
                    .font(.custom("JetBrains Mono", size: 12))
                    .foregroundColor(.mosaicTextPri)
                Spacer()
                if block.isStreaming {
                    ProgressView()
                        .scaleEffect(0.6)
                        .tint(.mosaicAccent)
                }
            }

            // Output
            if block.isStreaming && block.rawOutput.isEmpty {
                EmptyView()
            } else if block.isNativelyRendered,
                      let label = block.rendererBadgeLabel,
                      let result = block.cachedRendererResult {
                NativeOutputView(label: label, result: result, rawOutput: block.rawOutput)
            } else {
                rawText(block.rawOutput)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func rawText(_ output: String) -> some View {
        Text(output)
            .font(.custom("JetBrains Mono", size: 11))
            .foregroundColor(.mosaicTextPri)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - NativeOutputView

private struct NativeOutputView: View {
    let label: String
    let result: RendererResult
    let rawOutput: String

    @State private var showingRaw = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            NativeBadge(label: label, showingRaw: $showingRaw)

            if showingRaw {
                rawView.transition(.opacity)
            } else {
                nativeView.transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.18), value: showingRaw)
    }

    private var rawView: some View {
        Text(rawOutput)
            .font(.custom("JetBrains Mono", size: 11))
            .foregroundColor(.mosaicTextPri)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var nativeView: some View {
        // Use the pre-computed result — no re-parsing on render
        if case .native(let renderer, let data, _) = result {
            renderer.view(for: data)
        } else {
            rawView
        }
    }
}
