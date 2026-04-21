# Additional Native Renderers Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement 8 new native renderers (PingRenderer, DiskUsageRenderer, HttpResponseRenderer, ProcessTableRenderer, NpmInstallRenderer, JsonTreeRenderer, GitDiffRenderer, CronRenderer) and register them in RendererRegistry.

**Architecture:** Each renderer is a self-contained file in `Sources/Mosaic/Rendering/Renderers/` conforming to `OutputRenderer`. Data models are co-located as `RendererData`-conforming structs. Views are private structs inside the same file. All renderers must return `nil` from `parse()` on any format mismatch — no partial renders.

**Tech Stack:** Swift 5.9+, SwiftUI, Swift Charts (PingRenderer only), Foundation.JSONSerialization (JsonTreeRenderer), JetBrains Mono font for all code/terminal text.

---

## File Map

| Action | Path | Responsibility |
|--------|------|----------------|
| Create | `Sources/Mosaic/Rendering/Renderers/PingRenderer.swift` | Render `ping` output as a latency sparkline |
| Create | `Sources/Mosaic/Rendering/Renderers/DiskUsageRenderer.swift` | Render `df -h` output as filled progress bar rows |
| Create | `Sources/Mosaic/Rendering/Renderers/HttpResponseRenderer.swift` | Render `curl -I` HTTP headers with status badge |
| Create | `Sources/Mosaic/Rendering/Renderers/ProcessTableRenderer.swift` | Render `ps aux` as a top-N CPU process table |
| Create | `Sources/Mosaic/Rendering/Renderers/NpmInstallRenderer.swift` | Render npm/pip/apt install progress as a package list |
| Create | `Sources/Mosaic/Rendering/Renderers/JsonTreeRenderer.swift` | Render JSON output as a collapsible tree |
| Create | `Sources/Mosaic/Rendering/Renderers/GitDiffRenderer.swift` | Render `git diff` as a per-file diff view |
| Create | `Sources/Mosaic/Rendering/Renderers/CronRenderer.swift` | Render `crontab -l` as human-readable schedule cards |
| Modify | `Sources/Mosaic/Rendering/RendererRegistry.swift` | Register all 8 new renderers in `registerBuiltins()` |

---

### Task 1: PingRenderer

**Files:** Create: `Sources/Mosaic/Rendering/Renderers/PingRenderer.swift`

- [ ] Step 1: Create `PingRenderer.swift` with the full implementation below.

```swift
import SwiftUI
import Charts

// MARK: - PingRenderer
//
// Renders: ping <host>
// Trigger: command starts with "ping"
// Output shape: lines like "64 bytes from 1.1.1.1: icmp_seq=1 ttl=57 time=12.345 ms"
//               plus a summary "rtt min/avg/max/mdev = ..."

@MainActor
public final class PingRenderer: OutputRenderer {
    public let id          = "network.ping"
    public let displayName = "Ping"
    public let badgeLabel  = "PING"
    public let priority    = RendererPriority.network

    public func canRender(command: String, output: String) -> Bool {
        command.lowercased().hasPrefix("ping")
    }

    public func parse(command: String, output: String) -> (any RendererData)? {
        let lines = output.components(separatedBy: "\n")

        // Extract host from first line: "PING cloudflare.com (1.1.1.1): 56 data bytes"
        guard let firstLine = lines.first(where: { $0.lowercased().hasPrefix("ping") }) else {
            return nil
        }
        // Grab the first token after "PING " as the host
        let pingTokens = firstLine.components(separatedBy: " ")
        let host = pingTokens.count > 1 ? pingTokens[1] : "unknown"

        var packets: [PingPacket] = []

        // Parse individual reply lines
        let timeRegex = try? NSRegularExpression(pattern: #"icmp_seq=(\d+).*?time=([\d.]+)\s*ms"#)
        let timeoutRegex = try? NSRegularExpression(pattern: #"icmp_seq=(\d+).*[Tt]imeout"#)

        for line in lines {
            let ns = line as NSString
            let range = NSRange(location: 0, length: ns.length)

            if let m = timeRegex?.firstMatch(in: line, range: range),
               m.numberOfRanges >= 3,
               let seqRange = Range(m.range(at: 1), in: line),
               let msRange  = Range(m.range(at: 2), in: line),
               let seq = Int(line[seqRange]),
               let ms  = Double(line[msRange]) {
                packets.append(PingPacket(seq: seq, ms: ms, isTimeout: false))
            } else if let m = timeoutRegex?.firstMatch(in: line, range: range),
                      m.numberOfRanges >= 2,
                      let seqRange = Range(m.range(at: 1), in: line),
                      let seq = Int(line[seqRange]) {
                packets.append(PingPacket(seq: seq, ms: nil, isTimeout: true))
            }
        }

        guard !packets.isEmpty else { return nil }

        // Parse summary line: "rtt min/avg/max/mdev = 10.1/12.3/14.5/1.2 ms"
        var minMs: Double? = nil
        var avgMs: Double? = nil
        var maxMs: Double? = nil

        if let summaryLine = lines.first(where: { $0.contains("min/avg/max") }) {
            let summaryRegex = try? NSRegularExpression(
                pattern: #"=\s*([\d.]+)/([\d.]+)/([\d.]+)"#
            )
            let ns2 = summaryLine as NSString
            if let m = summaryRegex?.firstMatch(in: summaryLine,
                                                range: NSRange(location: 0, length: ns2.length)),
               m.numberOfRanges >= 4,
               let r1 = Range(m.range(at: 1), in: summaryLine),
               let r2 = Range(m.range(at: 2), in: summaryLine),
               let r3 = Range(m.range(at: 3), in: summaryLine) {
                minMs = Double(summaryLine[r1])
                avgMs = Double(summaryLine[r2])
                maxMs = Double(summaryLine[r3])
            }
        }

        return PingData(host: host, packets: packets, minMs: minMs, avgMs: avgMs, maxMs: maxMs)
    }

    public func view(for data: any RendererData) -> AnyView {
        guard let data = data as? PingData else { return AnyView(EmptyView()) }
        return AnyView(PingView(data: data))
    }
}

// MARK: - Data Models

public struct PingData: RendererData {
    public let host: String
    public let packets: [PingPacket]
    public let minMs: Double?
    public let avgMs: Double?
    public let maxMs: Double?
}

public struct PingPacket: Identifiable, Sendable {
    public let id = UUID()
    public let seq: Int
    public let ms: Double?
    public let isTimeout: Bool
}

// MARK: - View

private struct PingView: View {
    let data: PingData

    private var successPackets: [PingPacket] {
        data.packets.filter { !$0.isTimeout }
    }

    private var lossPercent: Int {
        guard !data.packets.isEmpty else { return 0 }
        let lost = data.packets.filter { $0.isTimeout }.count
        return Int(Double(lost) / Double(data.packets.count) * 100)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Host header
            HStack(spacing: 8) {
                Image(systemName: "network")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Color(hex: "#00D4AA"))
                Text(data.host)
                    .font(.custom("JetBrains Mono", size: 11.5).weight(.semibold))
                    .foregroundColor(Color(hex: "#D8E4F0"))
                Spacer()
                Text("\(data.packets.count) packets")
                    .font(.custom("JetBrains Mono", size: 9))
                    .foregroundColor(Color(hex: "#3A4A58"))
                if lossPercent > 0 {
                    Text("\(lossPercent)% loss")
                        .font(.custom("JetBrains Mono", size: 9).weight(.bold))
                        .foregroundColor(Color(hex: "#FF4D6A"))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color(hex: "#FF4D6A").opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 9)

            Divider().overlay(Color(hex: "#141418"))

            // Sparkline
            if !successPackets.isEmpty {
                Chart(successPackets, id: \.seq) {
                    LineMark(
                        x: .value("Seq", $0.seq),
                        y: .value("ms", $0.ms ?? 0)
                    )
                    .foregroundStyle(Color(hex: "#00D4AA"))
                    AreaMark(
                        x: .value("Seq", $0.seq),
                        y: .value("ms", $0.ms ?? 0)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color(hex: "#00D4AA").opacity(0.25), .clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                }
                .frame(height: 60)
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

                Divider().overlay(Color(hex: "#141418"))
            }

            // Stats row
            HStack(spacing: 0) {
                statCell(label: "MIN", value: data.minMs.map { String(format: "%.1f ms", $0) } ?? "—")
                statDivider()
                statCell(label: "AVG", value: data.avgMs.map { String(format: "%.1f ms", $0) } ?? "—")
                statDivider()
                statCell(label: "MAX", value: data.maxMs.map { String(format: "%.1f ms", $0) } ?? "—")
            }
            .padding(.vertical, 9)
        }
        .background(Color(hex: "#111115"))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(hex: "#1E1E26"), lineWidth: 1))
    }

    @ViewBuilder
    private func statCell(label: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.custom("JetBrains Mono", size: 8).weight(.bold))
                .foregroundColor(Color(hex: "#3A4A58"))
            Text(value)
                .font(.custom("JetBrains Mono", size: 11).weight(.semibold))
                .foregroundColor(Color(hex: "#D8E4F0"))
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func statDivider() -> some View {
        Rectangle()
            .fill(Color(hex: "#1E1E26"))
            .frame(width: 1, height: 28)
    }
}
```

