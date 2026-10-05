#if os(macOS)
import Foundation
import Testing
import KissmarkConnections
@testable import Kissmark

@MainActor
struct AgentConnectionTests {
    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
    @Test("Only explicitly added connections appear and their selection survives relaunch")
    func selectedRows() async throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let store = ConnectionSelectionStore(file: root.appendingPathComponent("selections.json"))
        let id = UUID()
        let claude = SelectionKey(client: .claudeCode), omp = SelectionKey(client: .omp, profile: "work")
        let snapshot = DiscoverySnapshot(installationID: id, candidates: [DiscoveryCandidate(key: claude), DiscoveryCandidate(key: omp)])
        let fetch: @Sendable (BrokerRequest) async throws -> BrokerReply = { BrokerReply(id: $0.id, snapshot: snapshot) }
        let model = AgentConnectionsModel(store: store, fetch: fetch)
        await model.refresh()
        #expect(model.rows.isEmpty)
        model.add(claude); model.add(omp); model.add(claude)
        #expect(Set(model.rows) == [claude, omp])
        let relaunched = AgentConnectionsModel(store: store, fetch: fetch)
        await relaunched.refresh()
        #expect(Set(relaunched.rows) == [claude, omp])
        relaunched.remove(claude)
        #expect(store.load(for: id) == [omp])
        #expect(store.load(for: UUID()).isEmpty)
    }
    @Test("Detection alone is never connected and unavailable discovery does not invent a session")
    func detectionIsNotConnection() async throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let key = SelectionKey(client: .codex)
        let snapshot = DiscoverySnapshot(installationID: UUID(), candidates: [DiscoveryCandidate(key: key, instance: "thread-one", runtime: .loaded)], providers: [ProviderOutcome(client: .codex, status: .available)])
        let model = AgentConnectionsModel(store: ConnectionSelectionStore(file: root.appendingPathComponent("state.json")), fetch: { BrokerReply(id: $0.id, snapshot: snapshot) })
        await model.refresh(); model.add(key)
        #expect(model.state(for: key) == .loaded)
        let missing = AgentConnectionsModel(store: ConnectionSelectionStore(file: root.appendingPathComponent("state.json")), fetch: { _ in throw ConnectionFailure.unavailable })
        await missing.refresh()
        #expect(missing.rows.isEmpty)
        #expect(!missing.serviceAvailable)
    }
    @Test("Generated installation commands preserve hostile paths and require the selected scope")
    func installationCommandArguments() throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let helper = root.appendingPathComponent("helper ' $(touch should-not-exist)")
        let project = root.appendingPathComponent("project with spaces")
        let command = try #require(ConnectionEncoding.installCommand(helper: helper, client: .omp, scope: "project", project: project, profile: "ignored", language: "en"))
        // Replace only the command's first quoted word with printf so the shell exposes its argv.
        let launch = "KISSMARK_LANGUAGE='en' " + ConnectionEncoding.shellQuote(helper.path)
        #expect(command.hasPrefix(launch))
        let arguments = String(command.dropFirst(launch.count))
        let process = Process(); process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "printf '%s\\n'" + arguments]
        let pipe = Pipe(); process.standardOutput = pipe
        try process.run(); let data = pipe.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
        #expect(String(decoding: data, as: UTF8.self).split(separator: "\n").map(String.init) == ["install", "--client", "omp", "--scope", "project", "--project", project.path])
        #expect(ConnectionEncoding.installCommand(helper: helper, client: .codex, scope: "project", project: nil, profile: "", language: "ko") == nil)
        #expect(ConnectionEncoding.installCommand(helper: helper, client: .claudeDesktop, scope: "project", project: project, profile: "", language: "ko") == nil)
        #expect(ConnectionEncoding.installCommand(helper: helper, client: .codex, scope: "user", project: nil, profile: "", language: "en; touch x") == nil)
        let literal = Process(); literal.executableURL = URL(fileURLWithPath: "/bin/sh")
        literal.arguments = ["-c", "printf %s " + ConnectionEncoding.shellQuote(helper.path)]
        let output = Pipe(); literal.standardOutput = output
        try literal.run(); let result = output.fileHandleForReading.readDataToEndOfFile(); literal.waitUntilExit()
        #expect(String(decoding: result, as: UTF8.self) == helper.path)
    }

    @Test("A slow prior snapshot cannot replace a completed newer search")
    func oldRefreshCannotReplaceNewSearch() async throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let old = DiscoverySnapshot(installationID: UUID())
        let newest = DiscoverySnapshot(installationID: UUID())
        let gate = SnapshotGate()
        let model = AgentConnectionsModel(store: ConnectionSelectionStore(file: root.appendingPathComponent("state.json")), fetch: { request in
            if request.operation == .snapshot { return await gate.hold(request) }
            return BrokerReply(id: request.id, snapshot: newest)
        })
        let refresh = Task { await model.refresh() }
        await gate.waitForRequest()
        await model.startSearch().value
        #expect(model.snapshot?.installationID == newest.installationID)
        await gate.release(old)
        await refresh.value
        #expect(model.snapshot?.installationID == newest.installationID)
    }

    @Test("A busy response keeps an already verified discovery service available")
    func busySearchKeepsAvailability() async throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let snapshot = DiscoverySnapshot(installationID: UUID())
        let model = AgentConnectionsModel(store: ConnectionSelectionStore(file: root.appendingPathComponent("state.json")), fetch: { request in
            if request.operation == .discover { throw ConnectionFailure.busy }
            return BrokerReply(id: request.id, snapshot: snapshot)
        })
        await model.refresh()
        #expect(model.serviceAvailable)
        await model.startSearch().value
        #expect(model.serviceAvailable)
        model.add(SelectionKey(client: .omp))
        #expect(model.rows == [SelectionKey(client: .omp)])
    }

    @Test("A concurrent probe does not discard still-fresh peer evidence")
    func busyProbeKeepsFreshEvidence() async throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let key = SelectionKey(client: .omp)
        let peer = MCPInstance(id: UUID(), key: key, lastPeerResponse: Date())
        let snapshot = DiscoverySnapshot(installationID: UUID(), instances: [peer])
        let model = AgentConnectionsModel(store: ConnectionSelectionStore(file: root.appendingPathComponent("state.json")), fetch: { request in
            if request.operation == .probe { throw ConnectionFailure.busy }
            return BrokerReply(id: request.id, snapshot: snapshot)
        })
        await model.refresh()
        #expect(model.state(for: key) == .connected)
        await model.probe(peer.id)
        #expect(model.state(for: key) == .connected)
    }

    @Test("A confirmed peer disappearing is distinct from an unverified client")
    func verifiedPeerDisappearance() async throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let key = SelectionKey(client: .omp)
        let installation = UUID()
        let feed = SnapshotFeed(DiscoverySnapshot(installationID: installation, instances: [MCPInstance(id: UUID(), key: key, lastPeerResponse: Date())]))
        let model = AgentConnectionsModel(store: ConnectionSelectionStore(file: root.appendingPathComponent("state.json")), fetch: { await feed.reply($0) })
        await model.refresh()
        #expect(model.state(for: key) == .connected)
        await feed.replace(DiscoverySnapshot(installationID: installation))
        await model.refresh()
        #expect(model.state(for: key) == .disconnected)
        await feed.replace(DiscoverySnapshot(installationID: UUID()))
        await model.refresh()
        #expect(model.state(for: key) == .unavailable)
    }
}

private actor SnapshotFeed {
    var snapshot: DiscoverySnapshot
    init(_ snapshot: DiscoverySnapshot) { self.snapshot = snapshot }
    func reply(_ request: BrokerRequest) -> BrokerReply { BrokerReply(id: request.id, snapshot: snapshot) }
    func replace(_ snapshot: DiscoverySnapshot) { self.snapshot = snapshot }
}

private actor SnapshotGate {
    private var held: (BrokerRequest, CheckedContinuation<BrokerReply, Never>)?
    private var waiting: CheckedContinuation<Void, Never>?
    func hold(_ request: BrokerRequest) async -> BrokerReply {
        await withCheckedContinuation { continuation in
            held = (request, continuation)
            waiting?.resume(); waiting = nil
        }
    }
    func waitForRequest() async {
        if held != nil { return }
        await withCheckedContinuation { waiting = $0 }
    }
    func release(_ snapshot: DiscoverySnapshot) {
        if let held { held.1.resume(returning: BrokerReply(id: held.0.id, snapshot: snapshot)) }
        held = nil
    }
}
#endif
