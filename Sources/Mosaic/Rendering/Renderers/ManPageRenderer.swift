import SwiftUI

@MainActor
public final class ManPageRenderer: OutputRenderer {
    public let id          = "misc.man"
    public let displayName = "Man Page"
    public let badgeLabel  = "MAN"
    public let priority    = RendererPriority.generic + 50

    public func canRender(command: String, output: String) -> Bool {
        let cmd = command.lowercased().trimmingCharacters(in: .whitespaces)
        guard cmd.hasPrefix("man ") else { return false }
        return output.contains("NAME") && (output.contains("SYNOPSIS") || output.contains("DESCRIPTION"))
    }

    public func parse(command: String, output: String) -> (any RendererData)? {
        // Strip ANSI and backspace-based bold/underline formatting from man output
        var clean = output
        // Remove ANSI escapes
        if let rx = try? NSRegularExpression(pattern: #"\x1B\[[0-9;]*[mGKH]"#) {
            let ns = clean as NSString
            clean = rx.stringByReplacingMatches(in: clean, range: NSRange(location: 0, length: ns.length), withTemplate: "")
        }
        // Remove backspace bold: "X\bX" → "X"
        if let rx = try? NSRegularExpression(pattern: #".\x08"#) {
            let ns = clean as NSString
            clean = rx.stringByReplacingMatches(in: clean, range: NSRange(location: 0, length: ns.length), withTemplate: "")
        }

        let lines = clean.components(separatedBy: "\n")
        let command_name = command.components(separatedBy: " ").dropFirst().joined(separator: " ").trimmingCharacters(in: .whitespaces)

        // Parse into sections — section headers are lines that start at column 0 and are all-caps
        var sections: [ManSection] = []
        var currentTitle  = ""
        var currentLines: [String] = []

        let sectionHeaderRegex = try? NSRegularExpression(pattern: #"^[A-Z][A-Z\s]+$"#)

        func flush() {
            guard !currentTitle.isEmpty else { return }
            let body = currentLines
                .map { $0.trimmingCharacters(in: .init(charactersIn: " \t")) }
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !body.isEmpty {
                sections.append(ManSection(title: currentTitle, body: body))
            }
        }

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let ns = trimmed as NSString
            let isSectionHeader = !trimmed.isEmpty
                && !line.hasPrefix(" ")
                && !line.hasPrefix("\t")
                && (sectionHeaderRegex?.firstMatch(in: trimmed, range: NSRange(location: 0, length: ns.length)) != nil)

            if isSectionHeader {
                flush()
                currentTitle = trimmed
                currentLines = []
            } else {
                currentLines.append(line)
            }
        }
        flush()

        guard !sections.isEmpty else { return nil }
        return ManPageData(commandName: command_name, sections: sections)
    }

    public func view(for data: any RendererData) -> AnyView {
        guard let data = data as? ManPageData else { return AnyView(EmptyView()) }
        return AnyView(ManPageView(data: data))
    }
}

public struct ManPageData: RendererData {
    public let commandName: String
    public let sections:    [ManSection]
}

public struct ManSection: Identifiable, Sendable {
    public let id    = UUID()
    public let title: String
    public let body:  String
}

struct ManPageView: View {
    let data: ManPageData
    @State private var expandedSections = Set<UUID>()

    private let alwaysExpanded: Set<String> = ["NAME", "SYNOPSIS", "DESCRIPTION"]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: "book.fill")
                    .font(.system(size: 10))
                    .foregroundColor(Color(hex: "#FFD060"))
                Text("man \(data.commandName)")
                    .font(.custom("JetBrains Mono", size: 10).weight(.semibold))
                    .foregroundColor(Color(hex: "#D8E4F0"))
                Spacer()
                Text("MAN")
                    .font(.custom("JetBrains Mono", size: 8).weight(.bold))
                    .foregroundColor(Color(hex: "#3A4A58"))
                    .kerning(0.4)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider().overlay(Color(hex: "#1E1E26"))

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(data.sections) { section in
                        ManSectionView(
                            section:  section,
                            expanded: alwaysExpanded.contains(section.title)
                                || expandedSections.contains(section.id),
                            onToggle: {
                                if expandedSections.contains(section.id) {
                                    expandedSections.remove(section.id)
                                } else {
                                    expandedSections.insert(section.id)
                                }
                            }
                        )
                        Divider().overlay(Color(hex: "#1E1E26"))
                    }
                }
            }
            .frame(maxHeight: 500)
        }
        .background(Color(hex: "#111115"))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(hex: "#1E1E26"), lineWidth: 1))
    }
}

struct ManSectionView: View {
    let section:  ManSection
    let expanded: Bool
    let onToggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: onToggle) {
                HStack {
                    Text(section.title)
                        .font(.custom("JetBrains Mono", size: 10).weight(.bold))
                        .foregroundColor(Color(hex: "#FFD060"))
                    Spacer()
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9))
                        .foregroundColor(Color(hex: "#3A4A58"))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .buttonStyle(.plain)

            if expanded {
                Text(section.body)
                    .font(.custom("JetBrains Mono", size: 10))
                    .foregroundColor(Color(hex: "#D8E4F0"))
                    .padding(.horizontal, 16)
                    .padding(.bottom, 10)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