- [ ] Step 2: Build to confirm no compile errors.

```bash
xcodebuild build \
  -scheme Mosaic \
  -destination 'generic/platform=iOS Simulator' \
  2>&1 | grep -E "error:|warning:|BUILD"
```

- [ ] Step 3: Commit.

```bash
git add "Sources/Mosaic/Rendering/Renderers/PingRenderer.swift"
git commit -m "feat: add PingRenderer — sparkline chart for ping output"
```

---

### Task 2: DiskUsageRenderer

**Files:** Create: `Sources/Mosaic/Rendering/Renderers/DiskUsageRenderer.swift`

- [ ] Step 1: Create `DiskUsageRenderer.swift`.

```swift
import SwiftUI

// MARK: - DiskUsageRenderer
//
// Renders: df -h, df -H
// Trigger: command starts with "df" OR output has "Filesystem" + "Use%"
// Output shape: header + one row per mount

@MainActor
public final class DiskUsageRenderer: OutputRenderer {
    public let id          = "system.disk"
    public let displayName = "Disk Usage"
    public let badgeLabel  = "DISK"
    public let priority    = RendererPriority.system

    // Pseudo-filesystems to skip unless they have real space numbers
    private static let pseudoFS: Set<String> = [
        "tmpfs", "devtmpfs", "devfs", "udev", "sysfs", "proc",
        "cgroup", "cgroupfs", "overlay", "shm", "none"
    ]

    public func canRender(command: String, output: String) -> Bool {
        let cmd = command.lowercased()
        let triggersOnCommand = cmd.hasPrefix("df")
        let triggersOnOutput  = output.contains("Filesystem") && output.contains("Use%")
        return triggersOnCommand || triggersOnOutput
    }

    public func parse(command: String, output: String) -> (any RendererData)? {
        let lines = output.components(separatedBy: "\n").filter { !$0.isEmpty }

        // Find the header line
        guard let headerIndex = lines.firstIndex(where: {
            $0.contains("Filesystem") && $0.contains("Use%")
        }) else { return nil }

        var mounts: [MountRow] = []

        for line in lines[(headerIndex + 1)...] {
            // df -h may wrap long filesystem names onto the next line;
            // wrapped lines start with whitespace.
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }

            // Split on whitespace — handles multiple spaces between columns
            let parts = trimmed.components(separatedBy: .whitespaces).filter { !$0.isEmpty }

            // Expect: filesystem size used avail use% mountpoint
            // Wrapped rows where only mountpoint appears have < 6 fields — skip them.
            guard parts.count >= 6 else { continue }

            let filesystem  = parts[0]
            let size        = parts[1]
            let used        = parts[2]
            let avail       = parts[3]
            let percentStr  = parts[4]
            let mountPoint  = parts[5...].joined(separator: " ")

            // Parse percent (strip %)
            let percentDigits = percentStr.trimmingCharacters(in: CharacterSet.decimalDigits.inverted)
            guard let percent = Int(percentDigits) else { continue }

            // Skip pseudo-filesystems with zero real usage
            let fsBase = filesystem.components(separatedBy: "/").last ?? filesystem
            if Self.pseudoFS.contains(fsBase.lowercased()) && percent == 0 { continue }

            mounts.append(MountRow(
                filesystem:  filesystem,
                size:        size,
                used:        used,
                avail:       avail,
                usePercent:  percent,
                mountPoint:  mountPoint
            ))
        }

        guard !mounts.isEmpty else { return nil }
        return DiskUsageData(mounts: mounts)
    }

    public func view(for data: any RendererData) -> AnyView {
        guard let data = data as? DiskUsageData else { return AnyView(EmptyView()) }
        return AnyView(DiskUsageView(data: data))
    }
}

// MARK: - Data Models

public struct DiskUsageData: RendererData {
    public let mounts: [MountRow]
}

public struct MountRow: Identifiable, Sendable {
    public let id = UUID()
    public let filesystem:  String
    public let size:        String
    public let used:        String
    public let avail:       String
    public let usePercent:  Int
    public let mountPoint:  String
}

// MARK: - View

private struct DiskUsageView: View {
    let data: DiskUsageData

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "internaldrive")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Color(hex: "#00D4AA"))
                Text("Disk Usage")
                    .font(.custom("JetBrains Mono", size: 11.5).weight(.semibold))
                    .foregroundColor(Color(hex: "#D8E4F0"))
                Spacer()
                Text("\(data.mounts.count) mounts")
                    .font(.custom("JetBrains Mono", size: 9))
                    .foregroundColor(Color(hex: "#3A4A58"))
            }
            .padding(.horizontal, 12).padding(.vertical, 9)

            Divider().overlay(Color(hex: "#141418"))

            ForEach(Array(data.mounts.enumerated()), id: \.element.id) { index, mount in
                MountRowView(mount: mount)
                if index < data.mounts.count - 1 {
                    Divider().overlay(Color(hex: "#141418"))
                }
            }
        }
        .background(Color(hex: "#111115"))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(hex: "#1E1E26"), lineWidth: 1))
    }
}

private struct MountRowView: View {
    let mount: MountRow

    private var barColor: Color {
        mount.usePercent > 80 ? Color(hex: "#FF4D6A")
            : mount.usePercent > 60 ? Color(hex: "#FFD060")
            : Color(hex: "#3DFF8F")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                // Filesystem name (truncated)
                Text(mount.filesystem)
                    .font(.custom("JetBrains Mono", size: 10.5))
                    .foregroundColor(Color(hex: "#D8E4F0"))
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer()

                Text("\(mount.used) / \(mount.size)")
                    .font(.custom("JetBrains Mono", size: 9))
                    .foregroundColor(Color(hex: "#3A4A58"))

                Text("\(mount.usePercent)%")
                    .font(.custom("JetBrains Mono", size: 9).weight(.bold))
                    .foregroundColor(barColor)
                    .frame(width: 36, alignment: .trailing)
            }

            // Progress bar
            GeometryReader { geo in
                let filled = geo.size.width * CGFloat(mount.usePercent) / 100
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color(hex: "#17171C"))
                        .frame(height: 4)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(barColor)
                        .frame(width: max(0, filled), height: 4)
                }
            }
            .frame(height: 4)

            Text(mount.mountPoint)
                .font(.custom("JetBrains Mono", size: 9))
                .foregroundColor(Color(hex: "#3A4A58"))
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
    }
}
```

- [ ] Step 2: Build.

```bash
xcodebuild build \
  -scheme Mosaic \
  -destination 'generic/platform=iOS Simulator' \
  2>&1 | grep -E "error:|warning:|BUILD"
```

- [ ] Step 3: Commit.

```bash
git add "Sources/Mosaic/Rendering/Renderers/DiskUsageRenderer.swift"
git commit -m "feat: add DiskUsageRenderer — progress bars for df -h output"
```

---

### Task 3: HttpResponseRenderer

**Files:** Create: `Sources/Mosaic/Rendering/Renderers/HttpResponseRenderer.swift`

- [ ] Step 1: Create `HttpResponseRenderer.swift`.

