// Sources/Mosaic/UI/Session/FirstNativeRenderBanner.swift
import SwiftUI

struct FirstNativeRenderBanner: View {
    let onDismiss: () -> Void
    @State private var visible = false

    var body: some View {
        VStack {
            Spacer()
            HStack(spacing: 12) {
                Text("✦")
                    .font(.title2)
                    .foregroundColor(.mosaicAccent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("First native render!")
                        .font(.headline)
                        .foregroundColor(.mosaicTextPri)
                    Text("Tap the badge to toggle raw output.")
                        .font(.caption)
                        .foregroundColor(.mosaicTextSec)
                }
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.mosaicTextSec)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color.mosaicSurface2)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.mosaicAccent.opacity(0.4), lineWidth: 1))
            .padding(.horizontal, 16)
            .padding(.bottom, 100)
            .opacity(visible ? 1 : 0)
            .offset(y: visible ? 0 : 24)
        }
        .onAppear {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { visible = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 6) {
                withAnimation(.easeOut(duration: 0.3)) { visible = false }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { onDismiss() }
            }
        }
    }
}
