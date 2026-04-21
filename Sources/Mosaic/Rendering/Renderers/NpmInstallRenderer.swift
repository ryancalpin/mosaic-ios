import SwiftUI

@MainActor
public final class NpmInstallRenderer: OutputRenderer {
    public let id          = "packages.install"
    public let displayName = "Package Install"
    public let badgeLabel  = "PACKAGES"
    public let priority    = RendererPriority.packages

    public func canRender(command: String, output: String) -> Bool {
        let cmd = command.lowercased()
        return cmd.hasPrefix("npm install") || cmd.hasPrefix("npm i ") || cmd == "npm i"
            || cmd.hasPrefix("pip install") || cmd.hasPrefix("pip3 install")
            || cmd.hasPrefix("apt install")  || cmd.hasPrefix("apt-get install")
    }

    public func parse(command: String, output: String) -> (any RendererData)? {
        let cmd = command.lowercased()
        let lines = output.components(separatedBy: "\n")
        let manager: String
        var packages: [PackageEntry] = []
        var summary: String? = nil
        if cmd.hasPrefix("npm") {
            manager = "npm"
            for line in lines {
                let t = line.trimmingCharacters(in: .whitespaces)
                if t.lowercased().contains("added") && t.contains("package") { summary = t }
                else if t.lowercased().hasPrefix("npm warn") { packages.append(PackageEntry(name: t.components(separatedBy: " ").dropFirst(2).joined(separator: " "), version: nil, status: .warning)) }
                else if t.lowercased().hasPrefix("npm error") || t.lowercased().hasPrefix("npm err!") { packages.append(PackageEntry(name: t.components(separatedBy: " ").dropFirst(2).joined(separator: " "), version: nil, status: .failed)) }
                else if t.hasPrefix("+ ") || t.hasPrefix("added ") {
                    let parts = t.components(separatedBy: " ").filter { !$0.isEmpty }
                    if parts.count >= 2 {
                        let nv = parts[1]
                        if let at = nv.lastIndex(of: "@"), at != nv.startIndex {
                            packages.append(PackageEntry(name: String(nv[nv.startIndex..<at]), version: String(nv[nv.index(after: at)...]), status: .installed))
                        } else { packages.append(PackageEntry(name: nv, version: nil, status: .installed)) }
                    }
                }
            }
        } else if cmd.hasPrefix("pip") {
            manager = "pip"
            for line in lines {
                let t = line.trimmingCharacters(in: .whitespaces)
                if t.hasPrefix("Collecting ") { packages.append(PackageEntry(name: String(t.dropFirst("Collecting ".count)).components(separatedBy: " ").first ?? "", version: nil, status: .installing)) }
                else if t.hasPrefix("Successfully installed ") {
                    summary = t
                    for pkg in String(t.dropFirst("Successfully installed ".count)).components(separatedBy: " ") where !pkg.isEmpty {
                        if let d = pkg.lastIndex(of: "-"), d != pkg.startIndex { packages.append(PackageEntry(name: String(pkg[pkg.startIndex..<d]), version: String(pkg[pkg.index(after: d)...]), status: .installed)) }
                        else { packages.append(PackageEntry(name: pkg, version: nil, status: .installed)) }
                    }
                } else if t.hasPrefix("ERROR:") { packages.append(PackageEntry(name: String(t.dropFirst(6)).trimmingCharacters(in: .whitespaces), version: nil, status: .failed)) }
            }
        } else {
            manager = "apt"
            for line in lines {
                let t = line.trimmingCharacters(in: .whitespaces)
                if t.hasPrefix("Get:") {
                    let parts = t.components(separatedBy: " ").filter { !$0.isEmpty }
                    if parts.count >= 4 { packages.append(PackageEntry(name: parts[3], version: parts.count > 4 ? parts[4] : nil, status: .installing)) }
                } else if t.hasPrefix("Setting up ") {
                    let clean = String(t.dropFirst("Setting up ".count)).components(separatedBy: " ").first?.components(separatedBy: "(").first ?? ""
                    packages.append(PackageEntry(name: clean, version: nil, status: .installed))
                } else if t.hasPrefix("E:") { packages.append(PackageEntry(name: String(t.dropFirst(2)).trimmingCharacters(in: .whitespaces), version: nil, status: .failed)) }
                else if t.contains("upgraded") && t.contains("installed") { summary = t }
            }
        }
        guard !packages.isEmpty || summary != nil else { return nil }
        return PackageInstallData(manager: manager, packages: packages, summary: summary)
    }