```swift
import SwiftUI

// MARK: - HttpResponseRenderer
//
// Renders: curl -I, curl -sI, curl -i
// Trigger: command has "curl" + header-inspection flag, OR output first line matches HTTP/\d
// Output shape: "HTTP/1.1 200 OK\nHeader: Value\n\n[body]"

@MainActor
public final class HttpResponseRenderer: OutputRenderer {
    public let id          = "network.http"
    public let displayName = "HTTP Response"
    public let badgeLabel  = "HTTP"
    public let priority    = RendererPriority.network

    private static let statusLineRegex = try? NSRegularExpression(
        pattern: #"^(HTTP/[\d.]+)\s+(\d{3})\s*(.*)"#
    )

    public func canRender(command: String, output: String) -> Bool {
        let cmd = command.lowercased()
        let commandHasCurlFlag = cmd.contains("curl") &&
            (cmd.contains(" -i") || cmd.contains(" -si") || cmd.contains("--head") ||
             cmd.contains(" --include"))
        let outputLooksLikeHTTP = output.hasPrefix("HTTP/")
        return commandHasCurlFlag || outputLooksLikeHTTP
    }

    public func parse(command: String, output: String) -> (any RendererData)? {
        let lines = output.components(separatedBy: "\n")
        guard !lines.isEmpty else { return nil }

        // First non-empty line must be the status line
        guard let statusLine = lines.first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty })
        else { return nil }

        let ns = statusLine as NSString
        let fullRange = NSRange(location: 0, length: ns.length)
        guard let m = Self.statusLineRegex?.firstMatch(in: statusLine, range: fullRange),
              m.numberOfRanges >= 3,
              let versionRange    = Range(m.range(at: 1), in: statusLine),
              let codeRange       = Range(m.range(at: 2), in: statusLine),
              let statusCode = Int(statusLine[codeRange])
        else { return nil }

        let version    = String(statusLine[versionRange])
        let statusText: String = {
            if m.numberOfRanges >= 4, let r = Range(m.range(at: 3), in: statusLine) {
                return String(statusLine[r]).trimmingCharacters(in: .whitespaces)
            }
            return ""
        }()

        // Parse headers until blank line
        var headers: [(key: String, value: String)] = []
        var seenStatusLine = false
        for line in lines {
            if !seenStatusLine {
                if line.trimmingCharacters(in: .whitespaces) == statusLine.trimmingCharacters(in: .whitespaces) {
                    seenStatusLine = true
                }
                continue
            }
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { break }  // blank line = end of headers
            // Split on first ": " only
            if let colonRange = trimmed.range(of: ": ") {
                let key   = String(trimmed[trimmed.startIndex..<colonRange.lowerBound])
                let value = String(trimmed[colonRange.upperBound...])
                headers.append((key: key, value: value))
            }
        }

        return HttpResponseData(
            version:    version,
            statusCode: statusCode,
            statusText: statusText,
            headers:    Array(headers.prefix(20))
        )
    }

    public func view(for data: any RendererData) -> AnyView {
        guard let data = data as? HttpResponseData else { return AnyView(EmptyView()) }
        return AnyView(HttpResponseView(data: data))
    }
}

// MARK: - Data Models

public struct HttpResponseData: RendererData {
    public let version:    String
    public let statusCode: Int
    public let statusText: String
    public let headers:    [(key: String, value: String)]
}

extension HttpResponseData: Sendable {}

// MARK: - View

private struct HttpResponseView: View {
    let data: HttpResponseData

    private var statusColor: Color {
        switch data.statusCode {
        case 200..<300: return Color(hex: "#3DFF8F")
        case 300..<400: return Color(hex: "#FFD060")
        default:        return Color(hex: "#FF4D6A")
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Status badge row
            HStack(spacing: 12) {
                // Large status code
                Text("\(data.statusCode)")
                    .font(.custom("JetBrains Mono", size: 28).weight(.bold))
                    .foregroundColor(statusColor)

                VStack(alignment: .leading, spacing: 2) {
                    Text(data.statusText)
                        .font(.custom("JetBrains Mono", size: 11.5).weight(.semibold))
                        .foregroundColor(Color(hex: "#D8E4F0"))
                    Text(data.version)
                        .font(.custom("JetBrains Mono", size: 9))
                        .foregroundColor(Color(hex: "#3A4A58"))
                }

                Spacer()
            }
            .padding(.horizontal, 12).padding(.vertical, 12)

            Divider().overlay(Color(hex: "#141418"))

            // Headers (max 10 shown)
            VStack(spacing: 0) {
                ForEach(Array(data.headers.prefix(10).enumerated()), id: \.offset) { index, header in
                    HStack(alignment: .top, spacing: 8) {
                        Text(header.key)
                            .font(.custom("JetBrains Mono", size: 10))
                            .foregroundColor(Color(hex: "#3A4A58"))
                            .frame(minWidth: 100, alignment: .leading)
                            .lineLimit(1)

                        Text(header.value)
                            .font(.custom("JetBrains Mono", size: 10))
                            .foregroundColor(Color(hex: "#D8E4F0"))
                            .lineLimit(2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.horizontal, 12).padding(.vertical, 6)

                    if index < min(9, data.headers.count - 1) {
                        Divider().overlay(Color(hex: "#141418"))
                    }
                }

                if data.headers.count > 10 {
                    Text("+ \(data.headers.count - 10) more headers")
                        .font(.custom("JetBrains Mono", size: 9))
                        .foregroundColor(Color(hex: "#3A4A58"))
                        .padding(.horizontal, 12).padding(.vertical, 6)
                }
            }
        }
        .background(Color(hex: "#111115"))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(hex: "#1E1E26"), lineWidth: 1))
    }
}
```

- [ ] Step 2: Build.

```bash
xcodebuild build \
  -scheme Mosaic \
  -destination 'generic/platform=iOS Simulator' \
  2>&1 | grep -E "error:|warning:|BUILD"
```

- [ ] Step 3: Commit.

```bash
git add "Sources/Mosaic/Rendering/Renderers/HttpResponseRenderer.swift"
git commit -m "feat: add HttpResponseRenderer — status badge + header list for curl -I"
```

---

### Task 4: ProcessTableRenderer

**Files:** Create: `Sources/Mosaic/Rendering/Renderers/ProcessTableRenderer.swift`

- [ ] Step 1: Create `ProcessTableRenderer.swift`.

