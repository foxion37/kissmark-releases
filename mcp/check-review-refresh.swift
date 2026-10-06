// Real app/MCP regression: switching folder roots must not swallow a later
// review request for the already-open document. Uses an isolated app copy/store.
// Run: swift mcp/check-review-refresh.swift /path/to/packaged/Kissmark.app
import AppKit
import Foundation

func failure(_ message: String) -> NSError {
    NSError(domain: "KissmarkReviewCheck", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
}

@discardableResult
func run(_ executable: String, _ arguments: [String], input: Data? = nil,
         environment: [String: String]? = nil) throws -> Data {
    let process = Process()
    let output = Pipe()
    let errors = Pipe()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    process.environment = environment
    process.standardOutput = output
    process.standardError = errors
    let stdin = Pipe()
    process.standardInput = stdin
    try process.run()
    if let input { try stdin.fileHandleForWriting.write(contentsOf: input) }
    try stdin.fileHandleForWriting.close()
    let data = output.fileHandleForReading.readDataToEndOfFile()
    let errorData = errors.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
        throw failure("\(executable) exited \(process.terminationStatus): \(String(decoding: errorData, as: UTF8.self))")
    }
    return data
}

func waitFor(_ description: String, _ condition: () throws -> Bool) throws {
    let deadline = Date().addingTimeInterval(8)
    var lastError: Error?
    repeat {
        do {
            if try condition() { return }
            lastError = nil
        } catch {
            // Readback can race the app's initial SQLite schema creation.
            lastError = error
        }
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
    } while Date() < deadline
    throw failure(lastError.map { "\(description); last error: \($0.localizedDescription)" } ?? description)
}