    public func view(for data: any RendererData) -> AnyView {
        guard let data = data as? PackageInstallData else { return AnyView(EmptyView()) }
        return AnyView(PackageInstallView(data: data))
    }
}

public enum PackageStatus: String, Sendable { case installing, installed, failed, warning }
public struct PackageEntry: Identifiable, Sendable { public let id = UUID(); public let name: String; public let version: String?; public let status: PackageStatus }
public struct PackageInstallData: RendererData { public let manager: String; public let packages: [PackageEntry]; public let summary: String? }

private struct PackageInstallView: View {
    let data: PackageInstallData
    private var managerColor: Color { data.manager == "npm" ? Color(hex: "#FF4D6A") : data.manager == "pip" ? Color(hex: "#4A9EFF") : Color(hex: "#FFD060") }
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text(data.manager.uppercased()).font(.custom("JetBrains Mono", size: 9).weight(.bold)).foregroundColor(managerColor).padding(.horizontal, 6).padding(.vertical, 2).background(managerColor.opacity(0.12)).clipShape(RoundedRectangle(cornerRadius: 4))
                Text("Package Install").font(.custom("JetBrains Mono", size: 11.5).weight(.semibold)).foregroundColor(Color(hex: "#D8E4F0"))
                Spacer()
                Text("\(data.packages.count) packages").font(.custom("JetBrains Mono", size: 9)).foregroundColor(Color(hex: "#3A4A58"))
            }.padding(.horizontal, 12).padding(.vertical, 9)
            Divider().overlay(Color(hex: "#141418"))
            ForEach(Array(data.packages.prefix(20).enumerated()), id: \.element.id) { index, pkg in
                HStack(spacing: 8) {
                    statusIcon(pkg.status).frame(width: 16)
                    Text(pkg.name).font(.custom("JetBrains Mono", size: 10.5)).foregroundColor(statusTextColor(pkg.status)).lineLimit(1)
                    Spacer()
                    if let ver = pkg.version { Text(ver).font(.custom("JetBrains Mono", size: 9)).foregroundColor(Color(hex: "#3A4A58")) }
                }.padding(.horizontal, 12).padding(.vertical, 6)
                if index < min(19, data.packages.count - 1) { Divider().overlay(Color(hex: "#141418")) }
            }
            if let summary = data.summary { Divider().overlay(Color(hex: "#141418")); Text(summary).font(.custom("JetBrains Mono", size: 9.5)).foregroundColor(Color(hex: "#3DFF8F")).padding(.horizontal, 12).padding(.vertical, 8).frame(maxWidth: .infinity, alignment: .leading) }
        }
        .background(Color(hex: "#111115")).clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(hex: "#1E1E26"), lineWidth: 1))
    }
    @ViewBuilder private func statusIcon(_ s: PackageStatus) -> some View {
        switch s {
        case .installing: Image(systemName: "arrow.down.circle").font(.system(size: 11)).foregroundColor(Color(hex: "#4A9EFF"))
        case .installed:  Image(systemName: "checkmark.circle.fill").font(.system(size: 11)).foregroundColor(Color(hex: "#3DFF8F"))
        case .failed:     Image(systemName: "xmark.circle.fill").font(.system(size: 11)).foregroundColor(Color(hex: "#FF4D6A"))
        case .warning:    Image(systemName: "exclamationmark.triangle").font(.system(size: 11)).foregroundColor(Color(hex: "#FFD060"))
        }
    }
    private func statusTextColor(_ s: PackageStatus) -> Color { s == .failed ? Color(hex: "#FF4D6A") : s == .warning ? Color(hex: "#FFD060") : Color(hex: "#D8E4F0") }
}
