import SwiftUI

// MARK: - ApprovalCardView
//
// Shown inline when a Tier 1 or Tier 2 command is intercepted.
// Tier 1: requires 2-second hold-to-confirm.
// Tier 2: requires single tap to confirm.

struct ApprovalCardView: View {
    let command: String
    let tier: SafetyTier
    let onConfirm: () -> Void
    let onCancel: () -> Void

    @State private var holdProgress: CGFloat = 0.0
    @State private var holdTimer: Timer? = nil
    @State private var isHolding = false

    private var isTier1: Bool {
        if case .tier1 = tier { return true }
        return false
    }

    private var reason: String {
        switch tier {
        case .tier1(let r): return r
        case .tier2(let r): return r
        default: return ""
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack(spacing: 8) {
                Image(systemName: isTier1 ? "exclamationmark.triangle.fill" : "exclamationmark.circle.fill")
                    .foregroundColor(isTier1 ? .mosaicRed : .mosaicWarn)
                Text(isTier1 ? "DESTRUCTIVE COMMAND" : "CONFIRM ACTION")
                    .font(.custom("JetBrains Mono", size: 9).weight(.bold))
                    .kerning(0.4)
                    .foregroundColor(isTier1 ? .mosaicRed : .mosaicWarn)
                Spacer()
            }

            // Command preview
            Text(command)
                .font(.custom("JetBrains Mono", size: 11))
                .foregroundColor(.mosaicTextPri)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.mosaicBg)
                .clipShape(RoundedRectangle(cornerRadius: 6))

            // Reason
            Text(reason)
                .font(.system(size: 12))
                .foregroundColor(.mosaicTextSec)

            // Buttons
            HStack(spacing: 10) {
                Button("Cancel") {
                    onCancel()
                }
                .buttonStyle(MosaicSecondaryButtonStyle())

                if isTier1 {
                    // Hold-to-confirm
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.mosaicRed.opacity(0.15))
                            .frame(height: 38)
                        GeometryReader { geo in
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.mosaicRed.opacity(0.4))
                                .frame(width: geo.size.width * holdProgress)
                                .animation(.linear(duration: 0.05), value: holdProgress)
                        }
                        .frame(height: 38)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        Text(isHolding ? "Hold to confirm…" : "Hold to confirm")
                            .font(.custom("JetBrains Mono", size: 10).weight(.bold))
                            .foregroundColor(.mosaicRed)
                            .frame(maxWidth: .infinity)
                    }
                    .frame(height: 38)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.mosaicRed.opacity(0.4), lineWidth: 1)
                    )
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { _ in startHolding() }
                            .onEnded   { _ in cancelHolding() }
                    )
                } else {
                    Button("Confirm") {
                        onConfirm()
                    }
                    .buttonStyle(MosaicDestructiveButtonStyle())
                }
            }
        }
        .padding(14)
        .background(Color.mosaicSurface2)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isTier1 ? Color.mosaicRed.opacity(0.3) : Color.mosaicWarn.opacity(0.3), lineWidth: 1)
        )
        .onDisappear { cancelHolding() }  // prevent timer leak if view is dismissed mid-hold
    }

    // MARK: - Hold Timer

    private func startHolding() {
        guard holdTimer == nil else { return }
        isHolding = true
        let start = Date()
        let t = Timer(timeInterval: 0.05, repeats: true) { @MainActor _ in
            let elapsed = Date().timeIntervalSince(start)
            holdProgress = min(CGFloat(elapsed / 2.0), 1.0)
            if holdProgress >= 1.0 {
                let confirm = onConfirm
                cancelHolding()
                confirm()
            }
        }
        // Schedule on .common so it fires even when keyboard scroll tracking is active
        RunLoop.main.add(t, forMode: .common)
        holdTimer = t
    }

    private func cancelHolding() {
        holdTimer?.invalidate()
        holdTimer = nil
        isHolding = false
        withAnimation(.easeOut(duration: 0.2)) {
            holdProgress = 0
        }
    }
}

// MARK: - Button Styles

struct MosaicSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.custom("JetBrains Mono", size: 10).weight(.bold))
            .foregroundColor(.mosaicTextSec)
            .frame(height: 38)
            .padding(.horizontal, 16)
            .background(Color.mosaicSurface1)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.mosaicBorder, lineWidth: 1))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

struct MosaicDestructiveButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.custom("JetBrains Mono", size: 10).weight(.bold))
            .foregroundColor(.white)
            .frame(maxWidth: .infinity, minHeight: 38)
            .background(Color.mosaicRed)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}
