import SwiftUI

struct CompletionItem: Identifiable, Equatable {
    enum Kind: String { case history, command, snippet }
    let id = UUID()
    let text: String
    let kind: Kind
}

struct CompletionDropdownView: View {
    let items: [CompletionItem]
    let onSelect: (String) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(items.prefix(5).enumerated()), id: \.element.id) { index, item in
                CompletionRow(item: item)
                    .onTapGesture {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        onSelect(item.text)
                    }
                if index < min(4, items.count - 1) {
                    Divider().background(Color.mosaicBorder).padding(.leading, 36)
                }
            }
        }
        .background(Color.mosaicSurface2)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.mosaicBorder, lineWidth: 0.5))
        .shadow(color: .black.opacity(0.4), radius: 12, x: 0, y: -4)
        .padding(.horizontal, 12)
        .transition(.opacity.combined(with: .move(edge: .bottom)))
    }
}

private struct CompletionRow: View {
    let item: CompletionItem
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: item.kind == .history ? "clock" : item.kind == .command ? "terminal" : "doc.text")
                .font(.system(size: 12)).foregroundColor(item.kind == .history ? .mosaicTextSec : item.kind == .command ? .mosaicAccent : .mosaicBlue)
                .frame(width: 16, height: 16)
            Text(item.text).font(.custom("JetBrains Mono", size: 13)).foregroundColor(.mosaicTextPri).lineLimit(1).truncationMode(.tail)
            Spacer()
        }
        .padding(.horizontal, 12).frame(minHeight: 44).contentShape(Rectangle())
    }
}
