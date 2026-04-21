import SwiftUI

// MARK: - EmptyStateView
//
// Shown when no sessions are open yet.

struct EmptyStateView: View {
    let onConnect: () -> Void

    var body: some View {
        ZStack {
            Color.mosaicBg.ignoresSafeArea()

            VStack(spacing: 24) {
                VStack(spacing: 8) {
                    Text("mosaic")
                        .font(.custom("JetBrains Mono", size: 28).weight(.bold))
                        .foregroundColor(.mosaicTextPri)
                    Text("native terminal runtime")
                        .font(.custom("JetBrains Mono", size: 11))
                        .foregroundColor(.mosaicTextSec)
                }

                Button {
                    onConnect()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "plus")
                        Text("Connect to a server")
                            .font(.custom("JetBrains Mono", size: 12).weight(.semibold))
                    }
                    .foregroundColor(.black)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(Color.mosaicAccent)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
            }
        }
    }
}
