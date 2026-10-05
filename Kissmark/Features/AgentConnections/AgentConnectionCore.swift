#if os(macOS)
import AppKit
import Foundation
import KissmarkConnections

struct ConnectionSelectionStore {
    struct State: Codable {
        var version = 1
        var installationID: UUID
        var selections: Set<SelectionKey>
    }
    let file: URL
    func load(for installationID: UUID) -> Set<SelectionKey> {
        guard let data = try? Data(contentsOf: file), data.count <= 65_536,
              let state = try? JSONDecoder().decode(State.self, from: data), state.version == 1,
              state.installationID == installationID else { return [] }
        return state.selections
    }
    func save(_ selections: Set<SelectionKey>, installationID: UUID) throws {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let data = try JSONEncoder().encode(State(installationID: installationID, selections: selections))
        try data.write(to: file, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    }
}

enum ConnectionEncoding {
    static func shellQuote(_ value: String) -> String { "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'" }
    /// Only the helper's own prompts are localized; every argument stays language-independent.
    static func languagePrefix(_ language: String) -> String? {
        ["ko", "en"].contains(language) ? "KISSMARK_LANGUAGE=" + shellQuote(language) : nil
    }
    static func setupCommand(helper: URL, language: String) -> String? {
        languagePrefix(language).map { "\($0) \(shellQuote(helper.path)) setup" }
    }
    static func installCommand(helper: URL, client: ConnectionClient, scope: String, project: URL?, profile: String, language: String) -> String? {
        guard let prefix = languagePrefix(language), ["user", "project"].contains(scope), client != .claudeDesktop || scope == "user" else { return nil }
        var arguments = [prefix, shellQuote(helper.path), "install", "--client", shellQuote(client.rawValue), "--scope", scope]
        if scope == "project" {
            guard let project else { return nil }
            arguments += ["--project", shellQuote(project.path)]
        }
        if client == .omp, scope == "user", !profile.isEmpty {
            guard profile.range(of: #"^[a-z0-9][a-z0-9._-]{0,63}$"#, options: .regularExpression) != nil,
                  !profile.hasSuffix(".") else { return nil }
            arguments += ["--profile", shellQuote(profile)]
        }
        return arguments.joined(separator: " ")
    }
}

enum AgentConnectionFiles {
    static var support: URL { FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Kissmark") }
    static var helper: URL { Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/kissmark-mcp") }
    static var socket: String { FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("tmp/kmd.sock").path }
    static func lastHandshake(_ client: ConnectionClient) -> Date? {
        let url = support.appendingPathComponent("connections/\(client.rawValue).json")
        guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]),
              values.isRegularFile == true, values.isSymbolicLink != true, (values.fileSize ?? 4097) <= 4096,
              let data = try? Data(contentsOf: url), let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              object["client"] as? String == client.rawValue, let at = object["connected_at"] as? Double, at.isFinite, at > 0 else { return nil }
        return Date(timeIntervalSince1970: at)
    }
}
#endif