```swift
import SwiftUI

// MARK: - ProcessTableRenderer
//
// Renders: ps aux, ps -ef, ps
// Trigger: command starts with "ps" OR first line contains "PID" and "%CPU"
// Shows top 15 processes by CPU, tap to expand full row

@MainActor
public final class ProcessTableRenderer: OutputRenderer {
    public let id          = "system.processes"
    public let displayName = "Process Table"
    public let badgeLabel  = "PROCESSES"
    public let priority    = RendererPriority.system

    public func canRender(command: String, output: String) -> Bool {
        let cmd = command.lowercased()
        let triggersOnCommand = cmd.hasPrefix("ps")
        let triggersOnOutput  = output.contains("PID") && output.contains("%CPU")
        return triggersOnCommand || triggersOnOutput
    }

    public func parse(command: String, output: String) -> (any RendererData)? {
        let lines = output.components(separatedBy: "\n").filter { !$0.isEmpty }

        // Find header line containing PID and %CPU
        guard let headerIndex = lines.firstIndex(where: {
            $0.contains("PID") && $0.contains("%CPU")
        }) else { return nil }

        let headerLine = lines[headerIndex]

        // Locate column offsets by finding character positions of headers
        // ps aux format: USER PID %CPU %MEM VSZ RSS TTY STAT START TIME COMMAND
        // We want: user, pid, cpu, mem, command (everything after TIME column)
        guard let userRange    = headerLine.range(of: "USER"),
              let pidRange     = headerLine.range(of: "PID"),
              let cpuRange     = headerLine.range(of: "%CPU"),
              let memRange     = headerLine.range(of: "%MEM"),
              let commandRange = headerLine.range(of: "COMMAND")
        else { return nil }

        func offset(_ r: Range<String.Index>) -> Int {
            headerLine.distance(from: headerLine.startIndex, to: r.lowerBound)
        }

        let userOff    = offset(userRange)
        let pidOff     = offset(pidRange)
        let cpuOff     = offset(cpuRange)
        let memOff     = offset(memRange)
        let commandOff = offset(commandRange)

        var processes: [ProcessRow] = []

        for line in lines[(headerIndex + 1)...] {
            // Simple whitespace split — more reliable than column offsets for variable-width data
            let parts = line.trimmingCharacters(in: .whitespaces)
                .components(separatedBy: .whitespaces)
                .filter { !$0.isEmpty }
            // ps aux order: USER PID %CPU %MEM VSZ RSS TTY STAT START TIME COMMAND...
            guard parts.count >= 11 else { continue }

            let user    = parts[0]
            let pid     = parts[1]
            let cpu     = Double(parts[2]) ?? 0
            let mem     = Double(parts[3]) ?? 0
            // COMMAND is index 10 onwards
            let command = parts[10...].joined(separator: " ")

            // Skip the column-index locals we computed above (they're only used to validate header)
            _ = userOff; _ = pidOff; _ = cpuOff; _ = memOff; _ = commandOff

            processes.append(ProcessRow(
                user:    user,
                pid:     pid,
                cpu:     cpu,
                mem:     mem,
                command: command
            ))
        }

        guard !processes.isEmpty else { return nil }

        // Sort by CPU descending, take top 15
        let sorted = processes.sorted { $0.cpu > $1.cpu }
        return ProcessTableData(processes: Array(sorted.prefix(15)))
    }

    public func view(for data: any RendererData) -> AnyView {
        guard let data = data as? ProcessTableData else { return AnyView(EmptyView()) }
        return AnyView(ProcessTableView(data: data))
    }
}

// MARK: - Data Models

public struct ProcessTableData: RendererData {
    public let processes: [ProcessRow]
}

public struct ProcessRow: Identifiable, Sendable {
    public let id = UUID()
    public let user:    String
    public let pid:     String
    public let cpu:     Double
    public let mem:     Double
    public let command: String

    public var cpuColor: Color {
        cpu > 20 ? Color(hex: "#FF4D6A") :
        cpu > 5  ? Color(hex: "#FFD060") :
                   Color(hex: "#3DFF8F")
    }
}

// MARK: - View

private struct ProcessTableView: View {
    let data: ProcessTableData
    @State private var expandedID: UUID? = nil

    var body: some View {
        VStack(spacing: 0) {
            // Column header
            HStack(spacing: 0) {
                Text("PID")
                    .frame(width: 52, alignment: .leading)
                Text("CPU%")
                    .frame(width: 44, alignment: .trailing)
                Text("MEM%")
                    .frame(width: 44, alignment: .trailing)
                Text("USER")
                    .frame(width: 60, alignment: .leading)
                    .padding(.leading, 8)
                Text("COMMAND")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 8)
            }
            .font(.custom("JetBrains Mono", size: 8).weight(.bold))
            .foregroundColor(Color(hex: "#3A4A58"))
            .padding(.horizontal, 12).padding(.vertical, 7)

            Divider().overlay(Color(hex: "#141418"))

            ForEach(Array(data.processes.enumerated()), id: \.element.id) { index, proc in
                VStack(spacing: 0) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            expandedID = expandedID == proc.id ? nil : proc.id
                        }
                    } label: {
                        HStack(spacing: 0) {
                            Text(proc.pid)
                                .frame(width: 52, alignment: .leading)
                                .foregroundColor(Color(hex: "#D8E4F0"))

                            Text(String(format: "%.1f", proc.cpu))
                                .frame(width: 44, alignment: .trailing)
                                .foregroundColor(proc.cpuColor)

                            Text(String(format: "%.1f", proc.mem))
                                .frame(width: 44, alignment: .trailing)
                                .foregroundColor(Color(hex: "#4A9EFF"))

                            Text(proc.user)
                                .frame(width: 60, alignment: .leading)
                                .foregroundColor(Color(hex: "#3A4A58"))
                                .padding(.leading, 8)

                            Text(proc.command)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .foregroundColor(Color(hex: "#D8E4F0"))
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .padding(.leading, 8)
                        }
                        .font(.custom("JetBrains Mono", size: 10))
                        .padding(.horizontal, 12).padding(.vertical, 7)
                    }
                    .buttonStyle(.plain)

                    if expandedID == proc.id {
                        HStack {
                            Text(proc.command)
                                .font(.custom("JetBrains Mono", size: 9.5))
                                .foregroundColor(Color(hex: "#D8E4F0"))
                                .padding(.horizontal, 12).padding(.vertical, 6)
                            Spacer()
                        }
                        .background(Color(hex: "#17171C"))
                    }
                }

                if index < data.processes.count - 1 {
                    Divider().overlay(Color(hex: "#141418"))
                }
            }
        }
        .background(Color(hex: "#111115"))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(hex: "#1E1E26"), lineWidth: 1))
    }
}
```

- [ ] Step 2: Build.

```bash
xcodebuild build \
  -scheme Mosaic \
  -destination 'generic/platform=iOS Simulator' \
  2>&1 | grep -E "error:|warning:|BUILD"
```

- [ ] Step 3: Commit.

```bash
git add "Sources/Mosaic/Rendering/Renderers/ProcessTableRenderer.swift"
git commit -m "feat: add ProcessTableRenderer — top-15 CPU table for ps aux"
```

---

### Task 5: NpmInstallRenderer

**Files:** Create: `Sources/Mosaic/Rendering/Renderers/NpmInstallRenderer.swift`

- [ ] Step 1: Create `NpmInstallRenderer.swift`.

