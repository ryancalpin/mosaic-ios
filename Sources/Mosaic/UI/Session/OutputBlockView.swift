// Sources/Mosaic/UI/Session/OutputBlockView.swift
import SwiftUI

// MARK: - OutputBlockView

@MainActor
struct OutputBlockView: View {
    @ObservedObject var block: OutputBlock

    @Environment(\.terminalFontSize)    private var fontSize
    @Environment(\.outputDensity)       private var density
    @Environment(\.showNativeRenderers) private var showNativeRenderers
    @Environment(\.showTimestamps)      private var showTimestamps

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Command line
            HStack(spacing: 6) {
                Text("›")
                    .font(.custom("JetBrains Mono", size: fontSize - 1).weight(.bold))
                    .foregroundColor(.mosaicAccent)
                Text(block.displayCommand)
                    .font(.custom("JetBrains Mono", size: fontSize - 1))
                    .foregroundColor(.mosaicTextPri)
                Spacer()
                if showTimestamps && !block.isStreaming {
                    Text(block.timestamp, style: .time)
                        .font(.custom("JetBrains Mono", size: max(8, fontSize - 4)))
                        .foregroundColor(.mosaicTextSec)
                }
                if block.isStreaming {
                    ProgressView()
                        .scaleEffect(0.6)
                        .tint(.mosaicAccent)
                }
            }

            // Output
            if block.isStreaming && block.rawOutput.isEmpty {
                EmptyView()
            } else if showNativeRenderers,
                      block.isNativelyRendered,
                      let label = block.rendererBadgeLabel,
                      let result = block.cachedRendererResult {
                NativeOutputView(label: label, result: result, rawOutput: block.rawOutput, fontSize: fontSize)
            } else {
                rawText(block.rawOutput)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, density.verticalPadding)
    }

    private func rawText(_ output: String) -> some View {
        Text(output)
            .font(.custom("JetBrains Mono", size: fontSize))
            .foregroundColor(.mosaicTextPri)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - NativeOutputView

@MainActor
private struct NativeOutputView: View {
    let label: String
    let result: RendererResult
    let rawOutput: String
    let fontSize: Double

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
            .font(.custom("JetBrains Mono", size: fontSize))
            .foregroundColor(.mosaicTextPri)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var nativeView: some View {
        if case .native(let renderer, let data, _) = result {
            renderer.view(for: data)
        } else {
            rawView
        }
    }
}
