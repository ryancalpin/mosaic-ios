import SwiftUI

@MainActor
public final class DiskUsageRenderer: OutputRenderer {
    public let id          = "system.disk"
    public let displayName = "Disk Usage"
    public let badgeLabel  = "DISK"
    public let priority    = RendererPriority.system
    private static let pseudoFS: Set<String> = ["tmpfs","devtmpfs","devfs","udev","sysfs","proc","cgroup","cgroupfs","overlay","shm","none"]

    public func canRender(command: String, output: String) -> Bool {
        let cmd = command.lowercased()
        return cmd.hasPrefix("df") || (output.contains("Filesystem") && output.contains("Use%"))
    }

    public func parse(command: String, output: String) -> (any RendererData)? {
        let lines = output.components(separatedBy: "\n").filter { !$0.isEmpty }
        guard let headerIndex = lines.firstIndex(where: { $0.contains("Filesystem") && $0.contains("Use%") }) else { return nil }
        var mounts: [MountRow] = []
        for line in lines[(headerIndex + 1)...] {
            let parts = line.trimmingCharacters(in: .whitespaces).components(separatedBy: .whitespaces).filter { !$0.isEmpty }
            guard parts.count >= 6 else { continue }
            let percentDigits = parts[4].trimmingCharacters(in: CharacterSet.decimalDigits.inverted)
            guard let percent = Int(percentDigits) else { continue }
            let fsBase = parts[0].components(separatedBy: "/").last ?? parts[0]
            if Self.pseudoFS.contains(fsBase.lowercased()) && percent == 0 { continue }
            mounts.append(MountRow(filesystem: parts[0], size: parts[1], used: parts[2], avail: parts[3], usePercent: percent, mountPoint: parts[5...].joined(separator: " ")))
        }
        guard !mounts.isEmpty else { return nil }
        return DiskUsageData(mounts: mounts)
    }

    public func view(for data: any RendererData) -> AnyView {
        guard let data = data as? DiskUsageData else { return AnyView(EmptyView()) }
        return AnyView(DiskUsageView(data: data))
    }
}

public struct DiskUsageData: RendererData { public let mounts: [MountRow] }
public struct MountRow: Identifiable, Sendable {
    public let id = UUID()
    public let filesystem: String; public let size: String; public let used: String; public let avail: String; public let usePercent: Int; public let mountPoint: String
}

private struct DiskUsageView: View {
    let data: DiskUsageData
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "internaldrive").font(.system(size: 11, weight: .semibold)).foregroundColor(Color(hex: "#00D4AA"))
                Text("Disk Usage").font(.custom("JetBrains Mono", size: 11.5).weight(.semibold)).foregroundColor(Color(hex: "#D8E4F0"))
                Spacer()
                Text("\(data.mounts.count) mounts").font(.custom("JetBrains Mono", size: 9)).foregroundColor(Color(hex: "#3A4A58"))
            }.padding(.horizontal, 12).padding(.vertical, 9)
            Divider().overlay(Color(hex: "#141418"))
            ForEach(Array(data.mounts.enumerated()), id: \.element.id) { index, mount in
                MountRowView(mount: mount)
                if index < data.mounts.count - 1 { Divider().overlay(Color(hex: "#141418")) }
            }
        }
        .background(Color(hex: "#111115")).clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(hex: "#1E1E26"), lineWidth: 1))
    }
}

private struct MountRowView: View {
    let mount: MountRow
    private var barColor: Color { mount.usePercent > 80 ? Color(hex: "#FF4D6A") : mount.usePercent > 60 ? Color(hex: "#FFD060") : Color(hex: "#3DFF8F") }
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(mount.filesystem).font(.custom("JetBrains Mono", size: 10.5)).foregroundColor(Color(hex: "#D8E4F0")).lineLimit(1).truncationMode(.middle)
                Spacer()
                Text("\(mount.used) / \(mount.size)").font(.custom("JetBrains Mono", size: 9)).foregroundColor(Color(hex: "#3A4A58"))
                Text("\(mount.usePercent)%").font(.custom("JetBrains Mono", size: 9).weight(.bold)).foregroundColor(barColor).frame(width: 36, alignment: .trailing)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2).fill(Color(hex: "#17171C")).frame(height: 4)
                    RoundedRectangle(cornerRadius: 2).fill(barColor).frame(width: max(0, geo.size.width * CGFloat(mount.usePercent) / 100), height: 4)
                }
            }.frame(height: 4)
            Text(mount.mountPoint).font(.custom("JetBrains Mono", size: 9)).foregroundColor(Color(hex: "#3A4A58")).lineLimit(1).truncationMode(.middle)
        }.padding(.horizontal, 12).padding(.vertical, 9)
    }
}
