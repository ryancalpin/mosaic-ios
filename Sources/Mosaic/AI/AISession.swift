import Foundation
import SwiftUI

@MainActor
final class AISession: ObservableObject {
    @Published var messages:        [AIMessage]     = []
    @Published var isThinking:      Bool            = false
    @Published var inputText:       String          = ""
    @Published var connectionState: ConnectionState = .disconnected
    @Published var pendingCommand:  String?         = nil
    @Published var pendingTier:     SafetyTier      = .safe

    private let connection: SSHConnection
    private let client:     ClaudeClient
    private let apiKey:     String
    private var outputTask: Task<Void, Never>?
    private var serverOS   = "Linux"

    private static let doneMarker = "__MOSAIC_DONE__"

    init(mirroring session: Session, apiKey: String) {
        self.apiKey     = apiKey
        self.connection = SSHConnection(connectionInfo: session.connection.connectionInfo)
        self.client     = ClaudeClient(apiKey: apiKey)
    }

    // MARK: - Lifecycle

    func connect() async {
        do {
            connectionState = .connecting
            try await connection.connect()
            connectionState = .connected
            startOutputDrain()
            try? await connection.send("uname -s\necho \"__MOSAIC_DONE__\"\n")
        } catch {
            connectionState = .error(error.localizedDescription)
        }
    }

    func disconnect() async {
        outputTask?.cancel()
        outputTask = nil
        await connection.disconnect()
        connectionState = .disconnected
    }

    // MARK: - Submit

    func submit(userInput: String, from session: Session) async {
        guard !userInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        guard !apiKey.isEmpty else {
            messages.append(AIMessage(role: .error, text: "No API key configured. Set one in Settings."))
            return
        }

        messages.append(AIMessage(role: .user, text: userInput))
        isThinking = true

        let ctx = ClaudeClient.TranslationContext(
            hostname:         session.connection.connectionInfo.hostname,
            username:         session.connection.connectionInfo.username,
            currentDirectory: session.currentDirectory,
            recentCommands:   session.blocks.suffix(20).map(\.command),
            serverOS:         serverOS
        )

        do {
            let command    = try await client.translateToCommand(userInput, context: ctx)
            let thinkStart = Date()

            messages.append(AIMessage(role: .thinking, text: "Running: \(command)", command: command))

            let elapsed = Date().timeIntervalSince(thinkStart)
            if elapsed < 0.8 {
                try? await Task.sleep(nanoseconds: UInt64((0.8 - elapsed) * 1_000_000_000))
            }

            isThinking   = false
            pendingTier  = SafetyClassifier.shared.classify(command)
            pendingCommand = command

        } catch {
            isThinking = false
            messages.append(AIMessage(role: .error, text: "Failed to get command: \(error.localizedDescription)"))
        }
    }

    // MARK: - Execute Approved

    func executeApproved(_ command: String) async {
        pendingCommand = nil
        let fullCmd = command + "\ntrue\necho \"__MOSAIC_DONE__\"\n"
        do {
            try await connection.send(fullCmd)
        } catch {
            messages.append(AIMessage(role: .error, text: "Send failed: \(error.localizedDescription)"))
        }
    }

    // MARK: - Output Drain

    private func startOutputDrain() {
        outputTask?.cancel()
        outputTask = Task { [weak self] in
            guard let self else { return }
            var buffer = ""
            for await data in self.connection.outputStream {
                guard !Task.isCancelled else { break }
                guard let text = String(data: data, encoding: .utf8)
                              ?? String(data: data, encoding: .isoLatin1) else { continue }
                buffer += text

                let lines = buffer.components(separatedBy: "\n")
                if lines.contains("Linux")  { self.serverOS = "Linux" }
                if lines.contains("Darwin") { self.serverOS = "Darwin" }

                let hasDone = lines.contains { $0.trimmingCharacters(in: .whitespacesAndNewlines) == Self.doneMarker }
                guard hasDone else { continue }

                let clean = buffer.strippingANSI
                    .components(separatedBy: "\n")
                    .filter { line in
                        let t = line.trimmingCharacters(in: .whitespacesAndNewlines)
                        return t != Self.doneMarker
                            && !t.hasPrefix("__MOSAIC")
                            && !t.hasPrefix("echo ")
                            && !t.hasPrefix("uname")
                            && !["Linux", "Darwin"].contains(t)
                    }
                    .joined(separator: "\n")
                    .trimmingCharacters(in: .whitespacesAndNewlines)

                buffer = ""

                guard let thinkMsg = self.messages.last(where: { $0.role == .thinking }),
                      let command  = thinkMsg.command,
                      !clean.isEmpty else { continue }

                let rendererResult = RendererRegistry.shared.process(command: command, output: clean)
                self.messages.append(
                    AIMessage(role: .result, text: clean, command: command, rendererResult: rendererResult)
                )
            }
        }
    }
}
