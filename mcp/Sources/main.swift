// kissmark-mcp: stdio MCP server that lets an agent show a Markdown Document in
// Kissmark (ADR 0026) and list/search the app's document memory (ADR 0028).
// Newline-delimited JSON-RPC 2.0 on stdin/stdout.
// The file is handed over through LaunchServices (`open -b`), which also gives the
// sandboxed app access to that one file, exactly like a Finder double-click.
import Foundation
import SQLite3

let processEnvironment = ProcessInfo.processInfo.environment
if let code = DiscoveryServiceSetup.run(arguments: CommandLine.arguments, environment: processEnvironment)
    ?? ClientInstallation.run(arguments: CommandLine.arguments, environment: processEnvironment) {
    exit(code)
}

/// `KISSMARK_BUNDLE_ID` targets a differently stamped build (e.g. a local dev copy).
let bundleID = ProcessInfo.processInfo.environment["KISSMARK_BUNDLE_ID"] ?? "com.singandmong.kissmark"
let markdownExtensions: Set<String> = ["md", "markdown"]
/// `KISSMARK_STORE_DIR` overrides the whole store directory (tests, dev builds).
let storeOverride = ProcessInfo.processInfo.environment["KISSMARK_STORE_DIR"]
/// `host` provenance, captured from `initialize` `clientInfo.name`.
var clientHost: String?

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// JSON-safe optional string (nil becomes NSNull, which serializes as null).
func jsonValue(_ string: String?) -> Any { string ?? NSNull() }

/// Schema of one review point, shared by `open_document` and `add_review_points`.
let reviewPointSchema: [String: Any] = [
    "type": "object",
    "properties": [
        "heading": ["type": "string", "description": "Heading the point belongs under."],
        "quote": ["type": "string", "description": "Exact sentence from the document (1-500 characters)."],
        "note": ["type": "string", "description": "Why the user should check this."]
    ],
    "required": ["quote"]
]

let openDocumentTool: [String: Any] = [
    "name": "open_document",
    "description": "Show a Markdown file in the Kissmark window. Use it to put an agent-written "
        + "document (plan, report, review) in front of the user.",
    "inputSchema": [
        "type": "object",
        "properties": [
            "path": [
                "type": "string",
                "description": "Path to a .md or .markdown file; relative paths resolve against the server's working directory."
            ],
            "project": [
                "type": "string",
                "description": "Project the open belongs to; defaults to the git root of the server's working directory."
            ],
            "agent": [
                "type": "string",
                "description": "Name of the calling agent, recorded as provenance."
            ],
            "session": [
                "type": "string",
                "description": "Session identifier, recorded as provenance."
            ],
            "points": [
                "type": "array",
                "description": "Up to 20 review points for the user to check. Each point: {heading?, quote, note?}; quote is an exact sentence from the document (max 500 characters).",
                "items": reviewPointSchema
            ]
        ],
        "required": ["path"]
    ]
]

let recentDocumentsTool: [String: Any] = [
    "name": "recent_documents",
    "description": "List documents Kissmark opened recently, newest first, one entry per path.",
    "inputSchema": [
        "type": "object",
        "properties": [
            "limit": [
                "type": "integer",
                "description": "Maximum number of documents (1-100, default 20)."
            ],
            "project": [
                "type": "string",
                "description": "Keep only documents with an open under this project."
            ],
            "agent": [
                "type": "string",
                "description": "Keep only documents with an open whose agent or host equals this."
            ]
        ]
    ]
]

let searchDocumentsTool: [String: Any] = [
    "name": "search_documents",
    "description": "Search document titles and bodies (case-insensitive for ASCII), newest first.",
    "inputSchema": [
        "type": "object",
        "properties": [
            "query": [
                "type": "string",
                "description": "Text to look for in titles and bodies."
            ],
            "limit": [
                "type": "integer",
                "description": "Maximum number of documents (1-100, default 20)."
            ],
            "project": [
                "type": "string",
                "description": "Keep only documents with an open under this project."
            ],
            "agent": [
                "type": "string",
                "description": "Keep only documents with an open whose agent or host equals this."
            ]
        ],
        "required": ["query"]
    ]
]

