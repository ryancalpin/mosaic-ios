import SwiftUI

// MARK: - NativeBadge
//
// The tappable pill that appears above every natively-rendered block.
// Tap to toggle between native view and raw terminal text.

struct NativeBadge: View {
    let label: String        // e.g. "CONTAINERS", "GIT STATUS"
    @Binding var showingRaw: Bool

    private var badgeText: String {
        showingRaw
            ? "← RAW OUTPUT · tap for native"
            : "NATIVE · \(label) · tap for raw"
    }

    private var badgeColor: Color {
        showingRaw ? .mosaicTextSec : .mosaicAccent
    }

    var body: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.18)) {
                showingRaw.toggle()
            }
        } label: {
            Text(badgeText)
                .font(.custom("JetBrains Mono", size: 8).weight(.bold))
                .kerning(0.4)
                .foregroundColor(badgeColor)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(badgeColor.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(badgeColor.opacity(0.25), lineWidth: 0.5)
                )
                .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.18), value: showingRaw)
    }
}