```swift
import SwiftUI

// MARK: - NpmInstallRenderer
//
// Renders: npm install, npm i, pip install, apt install, apt-get install
// Trigger: command prefix match only (npm/pip/apt)
// Parses progress lines from each package manager's output format.

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
            || cmd.hasPrefix("apt-get upgrade")
    }

    public func parse(command: String, output: String) -> (any RendererData)? {
        let cmd = command.lowercased()
        let lines = output.components(separatedBy: "\n")

        let manager: String
        var packages: [PackageEntry] = []
        var summary: String? = nil

        if cmd.hasPrefix("npm") {
            manager = "npm"
            (packages, summary) = parseNpm(lines: lines)
        } else if cmd.hasPrefix("pip") {
            manager = "pip"
            (packages, summary) = parsePip(lines: lines)
        } else {
            manager = "apt"
            (packages, summary) = parseApt(lines: lines)
        }

        guard !packages.isEmpty || summary != nil else { return nil }
        return PackageInstallData(manager: manager, packages: packages, summary: summary)
    }

    // MARK: npm parsing
    private func parseNpm(lines: [String]) -> ([PackageEntry], String?) {
        var entries: [PackageEntry] = []
        var summary: String? = nil

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.lowercased().contains("added") && trimmed.contains("package") {
                // e.g. "added 120 packages from 80 contributors"
                summary = trimmed
            } else if trimmed.lowercased().hasPrefix("npm warn") || trimmed.lowercased().hasPrefix("npm warning") {
                let msg = trimmed.components(separatedBy: " ").dropFirst(2).joined(separator: " ")
                entries.append(PackageEntry(name: msg, version: nil, status: .warning))
            } else if trimmed.lowercased().hasPrefix("npm error") || trimmed.lowercased().hasPrefix("npm err!") {
                let msg = trimmed.components(separatedBy: " ").dropFirst(2).joined(separator: " ")
                entries.append(PackageEntry(name: msg, version: nil, status: .failed))
            } else if trimmed.hasPrefix("+ ") || trimmed.hasPrefix("added ") {
                // "added lodash@4.17.21"
                let parts = trimmed.components(separatedBy: " ").filter { !$0.isEmpty }
                if parts.count >= 2 {
                    let nameVer = parts[1]
                    let atIdx   = nameVer.lastIndex(of: "@")
                    if let at = atIdx, at != nameVer.startIndex {
                        let name = String(nameVer[nameVer.startIndex..<at])
                        let ver  = String(nameVer[nameVer.index(after: at)...])
                        entries.append(PackageEntry(name: name, version: ver, status: .installed))
                    } else {
                        entries.append(PackageEntry(name: nameVer, version: nil, status: .installed))
                    }
                }
            }
        }
        return (entries, summary)
    }

    // MARK: pip parsing
    private func parsePip(lines: [String]) -> ([PackageEntry], String?) {
        var entries: [PackageEntry] = []
        var summary: String? = nil

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("Collecting ") {
                let pkg = String(trimmed.dropFirst("Collecting ".count))
                    .components(separatedBy: " ").first ?? ""
                entries.append(PackageEntry(name: pkg, version: nil, status: .installing))
            } else if trimmed.hasPrefix("Successfully installed ") {
                let rest = String(trimmed.dropFirst("Successfully installed ".count))
                let pkgs = rest.components(separatedBy: " ")
                for pkg in pkgs where !pkg.isEmpty {
                    let dashIdx = pkg.lastIndex(of: "-")
                    if let d = dashIdx, d != pkg.startIndex {
                        let name = String(pkg[pkg.startIndex..<d])
                        let ver  = String(pkg[pkg.index(after: d)...])
                        entries.append(PackageEntry(name: name, version: ver, status: .installed))
                    } else {
                        entries.append(PackageEntry(name: pkg, version: nil, status: .installed))
                    }
                }
                summary = trimmed
            } else if trimmed.hasPrefix("ERROR:") {
                entries.append(PackageEntry(name: String(trimmed.dropFirst(6)).trimmingCharacters(in: .whitespaces),
                                            version: nil, status: .failed))
            }
        }
        return (entries, summary)
    }

    // MARK: apt parsing
    private func parseApt(lines: [String]) -> ([PackageEntry], String?) {
        var entries: [PackageEntry] = []
        var summary: String? = nil

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("Get:") {
                // "Get:3 http://... package-name 1.2.3 [420 kB]"
                let parts = trimmed.components(separatedBy: " ").filter { !$0.isEmpty }
                if parts.count >= 4 {
                    let name = parts[3]
                    let ver  = parts.count > 4 ? parts[4] : nil
                    entries.append(PackageEntry(name: name, version: ver, status: .installing))
                }
            } else if trimmed.hasPrefix("Setting up ") {
                let rest = String(trimmed.dropFirst("Setting up ".count))
                    .components(separatedBy: " ").first ?? ""
                // rest might be "package-name (1.2.3)"
                let clean = rest.components(separatedBy: "(").first ?? rest
                entries.append(PackageEntry(name: clean, version: nil, status: .installed))
            } else if trimmed.hasPrefix("E:") {
                entries.append(PackageEntry(name: String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces),
                                            version: nil, status: .failed))
            } else if trimmed.contains("upgraded") && trimmed.contains("installed") {
                summary = trimmed
            }
        }
        return (entries, summary)
    }

    public func view(for data: any RendererData) -> AnyView {
        guard let data = data as? PackageInstallData else { return AnyView(EmptyView()) }
        return AnyView(PackageInstallView(data: data))
    }
}

// MARK: - Data Models

public enum PackageStatus: String, Sendable {
    case installing, installed, failed, warning
}

public struct PackageEntry: Identifiable, Sendable {
    public let id = UUID()
    public let name: String
    public let version: String?
    public let status: PackageStatus
}

public struct PackageInstallData: RendererData {
    public let manager:  String
    public let packages: [PackageEntry]
    public let summary:  String?
}

// MARK: - View

private struct PackageInstallView: View {
    let data: PackageInstallData

    private var managerIcon: String {
        switch data.manager {
        case "npm":  return "npm"
        case "pip":  return "pip"
        default:     return "apt"
        }
    }

    private var managerColor: Color {
        switch data.manager {
        case "npm":  return Color(hex: "#FF4D6A")
        case "pip":  return Color(hex: "#4A9EFF")
        default:     return Color(hex: "#FFD060")
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 8) {
                Text(data.manager.uppercased())
                    .font(.custom("JetBrains Mono", size: 9).weight(.bold))
                    .foregroundColor(managerColor)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(managerColor.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 4))

                Text("Package Install")
                    .font(.custom("JetBrains Mono", size: 11.5).weight(.semibold))
                    .foregroundColor(Color(hex: "#D8E4F0"))
                Spacer()
                Text("\(data.packages.count) packages")
                    .font(.custom("JetBrains Mono", size: 9))
                    .foregroundColor(Color(hex: "#3A4A58"))
            }
            .padding(.horizontal, 12).padding(.vertical, 9)

            Divider().overlay(Color(hex: "#141418"))

            // Package list (max 20 shown)
            ForEach(Array(data.packages.prefix(20).enumerated()), id: \.element.id) { index, pkg in
                HStack(spacing: 8) {
                    statusIcon(pkg.status)
                        .frame(width: 16)

                    Text(pkg.name)
                        .font(.custom("JetBrains Mono", size: 10.5))
                        .foregroundColor(statusTextColor(pkg.status))
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Spacer()

                    if let ver = pkg.version {
                        Text(ver)
                            .font(.custom("JetBrains Mono", size: 9))
                            .foregroundColor(Color(hex: "#3A4A58"))
                    }
                }
                .padding(.horizontal, 12).padding(.vertical, 6)

                if index < min(19, data.packages.count - 1) {
                    Divider().overlay(Color(hex: "#141418"))
                }
            }

            if data.packages.count > 20 {
                Text("+ \(data.packages.count - 20) more")
                    .font(.custom("JetBrains Mono", size: 9))
                    .foregroundColor(Color(hex: "#3A4A58"))
                    .padding(.horizontal, 12).padding(.vertical, 6)
            }

            // Summary
            if let summary = data.summary {
                Divider().overlay(Color(hex: "#141418"))
                Text(summary)
                    .font(.custom("JetBrains Mono", size: 9.5))
                    .foregroundColor(Color(hex: "#3DFF8F"))
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(Color(hex: "#111115"))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(hex: "#1E1E26"), lineWidth: 1))
    }

    @ViewBuilder
    private func statusIcon(_ status: PackageStatus) -> some View {
        switch status {
        case .installing:
            Image(systemName: "arrow.down.circle")
                .font(.system(size: 11))
                .foregroundColor(Color(hex: "#4A9EFF"))
        case .installed:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 11))
                .foregroundColor(Color(hex: "#3DFF8F"))
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 11))
                .foregroundColor(Color(hex: "#FF4D6A"))
        case .warning:
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 11))
                .foregroundColor(Color(hex: "#FFD060"))
        }
    }

    private func statusTextColor(_ status: PackageStatus) -> Color {
        switch status {
        case .installing: return Color(hex: "#D8E4F0")
        case .installed:  return Color(hex: "#D8E4F0")
        case .failed:     return Color(hex: "#FF4D6A")
        case .warning:    return Color(hex: "#FFD060")
        }
    }
}
```

- [ ] Step 2: Build.

```bash
xcodebuild build \
  -scheme Mosaic \
  -destination 'generic/platform=iOS Simulator' \
  2>&1 | grep -E "error:|warning:|BUILD"
```

- [ ] Step 3: Commit.

```bash
git add "Sources/Mosaic/Rendering/Renderers/NpmInstallRenderer.swift"
git commit -m "feat: add NpmInstallRenderer — package install progress for npm/pip/apt"
```

---

### Task 6: JsonTreeRenderer

**Files:** Create: `Sources/Mosaic/Rendering/Renderers/JsonTreeRenderer.swift`

- [ ] Step 1: Create `JsonTreeRenderer.swift`.

