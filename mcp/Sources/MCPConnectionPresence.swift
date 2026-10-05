import Foundation
import KissmarkConnections

/// Live transport evidence is separate from historical handshake receipts.
final class MCPConnectionPresence: @unchecked Sendable {
    private let condition = NSCondition()
    private let id = UUID()
    private let paths: DiscoveryPaths
    private let key: SelectionKey?
    private let scope: ConnectionScope?
    private let send: ([String: Any]) -> Void
    private var initializedReply = false
    private var started = false
    private var stopped = false
    private var pendingPing: String?
    private var pingSucceeded = false
    private var channel: LocalConnection?

    init(environment: [String: String], send: @escaping ([String: Any]) -> Void) {
        paths = DiscoveryPaths(environment: environment)
        scope = environment["KISSMARK_CLIENT_SCOPE"].flatMap(ConnectionScope.init(rawValue:))
        key = environment["KISSMARK_CLIENT_ID"].flatMap(ConnectionClient.init(rawValue:)).map {
            SelectionKey(client: $0, profile: environment["KISSMARK_CLIENT_PROFILE"].flatMap { $0.utf8.count <= 64 ? $0 : nil })
        }
        self.send = send
    }
    func didRespondToInitialize() { condition.lock(); initializedReply = true; condition.unlock() }
    func didInitialize() {
        condition.lock()
        guard initializedReply, !started, !stopped, key != nil else { condition.unlock(); return }
        started = true; condition.unlock()
        DispatchQueue.global(qos: .utility).async { self.serve() }
    }
    @discardableResult
    func receiveResponse(_ message: [String: Any]) -> Bool {
        condition.lock(); defer { condition.unlock() }
        guard let responseID = message["id"] as? String, responseID == pendingPing,
              message["method"] == nil, message["jsonrpc"] as? String == "2.0" else { return false }
        pingSucceeded = message["error"] == nil && message["result"] is [String: Any]
        pendingPing = nil; condition.broadcast()
        return true
    }
    func stop() {
        condition.lock(); stopped = true; channel?.shutdown(); condition.broadcast(); condition.unlock()
    }
    private func probe() throws -> MCPInstance {
        condition.lock()
        guard !stopped, let key else { condition.unlock(); throw ConnectionFailure.staleInstance }
        let pingID = "kissmark-ping-" + UUID().uuidString
        pendingPing = pingID; pingSucceeded = false
        condition.unlock()
        send(["jsonrpc": "2.0", "id": pingID, "method": "ping"])
        condition.lock(); defer { pendingPing = nil; condition.unlock() }
        let deadline = Date().addingTimeInterval(ConnectionProtocol.pingTimeout)
        while pendingPing != nil && !stopped {
            if !condition.wait(until: deadline) { break }
        }
        guard !stopped, pingSucceeded else { throw ConnectionFailure.timeout }
        return MCPInstance(id: id, key: key, scope: scope, lastPeerResponse: Date())
    }
    private func serve() {
        guard let key else { return }
        while true {
            condition.lock(); let done = stopped; condition.unlock()
            if done { return }
            do {
                let connection = try LocalConnection.connect(path: paths.socket)
                condition.lock(); channel = connection; condition.unlock()
                defer {
                    connection.shutdown()
                    condition.lock(); channel = nil; condition.unlock()
                }
                _ = try connection.request(BrokerRequest(.registerInstance, instance: MCPInstance(id: id, key: key, scope: scope)))
                while true {
                    condition.lock(); let done = stopped; condition.unlock()
                    if done { return }
                    let request: BrokerRequest
                    do { request = try connection.receive(BrokerRequest.self, timeout: 5) }
                    catch ConnectionFailure.timeout { continue }
                    guard request.version == ConnectionProtocol.version, request.operation == .probe,
                          request.instanceID == id else { throw ConnectionFailure.malformed }
                    let reply: BrokerReply
                    do { reply = BrokerReply(id: request.id, instance: try probe()) }
                    catch { reply = BrokerReply(id: request.id, error: error as? ConnectionFailure ?? .unavailable) }
                    try connection.send(reply)
                }
            } catch {
                // Broker setup/restart is independent of an existing agent session.
                condition.lock()
                if !stopped { _ = condition.wait(until: Date().addingTimeInterval(5)) }
                condition.unlock()
            }
        }
    }
}
