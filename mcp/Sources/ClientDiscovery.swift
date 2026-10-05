import Foundation
import AppKit
import KissmarkConnections

struct DiscoveryConfiguration: Codable {
    var executables: [String: String]
    var roots: [String: String]
    var codexSocket: String?
    static let rootKeys = ["HOME", "PATH", "CLAUDE_CONFIG_DIR", "CODEX_HOME", "PI_CONFIG_DIR", "PI_CODING_AGENT_DIR", "OMP_PROFILE", "PI_PROFILE"]
    static func capture(environment: [String: String], codexSocket: String? = nil) -> DiscoveryConfiguration {
        var executables: [String: String] = [:]
        for client in ConnectionClient.allCases {
            if let name = client.executable, let path = ClientSetup.findExecutable(name, environment: environment) { executables[client.rawValue] = path }
        }
        return DiscoveryConfiguration(executables: executables, roots: environment.filter { rootKeys.contains($0.key) }, codexSocket: codexSocket)
    }
}

final class ClientDiscovery: @unchecked Sendable {
    private let configuration: DiscoveryConfiguration
    init(configuration: DiscoveryConfiguration) { self.configuration = configuration }
    private var codexSocket: String {
        let root = configuration.roots["CODEX_HOME"].flatMap { $0.isEmpty ? nil : $0 } ?? ClientSetup.homeDirectory(configuration.roots) + "/.codex"
        return configuration.codexSocket ?? root + "/app-server-control/app-server-control.sock"
    }
    func reloadCodex() throws { try CodexDiscovery(path: codexSocket).reloadMCP() }
    func scan(cancelled: @escaping @Sendable () -> Bool = { false }) -> ([DiscoveryCandidate], [ProviderOutcome]) {
        final class Results: @unchecked Sendable {
            let lock = NSLock()
            var candidates: [DiscoveryCandidate] = []
            var outcomes: [ProviderOutcome] = []
            func add(_ candidates: [DiscoveryCandidate], _ outcome: ProviderOutcome) {
                lock.lock(); defer { lock.unlock() }; self.candidates += candidates; outcomes.append(outcome)
            }
        }
        let results = Results(); let group = DispatchGroup()
        for client in ConnectionClient.allCases {
            group.enter()
            DispatchQueue.global(qos: .utility).async {
                defer { group.leave() }
                let result = self.discover(client, cancelled: cancelled)
                results.add(result.0, result.1)
            }
        }
        group.wait()
        return (results.candidates.sorted { $0.id < $1.id }, results.outcomes.sorted { $0.id < $1.id })
    }
    private func discover(_ client: ConnectionClient, cancelled: @escaping @Sendable () -> Bool) -> ([DiscoveryCandidate], ProviderOutcome) {
        var candidates: [DiscoveryCandidate] = []
        if let bundle = client.bundleID {
            if NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle) != nil {
                candidates.append(DiscoveryCandidate(key: SelectionKey(client: client)))
            }
            // A GUI process does not establish a chat/session or MCP connection.
            return (candidates, ProviderOutcome(client: client, status: .unsupported, reason: .unsupported))
        }
        let executable = configuration.executables[client.rawValue]
        if let executable, ClientSetup.isRunnable(executable) { candidates.append(DiscoveryCandidate(key: SelectionKey(client: client))) }
        do {
            let sessions: [DiscoveryCandidate]
            if client == .codex {
                sessions = try CodexDiscovery(path: codexSocket, cancelled: cancelled).loadedThreads()
            } else {
                guard let executable, ClientSetup.isRunnable(executable) else { throw ConnectionFailure.unavailable }
                let helpArgs = client == .claudeCode ? ["agents", "--help"] : ["collab", "--help"]
                let help = try DiscoveryCommand.run(executable, helpArgs, environment: configuration.roots, timeout: 2, cancelled: cancelled)
                let helpText = String(decoding: help, as: UTF8.self)
                guard helpText.contains("--json"), helpText.contains(client == .claudeCode ? "agents" : "collab") else { throw ConnectionFailure.unsupported }
                let args = client == .claudeCode ? ["agents", "--json"] : ["collab", "list", "--json"]
                let data = try DiscoveryCommand.run(executable, args, environment: configuration.roots, timeout: 8, cancelled: cancelled)
                sessions = try Self.parse(data, client: client)
            }
            candidates += sessions
            return (candidates, ProviderOutcome(client: client, status: .available))
        } catch {
            let failure = error as? ConnectionFailure ?? .malformed
            let status: ProviderOutcome.Status = failure == .cancelled ? .cancelled : failure == .unsupported ? .unsupported : failure == .unavailable ? .unavailable : .failed
            return (candidates, ProviderOutcome(client: client, status: status, reason: failure))
        }
    }
    static func parse(_ data: Data, client: ConnectionClient) throws -> [DiscoveryCandidate] {
        guard data.count <= 4 * 1024 * 1024 else { throw ConnectionFailure.oversized }
        let object = try JSONSerialization.jsonObject(with: data)
        let rows: [[String: Any]]
        switch client {
        case .claudeCode:
            guard let array = object as? [[String: Any]] else { throw ConnectionFailure.malformed }
            rows = array
        case .omp:
            guard let envelope = object as? [String: Any], envelope["version"] as? Int == 1,
                  let array = envelope["hosts"] as? [[String: Any]] else { throw ConnectionFailure.unsupported }
            rows = array
        default: throw ConnectionFailure.unsupported
        }
        guard rows.count <= 1000 else { throw ConnectionFailure.oversized }
        var candidates: [DiscoveryCandidate] = []
        var identities = Set<String>()
        for row in rows {
            guard let pid = row["pid"] as? Int, pid > 0 else {
                if client == .claudeCode { continue } // Exited background entries are not live.
                throw ConnectionFailure.malformed
            }
            let identity: String
            if client == .claudeCode {
                guard let started = row["startedAt"] as? Double, started.isFinite, started > 0,
                      let status = row["status"] as? String, ["busy", "waiting", "idle"].contains(status),
                      let kind = row["kind"] as? String, ["interactive", "background"].contains(kind) else { throw ConnectionFailure.malformed }
                identity = "process:\(pid):\(started)"
            } else {
                guard let instance = row["instanceId"] as? String, !instance.isEmpty, instance.utf8.count <= 64,
                      let generation = row["generation"] as? Int, generation >= 1 else { throw ConnectionFailure.malformed }
                identity = instance + ":" + String(generation)
            }
            guard candidates.count < 200 else { throw ConnectionFailure.oversized }
            let session = row["sessionId"] as? String
            guard session.map({ !$0.isEmpty && $0.utf8.count <= 256 }) ?? true else { throw ConnectionFailure.malformed }
            if identities.insert(identity).inserted {
                candidates.append(DiscoveryCandidate(key: SelectionKey(client: client), instance: identity, session: session, runtime: .running))
            }
        }
        return candidates
    }
}
