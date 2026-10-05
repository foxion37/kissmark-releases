import Foundation
import KissmarkConnections

/// Shared filesystem safety, native profile resolution, and historical receipts.
enum ClientSetup {

    /// Fixed, secret-free failure codes that may appear in receipts.
    enum Failure: String, Error {
        case invalidRequest = "invalid_request"
        case clientNotFound = "client_not_found"
        case configMalformed = "config_malformed"
        case configUnsafe = "config_unsafe"
        case configLocked = "config_locked"
        case writeFailed = "write_failed"
        case helperUnresolved = "helper_unresolved"
    }

    static func recordHandshake(clientID: String?, directory: URL) {
        guard let id = clientID, ConnectionClient(rawValue: id) != nil else { return }
        let dir = directory.appendingPathComponent("connections", isDirectory: true)
        let receipt: [String: Any] = ["version": 1, "client": id,
                                      "connected_at": Int(Date().timeIntervalSince1970)]
        guard let data = try? JSONSerialization.data(withJSONObject: receipt, options: [.sortedKeys]) else { return }
        try? atomicWrite(data, to: dir.appendingPathComponent("\(id).json"), mode: nil)
    }

    static func isRunnable(_ path: String) -> Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDir) && !isDir.boolValue
            && FileManager.default.isExecutableFile(atPath: path)
    }

    static func findExecutable(_ name: String, environment: [String: String]) -> String? {
        let home = homeDirectory(environment)
        let conventional = [".local/bin", ".bun/bin", ".local/share/mise/shims",
                            ".local/share/mise/installs/node/lts/bin", ".npm-global/bin", ".claude/local"]
            .map { home + "/" + $0 } + ["/opt/homebrew/bin", "/usr/local/bin"]
        let fromPath = (environment["PATH"] ?? "").split(separator: ":").map(String.init).filter { $0.hasPrefix("/") }
        for dir in fromPath + conventional {
            let candidate = dir + "/" + name
            if isRunnable(candidate) { return candidate }
        }
        return nil
    }

    static func helperPath(_ argv0: String) throws -> String {
        var path = argv0.contains("/") ? argv0 : (Bundle.main.executablePath ?? "")
        if !path.hasPrefix("/") { path = path.isEmpty ? "" : FileManager.default.currentDirectoryPath + "/" + path }
        guard !path.isEmpty, let resolved = realpath(path, nil) else { throw Failure.helperUnresolved }
        path = String(cString: resolved)
        free(resolved)
        guard isRunnable(path) else { throw Failure.helperUnresolved }
        return path
    }

    // MARK: OMP

    static func homeDirectory(_ env: [String: String]) -> String {
        if let h = env["HOME"], h.hasPrefix("/") { return h }
        return NSHomeDirectory()
    }

    static func ompConfigPath(environment env: [String: String]) throws -> String {
        let home = homeDirectory(env)
        let configName = env["PI_CONFIG_DIR"].flatMap { $0.isEmpty ? nil : $0 } ?? ".omp"
        // OMP uses path.join(home, configName), not an absolute-root override.
        let root = URL(fileURLWithPath: home + "/" + configName, isDirectory: true).standardizedFileURL.path
        func profileName(_ raw: String?) throws -> String? {
            guard let name = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !name.isEmpty, name != "default" else { return nil }
            guard name.range(of: #"^[a-z0-9][a-z0-9._-]{0,63}$"#, options: .regularExpression) != nil,
                  !name.hasSuffix("."),
                  name.range(of: #"^(con|prn|aux|nul|com[0-9]|lpt[0-9])(\..*)?$"#, options: .regularExpression) == nil
            else { throw Failure.invalidRequest }
            return name
        }
        let profile = try profileName(env["OMP_PROFILE"] ?? env["PI_PROFILE"])
        let agent: String
        if let profile {
            agent = root + "/profiles/" + profile + "/agent"
        } else {
            var override = env["PI_CODING_AGENT_DIR"]
            if let inherited = try? profileName(env["PI_PROFILE"]),
               override == root + "/profiles/" + inherited + "/agent" {
                override = nil
            }
            if let override, !override.isEmpty {
                let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
                agent = URL(fileURLWithPath: override, relativeTo: cwd).standardizedFileURL.path
            } else {
                agent = root + "/agent"
            }
        }
        return URL(fileURLWithPath: agent).standardizedFileURL.path + "/mcp.json"
    }

    /// mkdir lock, same protocol as the official writer. Never breaks someone else's lock.
    static func acquireLock(_ path: String) throws {
        if mkdir(path, 0o700) == 0 { return }
        throw errno == EEXIST ? Failure.configLocked : Failure.writeFailed
    }

    // MARK: Files

    static func makePrivateDirectory(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
    }

    /// Unique temp (O_EXCL|O_NOFOLLOW, 0600) + fsync + rename. Refuses to replace a symlink or non-file.
    static func atomicWrite(_ data: Data, to url: URL, mode: mode_t?) throws {
        let dir = url.deletingLastPathComponent()
        try makePrivateDirectory(dir)
        var st = stat()
        if lstat(url.path, &st) == 0, (st.st_mode & S_IFMT) != S_IFREG { throw Failure.configUnsafe }
        let tmp = dir.appendingPathComponent(".\(url.lastPathComponent).\(UUID().uuidString).tmp").path
        let fd = open(tmp, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
        guard fd >= 0 else { throw Failure.writeFailed }
        var ok = true
        data.withUnsafeBytes { raw in
            var off = 0
            while off < raw.count {
                let n = write(fd, raw.baseAddress! + off, raw.count - off)
                if n <= 0 { if n < 0 && errno == EINTR { continue }; ok = false; return }
                off += n
            }
        }
        if ok, let m = mode { ok = fchmod(fd, m) == 0 }
        if ok { ok = fsync(fd) == 0 }
        close(fd)
        guard ok, rename(tmp, url.path) == 0 else { unlink(tmp); throw Failure.writeFailed }
    }
}