let addReviewPointsTool: [String: Any] = [
    "name": "add_review_points",
    "description": "Queue review points for a Markdown document and open it in Kissmark, where the user can check them.",
    "inputSchema": [
        "type": "object",
        "properties": [
            "path": [
                "type": "string",
                "description": "Path to a .md or .markdown file; relative paths resolve against the server's working directory."
            ],
            "points": [
                "type": "array",
                "description": "Up to 20 review points. Each point: {heading?, quote, note?}; quote is an exact sentence from the document (max 500 characters).",
                "items": reviewPointSchema
            ],
            "agent": [
                "type": "string",
                "description": "Name of the calling agent, recorded as provenance."
            ],
            "session": [
                "type": "string",
                "description": "Session identifier, recorded as provenance."
            ]
        ],
        "required": ["path", "points"]
    ]
]

let reviewStatusTool: [String: Any] = [
    "name": "review_status",
    "description": "Report the review state of a document: completion time and its review points in creation order. Read-only.",
    "inputSchema": [
        "type": "object",
        "properties": [
            "path": [
                "type": "string",
                "description": "Path of the document; relative paths resolve against the server's working directory."
            ]
        ],
        "required": ["path"]
    ]
]

enum ToolError: Error { case message(String) }

func storeDirectory() -> URL {
    if let override = storeOverride, !override.isEmpty {
        return URL(fileURLWithPath: override, isDirectory: true)
    }
    return FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Containers/\(bundleID)/Data/Library/Application Support/Kissmark",
                                isDirectory: true)
}

/// The one normalized path form shared with the app.
func normalizedPath(_ rawPath: String) -> String {
    let expanded = (rawPath as NSString).expandingTildeInPath
    let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
    return URL(fileURLWithPath: expanded, relativeTo: cwd)
        .standardizedFileURL.resolvingSymlinksInPath().path.precomposedStringWithCanonicalMapping
}

/// The `project` argument, else the git root of the working directory, else the working directory.
func derivedProject() -> String {
    let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        .standardizedFileURL.resolvingSymlinksInPath()
    var dir = cwd
    while FileManager.default.fileExists(atPath: dir.appendingPathComponent(".git").path) == false {
        guard dir.path != "/" else { return cwd.path }
        dir = dir.deletingLastPathComponent()
    }
    return dir.path
}

/// Writes the provenance queue entry the app consumes when it opens the file.
func writeQueueEntry(path: String, project: String?, agent: String?, session: String?,
                     kind: String = "open", points: [[String: Any]]? = nil) throws -> URL {
    let queue = storeDirectory().appendingPathComponent("queue", isDirectory: true)
    try FileManager.default.createDirectory(at: queue, withIntermediateDirectories: true)
    let name = "\(Int64(Date().timeIntervalSince1970 * 1000))-\(UUID().uuidString).json"
    var body: [String: Any] = [
        "version": 1,
        "kind": kind,
        "path": path,
        "requested_at": Date().timeIntervalSince1970,
        "project": jsonValue(project),
        "host": jsonValue(clientHost),
        "agent": jsonValue(agent),
        "session": jsonValue(session)
    ]
    if let points { body["points"] = points }
    let data = try JSONSerialization.data(withJSONObject: body, options: [.withoutEscapingSlashes])
    try data.write(to: queue.appendingPathComponent(name + ".tmp"))
    let target = queue.appendingPathComponent(name)
    try FileManager.default.moveItem(at: queue.appendingPathComponent(name + ".tmp"), to: target)
    return target
}

/// Resolves the path and checks it is an openable Markdown file.
func validatedMarkdownPath(_ rawPath: String) throws -> String {
    let path = normalizedPath(rawPath)
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) else {
        throw ToolError.message("File not found: \(path)")
    }
    guard !isDirectory.boolValue, markdownExtensions.contains(URL(fileURLWithPath: path).pathExtension.lowercased()) else {
        throw ToolError.message("Not a Markdown file (.md or .markdown): \(path)")
    }
    return path
}

