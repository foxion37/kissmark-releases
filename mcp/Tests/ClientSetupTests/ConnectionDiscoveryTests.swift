import XCTest
import Foundation
import Darwin
import KissmarkConnections
@testable import kissmark_mcp

final class ConnectionDiscoveryTests: XCTestCase {
    func testPeerFreshnessRejectsUninitializedExpiredAndFutureEvidence() {
        let now = Date(timeIntervalSince1970: 1000)
        var instance = MCPInstance(id: UUID(), key: SelectionKey(client: .omp))
        XCTAssertFalse(instance.isConnected(at: now))
        instance.lastPeerResponse = Date(timeIntervalSince1970: 999)
        XCTAssertTrue(instance.isConnected(at: now))
        instance.initialized = false
        XCTAssertFalse(instance.isConnected(at: now))
        instance.initialized = true
        instance.lastPeerResponse = Date(timeIntervalSince1970: 985)
        XCTAssertFalse(instance.isConnected(at: now))
        instance.lastPeerResponse = Date(timeIntervalSince1970: 1001)
        XCTAssertFalse(instance.isConnected(at: now))
    }
    func testReplyMustMatchRequestAndProtocol() {
        let request = BrokerRequest(.snapshot)
        XCTAssertThrowsError(try BrokerReply(id: UUID()).validate(for: request))
        var reply = BrokerReply(id: request.id)
        reply.version = 2
        XCTAssertThrowsError(try reply.validate(for: request))
        XCTAssertThrowsError(try BrokerReply(id: request.id, error: .accessDenied).validate(for: request))
    }
    func testSocketRejectsSymlinksRegularFilesAndOversizePaths() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let regular = directory.appendingPathComponent("regular")
        try Data().write(to: regular)
        let link = directory.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: regular)
        for url in [regular, link] {
            XCTAssertThrowsError(try LocalConnection.connect(path: url.path)) { XCTAssertEqual($0 as? ConnectionFailure, .unsafeEndpoint) }
        }
        XCTAssertThrowsError(try LocalConnection.address("/" + String(repeating: "x", count: 104)))
    }
    func testBoundedFramesAndDisconnectedPeer() throws {
        var descriptors: [Int32] = [0, 0]
        XCTAssertEqual(socketpair(AF_UNIX, SOCK_STREAM, 0, &descriptors), 0)
        let a = try LocalConnection(descriptor: descriptors[0])
        let b = try LocalConnection(descriptor: descriptors[1])
        let request = BrokerRequest(.snapshot)
        try a.send(request)
        let received = try b.receive(BrokerRequest.self)
        XCTAssertEqual(received.id, request.id)
        XCTAssertEqual(received.operation, .snapshot)
        XCTAssertThrowsError(try a.send(String(repeating: "x", count: 65_537))) { XCTAssertEqual($0 as? ConnectionFailure, .oversized) }
        _ = "not-json\n".withCString { Darwin.write(descriptors[0], $0, 9) }
        XCTAssertThrowsError(try b.receive(BrokerRequest.self)) { XCTAssertEqual($0 as? ConnectionFailure, .malformed) }
        a.shutdown()
        XCTAssertThrowsError(try b.receive(BrokerRequest.self, timeout: 0.1))
    }

    func testFailedProbeInvalidatesPriorSuccessImmediately() throws {
        var descriptors: [Int32] = [0, 0]
        XCTAssertEqual(socketpair(AF_UNIX, SOCK_STREAM, 0, &descriptors), 0)
        let broker = try LocalConnection(descriptor: descriptors[0])
        let helper = try LocalConnection(descriptor: descriptors[1])
        let instance = RegisteredInstance(MCPInstance(id: UUID(), key: SelectionKey(client: .omp), lastPeerResponse: Date()), channel: broker)
        let responded = expectation(description: "helper error delivered")
        DispatchQueue.global().async {
            do {
                let request = try helper.receive(BrokerRequest.self)
                instance.accept(BrokerReply(id: request.id, error: .timeout))
            } catch { XCTFail("Control request failed") }
            responded.fulfill()
        }
        XCTAssertThrowsError(try instance.probe())
        XCTAssertNil(instance.snapshot().lastPeerResponse)
        wait(for: [responded], timeout: 2)
    }

    func testNativeDiscoveryDoesNotInventSessionsOrLeakNames() throws {
        let claude = Data(#"[{"kind":"interactive","pid":123,"startedAt":1000,"status":"idle","cwd":"/private","name":"private prompt"},{"kind":"background","state":"working","startedAt":1000}]"#.utf8)
        let sessions = try ClientDiscovery.parse(claude, client: .claudeCode)
        XCTAssertEqual(sessions.count, 1)
        XCTAssertNil(sessions[0].session)
        XCTAssertEqual(sessions[0].runtime, .running)
        XCTAssertFalse(String(decoding: try JSONEncoder().encode(sessions), as: UTF8.self).contains("private"))
        let omp = Data(#"{"version":1,"hosts":[{"instanceId":"12345678","generation":2,"pid":124,"sessionId":"s1","busy":null,"sessionName":"private"}]}"#.utf8)
        let hosts = try ClientDiscovery.parse(omp, client: .omp)
        XCTAssertEqual(hosts[0].instance, "12345678:2")
        XCTAssertNil(hosts[0].key.profile)
        XCTAssertThrowsError(try ClientDiscovery.parse(Data(#"{"version":2,"hosts":[]}"#.utf8), client: .omp))
    }
    func testPermissionDeniedEndpointIsNotReportedMissing() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { chmod(directory.path, 0o700); try? FileManager.default.removeItem(at: directory) }
        XCTAssertEqual(chmod(directory.path, 0), 0)
        XCTAssertThrowsError(try LocalConnection.validateEndpoint(directory.appendingPathComponent("peer.sock").path)) {
            XCTAssertEqual($0 as? ConnectionFailure, .accessDenied)
        }
    }
}
