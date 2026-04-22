// Sources/Mosaic/UI/Session/TUIControlBar.swift
import SwiftUI

struct TUIControlBar: View {
    let onSendBytes: (Data) -> Void

    var body: some View {
        HStack(spacing: 0) {
            TUIKey(label: "ESC", detail: "⎋") {
                onSendBytes(Data([0x1B]))
            }

            Divider()
                .frame(height: 20)
                .overlay(Color.mosaicBorder)

            TUIKey(label: "Ctrl-C", detail: "^C") {
                onSendBytes(Data([0x03]))
            }

            Divider()
                .frame(height: 20)
                .overlay(Color.mosaicBorder)

            TUIKey(label: "Ctrl-Z", detail: "^Z") {
                onSendBytes(Data([0x1A]))
            }

            Spacer()

            Text("TUI MODE")
                .font(.custom("JetBrains Mono", size: 8).weight(.bold))
                .kerning(0.4)
                .foregroundColor(.mosaicYellow)
                .padding(.trailing, 16)
        }
        .frame(height: 44)
        .background(Color.mosaicSurface1)
        .overlay(
            Rectangle().fill(Color.mosaicBorder).frame(height: 0.5),
            alignment: .top
        )
    }
}

private struct TUIKey: View {
    let label: String
    let detail: String
    let action: () -> Void

    var body: some View {
        Button(action: {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        }) {
            VStack(spacing: 1) {
                Text(detail)
                    .font(.system(size: 14, weight: .medium, design: .monospaced))
                    .foregroundColor(.mosaicTextPri)
                Text(label)
                    .font(.system(size: 9))
                    .foregroundColor(.mosaicTextSec)
            }
            .frame(width: 64, height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
