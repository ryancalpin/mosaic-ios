import SwiftUI

// MARK: - BreadcrumbBar
//
// Thin bar between the tab strip and session content.
// Shows: user@hostname (muted) › ~/current/path (accent)  branch ↑N

struct BreadcrumbBar: View {
    let username:   String
    let hostname:   String
    let directory:  String
    let branch:     String?
    let ahead:      Int
    var isTUIMode:  Bool = false

    var body: some View {
        HStack(spacing: 4) {
            // user@host
            Text("\(username)@\(hostname)")
                .foregroundColor(.mosaicTextSec)

            Text("›")
                .foregroundColor(.mosaicTextMut)

            // path
            Text(directory)
                .foregroundColor(.mosaicAccent)

            if let branch {
                Spacer()
                    .frame(width: 6)

                Image(systemName: "arrow.branch")
                    .font(.system(size: 8))
                    .foregroundColor(.mosaicTextSec)

                Text(branch)
                    .foregroundColor(.mosaicTextSec)

                if ahead > 0 {
                    Text("↑\(ahead)")
                        .foregroundColor(.mosaicGreen)
                }
            }

            Spacer()

            if isTUIMode {
                Text("TUI")
                    .font(.custom("JetBrains Mono", size: 8).weight(.bold))
                    .kerning(0.4)
                    .foregroundColor(.mosaicYellow)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Color.mosaicYellow.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 3))
            }
        }
        .font(.custom("JetBrains Mono", size: 12))
        .lineLimit(1)
        .padding(.horizontal, 14)
        .frame(height: 28)
        .background(Color.mosaicSurface1)
        .overlay(
            Rectangle()
                .fill(Color.mosaicBorder)
                .frame(height: 0.5),
            alignment: .bottom
        )
    }
}