/// Asks LaunchServices to open the file in Kissmark; throws when that fails.
func launchInKissmark(path: String) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
    process.arguments = ["-b", bundleID, path]
    let stderr = Pipe()
    process.standardError = stderr
    process.standardOutput = FileHandle.nullDevice
    do {
        try process.run()
    } catch {
        throw ToolError.message("Could not launch /usr/bin/open: \(error)")
    }
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
        let detail = String(decoding: stderr.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        throw ToolError.message("Kissmark could not open the file (is Kissmark installed?): \(detail)")
    }
}

let noPointsNudge = " No review points were given. Read the document and call add_review_points with up to 5 points "
    + "({heading, quote, note}) the user should check; quote must be an exact sentence from the document."

/// Resolves and checks the path, records provenance, then asks LaunchServices to open it.
func openDocument(_ rawPath: String, project: String?, agent: String?, session: String?,
                  points: [[String: Any]]?) throws -> String {
    let path = try validatedMarkdownPath(rawPath)
    let entry = try writeQueueEntry(path: path,
                                    project: project ?? derivedProject(),
                                    agent: agent,
                                    session: session,
                                    points: points)
    do {
        try launchInKissmark(path: path)
    } catch {
        try? FileManager.default.removeItem(at: entry)
        throw error
    }
    return "Opened \(path) in Kissmark." + (points == nil ? noPointsNudge : "")
}

/// Queues review points and opens the document so the app ingests them.
func addReviewPoints(_ rawPath: String, points: [[String: Any]], agent: String?, session: String?) throws -> String {
    let path = try validatedMarkdownPath(rawPath)
    let entry = try writeQueueEntry(path: path,
                                    project: nil,
                                    agent: agent,
                                    session: session,
                                    kind: "review_points",
                                    points: points)
    do {
        try launchInKissmark(path: path)
    } catch {
        try? FileManager.default.removeItem(at: entry)
        throw error
    }
    return "Queued \(points.count) review point(s) for \(path); Kissmark ingests them on the open."
}

/// Validates the `points` tool argument; nil when absent or empty.
func pointsArgument(_ arguments: [String: Any]) throws -> [[String: Any]]? {
    guard let raw = arguments["points"] else { return nil }
    guard let list = raw as? [[String: Any]] else {
        throw ToolError.message("points must be an array of point objects")
    }
    guard list.count <= 20 else {
        throw ToolError.message("At most 20 review points, got \(list.count)")
    }
    var points: [[String: Any]] = []
    for item in list {
        guard let quote = item["quote"] as? String, !quote.isEmpty else {
            throw ToolError.message("Each review point needs a non-empty quote")
        }
        guard quote.count <= 500 else {
            throw ToolError.message("Review point quotes are limited to 500 characters")
        }
        points.append(["heading": jsonValue(item["heading"] as? String),
                       "quote": quote,
                       "note": jsonValue(item["note"] as? String)])
    }
    return points.isEmpty ? nil : points
}

/// `%`-escapes a LIKE pattern and wraps it for a substring match.
func likePattern(_ query: String) -> String {
    let escaped = query
        .replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "%", with: "\\%")
        .replacingOccurrences(of: "_", with: "\\_")
    return "%\(escaped)%"
}

let documentColumns = """
    SELECT d.path, d.title, d.last_opened_at, o.opener, o.project, o.host, o.agent, t.body
    FROM documents d
    JOIN opens o ON o.id = (SELECT id FROM opens WHERE path = d.path ORDER BY opened_at DESC, id DESC LIMIT 1)
    LEFT JOIN document_text t ON t.path = d.path
    """