```swift
import SwiftUI

// MARK: - JsonTreeRenderer
//
// Renders: jq output, cat *.json, any command whose output is valid JSON
// Trigger: command starts with "jq", OR output starts with { or [ and is valid JSON

@MainActor
public final class JsonTreeRenderer: OutputRenderer {
    public let id          = "data.json"
    public let displayName = "JSON Tree"
    public let badgeLabel  = "JSON"
    public let priority    = RendererPriority.data

    public func canRender(command: String, output: String) -> Bool {
        let cmd = command.lowercased()
        if cmd.hasPrefix("jq") { return true }
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        return (trimmed.hasPrefix("{") || trimmed.hasPrefix("["))
            && JSONSerialization.isValidJSONObject(
                (try? JSONSerialization.jsonObject(with: Data(trimmed.utf8))) ?? NSNull()
            )
    }

    public func parse(command: String, output: String) -> (any RendererData)? {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = trimmed.data(using: .utf8),
              let raw = try? JSONSerialization.jsonObject(with: data, options: [])
        else { return nil }

        let root = JsonNode(from: raw)
        return JsonTreeData(root: root)
    }

    public func view(for data: any RendererData) -> AnyView {
        guard let data = data as? JsonTreeData else { return AnyView(EmptyView()) }
        return AnyView(JsonTreeView(data: data))
    }
}

// MARK: - Data Models

public indirect enum JsonNode: Sendable {
    case object([(key: String, value: JsonNode)])
    case array([JsonNode])
    case string(String)
    case number(Double)
    case bool(Bool)
    case null

    init(from value: Any) {
        switch value {
        case let dict as [String: Any]:
            self = .object(dict.sorted(by: { $0.key < $1.key }).map { ($0.key, JsonNode(from: $0.value)) })
        case let arr as [Any]:
            self = .array(arr.map { JsonNode(from: $0) })
        case let str as String:
            self = .string(str)
        case let num as NSNumber:
            // Distinguish bool from number
            if num === kCFBooleanTrue || num === kCFBooleanFalse {
                self = .bool(num.boolValue)
            } else {
                self = .number(num.doubleValue)
            }
        default:
            self = .null
        }
    }

    var countBadge: String? {
        switch self {
        case .object(let pairs): return "{\(pairs.count)}"
        case .array(let items):  return "[\(items.count)]"
        default:                 return nil
        }
    }
}

public struct JsonTreeData: RendererData {
    public let root: JsonNode
}

// MARK: - View

private struct JsonTreeView: View {
    let data: JsonTreeData

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 8) {
                Image(systemName: "curlybraces")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Color(hex: "#00D4AA"))
                Text("JSON")
                    .font(.custom("JetBrains Mono", size: 11.5).weight(.semibold))
                    .foregroundColor(Color(hex: "#D8E4F0"))
                Spacer()
                if let badge = data.root.countBadge {
                    Text(badge)
                        .font(.custom("JetBrains Mono", size: 9))
                        .foregroundColor(Color(hex: "#3A4A58"))
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 9)

            Divider().overlay(Color(hex: "#141418"))

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    JsonNodeView(node: data.root, key: nil, depth: 0, autoExpand: true)
                }
                .padding(12)
            }
            .frame(maxHeight: 400)
        }
        .background(Color(hex: "#111115"))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(hex: "#1E1E26"), lineWidth: 1))
    }
}

private struct JsonNodeView: View {
    let node:       JsonNode
    let key:        String?
    let depth:      Int
    let autoExpand: Bool

    @State private var isExpanded: Bool = false

    init(node: JsonNode, key: String?, depth: Int, autoExpand: Bool) {
        self.node       = node
        self.key        = key
        self.depth      = depth
        self.autoExpand = autoExpand
        // Auto-expand root and depth 1; collapse deeper by default
        _isExpanded = State(initialValue: autoExpand && depth < 2)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            switch node {
            case .object(let pairs):
                collapsibleRow(badge: "{\(pairs.count)}", badgeColor: Color(hex: "#A78BFA")) {
                    ForEach(Array(pairs.enumerated()), id: \.offset) { _, pair in
                        JsonNodeView(node: pair.value, key: pair.key,
                                     depth: depth + 1, autoExpand: false)
                            .padding(.leading, 16)
                    }
                }

            case .array(let items):
                collapsibleRow(badge: "[\(items.count)]", badgeColor: Color(hex: "#4A9EFF")) {
                    ForEach(Array(items.enumerated()), id: \.offset) { idx, item in
                        JsonNodeView(node: item, key: "\(idx)",
                                     depth: depth + 1, autoExpand: false)
                            .padding(.leading, 16)
                    }
                }

            case .string(let s):
                leafRow(value: "\"\(s)\"", valueColor: Color(hex: "#3DFF8F"))

            case .number(let n):
                let display = n.truncatingRemainder(dividingBy: 1) == 0
                    ? String(format: "%.0f", n) : String(n)
                leafRow(value: display, valueColor: Color(hex: "#4A9EFF"))

            case .bool(let b):
                leafRow(value: b ? "true" : "false", valueColor: Color(hex: "#FFD060"))

            case .null:
                leafRow(value: "null", valueColor: Color(hex: "#FF4D6A"))
            }
        }
    }

    @ViewBuilder
    private func collapsibleRow(badge: String, badgeColor: Color,
                                @ViewBuilder children: () -> some View) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) { isExpanded.toggle() }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(Color(hex: "#3A4A58"))
                    .frame(width: 10)

                if let k = key {
                    Text(k)
                        .font(.custom("JetBrains Mono", size: 10))
                        .foregroundColor(Color(hex: "#3A4A58"))
                    Text(":")
                        .font(.custom("JetBrains Mono", size: 10))
                        .foregroundColor(Color(hex: "#1E1E26"))
                }

                Text(badge)
                    .font(.custom("JetBrains Mono", size: 9).weight(.bold))
                    .foregroundColor(badgeColor)
                    .padding(.horizontal, 4).padding(.vertical, 1)
                    .background(badgeColor.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 3))

                Spacer()
            }
            .padding(.vertical, 3)
        }
        .buttonStyle(.plain)

        if isExpanded {
            children()
        }
    }

    @ViewBuilder
    private func leafRow(value: String, valueColor: Color) -> some View {
        HStack(spacing: 4) {
            Rectangle().fill(Color.clear).frame(width: 14)

            if let k = key {
                Text(k)
                    .font(.custom("JetBrains Mono", size: 10))
                    .foregroundColor(Color(hex: "#3A4A58"))
                Text(":")
                    .font(.custom("JetBrains Mono", size: 10))
                    .foregroundColor(Color(hex: "#1E1E26"))
            }

            Text(value)
                .font(.custom("JetBrains Mono", size: 10))
                .foregroundColor(valueColor)
                .lineLimit(3)
                .truncationMode(.tail)

            Spacer()
        }
        .padding(.vertical, 3)
    }
}
```

- [ ] Step 2: Build.

```bash
xcodebuild build \
  -scheme Mosaic \
  -destination 'generic/platform=iOS Simulator' \
  2>&1 | grep -E "error:|warning:|BUILD"
```

- [ ] Step 3: Commit.

```bash
git add "Sources/Mosaic/Rendering/Renderers/JsonTreeRenderer.swift"
git commit -m "feat: add JsonTreeRenderer — collapsible tree view for JSON output"
```

---

### Task 7: GitDiffRenderer

**Files:** Create: `Sources/Mosaic/Rendering/Renderers/GitDiffRenderer.swift`

- [ ] Step 1: Create `GitDiffRenderer.swift`.

