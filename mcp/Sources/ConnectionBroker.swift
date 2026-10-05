import Foundation
import Darwin
import KissmarkConnections

struct DiscoveryPaths {
    let data: URL
    var directory: URL { data.appendingPathComponent("Library/Application Support/Kissmark/discovery") }
    var socket: String { data.appendingPathComponent("tmp/kmd.sock").path }
    var identity: URL { directory.appendingPathComponent("installation.json") }
    var configuration: URL { directory.appendingPathComponent("configuration.json") }
    init(environment: [String: String] = ProcessInfo.processInfo.environment) {
        if let override = environment["KISSMARK_DISCOVERY_DATA"] {
            data = URL(fileURLWithPath: override)
        } else {
            let home = ClientSetup.homeDirectory(environment)
            let bundle = environment["KISSMARK_BUNDLE_ID"] ?? "com.singandmong.kissmark"
            data = URL(fileURLWithPath: home).appendingPathComponent("Library/Containers/\(bundle)/Data")
        }
    }
    func installationID() throws -> UUID {
        var status = stat()
        guard lstat(identity.path, &status) == 0, status.st_uid == getuid(), status.st_mode & S_IFMT == S_IFREG,
              status.st_size < 128, status.st_mode & 0o077 == 0,
              let id = try? JSONDecoder().decode(UUID.self, from: Data(contentsOf: identity)) else { throw ConnectionFailure.unavailable }
        return id
    }
}

/// A registered stdio helper's private control connection, never its stdin pipe.
final class RegisteredInstance: @unchecked Sendable {
    let channel: LocalConnection
    private let condition = NSCondition()
    private var value: MCPInstance
    private var pending: UUID?
    private var reply: BrokerReply?
    private var closed = false
    init(_ instance: MCPInstance, channel: LocalConnection) { value = instance; self.channel = channel }
    func snapshot() -> MCPInstance { condition.lock(); defer { condition.unlock() }; return value }
    func accept(_ reply: BrokerReply) {
        condition.lock(); defer { condition.unlock() }
        guard reply.id == pending, reply.version == ConnectionProtocol.version else { return }
        self.reply = reply; condition.broadcast()
    }
    func close() {
        condition.lock(); closed = true; value.lastPeerResponse = nil; condition.broadcast(); condition.unlock()
    }
    func probe() throws -> MCPInstance {
        condition.lock(); defer { condition.unlock() }
        guard !closed else { throw ConnectionFailure.staleInstance }
        guard pending == nil else { throw ConnectionFailure.busy }
        let request = BrokerRequest(.probe, instanceID: value.id)
        pending = request.id; reply = nil
        value.lastPeerResponse = nil
        defer { pending = nil; reply = nil }
        try channel.send(request)
        let deadline = Date().addingTimeInterval(ConnectionProtocol.pingTimeout + 1)
        while reply == nil && !closed {
            if !condition.wait(until: deadline) { break }
        }
        guard !closed, let reply else { value.lastPeerResponse = nil; throw ConnectionFailure.timeout }
        try reply.validate(for: request)
        guard let instance = reply.instance, instance.id == value.id, instance.key == value.key,
              instance.scope == value.scope, instance.initialized, instance.isConnected() else { value.lastPeerResponse = nil; throw ConnectionFailure.staleInstance }
        value.lastPeerResponse = Date()
        return value
    }
}

