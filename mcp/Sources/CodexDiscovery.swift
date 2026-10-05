import Foundation
import Darwin
import CryptoKit
import KissmarkConnections

/// Codex's documented local control socket speaks WebSocket, not MCP or JSONL.
/// Read only loaded thread IDs; never request turns, previews, or stored history.
final class CodexDiscovery {
    private let channel: LocalConnection
    private let deadline = Date().addingTimeInterval(ConnectionProtocol.providerTimeout)
    private var nextID = 0
    private let cancelled: @Sendable () -> Bool
    init(path: String, cancelled: @escaping @Sendable () -> Bool = { false }) throws {
        self.cancelled = cancelled
        var status = stat()
        guard lstat(path, &status) == 0 else {
            throw errno == EACCES || errno == EPERM ? ConnectionFailure.accessDenied : .unavailable
        }
        guard status.st_uid == getuid() else { throw ConnectionFailure.unsafeEndpoint }
        // Codex publishes an owner-owned rendezvous symlink to a private socket.
        let resolved = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
        channel = try LocalConnection.connect(path: resolved)
        let key = Data((0..<16).map { _ in UInt8.random(in: 0...255) }).base64EncodedString()
        try write(Data("GET /rpc HTTP/1.1\r\nHost: localhost\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Key: \(key)\r\nSec-WebSocket-Version: 13\r\n\r\n".utf8))
        var header = Data()
        while !header.suffix(4).elementsEqual([13, 10, 13, 10]) {
            guard header.count < 8192 else { throw ConnectionFailure.oversized }
            header.append(try bytes(1))
        }
        guard let text = String(data: header, encoding: .utf8) else { throw ConnectionFailure.malformed }
        let lines = text.components(separatedBy: "\r\n")
        guard lines.first?.split(separator: " ").dropFirst().first == "101" else { throw ConnectionFailure.unsupported }
        var fields: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let name = line[..<colon].lowercased()
            guard fields[name] == nil else { throw ConnectionFailure.malformed }
            fields[name] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        let expected = Data(Insecure.SHA1.hash(data: Data((key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11").utf8))).base64EncodedString()
        guard fields["sec-websocket-accept"] == expected, fields["upgrade"]?.lowercased() == "websocket",
              fields["connection"]?.lowercased().split(separator: ",").contains(where: { $0.trimmingCharacters(in: .whitespaces) == "upgrade" }) == true,
              fields["sec-websocket-extensions"] == nil else { throw ConnectionFailure.malformed }
    }
    deinit { channel.shutdown() }
    private func wait(_ event: Int16) throws {
        while true {
            guard !cancelled() else { throw ConnectionFailure.cancelled }
            let remaining = deadline.timeIntervalSinceNow
            guard remaining > 0 else { throw ConnectionFailure.timeout }
            var p = pollfd(fd: channel.descriptor, events: event, revents: 0)
            let result = poll(&p, 1, Int32(min(remaining * 1000, 100)))
            if result == 0 || (result < 0 && errno == EINTR) { continue }
            guard result > 0, p.revents & event != 0 else { throw ConnectionFailure.unavailable }
            return
        }
    }
    private func write(_ data: Data) throws {
        try data.withUnsafeBytes { raw in
            var offset = 0
            while offset < raw.count {
                try wait(Int16(POLLOUT))
                let n = Darwin.write(channel.descriptor, raw.baseAddress! + offset, raw.count - offset)
                if n < 0 && (errno == EINTR || errno == EAGAIN) { continue }
                guard n > 0 else { throw ConnectionFailure.unavailable }
                offset += n
            }
        }
    }
    private func bytes(_ count: Int) throws -> Data {
        guard count <= 1_048_576 else { throw ConnectionFailure.oversized }
        var data = Data(count: count)
        try data.withUnsafeMutableBytes { raw in
            var offset = 0
            while offset < count {
                try wait(Int16(POLLIN))
                let n = Darwin.read(channel.descriptor, raw.baseAddress! + offset, count - offset)
                if n < 0 && (errno == EINTR || errno == EAGAIN) { continue }
                guard n > 0 else { throw ConnectionFailure.unavailable }
                offset += n
            }
        }
        return data
    }
    private func send(_ data: Data, opcode: UInt8 = 1) throws {
        guard data.count <= 65_536 else { throw ConnectionFailure.oversized }
        var frame = Data([0x80 | opcode])
        if data.count < 126 { frame.append(0x80 | UInt8(data.count)) }
        else if data.count <= 65535 {
            frame.append(0xFE); frame.append(UInt8(data.count >> 8)); frame.append(UInt8(data.count & 255))
        } else {
            frame.append(0xFF)
            let count = UInt64(data.count)
            for shift in stride(from: 56, through: 0, by: -8) { frame.append(UInt8((count >> shift) & 255)) }
        }
        let mask = (0..<4).map { _ in UInt8.random(in: 0...255) }
        frame.append(contentsOf: mask)
        for (index, byte) in data.enumerated() { frame.append(byte ^ mask[index % 4]) }
        try write(frame)
    }
    private func message() throws -> [String: Any] {
        var assembled = Data()
        var fragmented = false
        while true {
            let header = Array(try bytes(2))
            let opcode = header[0] & 15
            let final = header[0] & 0x80 != 0
            guard header[0] & 0x70 == 0, header[1] & 0x80 == 0 else { throw ConnectionFailure.malformed }
            var length = UInt64(header[1] & 0x7F)
            if length == 126 { length = try bytes(2).reduce(0) { ($0 << 8) | UInt64($1) } }
            else if length == 127 { length = try bytes(8).reduce(0) { ($0 << 8) | UInt64($1) } }
            guard length <= 1_048_576 else { throw ConnectionFailure.oversized }
            if opcode >= 8 {
                guard final, length <= 125 else { throw ConnectionFailure.malformed }
                let payload = try bytes(Int(length))
                if opcode == 9 { try send(payload, opcode: 10); continue }
                if opcode == 10 { continue }
                if opcode == 8 { throw ConnectionFailure.unavailable }
                throw ConnectionFailure.malformed
            }
            guard (opcode == 1 && !fragmented) || (opcode == 0 && fragmented) else { throw ConnectionFailure.malformed }
            guard assembled.count + Int(length) <= 1_048_576 else { throw ConnectionFailure.oversized }
            assembled.append(try bytes(Int(length)))
            if final {
                guard let object = try JSONSerialization.jsonObject(with: assembled) as? [String: Any] else { throw ConnectionFailure.malformed }
                return object
            }
            fragmented = true
        }
    }
    private func call(_ method: String, params: [String: Any]? = nil) throws -> [String: Any] {
        nextID += 1
        var request: [String: Any] = ["id": nextID, "method": method]
        if let params { request["params"] = params }
        try send(JSONSerialization.data(withJSONObject: request))
        while true {
            let response = try message()
            guard response["method"] == nil, response["id"] as? Int == nextID else { continue }
            if response["error"] != nil { throw ConnectionFailure.unsupported }
            guard let result = response["result"] as? [String: Any] else { throw ConnectionFailure.malformed }
            return result
        }
    }
    func loadedThreads() throws -> [DiscoveryCandidate] {
        _ = try call("initialize", params: ["clientInfo": ["name": "kissmark", "version": "2.2.0"]])
        try send(JSONSerialization.data(withJSONObject: ["method": "initialized"]))
        var candidates: [DiscoveryCandidate] = []
        var cursor: String?
        var seen = Set<String>()
        var seenCursors = Set<String>()
        repeat {
            var params: [String: Any] = ["limit": 100]
            if let cursor { params["cursor"] = cursor }
            let result = try call("thread/loaded/list", params: params)
            guard let ids = result["data"] as? [String], result.keys.contains("nextCursor") else { throw ConnectionFailure.malformed }
            for id in ids {
                guard !id.isEmpty, id.utf8.count <= 256, candidates.count < 200 else { throw ConnectionFailure.oversized }
                if seen.insert(id).inserted {
                    // A loaded thread is not necessarily an actively executing conversation.
                    candidates.append(DiscoveryCandidate(key: SelectionKey(client: .codex), instance: "loaded:" + id, runtime: .loaded))
                }
            }
            cursor = result["nextCursor"] as? String
            if let cursor, !seenCursors.insert(cursor).inserted { throw ConnectionFailure.malformed }
        } while cursor != nil
        return candidates
    }
}

extension CodexDiscovery {
    func reloadMCP() throws {
        _ = try call("initialize", params: ["clientInfo": ["name": "kissmark", "version": "2.2.0"]])
        try send(JSONSerialization.data(withJSONObject: ["method": "initialized"]))
        _ = try call("config/mcpServer/reload")
    }
}