func main() throws {
    guard CommandLine.arguments.count == 2 else {
        throw failure("Usage: swift mcp/check-review-refresh.swift /path/to/packaged/Kissmark.app")
    }
    let fm = FileManager.default
    let source = URL(fileURLWithPath: CommandLine.arguments[1]).standardizedFileURL
    guard fm.isExecutableFile(atPath: source.appendingPathComponent("Contents/Helpers/kissmark-mcp").path) else {
        throw failure("Provide an app containing its bundled kissmark-mcp helper")
    }
    let id = "com.singandmong.kissmark.mcpcheck.\(UUID().uuidString.lowercased())"
    let stage = fm.homeDirectoryForCurrentUser.appendingPathComponent("Applications/Kissmark-MCP-check-\(UUID().uuidString)")
    let app = stage.appendingPathComponent("Kissmark.app")
    let fixtures = fm.temporaryDirectory.resolvingSymlinksInPath()
        .appendingPathComponent("Kissmark-MCP-docs-\(UUID().uuidString)")
    let container = fm.homeDirectoryForCurrentUser.appendingPathComponent("Library/Containers/\(id)")
    let store = container.appendingPathComponent("Data/Library/Application Support/Kissmark")
    let registry = "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
    defer {
        let applications = NSRunningApplication.runningApplications(withBundleIdentifier: id)
        for application in applications { _ = application.terminate() }
        let deadline = Date().addingTimeInterval(5)
        while applications.contains(where: { !$0.isTerminated }) && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        if applications.allSatisfy({ $0.isTerminated }) {
            _ = try? run(registry, ["-u", app.path])
            try? fm.removeItem(at: stage)
            try? fm.removeItem(at: fixtures)
            try? fm.removeItem(at: container)
        } else {
            fputs("QA app refused normal quit; isolated files retained at \(stage.path)\n", stderr)
        }
    }
    try fm.createDirectory(at: stage, withIntermediateDirectories: true)
    try run("/usr/bin/ditto", [source.path, app.path])
    try run("/usr/bin/plutil", ["-replace", "CFBundleIdentifier", "-string", id, app.appendingPathComponent("Contents/Info.plist").path])
    let entitlements = stage.appendingPathComponent("entitlements.plist")
    try PropertyListSerialization.data(fromPropertyList: [
        "com.apple.security.app-sandbox": true,
        "com.apple.security.files.user-selected.read-write": true,
        "com.apple.security.network.client": true
    ], format: .xml, options: 0).write(to: entitlements)
    try run("/usr/bin/codesign", ["--force", "--options", "runtime", "--entitlements", entitlements.path, "--sign", "-", app.path])
    try run(registry, ["-f", app.path])
    var environment = ProcessInfo.processInfo.environment.filter { !$0.key.hasPrefix("KISSMARK_") }
    environment["KISSMARK_BUNDLE_ID"] = id
    environment["KISSMARK_STORE_DIR"] = store.path
    let helper = app.appendingPathComponent("Contents/Helpers/kissmark-mcp")

    func call(_ name: String, _ arguments: [String: Any]) throws -> [String: Any] {
        let requests: [[String: Any]] = [
            ["jsonrpc": "2.0", "id": 1, "method": "initialize", "params": [
                "protocolVersion": "2024-11-05", "capabilities": [:],
                "clientInfo": ["name": "review-refresh-check", "version": "1"]]],
            ["jsonrpc": "2.0", "method": "notifications/initialized"],
            ["jsonrpc": "2.0", "id": 2, "method": "tools/call", "params": ["name": name, "arguments": arguments]]
        ]
        var input = Data()
        for request in requests {
            input.append(try JSONSerialization.data(withJSONObject: request))
            input.append(0x0a)
        }
        let output = try run(helper.path, [], input: input, environment: environment)
        for line in output.split(separator: 0x0a) {
            guard let reply = try JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                  reply["id"] as? Int == 2 else { continue }
            guard reply["error"] == nil, let result = reply["result"] as? [String: Any],
                  result["isError"] as? Bool != true else { throw failure("MCP \(name) returned an error") }
            return result
        }
        throw failure("MCP \(name) returned no response")
    }
    func dataResult(_ name: String, _ arguments: [String: Any]) throws -> [String: Any] {
        let result = try call(name, arguments)
        guard let content = result["content"] as? [[String: Any]], let text = content.first?["text"] as? String,
              let value = try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any] else {
            throw failure("MCP \(name) returned invalid data")
        }
        return value
    }
    let first = fixtures.appendingPathComponent("A/First.md")
    let second = fixtures.appendingPathComponent("B/Second.md")
    let quotes = ["Review after switching folders.", "Review while the same document stays open."]
    for (url, text) in [(first, "# First\n"), (second, "# Second\n\n" + quotes.joined(separator: "\n\n") + "\n")] {
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
    }
    // Opening A first establishes a workspace; opening B must replace its root.
    for document in [first, second] {
        _ = try call("open_document", ["path": document.path, "project": fixtures.path])
        var observedPath: String?
        do {
            try waitFor("App did not open \(document.lastPathComponent)") {
                let result = try dataResult("recent_documents", ["project": fixtures.path, "limit": 1])
                observedPath = (result["documents"] as? [[String: Any]])?.first?["path"] as? String
                return observedPath == document.path
            }
        } catch {
            throw failure("\(error.localizedDescription); expected \(document.path), observed \(observedPath ?? "none"), store exists: \(fm.fileExists(atPath: store.appendingPathComponent("memory.sqlite").path))")
        }
    }
    let original = try Data(contentsOf: second)
    for (index, quote) in quotes.enumerated() {
        _ = try call("add_review_points", ["path": second.path, "points": [["quote": quote]]])
        try waitFor("Same-document review request \(index + 1) was not consumed without switching documents") {
            let result = try dataResult("review_status", ["path": second.path])
            let points = result["points"] as? [[String: Any]] ?? []
            return points.count == index + 1 && points.contains { $0["quote"] as? String == quote }
        }
        print("ok: same-document review request \(index + 1) after folder change")
    }
    guard try Data(contentsOf: second) == original else { throw failure("Review changed the document file") }
    print("ok: review ingestion preserves document bytes")
}

do {
    try main()
} catch {
    fputs("FAIL: \(error.localizedDescription)\n", stderr)
    exit(1)
}