/// Reads documents from the read-only memory database; missing DB means no history yet.
func fetchDocuments(searchQuery: String?, project: String?, agent: String?, limit: Int) throws -> [[String: Any]] {
    let dbPath = storeDirectory().appendingPathComponent("memory.sqlite").path
    guard FileManager.default.fileExists(atPath: dbPath) else { return [] }
    var db: OpaquePointer?
    // Read-write handle, query-only: a SQLITE_OPEN_READONLY handle cannot open a WAL
    // store whose -shm is missing (restored or copied stores). query_only still
    // guarantees this process never changes data; the app stays the only writer.
    guard sqlite3_open_v2(dbPath, &db, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK, let db,
          sqlite3_exec(db, "PRAGMA query_only = ON", nil, nil, nil) == SQLITE_OK else {
        sqlite3_close(db)
        throw ToolError.message("Could not open memory database: \(dbPath)")
    }
    defer { sqlite3_close(db) }

    var sql = documentColumns + "\nWHERE 1=1\n"
    var bindings: [String] = []
    if let searchQuery {
        let pattern = likePattern(searchQuery)
        sql += " AND (d.title LIKE ? ESCAPE '\\' OR t.body LIKE ? ESCAPE '\\')\n"
        bindings += [pattern, pattern]
    }
    if let project {
        sql += " AND EXISTS (SELECT 1 FROM opens p WHERE p.path = d.path AND p.project = ?)\n"
        bindings.append(project)
    }
    if let agent {
        sql += " AND EXISTS (SELECT 1 FROM opens p WHERE p.path = d.path AND (p.agent = ? OR p.host = ?))\n"
        bindings += [agent, agent]
    }
    sql += " ORDER BY d.last_opened_at DESC, d.path LIMIT ?"

    var stmt: OpaquePointer?
    guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
        throw ToolError.message("Could not read memory database \(dbPath): \(String(cString: sqlite3_errmsg(db)))")
    }
    defer { sqlite3_finalize(stmt) }
    for (offset, value) in bindings.enumerated() {
        sqlite3_bind_text(stmt, Int32(offset + 1), value, -1, SQLITE_TRANSIENT)
    }
    sqlite3_bind_int(stmt, Int32(bindings.count + 1), Int32(limit))

    var rows: [[String: Any]] = []
    while sqlite3_step(stmt) == SQLITE_ROW {
        func text(_ column: Int32) -> String? {
            guard let cString = sqlite3_column_text(stmt, column) else { return nil }
            return String(cString: cString)
        }
        let title = text(1) ?? ""
        let body = text(7)
        var row: [String: Any] = [
            "path": text(0) ?? "",
            "title": title,
            "last_opened_at": ISO8601DateFormatter().string(from: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 2))),
            "opener": text(3) ?? "user",
            "project": jsonValue(text(4)),
            "host": jsonValue(text(5)),
            "agent": jsonValue(text(6))
        ]
        if let searchQuery, let body {
            row["snippet"] = snippet(body: body, query: searchQuery)
        }
        rows.append(row)
    }
    return rows
}

/// Up to 160 characters of body around the first (case-insensitive) match.
func snippet(body: String, query: String) -> String {
    guard let range = body.range(of: query, options: .caseInsensitive) else {
        return String(body.prefix(160))
    }
    let offset = body.distance(from: body.startIndex, to: range.lowerBound)
    let start = body.index(body.startIndex, offsetBy: max(0, offset - 48), limitedBy: body.endIndex) ?? body.endIndex
    let end = body.index(start, offsetBy: 160, limitedBy: body.endIndex) ?? body.endIndex
    return String(body[start..<end])
}

/// The review state of one document; missing store or pre-v2 store yields null/empty.
func fetchReviewStatus(_ rawPath: String) throws -> [String: Any] {
    let path = normalizedPath(rawPath)
    var status: [String: Any] = ["path": path, "completed_at": NSNull(), "points": []]
    let dbPath = storeDirectory().appendingPathComponent("memory.sqlite").path
    guard FileManager.default.fileExists(atPath: dbPath) else { return status }
    var db: OpaquePointer?
    // Read-write handle, query-only: see fetchDocuments.
    guard sqlite3_open_v2(dbPath, &db, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK, let db,
          sqlite3_exec(db, "PRAGMA query_only = ON", nil, nil, nil) == SQLITE_OK else {
        sqlite3_close(db)
        throw ToolError.message("Could not open memory database: \(dbPath)")
    }
    defer { sqlite3_close(db) }

    func text(_ stmt: OpaquePointer, _ column: Int32) -> String? {
        guard let cString = sqlite3_column_text(stmt, column) else { return nil }
        return String(cString: cString)
    }
    func iso(_ stmt: OpaquePointer, _ column: Int32) -> String {
        ISO8601DateFormatter().string(from: Date(timeIntervalSince1970: sqlite3_column_double(stmt, column)))
    }

    if let stmt = try? preparedStatement(db, "SELECT completed_at FROM review_completions WHERE path = ?", [path]) {
        defer { sqlite3_finalize(stmt) }
        if sqlite3_step(stmt) == SQLITE_ROW {
            status["completed_at"] = iso(stmt, 0)
        }
    }
    if let stmt = try? preparedStatement(db, """
        SELECT id, source, kind, heading, quote, note, checked_at, comment, agent
        FROM review_points WHERE path = ? ORDER BY created_at, id
        """, [path]) {
        defer { sqlite3_finalize(stmt) }
        var points: [[String: Any]] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            points.append([
                "id": Int(sqlite3_column_int64(stmt, 0)),
                "source": text(stmt, 1) ?? "",
                "kind": text(stmt, 2) ?? "",
                "heading": jsonValue(text(stmt, 3)),
                "quote": text(stmt, 4) ?? "",
                "note": jsonValue(text(stmt, 5)),
                "checked_at": sqlite3_column_type(stmt, 6) == SQLITE_NULL ? NSNull() : iso(stmt, 6),
                "comment": jsonValue(text(stmt, 7)),
                "agent": jsonValue(text(stmt, 8))
            ])
        }
        status["points"] = points
    }
    return status
}

