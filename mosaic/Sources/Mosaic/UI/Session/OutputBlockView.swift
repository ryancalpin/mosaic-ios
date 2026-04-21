import SwiftUI

// MARK: - OutputBlockView
//
// Renders one OutputBlock — one command + its output.
// If the block has a native renderer, shows NativeBadge + renderer view.
// Tap badge toggles to raw and back.

struct OutputBlockView: View {
    var block: OutputBlock
    let registry = RendererRegistry.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Command prompt line
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
                // Nothing yet
            } else if block.isNativelyRendered, let label = block.rendererBadgeLabel {
                NativeOutputView(block: block, label: label, registry: registry)
            } else {
                rawTextView
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: - Subviews

    private var rawTextView: some View {
        Text(block.rawOutput.strippingANSI)
            .font(.custom("JetBrains Mono", size: 11))
            .foregroundColor(.mosaicTextPri)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - NativeOutputView (separate view to own showingRaw state)

private struct NativeOutputView: View {
    let block: OutputBlock
    let label: String
    let registry: RendererRegistry

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
        Text(block.rawOutput.strippingANSI)
            .font(.custom("JetBrains Mono", size: 11))
            .foregroundColor(.mosaicTextPri)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var nativeView: some View {
        let result = registry.process(
            command: block.command,
            output:  block.rawOutput.strippingANSI
        )
        if case .native(let r, let data, _) = result {
            r.view(for: data)
        } else {
            rawView
        }
    }
}
