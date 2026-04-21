import SwiftUI

@MainActor
public final class ProcessTableRenderer: OutputRenderer {
    public let id          = "system.processes"
    public let displayName = "Process Table"
    public let badgeLabel  = "PROCESSES"
    public let priority    = RendererPriority.system

    public func canRender(command: String, output: String) -> Bool {
        let cmd = command.lowercased()
        return cmd.hasPrefix("ps") || (output.contains("PID") && output.contains("%CPU"))
    }

    public func parse(command: String, output: String) -> (any RendererData)? {
        let lines = output.components(separatedBy: "\n").filter { !$0.isEmpty }
        guard let headerIndex = lines.firstIndex(where: { $0.contains("PID") && $0.contains("%CPU") }) else { return nil }
        var processes: [ProcessRow] = []
        for line in lines[(headerIndex + 1)...] {
            let parts = line.trimmingCharacters(in: .whitespaces).components(separatedBy: .whitespaces).filter { !$0.isEmpty }
            guard parts.count >= 11 else { continue }
            processes.append(ProcessRow(user: parts[0], pid: parts[1], cpu: Double(parts[2]) ?? 0, mem: Double(parts[3]) ?? 0, command: parts[10...].joined(separator: " ")))
        }
        guard !processes.isEmpty else { return nil }
        return ProcessTableData(processes: Array(processes.sorted { $0.cpu > $1.cpu }.prefix(15)))
    }

    public func view(for data: any RendererData) -> AnyView {
        guard let data = data as? ProcessTableData else { return AnyView(EmptyView()) }
        return AnyView(ProcessTableView(data: data))
    }
}

public struct ProcessTableData: RendererData { public let processes: [ProcessRow] }
public struct ProcessRow: Identifiable, Sendable {
    public let id = UUID(); public let user: String; public let pid: String; public let cpu: Double; public let mem: Double; public let command: String
    public var cpuColor: Color { cpu > 20 ? Color(hex: "#FF4D6A") : cpu > 5 ? Color(hex: "#FFD060") : Color(hex: "#3DFF8F") }
}

private struct ProcessTableView: View {
    let data: ProcessTableData
    @State private var expandedID: UUID? = nil
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Text("PID").frame(width: 52, alignment: .leading)
                Text("CPU%").frame(width: 44, alignment: .trailing)
                Text("MEM%").frame(width: 44, alignment: .trailing)
                Text("USER").frame(width: 60, alignment: .leading).padding(.leading, 8)
                Text("COMMAND").frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 8)
            }.font(.custom("JetBrains Mono", size: 8).weight(.bold)).foregroundColor(Color(hex: "#3A4A58")).padding(.horizontal, 12).padding(.vertical, 7)
            Divider().overlay(Color(hex: "#141418"))
            ForEach(Array(data.processes.enumerated()), id: \.element.id) { index, proc in
                VStack(spacing: 0) {
                    Button { withAnimation(.easeInOut(duration: 0.18)) { expandedID = expandedID == proc.id ? nil : proc.id } } label: {
                        HStack(spacing: 0) {
                            Text(proc.pid).frame(width: 52, alignment: .leading).foregroundColor(Color(hex: "#D8E4F0"))
                            Text(String(format: "%.1f", proc.cpu)).frame(width: 44, alignment: .trailing).foregroundColor(proc.cpuColor)
                            Text(String(format: "%.1f", proc.mem)).frame(width: 44, alignment: .trailing).foregroundColor(Color(hex: "#4A9EFF"))
                            Text(proc.user).frame(width: 60, alignment: .leading).foregroundColor(Color(hex: "#3A4A58")).padding(.leading, 8)
                            Text(proc.command).frame(maxWidth: .infinity, alignment: .leading).foregroundColor(Color(hex: "#D8E4F0")).lineLimit(1).truncationMode(.middle).padding(.leading, 8)
                        }.font(.custom("JetBrains Mono", size: 10)).padding(.horizontal, 12).padding(.vertical, 7)
                    }.buttonStyle(.plain)
                    if expandedID == proc.id {
                        HStack { Text(proc.command).font(.custom("JetBrains Mono", size: 9.5)).foregroundColor(Color(hex: "#D8E4F0")).padding(.horizontal, 12).padding(.vertical, 6); Spacer() }.background(Color(hex: "#17171C"))
                    }
                }
                if index < data.processes.count - 1 { Divider().overlay(Color(hex: "#141418")) }
            }
        }
        .background(Color(hex: "#111115")).clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(hex: "#1E1E26"), lineWidth: 1))
    }
}
