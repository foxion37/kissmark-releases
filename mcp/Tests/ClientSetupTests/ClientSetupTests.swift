import XCTest
import KissmarkConnections
@testable import kissmark_mcp

final class ClientSetupTests: XCTestCase {
    var root: URL!
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("kissmark-setup-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDown() { try? FileManager.default.removeItem(at: root) }
    var entry: [String: Any] { ["command": "/H/kissmark", "env": ["KISSMARK_CLIENT_ID": "omp"]] }

    func testJSONCPreservesOtherSettingsAndOnlyClearsKissmarkDisable() throws {
        let file = root.appendingPathComponent("mcp.json")
        let original = """
        {
          // keep the user's comments
          "other": {"number": 9007199254740993},
          "mcpServers": {"untouched": {"command": "keep"}, "kissmark": {"command": "old"},},
          "disabledServers": ["kissmark", "untouched"],
        }
        """
        try Data(original.utf8).write(to: file)
        chmod(file.path, 0o640)
        try ClientInstallation.changeJSON(file: file, section: "mcpServers", entry: entry, helper: "/H/kissmark", clearDisabled: true)
        let text = try String(contentsOf: file)
        XCTAssertTrue(text.contains("// keep the user's comments"))
        XCTAssertTrue(text.contains("9007199254740993"))
        let parsed = try JSONConfiguration(Data(text.utf8))
        XCTAssertEqual(parsed.object["disabledServers"] as? [String], ["untouched"])
        let servers = parsed.object["mcpServers"] as! [String: Any]
        XCTAssertEqual((servers["untouched"] as? [String: String])?["command"], "keep")
        XCTAssertEqual((servers["kissmark"] as? [String: Any])?["command"] as? String, "/H/kissmark")
        XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? Int, 0o640)
        let first = try Data(contentsOf: file)
        try ClientInstallation.changeJSON(file: file, section: "mcpServers", entry: entry, helper: "/H/kissmark", clearDisabled: true)
        XCTAssertEqual(try Data(contentsOf: file), first)
        try ClientInstallation.changeJSON(file: file, section: "mcpServers", entry: nil, helper: "/H/kissmark", clearDisabled: true)
        let removed = try JSONConfiguration(Data(contentsOf: file)).object["mcpServers"] as! [String: Any]
        XCTAssertNil(removed["kissmark"]); XCTAssertNotNil(removed["untouched"])
    }
    func testJSONMutationRejectsMalformedLockedAndSymlinkInputsUnchanged() throws {
        let file = root.appendingPathComponent("mcp.json")
        for source in ["{", "[]", #"{"mcpServers":[]}"#, #"{"mcpServers":{},"mcpServers":{}}"#, #"{"disabledServers":"bad"}"#] {
            try Data(source.utf8).write(to: file)
            XCTAssertThrowsError(try ClientInstallation.changeJSON(file: file, section: "mcpServers", entry: entry, helper: "/H/kissmark", clearDisabled: true))
            XCTAssertEqual(try String(contentsOf: file), source)
        }
        try Data("{}".utf8).write(to: file)
        try FileManager.default.createDirectory(atPath: file.path + ".lock", withIntermediateDirectories: true)
        XCTAssertThrowsError(try ClientInstallation.changeJSON(file: file, section: "mcpServers", entry: entry, helper: "/H/kissmark"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path + ".lock"))
        let link = root.appendingPathComponent("link.json")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: file)
        XCTAssertThrowsError(try ClientInstallation.changeJSON(file: link, section: "mcpServers", entry: entry, helper: "/H/kissmark"))
        XCTAssertEqual(try String(contentsOf: file), "{}")
    }
    func testProjectScopeNeverWritesUserOMPConfiguration() throws {
        let project = root.appendingPathComponent("project")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        let request = try ClientInstallation.parse(["install", "--client", "omp", "--scope", "project", "--project", project.path])
        let env = ["HOME": root.path, "OMP_PROFILE": "work", "PI_CODING_AGENT_DIR": root.appendingPathComponent("agent").path]
        XCTAssertFalse(try ClientInstallation.apply(request, helper: "/H/kissmark", environment: env))
        XCTAssertTrue(FileManager.default.fileExists(atPath: project.appendingPathComponent(".omp/mcp.json").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent(".omp").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("agent").path))
    }
    func testScopeAndOwnershipMustBeExplicit() throws {
        for args in [
            ["install", "--client", "omp"],
            ["install", "--client", "codex", "--scope", "project"],
            ["install", "--client", "claude-desktop", "--scope", "project", "--project", root.path],
            ["install", "--client", "codex", "--scope", "user", "--profile", "work"],
        ] { XCTAssertThrowsError(try ClientInstallation.parse(args)) }
        let file = root.appendingPathComponent("mcp.json")
        let source = #"{"mcpServers":{"kissmark":{"command":"not-ours"}}}"#
        try Data(source.utf8).write(to: file)
        XCTAssertThrowsError(try ClientInstallation.changeJSON(file: file, section: "mcpServers", entry: nil, helper: "/H/kissmark"))
        XCTAssertEqual(try String(contentsOf: file), source)
    }
    func testOMPProfilePrecedence() throws {
        let home = ["HOME": "/Users/u"]
        XCTAssertEqual(try ClientSetup.ompConfigPath(environment: home), "/Users/u/.omp/agent/mcp.json")
        XCTAssertEqual(try ClientSetup.ompConfigPath(environment: home.merging(["OMP_PROFILE": "work", "PI_CODING_AGENT_DIR": "/custom"]) { $1 }), "/Users/u/.omp/profiles/work/agent/mcp.json")
        XCTAssertEqual(try ClientSetup.ompConfigPath(environment: home.merging(["OMP_PROFILE": "default", "PI_CODING_AGENT_DIR": "/custom"]) { $1 }), "/custom/mcp.json")
        XCTAssertEqual(try ClientSetup.ompConfigPath(environment: home.merging(["OMP_PROFILE": "", "PI_PROFILE": "work", "PI_CODING_AGENT_DIR": "/Users/u/.omp/profiles/work/agent"]) { $1 }), "/Users/u/.omp/agent/mcp.json")
        for value in ["../bad", "UPPER", "con", "ends."] { XCTAssertThrowsError(try ClientSetup.ompConfigPath(environment: home.merging(["OMP_PROFILE": value]) { $1 })) }
    }
    func testHistoricalHandshakeUsesOnlyFixedFieldsAndRefusesSymlink() throws {
        ClientSetup.recordHandshake(clientID: "omp", directory: root)
        let file = root.appendingPathComponent("connections/omp.json")
        let value = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as! [String: Any]
        XCTAssertEqual(Set(value.keys), ["version", "client", "connected_at"])
        try FileManager.default.removeItem(at: file)
        let victim = root.appendingPathComponent("victim")
        try Data("keep".utf8).write(to: victim)
        try FileManager.default.createSymbolicLink(at: file, withDestinationURL: victim)
        ClientSetup.recordHandshake(clientID: "omp", directory: root)
        ClientSetup.recordHandshake(clientID: "../outside", directory: root)
        XCTAssertEqual(try String(contentsOf: victim), "keep")
    }
    func testInstalledCLISymlinkResolvesToBundleIdentity() throws {
        let executable = root.appendingPathComponent("app-helper")
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: executable)
        chmod(executable.path, 0o755)
        let link = root.appendingPathComponent("kissmark-mcp")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: executable)
        let resolved = try ClientSetup.helperPath(link.path)
        var actual = stat(), expected = stat()
        XCTAssertEqual(lstat(resolved, &actual), 0)
        XCTAssertEqual(stat(executable.path, &expected), 0)
        XCTAssertEqual(actual.st_mode & S_IFMT, S_IFREG)
        XCTAssertEqual(actual.st_dev, expected.st_dev)
        XCTAssertEqual(actual.st_ino, expected.st_ino)
    }
    func testMissingProjectUninstallCreatesNoConfigurationDirectories() throws {
        for (client, directory) in [("omp", ".omp"), ("cursor", ".cursor"), ("vscode", ".vscode")] {
            let request = try ClientInstallation.parse(["uninstall", "--client", client, "--scope", "project", "--project", root.path])
            XCTAssertThrowsError(try ClientInstallation.apply(request, helper: "/H/kissmark", environment: ["HOME": root.path]))
            XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent(directory).path))
        }
    }
}