```swift
import SwiftUI

// MARK: - GitDiffRenderer
//
// Renders: git diff, git diff --cached, git diff HEAD
// Trigger: command starts with "git diff" OR output starts with "diff --git"
// Output shape: standard unified diff format

@MainActor
public final class GitDiffRenderer: OutputRenderer {
    public let id          = "git.diff"
    public let displayName = "Git Diff"
    public let badgeLabel  = "GIT DIFF"
    public let priority    = RendererPriority.git

    public func canRender(command: String, output: String) -> Bool {
        let cmd = command.lowercased()
        let triggersOnCommand = cmd.hasPrefix("git diff")
        let triggersOnOutput  = output.hasPrefix("diff --git")
        return triggersOnCommand || triggersOnOutput
    }

    public func parse(command: String, output: String) -> (any RendererData)? {
        // Split on "diff --git" boundaries
        let fileChunks = output.components(separatedBy: "\ndiff --git ")
            .enumerated()
            .map { idx, chunk in
                idx == 0 && chunk.hasPrefix("diff --git ")
                    ? String(chunk.dropFirst("diff --git ".count))
                    : chunk
            }
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

        guard !fileChunks.isEmpty else { return nil }

        var files: [DiffFile] = []

        for chunk in fileChunks {
            let chunkLines = chunk.components(separatedBy: "\n")
            guard !chunkLines.isEmpty else { continue }

            // First line: "a/oldpath b/newpath"
            let firstLine  = chunkLines[0]
            let pathParts  = firstLine.components(separatedBy: " b/")
            let oldPath = pathParts.first.map { $0.hasPrefix("a/") ? String($0.dropFirst(2)) : $0 } ?? firstLine
            let newPath = pathParts.count > 1 ? pathParts[1] : oldPath

            var hunks: [DiffHunk] = []
            var currentHunkHeader = ""
            var currentLines: [DiffLine] = []

            for line in chunkLines[1...] {
                if line.hasPrefix("@@") {
                    // Save the previous hunk if it has content
                    if !currentLines.isEmpty || !currentHunkHeader.isEmpty {
                        hunks.append(DiffHunk(header: currentHunkHeader, lines: currentLines))
                    }
                    currentHunkHeader = line
                    currentLines = []
                } else if line.hasPrefix("+") && !line.hasPrefix("+++") {
                    currentLines.append(DiffLine(type: .added,   content: String(line.dropFirst())))
                } else if line.hasPrefix("-") && !line.hasPrefix("---") {
                    currentLines.append(DiffLine(type: .removed, content: String(line.dropFirst())))
                } else if line.hasPrefix(" ") {
                    currentLines.append(DiffLine(type: .context, content: String(line.dropFirst())))
                }
                // Skip --- / +++ / index / binary lines
            }

            // Save last hunk
            if !currentLines.isEmpty || !currentHunkHeader.isEmpty {
                hunks.append(DiffHunk(header: currentHunkHeader, lines: currentLines))
            }

            guard !hunks.isEmpty else { continue }
            files.append(DiffFile(oldPath: oldPath, newPath: newPath, hunks: hunks))
        }

        guard !files.isEmpty else { return nil }
        return GitDiffData(files: files)
    }

    public func view(for data: any RendererData) -> AnyView {
        guard let data = data as? GitDiffData else { return AnyView(EmptyView()) }
        return AnyView(GitDiffView(data: data))
    }
}

// MARK: - Data Models

public struct GitDiffData: RendererData {
    public let files: [DiffFile]
}

public struct DiffFile: Identifiable, Sendable {
    public let id = UUID()
    public let oldPath: String
    public let newPath: String
    public let hunks: [DiffHunk]

    public var addedCount: Int   { hunks.flatMap(\.lines).filter { $0.type == .added }.count }
    public var removedCount: Int { hunks.flatMap(\.lines).filter { $0.type == .removed }.count }
    public var displayName: String { newPath == oldPath ? newPath : "\(oldPath) → \(newPath)" }
}

public struct DiffHunk: Identifiable, Sendable {
    public let id = UUID()
    public let header: String
    public let lines: [DiffLine]
}

public struct DiffLine: Identifiable, Sendable {
    public let id = UUID()
    public let type: DiffLineType
    public let content: String
}

public enum DiffLineType: Sendable {
    case added, removed, context
}

// MARK: - View

private struct GitDiffView: View {
    let data: GitDiffData

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 8) {
                Image(systemName: "arrow.left.arrow.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Color(hex: "#00D4AA"))
                Text("Git Diff")
                    .font(.custom("JetBrains Mono", size: 11.5).weight(.semibold))
                    .foregroundColor(Color(hex: "#D8E4F0"))
                Spacer()
                Text("\(data.files.count) file\(data.files.count == 1 ? "" : "s")")
                    .font(.custom("JetBrains Mono", size: 9))
                    .foregroundColor(Color(hex: "#3A4A58"))
            }
            .padding(.horizontal, 12).padding(.vertical, 9)

            Divider().overlay(Color(hex: "#141418"))

            ForEach(data.files) { file in
                DiffFileView(file: file)
                Divider().overlay(Color(hex: "#141418"))
            }
        }
        .background(Color(hex: "#111115"))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(hex: "#1E1E26"), lineWidth: 1))
    }
}

private struct DiffFileView: View {
    let file: DiffFile
    @State private var isExpanded = true

    var body: some View {
        VStack(spacing: 0) {
            // File header row
            Button {
                withAnimation(.easeInOut(duration: 0.15)) { isExpanded.toggle() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(Color(hex: "#3A4A58"))

                    Text(file.displayName)
                        .font(.custom("JetBrains Mono", size: 10.5))
                        .foregroundColor(Color(hex: "#D8E4F0"))
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Spacer()

                    // +N -M badges
                    if file.addedCount > 0 {
                        Text("+\(file.addedCount)")
                            .font(.custom("JetBrains Mono", size: 8.5).weight(.bold))
                            .foregroundColor(Color(hex: "#3DFF8F"))
                            .padding(.horizontal, 5).padding(.vertical, 2)
                            .background(Color(hex: "#3DFF8F").opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                    }
                    if file.removedCount > 0 {
                        Text("-\(file.removedCount)")
                            .font(.custom("JetBrains Mono", size: 8.5).weight(.bold))
                            .foregroundColor(Color(hex: "#FF4D6A"))
                            .padding(.horizontal, 5).padding(.vertical, 2)
                            .background(Color(hex: "#FF4D6A").opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                    }
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
            }
            .buttonStyle(.plain)

            if isExpanded {
                ForEach(file.hunks) { hunk in
                    DiffHunkView(hunk: hunk)
                }
            }
        }
    }
}

private struct DiffHunkView: View {
    let hunk: DiffHunk

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Hunk header "@@ -L,N +L,N @@"
            Text(hunk.header)
                .font(.custom("JetBrains Mono", size: 9))
                .foregroundColor(Color(hex: "#3A4A58"))
                .padding(.horizontal, 12).padding(.vertical, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(hex: "#17171C"))

            ForEach(hunk.lines) { line in
                DiffLineView(line: line)
            }
        }
    }
}

private struct DiffLineView: View {
    let line: DiffLine

    private var prefix: String {
        switch line.type {
        case .added:   return "+"
        case .removed: return "-"
        case .context: return " "
        }
    }

    private var textColor: Color {
        switch line.type {
        case .added:   return Color(hex: "#3DFF8F")
        case .removed: return Color(hex: "#FF4D6A")
        case .context: return Color(hex: "#D8E4F0").opacity(0.6)
        }
    }

    private var bgColor: Color {
        switch line.type {
        case .added:   return Color(hex: "#3DFF8F").opacity(0.06)
        case .removed: return Color(hex: "#FF4D6A").opacity(0.06)
        case .context: return .clear
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            Text(prefix)
                .font(.custom("JetBrains Mono", size: 10))
                .foregroundColor(textColor)
                .frame(width: 10)

            Text(line.content)
                .font(.custom("JetBrains Mono", size: 10))
                .foregroundColor(textColor)
                .lineLimit(3)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 12).padding(.vertical, 2)
        .background(bgColor)
    }
}
```

- [ ] Step 2: Build.

```bash
xcodebuild build \
  -scheme Mosaic \
  -destination 'generic/platform=iOS Simulator' \
  2>&1 | grep -E "error:|warning:|BUILD"
```

- [ ] Step 3: Commit.

```bash
git add "Sources/Mosaic/Rendering/Renderers/GitDiffRenderer.swift"
git commit -m "feat: add GitDiffRenderer — collapsible per-file diff view for git diff"
```

---

### Task 8: CronRenderer

**Files:** Create: `Sources/Mosaic/Rendering/Renderers/CronRenderer.swift`

- [ ] Step 1: Create `CronRenderer.swift`.

