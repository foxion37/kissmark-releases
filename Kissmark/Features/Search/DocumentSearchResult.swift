import Foundation

/// One hit from Folder or Memory search. `nonisolated` so the Folder scan can build
/// results off the main actor (the app defaults to MainActor isolation).
nonisolated struct DocumentSearchResult: Identifiable, Equatable, Sendable {
    let path: String
    let title: String
    let snippet: String
    /// Memory results only: latest open.
    let lastOpenedAt: Date?
    /// Memory results only: stored security-scoped bookmark, so outside-Folder Documents reopen.
    let bookmark: Data?
    let project: String?
    let agent: String?

    var id: String { path }
    var url: URL { URL(fileURLWithPath: path) }

    init(
        path: String, title: String, snippet: String,
        lastOpenedAt: Date? = nil, bookmark: Data? = nil,
        project: String? = nil, agent: String? = nil
    ) {
        self.path = path
        self.title = title
        self.snippet = snippet
        self.lastOpenedAt = lastOpenedAt
        self.bookmark = bookmark
        self.project = project
        self.agent = agent
    }

    /// The query's range in `text`: literal, case-insensitive, canonically equivalent
    /// (Foundation's default non-literal compare, so decomposed Hangul matches precomposed).
    static func match(of query: String, in text: String) -> Range<String.Index>? {
        text.range(of: query, options: .caseInsensitive)
    }

    /// About 160 characters around the first match with whitespace collapsed;
    /// the start of `text` when there is no match.
    static func snippet(of query: String, in text: String) -> String {
        let lead = 48, length = 160
        let start: String.Index
        if let range = match(of: query, in: text) {
            start = text.index(range.lowerBound, offsetBy: -lead, limitedBy: text.startIndex) ?? text.startIndex
        } else {
            start = text.startIndex
        }
        let end = text.index(start, offsetBy: length, limitedBy: text.endIndex) ?? text.endIndex
        let window = text[start..<end].split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return (start > text.startIndex ? "…" : "") + window + (end < text.endIndex ? "…" : "")
    }
}
