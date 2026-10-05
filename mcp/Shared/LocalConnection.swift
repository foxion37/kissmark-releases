#if os(macOS)
import Foundation
import Darwin

/// One reader per channel; writes are serialized. Only same-user peers are accepted.
public final class LocalConnection: @unchecked Sendable {
    public let descriptor: Int32
    private let writeLock = NSLock()
    private var pending = Data()
    public init(descriptor: Int32) throws {
        var uid: uid_t = 0; var gid: gid_t = 0
        guard getpeereid(descriptor, &uid, &gid) == 0, uid == getuid() else {
            Darwin.close(descriptor); throw ConnectionFailure.unsafeEndpoint
        }
        self.descriptor = descriptor
        var noSignal: Int32 = 1
        _ = setsockopt(descriptor, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, socklen_t(MemoryLayout<Int32>.size))
        _ = fcntl(descriptor, F_SETFL, O_NONBLOCK)
        _ = fcntl(descriptor, F_SETFD, FD_CLOEXEC)
    }
    deinit { Darwin.close(descriptor) }
    public func shutdown() { _ = Darwin.shutdown(descriptor, SHUT_RDWR) }
    public var peerClosed: Bool {
        var byte: UInt8 = 0
        let count = recv(descriptor, &byte, 1, MSG_PEEK | MSG_DONTWAIT)
        return count == 0 || (count < 0 && errno != EAGAIN && errno != EINTR)
    }

    public static func address(_ path: String) throws -> sockaddr_un {
        var address = sockaddr_un()
        let bytes = Array(path.utf8CString)
        guard !path.utf8.contains(0), bytes.count <= MemoryLayout.size(ofValue: address.sun_path) else { throw ConnectionFailure.pathTooLong }
        address.sun_family = sa_family_t(AF_UNIX)
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        withUnsafeMutableBytes(of: &address.sun_path) { destination in bytes.withUnsafeBytes { destination.copyBytes(from: $0) } }
        return address
    }
    public static func validateEndpoint(_ path: String) throws {
        var status = stat()
        guard lstat(path, &status) == 0 else {
            throw errno == EACCES || errno == EPERM ? ConnectionFailure.accessDenied : .unavailable
        }
        guard status.st_uid == getuid(), status.st_mode & S_IFMT == S_IFSOCK,
              status.st_mode & 0o077 == 0 else { throw ConnectionFailure.unsafeEndpoint }
    }
    public static func connect(path: String) throws -> LocalConnection {
        try validateEndpoint(path)
        var address = try address(path)
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw ConnectionFailure.unavailable }
        _ = fcntl(fd, F_SETFL, O_NONBLOCK)
        let result = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        if result != 0 {
            let code = errno
            guard code == EINPROGRESS else {
                Darwin.close(fd)
                throw code == EACCES || code == EPERM ? ConnectionFailure.accessDenied : .unavailable
            }
            var ready = pollfd(fd: fd, events: Int16(POLLOUT), revents: 0)
            var failure: Int32 = 0
            var length = socklen_t(MemoryLayout<Int32>.size)
            guard poll(&ready, 1, 2000) > 0, getsockopt(fd, SOL_SOCKET, SO_ERROR, &failure, &length) == 0,
                  failure == 0 else { Darwin.close(fd); throw ConnectionFailure.unavailable }
        }
        return try LocalConnection(descriptor: fd)
    }
    private func wait(_ events: Int16, until deadline: Date) throws {
        while true {
            let remaining = deadline.timeIntervalSinceNow
            guard remaining > 0 else { throw ConnectionFailure.timeout }
            var descriptor = pollfd(fd: descriptor, events: events, revents: 0)
            let result = poll(&descriptor, 1, Int32(min(remaining * 1000, Double(Int32.max))))
            if result < 0 && errno == EINTR { continue }
            guard result > 0 else { throw result == 0 ? ConnectionFailure.timeout : .unavailable }
            if descriptor.revents & events != 0 { return }
            throw ConnectionFailure.unavailable
        }
    }
    public func send<T: Encodable>(_ value: T, timeout: TimeInterval = 2) throws {
        var data = try JSONEncoder().encode(value)
        guard data.count <= ConnectionProtocol.maximumFrameBytes else { throw ConnectionFailure.oversized }
        data.append(0x0A)
        writeLock.lock(); defer { writeLock.unlock() }
        let deadline = Date().addingTimeInterval(timeout)
        try data.withUnsafeBytes { raw in
            var offset = 0
            while offset < raw.count {
                try wait(Int16(POLLOUT), until: deadline)
                let count = Darwin.write(descriptor, raw.baseAddress! + offset, raw.count - offset)
                if count < 0 && (errno == EINTR || errno == EAGAIN) { continue }
                guard count > 0 else { throw ConnectionFailure.unavailable }
                offset += count
            }
        }
    }
    public func receive<T: Decodable>(_ type: T.Type, timeout: TimeInterval = 15) throws -> T {
        let deadline = Date().addingTimeInterval(timeout)
        while true {
            if let newline = pending.firstIndex(of: 0x0A) {
                guard newline <= ConnectionProtocol.maximumFrameBytes else { throw ConnectionFailure.oversized }
                let frame = pending.prefix(upTo: newline)
                guard let decoded = try? JSONDecoder().decode(type, from: frame) else { throw ConnectionFailure.malformed }
                pending.removeSubrange(...newline)
                return decoded
            }
            guard pending.count <= ConnectionProtocol.maximumFrameBytes else { throw ConnectionFailure.oversized }
            try wait(Int16(POLLIN), until: deadline)
            var buffer = [UInt8](repeating: 0, count: 4096)
            let count = Darwin.read(descriptor, &buffer, buffer.count)
            if count < 0 && (errno == EINTR || errno == EAGAIN) { continue }
            guard count > 0 else { throw ConnectionFailure.unavailable }
            pending.append(contentsOf: buffer.prefix(count))
        }
    }
    public func request(_ request: BrokerRequest, timeout: TimeInterval = ConnectionProtocol.discoveryTimeout) throws -> BrokerReply {
        try send(request)
        let reply = try receive(BrokerReply.self, timeout: timeout)
        try reply.validate(for: request)
        return reply
    }
}
#endif