/// Prepares a bound statement; throws when the SQL fails (e.g. pre-v2 store).
private func preparedStatement(_ db: OpaquePointer, _ sql: String, _ bindings: [String]) throws -> OpaquePointer {
    var stmt: OpaquePointer?
    guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
        throw ToolError.message(String(cString: sqlite3_errmsg(db)))
    }
    for (offset, value) in bindings.enumerated() {
        sqlite3_bind_text(stmt, Int32(offset + 1), value, -1, SQLITE_TRANSIENT)
    }
    return stmt
}

func optionalArgument(_ arguments: [String: Any], _ name: String) -> String? {
    guard let value = arguments[name] as? String, !value.isEmpty else { return nil }
    return value
}

func limitArgument(_ arguments: [String: Any]) -> Int {
    let raw = (arguments["limit"] as? NSNumber)?.intValue ?? 20
    return min(max(raw, 1), 100)
}

func toolResult(_ text: String, isError: Bool) -> [String: Any] {
    ["content": [["type": "text", "text": text]], "isError": isError]
}

func documentsResult(_ documents: [[String: Any]]) -> [String: Any] {
    let json = ["documents": documents]
    let text = (try? JSONSerialization.data(withJSONObject: json, options: [.withoutEscapingSlashes, .sortedKeys]))
        .flatMap { String(data: $0, encoding: .utf8) } ?? "{\"documents\": []}"
    return toolResult(text, isError: false)
}

