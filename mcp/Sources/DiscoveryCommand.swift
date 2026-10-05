import Foundation
import Darwin
import KissmarkConnections

/// Only callers' fixed metadata commands use this runner. Never prints child bytes.
enum DiscoveryCommand {
    static func run(_ executable: String, _ arguments: [String], environment: [String: String], directory: URL? = nil, timeout: TimeInterval = ConnectionProtocol.providerTimeout, cancelled: @Sendable () -> Bool = { false }) throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.currentDirectoryURL = directory
        var child = environment
        child["PATH"] = (executable as NSString).deletingLastPathComponent + ":" + (environment["PATH"] ?? "/usr/bin:/bin")
        process.environment = child
        process.standardInput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        let pipe = Pipe()
        process.standardOutput = pipe
        let descriptor = pipe.fileHandleForReading.fileDescriptor
        _ = fcntl(descriptor, F_SETFL, O_NONBLOCK)
        do { try process.run() } catch {
            let failure = error as NSError
            let cause = (failure.userInfo[NSUnderlyingErrorKey] as? NSError) ?? failure
            if (cause.domain == NSPOSIXErrorDomain && [Int(EACCES), Int(EPERM)].contains(cause.code))
                || (failure.domain == NSCocoaErrorDomain && failure.code == NSFileReadNoPermissionError) {
                throw ConnectionFailure.accessDenied
            }
            throw ConnectionFailure.unavailable
        }
        defer {
            if process.isRunning {
                process.terminate()
                let deadline = Date().addingTimeInterval(1)
                while process.isRunning && Date() < deadline { usleep(10_000) }
                if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            }
            process.waitUntilExit()
            try? pipe.fileHandleForReading.close()
        }
        let deadline = Date().addingTimeInterval(timeout)
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 8192)
        while true {
            guard !cancelled() else { throw ConnectionFailure.cancelled }
            guard Date() < deadline else { throw ConnectionFailure.timeout }
            let count = Darwin.read(descriptor, &buffer, buffer.count)
            if count > 0 {
                guard data.count + count <= 4 * 1024 * 1024 else { throw ConnectionFailure.oversized }
                data.append(contentsOf: buffer.prefix(count))
            } else if count == 0 {
                break
            } else if errno != EAGAIN && errno != EINTR { throw ConnectionFailure.clientFailed }
            else {
                var pollDescriptor = pollfd(fd: descriptor, events: Int16(POLLIN), revents: 0)
                _ = poll(&pollDescriptor, 1, 50)
            }
        }
        while process.isRunning {
            guard !cancelled() else { throw ConnectionFailure.cancelled }
            guard Date() < deadline else { throw ConnectionFailure.timeout }
            usleep(10_000)
        }
        process.waitUntilExit()
        guard process.terminationReason == .exit, process.terminationStatus == 0 else { throw ConnectionFailure.clientFailed }
        return data
    }
}
