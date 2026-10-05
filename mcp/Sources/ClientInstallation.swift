import Foundation
import AppKit
import Darwin
import KissmarkConnections

enum ClientInstallation {
    struct Request {
        var client: ConnectionClient
        var scope: String
        var project: URL?
        var profile: String?
        var remove: Bool
        var confirmed: Bool
    }
    static func parse(_ arguments: [String]) throws -> Request {
        guard let action = arguments.first, ["install", "uninstall"].contains(action) else { throw ClientSetup.Failure.invalidRequest }
        var values: [String: String] = [:]; var confirmed = false; var index = 1
        while index < arguments.count {
            let flag = arguments[index]
            if flag == "--yes" { guard !confirmed else { throw ClientSetup.Failure.invalidRequest }; confirmed = true; index += 1; continue }
            guard ["--client", "--scope", "--project", "--profile"].contains(flag), values[flag] == nil,
                  index + 1 < arguments.count else { throw ClientSetup.Failure.invalidRequest }
            values[flag] = arguments[index + 1]; index += 2
        }
        guard let rawClient = values["--client"], let client = ConnectionClient(rawValue: rawClient),
              let scope = values["--scope"], ["user", "project"].contains(scope) else { throw ClientSetup.Failure.invalidRequest }
        var project: URL?
        if scope == "project" {
            guard let path = values["--project"], path.hasPrefix("/") else { throw ClientSetup.Failure.invalidRequest }
            var directory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: path, isDirectory: &directory), directory.boolValue else { throw ClientSetup.Failure.invalidRequest }
            project = URL(fileURLWithPath: path).standardizedFileURL
        } else if values["--project"] != nil { throw ClientSetup.Failure.invalidRequest }
        if values["--profile"] != nil, client != .omp || scope != "user" { throw ConnectionFailure.unsupported }
        if client == .claudeDesktop, scope != "user" { throw ConnectionFailure.unsupported }
        if client == .vscode, action == "uninstall", scope == "user" { throw ConnectionFailure.unsupported }
        return Request(client: client, scope: scope, project: project, profile: values["--profile"], remove: action == "uninstall", confirmed: confirmed)
    }
    static func run(arguments: [String], environment: [String: String]) -> Int32? {
        guard arguments.count > 1 else { return nil }
        let language = ClientLanguage.resolve(environment: environment)
        if arguments[1] == "--help" {
            print(language.text(korean: """
            Kissmark MCP
              kissmark-mcp setup [--codex-socket ABSOLUTE_PATH] [--yes]
              kissmark-mcp setup --remove [--yes]
              kissmark-mcp install --client CLIENT --scope user|project [--project ABSOLUTE_PATH] [--profile OMP_PROFILE] [--yes]
              kissmark-mcp uninstall --client CLIENT --scope user|project [--project ABSOLUTE_PATH] [--profile OMP_PROFILE] [--yes]
            CLIENT: claude-code, codex, omp, cursor, claude-desktop, vscode
            user = 선택한 에이전트의 사용자 공통(global) 설정. 모든 에이전트에 등록하지 않습니다.
            GUI 설치 요청은 승인 대기이며 실제 MCP 연결 성공을 뜻하지 않습니다.
            Claude Desktop 확장 제거와 VS Code 사용자 프로필 제거는 해당 앱의 설정에서 합니다.
            """, english: """
            Kissmark MCP
              kissmark-mcp setup [--codex-socket ABSOLUTE_PATH] [--yes]
              kissmark-mcp setup --remove [--yes]
              kissmark-mcp install --client CLIENT --scope user|project [--project ABSOLUTE_PATH] [--profile OMP_PROFILE] [--yes]
              kissmark-mcp uninstall --client CLIENT --scope user|project [--project ABSOLUTE_PATH] [--profile OMP_PROFILE] [--yes]
            CLIENT: claude-code, codex, omp, cursor, claude-desktop, vscode
            user = the selected agent's user-wide (global) settings. It does not register every agent.
            A GUI install request waits for approval and does not mean the MCP connection succeeded.
            Remove the Claude Desktop extension and the VS Code user-profile entry in those apps' settings.
            """))
            return 0
        }
        do {
            let request = try parse(Array(arguments.dropFirst()))
            let helper = try ClientSetup.helperPath(arguments[0])
            var env = environment
            if let profile = request.profile { env["OMP_PROFILE"] = profile }
            if request.client == .omp { _ = try ClientSetup.ompConfigPath(environment: env) }
            print(language.text(
                korean: "\(request.client.title), \(request.scope == "user" ? "사용자 공통" : "선택한 프로젝트") 범위의 kissmark 등록을 \(request.remove ? "제거" : "설정")합니다. 다른 MCP 설정과 실행 중인 세션은 유지합니다.",
                english: "\(request.remove ? "Removing" : "Setting up") the kissmark registration for \(request.client.title) in the \(request.scope == "user" ? "user-wide (global)" : "selected project") scope. Other MCP settings and running sessions are kept."))
            if !request.confirmed {
                print(language.text(korean: "계속하려면 yes를 입력하세요:", english: "Type yes to continue:"), terminator: " "); fflush(stdout)
                guard readLine() == "yes" else { print(language.text(korean: "취소했습니다.", english: "Cancelled.")); return 2 }
            }
            let pending = try apply(request, helper: helper, environment: env)
            print(pending
                ? language.text(korean: "공식 설치창에 요청했습니다. 해당 앱에서 승인하고 MCP 서버를 시작하세요. 아직 연결 성공으로 확인된 것은 아닙니다.",
                                english: "Requested in the official install dialog. Approve it in that app and start the MCP server. The connection is not confirmed yet.")
                : language.text(korean: "설정 변경 완료. Kissmark에서 다시 검색하세요. 에이전트의 MCP 다시 불러오기 또는 새 세션이 필요할 수 있습니다.",
                                english: "Settings updated. Search again in Kissmark. The agent may need an MCP reload or a new session."))
            return 0
        } catch {
            let code = (error as? ClientSetup.Failure)?.rawValue ?? (error as? ConnectionFailure)?.rawValue ?? "installation_failed"
            FileHandle.standardError.write(Data("kissmark-mcp: \(code)\n".utf8)); return 1
        }
    }
    static func apply(_ request: Request, helper: String, environment: [String: String]) throws -> Bool {
        let home = ClientSetup.homeDirectory(environment)
        let client = request.client
        var env = environment
        if let profile = request.profile { env["OMP_PROFILE"] = profile }
        var entryEnv = ["KISSMARK_CLIENT_ID": client.rawValue, "KISSMARK_CLIENT_SCOPE": request.scope]
        if client == .omp, request.scope == "user" {
            let profile = (env["OMP_PROFILE"] ?? env["PI_PROFILE"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !profile.isEmpty && profile != "default" { entryEnv["KISSMARK_CLIENT_PROFILE"] = profile }
        }
        let entry: [String: Any] = ["type": "stdio", "command": helper, "args": [String](), "env": entryEnv]
        switch client {
        case .claudeCode:
            guard let executable = ClientSetup.findExecutable("claude", environment: env) else { throw ClientSetup.Failure.clientNotFound }
            let scope = request.scope == "project" ? "project" : "user"
            if request.remove {
                let config = request.project?.appendingPathComponent(".mcp.json") ?? URL(fileURLWithPath: env["CLAUDE_CONFIG_DIR"].map { $0 + "/.claude.json" } ?? home + "/.claude.json")
                try verifyOwnership(file: config, section: "mcpServers", helper: helper)
            }
            var args = ["mcp", request.remove ? "remove" : "add", "--scope", scope]
            if !request.remove { args += ["--transport", "stdio"] }
            args.append("kissmark")
            if !request.remove { args += ["--env", "KISSMARK_CLIENT_ID=claude-code", "KISSMARK_CLIENT_SCOPE=\(request.scope)", "--", helper] }
            _ = try DiscoveryCommand.run(executable, args, environment: env, directory: request.project)
        case .codex:
            guard let executable = ClientSetup.findExecutable("codex", environment: env) else { throw ClientSetup.Failure.clientNotFound }
            if let project = request.project {
                let root = project.appendingPathComponent(".codex")
                if !request.remove { try ClientSetup.makePrivateDirectory(root) }
                env["CODEX_HOME"] = root.path
            }
            if request.remove {
                let data = try DiscoveryCommand.run(executable, ["mcp", "get", "kissmark", "--json"], environment: env)
                guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let transport = object["transport"] as? [String: Any], transport["command"] as? String == helper else { throw ClientSetup.Failure.configUnsafe }
            }
            let args = request.remove ? ["mcp", "remove", "kissmark"] : ["mcp", "add", "kissmark", "--env", "KISSMARK_CLIENT_ID=codex", "--env", "KISSMARK_CLIENT_SCOPE=\(request.scope)", "--", helper]
            _ = try DiscoveryCommand.run(executable, args, environment: env)
        case .omp:
            let file = try request.project?.appendingPathComponent(".omp/mcp.json") ?? URL(fileURLWithPath: ClientSetup.ompConfigPath(environment: env))
            try changeJSON(file: file, section: "mcpServers", entry: request.remove ? nil : entry, helper: helper, clearDisabled: true)
        case .cursor, .vscode:
            if let project = request.project {
                try changeJSON(file: project.appendingPathComponent(client == .cursor ? ".cursor/mcp.json" : ".vscode/mcp.json"),
                               section: client == .cursor ? "mcpServers" : "servers", entry: request.remove ? nil : entry, helper: helper)
            } else if request.remove {
                try changeJSON(file: URL(fileURLWithPath: home + "/.cursor/mcp.json"), section: "mcpServers", entry: nil, helper: helper)
            } else {
                var object = entry
                if client == .vscode { object["name"] = "kissmark" }
                let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
                let payload = client == .cursor ? data.base64EncodedString() : String(decoding: data, as: UTF8.self)
                let query = payload.addingPercentEncoding(withAllowedCharacters: CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"))!
                let url = client == .cursor ? "cursor://anysphere.cursor-deeplink/mcp/install?name=kissmark&config=\(query)" : "vscode:mcp/install?\(query)"
                _ = try DiscoveryCommand.run("/usr/bin/open", ["-b", client.bundleID!, url], environment: env)
                return true
            }
        case .claudeDesktop:
            guard !request.remove else { throw ConnectionFailure.unsupported }
            let bundle = URL(fileURLWithPath: helper).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Resources/kissmark.mcpb")
            guard FileManager.default.fileExists(atPath: bundle.path) else { throw ClientSetup.Failure.helperUnresolved }
            _ = try DiscoveryCommand.run("/usr/bin/open", ["-b", client.bundleID!, bundle.path], environment: env)
            return true
        }
        return false
    }
    static func verifyOwnership(file: URL, section: String, helper: String) throws {
        var status = stat()
        guard lstat(file.path, &status) == 0, status.st_mode & S_IFMT == S_IFREG, status.st_uid == getuid(), status.st_size <= 8 << 20 else { throw ClientSetup.Failure.configUnsafe }
        let config = try JSONConfiguration(Data(contentsOf: file))
        guard let servers = config.object[section] as? [String: Any], let entry = servers["kissmark"] as? [String: Any],
              entry["command"] as? String == helper else { throw ClientSetup.Failure.configUnsafe }
    }
    static func changeJSON(file: URL, section: String, entry: [String: Any]?, helper: String, clearDisabled: Bool = false) throws {
        if entry != nil {
            try ClientSetup.makePrivateDirectory(file.deletingLastPathComponent())
        } else if !FileManager.default.fileExists(atPath: file.path) {
            throw ClientSetup.Failure.configUnsafe
        }
        let lock = file.path + ".lock"
        try ClientSetup.acquireLock(lock); defer { rmdir(lock) }
        var status = stat(); var mode: mode_t?
        let data: Data
        if lstat(file.path, &status) == 0 {
            guard status.st_uid == getuid(), status.st_mode & S_IFMT == S_IFREG, status.st_size <= 8 << 20 else { throw ClientSetup.Failure.configUnsafe }
            mode = status.st_mode & 0o777
            data = try Data(contentsOf: file)
        } else {
            guard errno == ENOENT, entry != nil else { throw ClientSetup.Failure.configUnsafe }
            data = Data("{}\n".utf8)
        }
        let config = try JSONConfiguration(data)
        if entry == nil { try verifyOwnership(file: file, section: section, helper: helper) }
        var output = try config.changing(path: [section, "kissmark"], value: entry)
        if clearDisabled, let disabled = config.object["disabledServers"] {
            guard let names = disabled as? [String] else { throw ClientSetup.Failure.configMalformed }
            output = try JSONConfiguration(output).changing(path: ["disabledServers"], value: names.filter { $0 != "kissmark" })
        }
        _ = try JSONConfiguration(output)
        if output != data { try ClientSetup.atomicWrite(output, to: file, mode: mode) }
    }
}