/// Returns the JSON-RPC result, or an error object; nil means a notification (no reply).
func handle(method: String, params: [String: Any]) -> (result: Any?, error: [String: Any]?) {
    switch method {
    case "initialize":
        clientHost = (params["clientInfo"] as? [String: Any])?["name"] as? String
        let version = params["protocolVersion"] as? String ?? "2025-06-18"
        return ([
            "protocolVersion": version,
            "capabilities": ["tools": [String: Any]()],
            "serverInfo": ["name": "kissmark", "version": "0.4.0"]
        ], nil)
    case "ping":
        return ([String: Any](), nil)
    case "tools/list":
        return (["tools": [openDocumentTool, recentDocumentsTool, searchDocumentsTool,
                           addReviewPointsTool, reviewStatusTool]], nil)
    case "tools/call":
        let arguments = params["arguments"] as? [String: Any] ?? [:]
        switch params["name"] as? String {
        case "open_document":
            guard let path = arguments["path"] as? String, !path.isEmpty else {
                return (toolResult("Missing required argument: path", isError: true), nil)
            }
            do {
                let points = try pointsArgument(arguments)
                return (toolResult(try openDocument(path,
                                                    project: optionalArgument(arguments, "project"),
                                                    agent: optionalArgument(arguments, "agent"),
                                                    session: optionalArgument(arguments, "session"),
                                                    points: points),
                                    isError: false), nil)
            } catch ToolError.message(let message) {
                return (toolResult(message, isError: true), nil)
            } catch {
                return (toolResult("\(error)", isError: true), nil)
            }
        case "add_review_points":
            guard let path = arguments["path"] as? String, !path.isEmpty else {
                return (toolResult("Missing required argument: path", isError: true), nil)
            }
            do {
                guard let points = try pointsArgument(arguments) else {
                    return (toolResult("Missing required argument: points", isError: true), nil)
                }
                return (toolResult(try addReviewPoints(path,
                                                       points: points,
                                                       agent: optionalArgument(arguments, "agent"),
                                                       session: optionalArgument(arguments, "session")),
                                    isError: false), nil)
            } catch ToolError.message(let message) {
                return (toolResult(message, isError: true), nil)
            } catch {
                return (toolResult("\(error)", isError: true), nil)
            }
        case "review_status":
            guard let path = arguments["path"] as? String, !path.isEmpty else {
                return (toolResult("Missing required argument: path", isError: true), nil)
            }
            do {
                let json = try JSONSerialization.data(withJSONObject: try fetchReviewStatus(path),
                                                      options: [.withoutEscapingSlashes, .sortedKeys])
                return (toolResult(String(data: json, encoding: .utf8) ?? "{}", isError: false), nil)
            } catch ToolError.message(let message) {
                return (toolResult(message, isError: true), nil)
            } catch {
                return (toolResult("\(error)", isError: true), nil)
            }
        case "recent_documents":
            do {
                return (documentsResult(try fetchDocuments(searchQuery: nil,
                                                           project: optionalArgument(arguments, "project"),
                                                           agent: optionalArgument(arguments, "agent"),
                                                           limit: limitArgument(arguments))), nil)
            } catch ToolError.message(let message) {
                return (toolResult(message, isError: true), nil)
            } catch {
                return (toolResult("\(error)", isError: true), nil)
            }
        case "search_documents":
            guard let query = arguments["query"] as? String, !query.isEmpty else {
                return (toolResult("Missing required argument: query", isError: true), nil)
            }
            do {
                return (documentsResult(try fetchDocuments(searchQuery: query,
                                                           project: optionalArgument(arguments, "project"),
                                                           agent: optionalArgument(arguments, "agent"),
                                                           limit: limitArgument(arguments))), nil)
            } catch ToolError.message(let message) {
                return (toolResult(message, isError: true), nil)
            } catch {
                return (toolResult("\(error)", isError: true), nil)
            }
        default:
            return (nil, ["code": -32602, "message": "Unknown tool: \(params["name"] ?? "")"])
        }
    default:
        return (nil, ["code": -32601, "message": "Method not found: \(method)"])
    }
}

let outputLock = NSLock()

func send(_ object: [String: Any]) {
    guard var data = try? JSONSerialization.data(withJSONObject: object, options: [.withoutEscapingSlashes]) else { return }
    data.append(0x0A)
    outputLock.lock()
    defer { outputLock.unlock() }
    FileHandle.standardOutput.write(data)
}

let connectionPresence = MCPConnectionPresence(environment: ProcessInfo.processInfo.environment, send: send)
defer { connectionPresence.stop() }

while let line = readLine() {
    guard let data = line.data(using: .utf8),
          let message = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        if !line.trimmingCharacters(in: .whitespaces).isEmpty {
            send(["jsonrpc": "2.0", "id": NSNull(), "error": ["code": -32700, "message": "Parse error"]])
        }
        continue
    }
    if connectionPresence.receiveResponse(message) { continue }
    guard let method = message["method"] as? String else { continue }
    if method == "notifications/initialized" {
        connectionPresence.didInitialize()
        continue
    }
    let (result, error) = handle(method: method, params: message["params"] as? [String: Any] ?? [:])
    // Notifications (no id) never get a reply.
    guard let id = message["id"], !(id is NSNull) else { continue }
    if let error {
        send(["jsonrpc": "2.0", "id": id, "error": error])
    } else {
        send(["jsonrpc": "2.0", "id": id, "result": result ?? [String: Any]()])
        if method == "initialize" {
            connectionPresence.didRespondToInitialize()
            ClientSetup.recordHandshake(
                clientID: ProcessInfo.processInfo.environment["KISSMARK_CLIENT_ID"],
                directory: storeDirectory()
            )
        }
    }
}
