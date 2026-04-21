import SwiftUI

public struct HttpHeader: Sendable {
    public let key: String
    public let value: String
}

@MainActor
public final class HttpResponseRenderer: OutputRenderer {
    public let id          = "network.http"
    public let displayName = "HTTP Response"
    public let badgeLabel  = "HTTP"
    public let priority    = RendererPriority.network
    private static let statusLineRegex = try? NSRegularExpression(pattern: #"^(HTTP/[\d.]+)\s+(\d{3})\s*(.*)"#)

    public func canRender(command: String, output: String) -> Bool {
        let cmd = command.lowercased()
        return (cmd.contains("curl") && (cmd.contains(" -i") || cmd.contains(" -si") || cmd.contains("--head") || cmd.contains("--include"))) || output.hasPrefix("HTTP/")
    }

    public func parse(command: String, output: String) -> (any RendererData)? {
        let lines = output.components(separatedBy: "\n")
        guard let statusLine = lines.first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) else { return nil }
        let ns = statusLine as NSString
        guard let m = Self.statusLineRegex?.firstMatch(in: statusLine, range: NSRange(location: 0, length: ns.length)),
              m.numberOfRanges >= 3,
              let versionRange = Range(m.range(at: 1), in: statusLine),
              let codeRange    = Range(m.range(at: 2), in: statusLine),
              let statusCode   = Int(statusLine[codeRange]) else { return nil }
        let version    = String(statusLine[versionRange])
        let statusText = (m.numberOfRanges >= 4 ? Range(m.range(at: 3), in: statusLine) : nil).map { String(statusLine[$0]).trimmingCharacters(in: .whitespaces) } ?? ""
        var headers: [HttpHeader] = []
        var seenStatus = false
        for line in lines {
            if !seenStatus {
                if line.trimmingCharacters(in: .whitespaces) == statusLine.trimmingCharacters(in: .whitespaces) { seenStatus = true }
                continue
            }
            let t = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if t.isEmpty { break }
            if let r = t.range(of: ": ") {
                headers.append(HttpHeader(key: String(t[t.startIndex..<r.lowerBound]), value: String(t[r.upperBound...])))
            }
        }
        return HttpResponseData(version: version, statusCode: statusCode, statusText: statusText, headers: Array(headers.prefix(20)))
    }

    public func view(for data: any RendererData) -> AnyView {
        guard let data = data as? HttpResponseData else { return AnyView(EmptyView()) }
        return AnyView(HttpResponseView(data: data))
    }
}

public struct HttpResponseData: RendererData, Sendable {
    public let version: String
    public let statusCode: Int
    public let statusText: String
    public let headers: [HttpHeader]
}

private struct HttpResponseView: View {
    let data: HttpResponseData
    private var statusColor: Color { data.statusCode < 300 ? Color(hex: "#3DFF8F") : data.statusCode < 400 ? Color(hex: "#FFD060") : Color(hex: "#FF4D6A") }
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text("\(data.statusCode)").font(.custom("JetBrains Mono", size: 28).weight(.bold)).foregroundColor(statusColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text(data.statusText).font(.custom("JetBrains Mono", size: 11.5).weight(.semibold)).foregroundColor(Color(hex: "#D8E4F0"))
                    Text(data.version).font(.custom("JetBrains Mono", size: 9)).foregroundColor(Color(hex: "#3A4A58"))
                }
                Spacer()
            }.padding(.horizontal, 12).padding(.vertical, 12)
            Divider().overlay(Color(hex: "#141418"))
            ForEach(Array(data.headers.prefix(10).enumerated()), id: \.offset) { index, header in
                HStack(alignment: .top, spacing: 8) {
                    Text(header.key).font(.custom("JetBrains Mono", size: 10)).foregroundColor(Color(hex: "#3A4A58")).frame(minWidth: 100, alignment: .leading).lineLimit(1)
                    Text(header.value).font(.custom("JetBrains Mono", size: 10)).foregroundColor(Color(hex: "#D8E4F0")).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                }.padding(.horizontal, 12).padding(.vertical, 6)
                if index < min(9, data.headers.count - 1) { Divider().overlay(Color(hex: "#141418")) }
            }
            if data.headers.count > 10 {
                Text("+ \(data.headers.count - 10) more headers").font(.custom("JetBrains Mono", size: 9)).foregroundColor(Color(hex: "#3A4A58")).padding(.horizontal, 12).padding(.vertical, 6)
            }
        }
        .background(Color(hex: "#111115")).clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(hex: "#1E1E26"), lineWidth: 1))
    }
}