final class ConnectionBroker: @unchecked Sendable {
    let paths: DiscoveryPaths
    let installationID: UUID
    private let lock = NSLock()
    private var instances: [UUID: RegisteredInstance] = [:]
    private var candidates: [DiscoveryCandidate] = []
    private var providers: [ProviderOutcome] = []
    private var scannedAt = Date.distantPast
    private var scanning = false
    private let discovery: ClientDiscovery
    init(paths: DiscoveryPaths, discovery: ClientDiscovery) throws {
        self.paths = paths; self.installationID = try paths.installationID(); self.discovery = discovery
    }
    private func snapshot() -> DiscoverySnapshot {
        lock.lock(); defer { lock.unlock() }
        var result = DiscoverySnapshot(installationID: installationID, candidates: candidates, providers: providers,
                                       instances: instances.values.map { $0.snapshot() }.sorted { $0.id.uuidString < $1.id.uuidString })
        result.capturedAt = scannedAt
        return result
    }
    func run() throws {
        let path = paths.socket
        let parent = URL(fileURLWithPath: path).deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        var status = stat()
        guard lstat(parent.path, &status) == 0, status.st_mode & S_IFMT == S_IFDIR,
              status.st_uid == getuid(), status.st_mode & 0o077 == 0 else { throw ConnectionFailure.unsafeEndpoint }
        if lstat(path, &status) == 0 {
            try LocalConnection.validateEndpoint(path)
            if let existing = try? LocalConnection.connect(path: path) { existing.shutdown(); throw ConnectionFailure.busy }
            guard unlink(path) == 0 else { throw ConnectionFailure.unsafeEndpoint }
        }
        var address = try LocalConnection.address(path)
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw ConnectionFailure.unavailable }
        defer { Darwin.close(fd); unlink(path) }
        _ = fcntl(fd, F_SETFD, FD_CLOEXEC)
        let oldMask = umask(0o077)
        let result = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        umask(oldMask)
        guard result == 0, chmod(path, 0o600) == 0, listen(fd, 16) == 0 else { throw ConnectionFailure.unavailable }
        print("Kissmark discovery ready"); fflush(stdout)
        while true {
            let peer = accept(fd, nil, nil)
            if peer < 0 { if errno == EINTR { continue }; throw ConnectionFailure.unavailable }
            guard let channel = try? LocalConnection(descriptor: peer) else { continue }
            // ponytail: one blocking worker per live helper; use DispatchSourceRead if large session counts are needed.
            DispatchQueue.global(qos: .utility).async { self.handle(channel) }
        }
    }
    private func handle(_ channel: LocalConnection) {
        defer { channel.shutdown() }
        guard let request = try? channel.receive(BrokerRequest.self, timeout: 2) else { return }
        guard request.version == ConnectionProtocol.version else {
            try? channel.send(BrokerReply(id: request.id, error: .versionMismatch)); return
        }
        do {
            switch request.operation {
            case .registerInstance:
                guard var instance = request.instance, instance.initialized,
                      instance.key.profile.map({ $0.utf8.count <= 64 }) ?? true else { throw ConnectionFailure.malformed }
                instance.lastPeerResponse = nil
                let registered = RegisteredInstance(instance, channel: channel)
                lock.lock()
                guard instances[instance.id] == nil else { lock.unlock(); throw ConnectionFailure.busy }
                do {
                    // Publish only after the registration reply; probes must never overtake it.
                    try channel.send(BrokerReply(id: request.id, instance: instance))
                    instances[instance.id] = registered
                    lock.unlock()
                } catch {
                    lock.unlock()
                    throw error
                }
                defer {
                    registered.close()
                    lock.lock(); instances.removeValue(forKey: instance.id); lock.unlock()
                }
                while true {
                    do { registered.accept(try channel.receive(BrokerReply.self, timeout: 30)) }
                    catch ConnectionFailure.timeout { continue }
                }
            case .probe:
                guard let id = request.instanceID else { throw ConnectionFailure.malformed }
                lock.lock(); let instance = instances[id]; lock.unlock()
                guard let instance else { throw ConnectionFailure.staleInstance }
                try channel.send(BrokerReply(id: request.id, instance: try instance.probe()))
            case .discover:
                lock.lock(); let alreadyScanning = scanning; if !alreadyScanning { scanning = true }; lock.unlock()
                guard !alreadyScanning else { throw ConnectionFailure.busy }
                let result = discovery.scan { channel.peerClosed }
                lock.lock()
                if !channel.peerClosed { candidates = result.0; providers = result.1; scannedAt = Date() }
                scanning = false
                lock.unlock()
                try channel.send(BrokerReply(id: request.id, snapshot: snapshot()))
            case .snapshot:
                try channel.send(BrokerReply(id: request.id, snapshot: snapshot()))
            case .reloadCodex:
                try discovery.reloadCodex()
                try channel.send(BrokerReply(id: request.id))
            }
        } catch {
            try? channel.send(BrokerReply(id: request.id, error: error as? ConnectionFailure ?? .unavailable))
        }
    }
}
