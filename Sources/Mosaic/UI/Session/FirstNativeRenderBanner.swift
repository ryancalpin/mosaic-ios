// Sources/Mosaic/UI/Session/FirstNativeRenderBanner.swift
import SwiftUI

struct FirstNativeRenderBanner: View {
    let onDismiss: () -> Void
    @State private var visible = false
    @State private var dismissTask: Task<Void, Never>?

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
            dismissTask = Task {
                try? await Task.sleep(nanoseconds: 6_000_000_000)
                guard !Task.isCancelled else { return }
                withAnimation(.easeOut(duration: 0.3)) { visible = false }
                try? await Task.sleep(nanoseconds: 300_000_000)
                guard !Task.isCancelled else { return }
                onDismiss()
            }
        }
        .onDisappear {
            dismissTask?.cancel()
        }
    }
}