```swift
import SwiftUI

// MARK: - CronRenderer
//
// Renders: crontab -l
// Trigger: command starts with "crontab"
// Output shape: lines of cron expressions + commands, plus comments

@MainActor
public final class CronRenderer: OutputRenderer {
    public let id          = "system.cron"
    public let displayName = "Cron Schedule"
    public let badgeLabel  = "CRON"
    public let priority    = RendererPriority.system

    public func canRender(command: String, output: String) -> Bool {
        command.lowercased().hasPrefix("crontab")
    }

    public func parse(command: String, output: String) -> (any RendererData)? {
        let lines = output.components(separatedBy: "\n")
        var entries: [CronEntry] = []

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }

            if trimmed.hasPrefix("#") {
                entries.append(CronEntry(
                    schedule:      "",
                    command:       String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces),
                    humanReadable: "",
                    isComment:     true,
                    nextRunApprox: nil
                ))
                continue
            }

            // Split on whitespace — first 5 tokens are the schedule fields
            let parts = trimmed.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
            guard parts.count >= 6 else { continue }

            let scheduleFields = Array(parts[0..<5])
            let command        = parts[5...].joined(separator: " ")
            let scheduleStr    = scheduleFields.joined(separator: " ")
            let humanReadable  = humanReadableSchedule(fields: scheduleFields)

            entries.append(CronEntry(
                schedule:      scheduleStr,
                command:       command,
                humanReadable: humanReadable,
                isComment:     false,
                nextRunApprox: nil
            ))
        }

        guard !entries.isEmpty else { return nil }
        return CronData(entries: entries)
    }

    // MARK: Human-readable schedule conversion
    private func humanReadableSchedule(fields: [String]) -> String {
        guard fields.count == 5 else { return fields.joined(separator: " ") }
        let min  = fields[0]
        let hour = fields[1]
        let dom  = fields[2]
        let mon  = fields[3]
        let dow  = fields[4]

        // Common patterns
        if min == "*" && hour == "*" && dom == "*" && mon == "*" && dow == "*" {
            return "Every minute"
        }
        if min.hasPrefix("*/") && hour == "*" && dom == "*" && mon == "*" && dow == "*" {
            let n = String(min.dropFirst(2))
            return "Every \(n) minute\(n == "1" ? "" : "s")"
        }
        if hour.hasPrefix("*/") && min == "0" && dom == "*" && mon == "*" && dow == "*" {
            let n = String(hour.dropFirst(2))
            return "Every \(n) hour\(n == "1" ? "" : "s")"
        }
        if min != "*" && hour != "*" && dom == "*" && mon == "*" && dow == "*" {
            let h = Int(hour) ?? 0
            let m = Int(min)  ?? 0
            let period = h < 12 ? "AM" : "PM"
            let h12    = h == 0 ? 12 : h > 12 ? h - 12 : h
            return String(format: "Daily at %d:%02d %@", h12, m, period)
        }
        if dow != "*" && dom == "*" {
            let dayNames = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
            if let d = Int(dow), d < 7 {
                let h = Int(hour) ?? 0
                let m = Int(min)  ?? 0
                let period = h < 12 ? "AM" : "PM"
                let h12    = h == 0 ? 12 : h > 12 ? h - 12 : h
                return String(format: "Every %@ at %d:%02d %@", dayNames[d], h12, m, period)
            }
        }
        if dom != "*" && dow == "*" {
            let h = Int(hour) ?? 0
            let m = Int(min)  ?? 0
            let period = h < 12 ? "AM" : "PM"
            let h12    = h == 0 ? 12 : h > 12 ? h - 12 : h
            return String(format: "Monthly on day %@ at %d:%02d %@", dom, h12, m, period)
        }
        if min == "0" && hour == "0" && dom == "1" && mon == "*" && dow == "*" {
            return "First of every month at midnight"
        }
        // Fallback to raw
        return fields.joined(separator: " ")
    }

    public func view(for data: any RendererData) -> AnyView {
        guard let data = data as? CronData else { return AnyView(EmptyView()) }
        return AnyView(CronView(data: data))
    }
}

// MARK: - Data Models

public struct CronData: RendererData {
    public let entries: [CronEntry]
}

public struct CronEntry: Identifiable, Sendable {
    public let id = UUID()
    public let schedule:      String
    public let command:       String
    public let humanReadable: String
    public let isComment:     Bool
    public let nextRunApprox: String?
}

// MARK: - View

private struct CronView: View {
    let data: CronData

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 8) {
                Image(systemName: "clock.arrow.2.circlepath")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Color(hex: "#00D4AA"))
                Text("Cron Schedule")
                    .font(.custom("JetBrains Mono", size: 11.5).weight(.semibold))
                    .foregroundColor(Color(hex: "#D8E4F0"))
                Spacer()
                let jobCount = data.entries.filter { !$0.isComment }.count
                Text("\(jobCount) job\(jobCount == 1 ? "" : "s")")
                    .font(.custom("JetBrains Mono", size: 9))
                    .foregroundColor(Color(hex: "#3A4A58"))
            }
            .padding(.horizontal, 12).padding(.vertical, 9)

            Divider().overlay(Color(hex: "#141418"))

            ForEach(Array(data.entries.enumerated()), id: \.element.id) { index, entry in
                if entry.isComment {
                    CronCommentRow(entry: entry)
                } else {
                    CronJobRow(entry: entry)
                }
                if index < data.entries.count - 1 {
                    Divider().overlay(Color(hex: "#141418"))
                }
            }
        }
        .background(Color(hex: "#111115"))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(hex: "#1E1E26"), lineWidth: 1))
    }
}

private struct CronJobRow: View {
    let entry: CronEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Human-readable schedule in accent color
            Text(entry.humanReadable)
                .font(.custom("JetBrains Mono", size: 10.5).weight(.semibold))
                .foregroundColor(Color(hex: "#00D4AA"))

            // Raw cron expression
            Text(entry.schedule)
                .font(.custom("JetBrains Mono", size: 9))
                .foregroundColor(Color(hex: "#3A4A58"))

            // Command in mono
            Text(entry.command)
                .font(.custom("JetBrains Mono", size: 10))
                .foregroundColor(Color(hex: "#D8E4F0"))
                .lineLimit(2)
                .truncationMode(.tail)

            if let next = entry.nextRunApprox {
                Text("Next: \(next)")
                    .font(.custom("JetBrains Mono", size: 9))
                    .foregroundColor(Color(hex: "#3A4A58"))
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
    }
}

private struct CronCommentRow: View {
    let entry: CronEntry

    var body: some View {
        HStack(spacing: 6) {
            Text("#")
                .font(.custom("JetBrains Mono", size: 10).weight(.bold))
                .foregroundColor(Color(hex: "#3A4A58"))
            Text(entry.command)
                .font(.custom("JetBrains Mono", size: 10))
                .foregroundColor(Color(hex: "#3A4A58"))
            Spacer()
        }
        .padding(.horizontal, 12).padding(.vertical, 7)
    }
}
```

- [ ] Step 2: Build.

```bash
xcodebuild build \
  -scheme Mosaic \
  -destination 'generic/platform=iOS Simulator' \
  2>&1 | grep -E "error:|warning:|BUILD"
```

- [ ] Step 3: Commit.

```bash
git add "Sources/Mosaic/Rendering/Renderers/CronRenderer.swift"
git commit -m "feat: add CronRenderer — human-readable schedule cards for crontab -l"
```

---

### Task 9: Register All 8 Renderers in RendererRegistry

**Files:** Modify: `Sources/Mosaic/Rendering/RendererRegistry.swift`

- [ ] Step 1: Update `registerBuiltins()` to register all 8 new renderers. Replace the comment block with live `register()` calls.

The current `registerBuiltins()` in `RendererRegistry.swift` (lines 96–110) reads:

```swift
private func registerBuiltins() {
    register(DockerPsRenderer())
    register(GitStatusRenderer())
    register(FileListRenderer())
    // Phase 2 renderers registered here as they're built:
    // register(PingRenderer())
    // register(DiskUsageRenderer())
    // register(HttpResponseRenderer())
    // register(NpmInstallRenderer())
    // register(JsonTreeRenderer())
    // register(CronRenderer())
    // register(ProcessTableRenderer())
    // register(GitDiffRenderer())
    // register(GitLogRenderer())
}
```

Replace it with:

```swift
private func registerBuiltins() {
    // Phase 1 renderers
    register(DockerPsRenderer())
    register(GitStatusRenderer())
    register(FileListRenderer())

    // Phase 2 renderers
    register(PingRenderer())
    register(DiskUsageRenderer())
    register(HttpResponseRenderer())
    register(ProcessTableRenderer())
    register(NpmInstallRenderer())
    register(JsonTreeRenderer())
    register(GitDiffRenderer())
    register(CronRenderer())
}
```

- [ ] Step 2: Build — confirm all 8 renderers compile and register cleanly.

```bash
xcodebuild build \
  -scheme Mosaic \
  -destination 'generic/platform=iOS Simulator' \
  2>&1 | grep -E "error:|warning:|BUILD"
```

Confirm output ends with `** BUILD SUCCEEDED **`.

- [ ] Step 3: Run the test suite and confirm all tests pass.

```bash
xcodebuild test \
  -scheme Mosaic \
  -destination 'platform=iOS Simulator,name=iPhone 15 Pro' \
  2>&1 | grep -E "Test Suite|passed|failed|BUILD"
```

- [ ] Step 4: Commit.

```bash
git add "Sources/Mosaic/Rendering/RendererRegistry.swift"
git commit -m "feat: register 8 new Phase 2 renderers in RendererRegistry"
```

---

## Completion Checklist

Before declaring this plan complete:

- [ ] All 8 renderer files exist in `Sources/Mosaic/Rendering/Renderers/`
- [ ] Each renderer: `canRender()` returns false for non-matching commands, `parse()` returns nil for non-matching output
- [ ] `RendererRegistry.registerBuiltins()` calls `register()` for all 8
- [ ] `** BUILD SUCCEEDED **` confirmed with no errors
- [ ] All existing tests still pass
- [ ] No hardcoded hex strings that aren't in the project color palette
- [ ] No emoji in production code (emoji are used in the design doc only — replace with SF Symbols)
- [ ] All `Sendable` conformances are correct (no mutable shared state escaping to other actors)
