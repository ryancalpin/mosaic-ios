import Testing
import SwiftUI
@testable import Mosaic

@Suite("RendererRegistry")
@MainActor
struct RendererRegistryTests {

    // MARK: - Alias resolution

    @Test func aliasResolvesDockerPs() {
        let registry = RendererRegistry.shared
        registry.updateAliases(from: "dps='docker ps'")
        let result = registry.process(command: "dps", output: dockerPsSampleOutput)
        guard case .native(let r, _, _) = result else {
            Issue.record("Expected native result for aliased 'dps', got raw")
            return
        }
        #expect(r.id == "docker.ps")
    }

    @Test func aliasDoubleQuote() {
        let registry = RendererRegistry.shared
        registry.updateAliases(from: #"gst="git status""#)
        let result = registry.process(command: "gst", output: gitStatusSampleOutput)
        guard case .native(let r, _, _) = result else {
            Issue.record("Expected native result for aliased 'gst'")
            return
        }
        #expect(r.id == "git.status")
    }

    @Test func aliasClearedOnUpdate() {
        let registry = RendererRegistry.shared
        registry.updateAliases(from: "dps='docker ps'")
        registry.updateAliases(from: "")   // clear
        // "dps" is no longer an alias — verify by using output that won't match any heuristic
        let clearResult = registry.process(command: "dps", output: "hello world")
        guard case .raw = clearResult else {
            Issue.record("After alias clear, unrecognized command should produce raw output")
            return
        }
    }

    // MARK: - Empty output → always raw

    @Test func emptyOutputIsRaw() {
        let result = RendererRegistry.shared.process(command: "docker ps", output: "")
        guard case .raw = result else { Issue.record("Empty output should be raw"); return }
    }

    @Test func whitespaceOnlyOutputIsRaw() {
        let result = RendererRegistry.shared.process(command: "docker ps", output: "   \n  ")
        guard case .raw = result else { Issue.record("Whitespace-only output should be raw"); return }
    }

    // MARK: - RendererResult helpers

    @Test func nativeResultRawText() {
        let result = RendererRegistry.shared.process(command: "docker ps", output: dockerPsSampleOutput)
        #expect(result.rawText == dockerPsSampleOutput)
    }

    @Test func rawResultIsNativeFalse() {
        let result = RendererResult.raw("hello")
        #expect(!result.isNative)
        #expect(result.rawText == "hello")
    }

    // MARK: - Fallthrough to raw for unknown command

    @Test func unknownCommandFallsThrough() {
        let result = RendererRegistry.shared.process(command: "foobar-custom-cmd", output: "some unrecognized output without special markers")
        guard case .raw = result else { Issue.record("Unrecognized command+output should be raw"); return }
    }

    // MARK: - Register / unregister

    @Test func registerCustomRenderer() {
        let registry = RendererRegistry.shared
        let before = registry.renderers.count
        let stub = StubRenderer(rendererID: "test.stub.register")
        registry.register(stub)
        #expect(registry.renderers.count == before + 1)
        registry.unregister(id: "test.stub.register")
        #expect(registry.renderers.count == before)
    }

    @Test func priorityOrderMaintained() {
        let registry = RendererRegistry.shared
        let high = StubRenderer(rendererID: "test.high", priority: 9999)
        let low  = StubRenderer(rendererID: "test.low",  priority: 1)
        registry.register(low)
        registry.register(high)
        let ids = registry.renderers.prefix(5).map(\.id)
        // high priority should appear before low priority
        let highIdx = ids.firstIndex(of: "test.high") ?? Int.max
        let lowIdx  = ids.firstIndex(of: "test.low")  ?? Int.max
        #expect(highIdx < lowIdx)
        registry.unregister(id: "test.high")
        registry.unregister(id: "test.low")
    }
}

// MARK: - Fixtures

let dockerPsSampleOutput = """
CONTAINER ID   IMAGE          COMMAND                  CREATED         STATUS         PORTS                    NAMES
a1b2c3d4e5f6   nginx:latest   "/docker-entrypoint.…"   2 hours ago     Up 2 hours     0.0.0.0:80->80/tcp       web
b2c3d4e5f6a1   postgres:15    "docker-entrypoint.s…"   3 hours ago     Up 3 hours     0.0.0.0:5432->5432/tcp   db
"""

let gitStatusSampleOutput = """
On branch main
Your branch is up to date with 'origin/main'.

Changes not staged for commit:
  (use "git add <file>..." to update what will be committed)
	modified:   Sources/Mosaic/App/MosaicApp.swift

nothing added to commit but untracked files present
"""

// MARK: - Stub renderer for tests

@MainActor
final class StubRenderer: OutputRenderer {
    let id: String
    let displayName = "Stub"
    let badgeLabel  = "STUB"
    let priority:    Int

    init(rendererID: String, priority: Int = 500) {
        self.id = rendererID
        self.priority = priority
    }

    func canRender(command: String, output: String) -> Bool { false }
    func parse(command: String, output: String) -> (any RendererData)? { nil }
    func view(for data: any RendererData) -> AnyView { AnyView(EmptyView()) }
}
