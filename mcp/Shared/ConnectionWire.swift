import Foundation

public enum ConnectionProtocol {
    public static let version = 1
    public static let maximumFrameBytes = 65_536
    public static let providerTimeout: TimeInterval = 10
    public static let discoveryTimeout: TimeInterval = 15
    public static let pingTimeout: TimeInterval = 2
    public static let freshness: TimeInterval = 15
    public static let refreshInterval: TimeInterval = 5
}

public enum ConnectionClient: String, Codable, CaseIterable, Sendable {
    case claudeCode = "claude-code", codex, omp, cursor, claudeDesktop = "claude-desktop", vscode
    public var title: String {
        switch self {
        case .claudeCode: return "Claude Code"
        case .codex: return "Codex"
        case .omp: return "OMP"
        case .cursor: return "Cursor"
        case .claudeDesktop: return "Claude Desktop"
        case .vscode: return "VS Code"
        }
    }
    public var executable: String? {
        switch self { case .claudeCode: return "claude"; case .codex: return "codex"; case .omp: return "omp"; default: return nil }
    }
    public var bundleID: String? {
        switch self {
        case .cursor: return "com.todesktop.230313mzl4w4u92"
        case .claudeDesktop: return "com.anthropic.claudefordesktop"
        case .vscode: return "com.microsoft.VSCode"
        default: return nil
        }
    }
}

public struct SelectionKey: Codable, Hashable, Sendable, Identifiable {
    public var client: ConnectionClient
    public var profile: String?
    public var id: String { client.rawValue + ":" + (profile ?? "") }
    public init(client: ConnectionClient, profile: String? = nil) { self.client = client; self.profile = profile }
}

public struct DiscoveryCandidate: Codable, Equatable, Sendable, Identifiable {
    public enum Runtime: String, Codable, Sendable { case installed, running, loaded }
    public var key: SelectionKey
    public var instance: String?
    public var session: String?
    public var runtime: Runtime
    public var id: String { key.id + ":" + (instance ?? "installed") }
    public init(key: SelectionKey, instance: String? = nil, session: String? = nil, runtime: Runtime = .installed) {
        self.key = key; self.instance = instance; self.session = session; self.runtime = runtime
    }
}

public struct ProviderOutcome: Codable, Equatable, Sendable, Identifiable {
    public enum Status: String, Codable, Sendable { case available, unsupported, unavailable, failed, cancelled }
    public var client: ConnectionClient
    public var status: Status
    public var reason: ConnectionFailure?
    public var id: String { client.rawValue }
    public init(client: ConnectionClient, status: Status, reason: ConnectionFailure? = nil) {
        self.client = client; self.status = status; self.reason = reason
    }
}

public enum ConnectionFailure: String, Error, Codable, Sendable {
    case unavailable, unsafeEndpoint, pathTooLong, malformed, oversized, versionMismatch, requestMismatch
    case timeout, unsupported, clientFailed, accessDenied, cancelled, busy, staleInstance
}

public enum ConnectionScope: String, Codable, Sendable { case user, project }

public struct MCPInstance: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var key: SelectionKey
    public var initialized: Bool
    public var scope: ConnectionScope?
    public var lastPeerResponse: Date?
    public init(id: UUID, key: SelectionKey, initialized: Bool = true, scope: ConnectionScope? = nil, lastPeerResponse: Date? = nil) {
        self.id = id; self.key = key; self.initialized = initialized; self.scope = scope; self.lastPeerResponse = lastPeerResponse
    }
    public func isConnected(at now: Date = Date()) -> Bool {
        guard initialized, let response = lastPeerResponse else { return false }
        let age = now.timeIntervalSince(response)
        return age >= 0 && age < ConnectionProtocol.freshness
    }
}

public struct DiscoverySnapshot: Codable, Sendable {
    public var installationID: UUID
    public var capturedAt: Date
    public var candidates: [DiscoveryCandidate]
    public var providers: [ProviderOutcome]
    public var instances: [MCPInstance]
    public init(installationID: UUID, candidates: [DiscoveryCandidate] = [], providers: [ProviderOutcome] = [], instances: [MCPInstance] = []) {
        self.installationID = installationID; self.capturedAt = Date()
        self.candidates = candidates; self.providers = providers; self.instances = instances
    }
}

public struct BrokerRequest: Codable, Sendable {
    public enum Operation: String, Codable, Sendable { case discover, snapshot, probe, registerInstance, reloadCodex }
    public var version = ConnectionProtocol.version
    public var id: UUID
    public var operation: Operation
    public var instanceID: UUID?
    public var instance: MCPInstance?
    public init(_ operation: Operation, instanceID: UUID? = nil, instance: MCPInstance? = nil) {
        id = UUID(); self.operation = operation; self.instanceID = instanceID; self.instance = instance
    }
}

public struct BrokerReply: Codable, Sendable {
    public var version = ConnectionProtocol.version
    public var id: UUID
    public var snapshot: DiscoverySnapshot?
    public var instance: MCPInstance?
    public var error: ConnectionFailure?
    public init(id: UUID, snapshot: DiscoverySnapshot? = nil, instance: MCPInstance? = nil, error: ConnectionFailure? = nil) {
        self.id = id; self.snapshot = snapshot; self.instance = instance; self.error = error
    }
    public func validate(for request: BrokerRequest) throws {
        guard version == ConnectionProtocol.version else { throw ConnectionFailure.versionMismatch }
        guard id == request.id else { throw ConnectionFailure.requestMismatch }
        if let error { throw error }
    }
}
