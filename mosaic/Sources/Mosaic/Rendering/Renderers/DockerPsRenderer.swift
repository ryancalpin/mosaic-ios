import SwiftUI

// MARK: - DockerPsRenderer
//
// Renders: docker ps, docker ps -a, docker container ls
// Trigger: command starts with "docker ps" or "docker container ls"
// Output shape: tabular with columns CONTAINER ID, IMAGE, COMMAND, CREATED, STATUS, PORTS, NAMES

@MainActor
public final class DockerPsRenderer: OutputRenderer {
    public let id           = "docker.ps"
    public let displayName  = "Container List"
    public let badgeLabel   = "CONTAINERS"
    public let priority     = RendererPriority.docker

    public func canRender(command: String, output: String) -> Bool {
        let cmd = command.lowercased()
        let triggersOnCommand =
            cmd.hasPrefix("docker ps") ||
            cmd.hasPrefix("docker container ls") ||
            cmd.hasPrefix("docker container list")

        // Heuristic fallback: output looks like docker ps table
        let triggersOnOutput = output.contains("CONTAINER ID") && output.contains("NAMES")

        return triggersOnCommand || triggersOnOutput
    }

    public func parse(command: String, output: String) -> (any RendererData)? {
        let lines = output.components(separatedBy: "\n").filter { !$0.isEmpty }
        guard lines.count >= 1 else { return nil }

        // Find the header line
        guard let headerLine = lines.first(where: { $0.contains("CONTAINER ID") }) else {
            return nil
        }

        // Parse column offsets from header
        guard let idRange      = headerLine.range(of: "CONTAINER ID"),
              let imageRange   = headerLine.range(of: "IMAGE"),
              let commandRange = headerLine.range(of: "COMMAND"),
              let createdRange = headerLine.range(of: "CREATED"),
              let statusRange  = headerLine.range(of: "STATUS"),
              let portsRange   = headerLine.range(of: "PORTS"),
              let namesRange   = headerLine.range(of: "NAMES") else {
            return nil
        }

        let idOffset      = headerLine.distance(from: headerLine.startIndex, to: idRange.lowerBound)
        let imageOffset   = headerLine.distance(from: headerLine.startIndex, to: imageRange.lowerBound)
        let commandOffset = headerLine.distance(from: headerLine.startIndex, to: commandRange.lowerBound)
        let createdOffset = headerLine.distance(from: headerLine.startIndex, to: createdRange.lowerBound)
        let statusOffset  = headerLine.distance(from: headerLine.startIndex, to: statusRange.lowerBound)
        let portsOffset   = headerLine.distance(from: headerLine.startIndex, to: portsRange.lowerBound)
        let namesOffset   = headerLine.distance(from: headerLine.startIndex, to: namesRange.lowerBound)
        _ = createdOffset  // used implicitly via statusOffset boundary

        guard let headerIndex = lines.firstIndex(where: { $0.contains("CONTAINER ID") }) else {
            return nil
        }

        var containers: [ContainerRow] = []

        for line in lines[(headerIndex + 1)...] where line.utf8.count >= namesOffset {
            func col(from start: Int, to end: Int) -> String {
                let u = line.utf8
                guard start < u.count else { return "" }
                let si = u.index(u.startIndex, offsetBy: start, limitedBy: u.endIndex) ?? u.endIndex
                let ei = u.index(u.startIndex, offsetBy: end, limitedBy: u.endIndex) ?? u.endIndex
                guard si <= ei else { return "" }
                // Column boundaries always land on ASCII spaces so samePosition is always valid
                let s = si.samePosition(in: line) ?? line.startIndex
                let e = ei.samePosition(in: line) ?? line.endIndex
                return String(line[s..<e]).trimmingCharacters(in: .whitespaces)
            }

            let containerID = col(from: idOffset, to: imageOffset)
            let image       = col(from: imageOffset, to: commandOffset)
            let status      = col(from: statusOffset, to: portsOffset)
            let ports       = col(from: portsOffset, to: namesOffset)
            let name        = col(from: namesOffset, to: line.count)

            guard !containerID.isEmpty, !name.isEmpty else { continue }

            containers.append(ContainerRow(
                containerID: String(containerID.prefix(12)),
                name:        name,
                image:       image,
                status:      status,
                ports:       ports.isEmpty ? nil : ports,
                isRunning:   status.lowercased().hasPrefix("up")
            ))
        }

        guard !containers.isEmpty else { return nil }
        return DockerPsData(containers: containers)
    }

    public func view(for data: any RendererData) -> AnyView {
        guard let data = data as? DockerPsData else { return AnyView(EmptyView()) }
        return AnyView(DockerPsView(data: data))
    }
}

// MARK: - Data Models

public struct DockerPsData: RendererData {
    public let containers: [ContainerRow]
}

public struct ContainerRow: Identifiable, Sendable {
    public let id = UUID()
    public let containerID: String
    public let name: String
    public let image: String
    public let status: String
    public let ports: String?
    public let isRunning: Bool

    public var uptimeString: String {
        // Extract "3 days" from "Up 3 days"
        if let range = status.range(of: "Up ", options: .caseInsensitive) {
            return String(status[range.upperBound...]).trimmingCharacters(in: .whitespaces)
        }
        return status
    }
}

// MARK: - View

struct DockerPsView: View {
    let data: DockerPsData

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(data.containers.enumerated()), id: \.element.id) { index, container in
                ContainerRowView(container: container)
                if index < data.containers.count - 1 {
                    Divider().overlay(Color(hex: "#141418"))
                }
            }
        }
        .background(Color(hex: "#111115"))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(hex: "#1E1E26"), lineWidth: 1))
    }
}

struct ContainerRowView: View {
    let container: ContainerRow

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 7) {
                // Status dot
                Circle()
                    .fill(container.isRunning ? Color(hex: "#3DFF8F") : Color(hex: "#3A4A58"))
                    .frame(width: 7, height: 7)
                    .opacity(container.isRunning ? 1 : 0.6)

                Text(container.name)
                    .font(.custom("JetBrains Mono", size: 11.5).weight(.semibold))
                    .foregroundColor(Color(hex: "#D8E4F0"))

                Spacer()

                if container.isRunning {
                    Text(container.uptimeString)
                        .font(.custom("JetBrains Mono", size: 9))
                        .foregroundColor(Color(hex: "#3A4A58"))
                }
            }

            if container.isRunning {
                HStack(spacing: 8) {
                    Text(container.image)
                        .font(.custom("JetBrains Mono", size: 9))
                        .foregroundColor(Color(hex: "#3A4A58"))

                    if let ports = container.ports {
                        Text(ports)
                            .font(.custom("JetBrains Mono", size: 9))
                            .foregroundColor(Color(hex: "#5AB4FF"))
                    }
                }
                .padding(.leading, 15)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }
}
