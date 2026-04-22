import SwiftUI

@MainActor
public final class SqlTableRenderer: OutputRenderer {
    public let id          = "data.sql"
    public let displayName = "SQL Result"
    public let badgeLabel  = "SQL"
    public let priority    = RendererPriority.data

    public func canRender(command: String, output: String) -> Bool {
        let cmd = command.lowercased()
        // psql, mysql, sqlite3
        let isSQL = cmd.hasPrefix("psql") || cmd.hasPrefix("mysql") || cmd.hasPrefix("sqlite3")
            || cmd.contains("select ") || cmd.contains("SELECT ")
        // Output uses +-----+ borders (psql/mysql), spaced pipes " | ", or bare pipes (sqlite3)
        let looksTabular = output.contains("+--")
            || (output.contains("|") && output.contains(" | "))
            || (output.contains("|") && isSQL)  // sqlite3 bare-pipe mode
        return isSQL && looksTabular
    }

    public func parse(command: String, output: String) -> (any RendererData)? {
        let lines = output.components(separatedBy: "\n")

        // Find header separator line (+-----+-----+) or (|col|col|)
        let sepLine = lines.first { $0.hasPrefix("+") && $0.hasSuffix("+") }
        let headerLine: String?
        if let sep = sepLine, let idx = lines.firstIndex(of: sep), idx + 1 < lines.count {
            headerLine = lines[idx + 1]
        } else {
            headerLine = lines.first { $0.contains("|") && !$0.hasPrefix("+") }
        }

        guard let hLine = headerLine else { return nil }

        let columns = hLine.components(separatedBy: "|")
            .filter { !$0.isEmpty }
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        guard !columns.isEmpty else { return nil }

        var rows: [[String]] = []
        var pastHeader = false
        var headerCount = 0

        for line in lines {
            if line.hasPrefix("+") { headerCount += 1; if headerCount >= 2 { pastHeader = true }; continue }
            if !pastHeader { continue }
            if !line.contains("|") { continue }
            let cells = line.components(separatedBy: "|")
                .filter { !$0.isEmpty }
                .map { $0.trimmingCharacters(in: .whitespaces) }
            if cells.count == columns.count {
                rows.append(cells)
            }
        }

        // Fallback for output without +---+ borders (sqlite3 pipe mode)
        if rows.isEmpty {
            var dataLines = lines.filter { $0.contains("|") }
            if dataLines.count > 1 {
                dataLines.removeFirst() // remove header
                for line in dataLines {
                    let cells = line.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
                    if cells.count == columns.count { rows.append(cells) }
                }
            }
        }

        guard !rows.isEmpty else { return nil }

        let rowCount = rows.count
        let footerLine = lines.last { $0.contains("row") && ($0.contains("(") || $0.isEmpty == false) }
        return SqlTableData(columns: columns, rows: rows, rowCount: rowCount, footer: footerLine)
    }

    public func view(for data: any RendererData) -> AnyView {
        guard let data = data as? SqlTableData else { return AnyView(EmptyView()) }
        return AnyView(SqlTableView(data: data))
    }
}

public struct SqlTableData: RendererData {
    public let columns:  [String]
    public let rows:     [[String]]
    public let rowCount: Int
    public let footer:   String?
}

struct SqlTableView: View {
    let data: SqlTableData

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("SQL RESULT")
                    .font(.custom("JetBrains Mono", size: 8).weight(.bold))
                    .foregroundColor(Color(hex: "#3A4A58"))
                    .kerning(0.4)
                Spacer()
                Text("\(data.rowCount) row\(data.rowCount == 1 ? "" : "s")")
                    .font(.custom("JetBrains Mono", size: 9))
                    .foregroundColor(Color(hex: "#3A4A58"))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider().overlay(Color(hex: "#1E1E26"))

            ScrollView(.horizontal, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    // Header row
                    HStack(spacing: 0) {
                        ForEach(Array(data.columns.enumerated()), id: \.offset) { _, col in
                            Text(col)
                                .font(.custom("JetBrains Mono", size: 9).weight(.bold))
                                .foregroundColor(Color(hex: "#4A9EFF"))
                                .frame(minWidth: 80, alignment: .leading)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                        }
                    }
                    .background(Color(hex: "#17171C"))

                    Divider().overlay(Color(hex: "#1E1E26"))

                    // Data rows
                    ForEach(Array(data.rows.enumerated()), id: \.offset) { rowIdx, row in
                        HStack(spacing: 0) {
                            ForEach(Array(row.enumerated()), id: \.offset) { colIdx, cell in
                                Text(cell.isEmpty ? "NULL" : cell)
                                    .font(.custom("JetBrains Mono", size: 9))
                                    .foregroundColor(cell.isEmpty ? Color(hex: "#3A4A58") : Color(hex: "#D8E4F0"))
                                    .frame(minWidth: 80, alignment: .leading)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                if colIdx < row.count - 1 {
                                    Divider().overlay(Color(hex: "#141418"))
                                }
                            }
                        }
                        .background(rowIdx % 2 == 0 ? Color(hex: "#111115") : Color(hex: "#13131A"))
                        if rowIdx < data.rows.count - 1 {
                            Divider().overlay(Color(hex: "#141418"))
                        }
                    }
                }
            }

            if let footer = data.footer {
                Divider().overlay(Color(hex: "#1E1E26"))
                Text(footer.trimmingCharacters(in: .whitespaces))
                    .font(.custom("JetBrains Mono", size: 9))
                    .foregroundColor(Color(hex: "#3A4A58"))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
            }
        }
        .background(Color(hex: "#111115"))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(hex: "#1E1E26"), lineWidth: 1))
    }
}
