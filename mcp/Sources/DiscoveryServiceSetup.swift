import Foundation
import Darwin
import KissmarkConnections

/// Explicit CLI-only setup. The app and package installer never call this.
enum DiscoveryServiceSetup {
    static func run(arguments: [String], environment: [String: String]) -> Int32? {
        guard arguments.count > 1, ["setup", "_discovery"].contains(arguments[1]) else { return nil }
        let paths = DiscoveryPaths(environment: environment)
        do {
            if arguments[1] == "_discovery" {
                guard arguments.count == 2 else { throw ClientSetup.Failure.invalidRequest }
                let configuration = try readConfiguration(paths)
                let discovery = ClientDiscovery(configuration: configuration)
                try ConnectionBroker(paths: paths, discovery: discovery).run()
                return 0
            }
            let flags = Array(arguments.dropFirst(2))
            var remove = false, confirmed = false, codexSocket: String?
            var index = 0; var seen = Set<String>()
            while index < flags.count {
                let flag = flags[index]
                guard seen.insert(flag).inserted else { throw ClientSetup.Failure.invalidRequest }
                switch flag {
                case "--remove": remove = true
                case "--yes": confirmed = true
                case "--codex-socket":
                    index += 1
                    guard index < flags.count, flags[index].hasPrefix("/") else { throw ClientSetup.Failure.invalidRequest }
                    codexSocket = flags[index]
                default: throw ClientSetup.Failure.invalidRequest
                }
                index += 1
            }
            let language = ClientLanguage.resolve(environment: environment)
            let helper = try ClientSetup.helperPath(arguments[0])
            let home = ClientSetup.homeDirectory(environment)
            let label = environment["KISSMARK_DISCOVERY_LABEL"] ?? "com.singandmong.kissmark.discovery"
            guard label.range(of: #"^[a-zA-Z0-9.-]+$"#, options: .regularExpression) != nil else { throw ClientSetup.Failure.invalidRequest }
            let plist = URL(fileURLWithPath: home).appendingPathComponent("Library/LaunchAgents/\(label).plist")
            let link = URL(fileURLWithPath: home).appendingPathComponent(".local/bin/kissmark-mcp")
            print(remove
                ? language.text(korean: "현재 사용자의 Kissmark 연결 검색 기능과 CLI 링크를 제거합니다. 에이전트 MCP 설정은 유지합니다.",
                                english: "Removing the current user's Kissmark connection search and CLI link. Agent MCP settings are kept.")
                : language.text(korean: "현재 사용자용 Kissmark 연결 검색 기능을 로그인 시 실행하도록 등록하고 ~/.local/bin/kissmark-mcp를 연결합니다. 에이전트 MCP 설정은 바꾸지 않습니다.",
                                english: "Registering Kissmark connection search to run at login for the current user and linking ~/.local/bin/kissmark-mcp. Agent MCP settings are not changed."))
            if !confirmed {
                print(language.text(korean: "계속하려면 yes를 입력하세요:", english: "Type yes to continue:"), terminator: " "); fflush(stdout)
                guard readLine() == "yes" else { print(language.text(korean: "취소했습니다.", english: "Cancelled.")); return 2 }
            }
            try ClientSetup.makePrivateDirectory(paths.directory)
            let lock = paths.configuration.path + ".lock"
            try ClientSetup.acquireLock(lock); defer { rmdir(lock) }
            let target = "gui/\(getuid())"
            let service = target + "/" + label
            let existing = try ownedPlist(plist, label: label, helper: helper)
            var linkStatus = stat()
            if lstat(link.path, &linkStatus) == 0 {
                guard linkStatus.st_uid == getuid(), linkStatus.st_mode & S_IFMT == S_IFLNK,
                      try FileManager.default.destinationOfSymbolicLink(atPath: link.path) == helper else { throw ClientSetup.Failure.configUnsafe }
            } else if errno != ENOENT { throw ClientSetup.Failure.configUnsafe }
            if remove {
                if existing {
                    try stopService(service, environment: environment)
                    try FileManager.default.removeItem(at: plist)
                }
                if lstat(link.path, &linkStatus) == 0 { try FileManager.default.removeItem(at: link) }
                for file in [paths.configuration, paths.identity] {
                    if FileManager.default.fileExists(atPath: file.path) {
                        try validatePrivateFile(file); try FileManager.default.removeItem(at: file)
                    }
                }
                print(language.text(korean: "연결 검색 기능을 제거했습니다. 실행 중인 에이전트 세션은 유지했습니다.", english: "Connection search removed. Running agent sessions were kept."))
                return 0
            }
            _ = try LocalConnection.address(paths.socket)
            let configuration = DiscoveryConfiguration.capture(environment: environment, codexSocket: codexSocket)
            if FileManager.default.fileExists(atPath: paths.identity.path) { _ = try paths.installationID() }
            else { try ClientSetup.atomicWrite(try JSONEncoder().encode(UUID()), to: paths.identity, mode: nil) }
            if FileManager.default.fileExists(atPath: paths.configuration.path) { try validatePrivateFile(paths.configuration) }
            try ClientSetup.atomicWrite(try JSONEncoder().encode(configuration), to: paths.configuration, mode: nil)
            var childEnv = configuration.roots
            for key in ["KISSMARK_DISCOVERY_DATA", "KISSMARK_BUNDLE_ID"] { if let value = environment[key] { childEnv[key] = value } }
            let content: [String: Any] = ["Label": label, "ProgramArguments": [helper, "_discovery"],
                "RunAtLoad": true, "KeepAlive": ["SuccessfulExit": false], "ThrottleInterval": 10,
                "EnvironmentVariables": childEnv, "StandardOutPath": "/dev/null", "StandardErrorPath": "/dev/null"]
            if existing { try stopService(service, environment: environment) }
            try ClientSetup.atomicWrite(try PropertyListSerialization.data(fromPropertyList: content, format: .xml, options: 0), to: plist, mode: nil)
            try ClientSetup.makePrivateDirectory(link.deletingLastPathComponent())
            if lstat(link.path, &linkStatus) != 0 { try FileManager.default.createSymbolicLink(atPath: link.path, withDestinationPath: helper) }
            do {
                _ = try DiscoveryCommand.run("/bin/launchctl", ["bootstrap", target, plist.path], environment: environment)
            } catch {
                // Leave explicit setup files for inspection/removal; never claim a started service.
                print(language.text(korean: "검색 기능 시작 실패. macOS 로그인 항목 허용 상태를 확인하거나 setup --remove로 제거하세요.", english: "Could not start connection search. Check that macOS allows its login item, or remove it with setup --remove."))
                return 1
            }
            let deadline = Date().addingTimeInterval(5)
            while Date() < deadline {
                if let channel = try? LocalConnection.connect(path: paths.socket),
                   let reply = try? channel.request(BrokerRequest(.snapshot), timeout: 1), reply.snapshot != nil {
                    print(language.text(korean: "연결 검색 기능 준비 완료. CLI 경로가 PATH에 없으면 ~/.local/bin/kissmark-mcp를 사용하세요.", english: "Connection search is ready. If the CLI is not on your PATH, use ~/.local/bin/kissmark-mcp."))
                    return 0
                }
                usleep(100_000)
            }
            print(language.text(korean: "검색 기능 응답을 확인하지 못했습니다. 등록 완료를 연결 성공으로 처리하지 않습니다.", english: "Connection search did not respond. Registration is not treated as a successful connection."))
            return 1
        } catch {
            let code = (error as? ClientSetup.Failure)?.rawValue ?? (error as? ConnectionFailure)?.rawValue ?? "setup_failed"
            FileHandle.standardError.write(Data("kissmark-mcp: \(code)\n".utf8))
            if arguments[1] == "setup", code == ClientSetup.Failure.configUnsafe.rawValue {
                let home = ClientSetup.homeDirectory(environment)
                let label = environment["KISSMARK_DISCOVERY_LABEL"] ?? "com.singandmong.kissmark.discovery"
                let service = shellQuote("gui/\(getuid())/\(label)")
                let plist = URL(fileURLWithPath: home).appendingPathComponent("Library/LaunchAgents/\(label).plist").path
                let link = URL(fileURLWithPath: home).appendingPathComponent(".local/bin/kissmark-mcp").path
                let language = ClientLanguage.resolve(environment: environment)
                let guidance = language.text(korean: """
                등록 경로나 소유권이 현재 kissmark-mcp와 맞지 않아 자동으로 변경하지 않았습니다.
                앱을 옮겼다면 이전 앱의 kissmark-mcp로 setup --remove를 실행하세요.
                이전 앱이 없다면 아래 파일이 예전 Kissmark 등록인지 먼저 확인하세요.
                확인한 등록만 중지: launchctl bootout \(service)
                중지 후 해당 등록 파일과 CLI 링크를 직접 제거하고 새 앱의 절대 경로로 setup을 실행하세요.
                등록 파일: \(shellQuote(plist))
                CLI 링크: \(shellQuote(link))

                """, english: """
                The registration path or ownership does not match this helper, so nothing was changed automatically.
                If you moved the app, run setup --remove with the previous app's helper.
                If the previous app is gone, first confirm the files below are an old Kissmark registration.
                Stop only the confirmed registration: launchctl bootout \(service)
                After stopping it, remove that registration file and the CLI link yourself, then run setup with the new app's absolute path.
                Registration file: \(shellQuote(plist))
                CLI link: \(shellQuote(link))

                """)
                FileHandle.standardError.write(Data(guidance.utf8))
            }
            return 1
        }
    }
    private static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
    static func validatePrivateFile(_ file: URL) throws {
        var status = stat()
        guard lstat(file.path, &status) == 0, status.st_uid == getuid(), status.st_mode & S_IFMT == S_IFREG,
              status.st_mode & 0o077 == 0, status.st_size <= 65_536 else { throw ClientSetup.Failure.configUnsafe }
    }
    static func readConfiguration(_ paths: DiscoveryPaths) throws -> DiscoveryConfiguration {
        try validatePrivateFile(paths.configuration)
        return try JSONDecoder().decode(DiscoveryConfiguration.self, from: Data(contentsOf: paths.configuration))
    }
    private static func ownedPlist(_ path: URL, label: String, helper: String) throws -> Bool {
        var status = stat()
        guard lstat(path.path, &status) == 0 else {
            guard errno == ENOENT else { throw ClientSetup.Failure.configUnsafe }; return false
        }
        try validatePrivateFile(path)
        guard let object = try PropertyListSerialization.propertyList(from: Data(contentsOf: path), format: nil) as? [String: Any],
              object["Label"] as? String == label, object["ProgramArguments"] as? [String] == [helper, "_discovery"] else { throw ClientSetup.Failure.configUnsafe }
        return true
    }
    private static func stopService(_ service: String, environment: [String: String]) throws {
        if (try? DiscoveryCommand.run("/bin/launchctl", ["print", service], environment: environment)) != nil {
            _ = try DiscoveryCommand.run("/bin/launchctl", ["bootout", service], environment: environment)
        }
    }
}
