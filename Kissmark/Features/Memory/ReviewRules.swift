import Foundation

/// Pure rule scanner for review points (ADR 0028 round 2).
/// No SQLite: tests and MemoryStore both call `points(in:)`.
enum ReviewRules {
    struct Point: Equatable {
        let kind: String
        let heading: String?
        let quote: String
    }

    static let cap = 20
    static let maxQuoteLength = 200
    private static let order = ["changed", "failure", "warning", "decision", "next", "task"]
    private static let headingKinds: [(kind: String, ascii: String, korean: [String])] = [
        ("decision", "decisions?", ["결정"]),
        ("warning", "warnings?|caution|risks?", ["경고", "주의", "위험", "리스크"]),
        ("failure", "fail|failed|failures?|errors?", ["실패", "오류"]),
        ("next", "next(?: steps| actions)?|to[- ]?do|to do", ["다음", "할 일", "후속"]),
    ]

    static func points(
        in text: String,
        snapshot: String? = nil,
        checked: [Point] = []
    ) -> [Point] {
        var buckets: [String: [Point]] = [:]
        var currentHeading: String?
        var section: (heading: String, kind: String?, lines: [String])?
        var paragraph: [String] = []
        var inFence = false

        func add(_ kind: String, _ heading: String?, _ quote: String) {
            let trimmed = String(quote.trimmingCharacters(in: .whitespaces).prefix(maxQuoteLength))
            guard !trimmed.isEmpty, !checked.contains(Point(kind: kind, heading: heading, quote: trimmed)) else { return }
            buckets[kind, default: []].append(Point(kind: kind, heading: heading, quote: trimmed))
        }
        func flushSection() {
            guard let closed = section, let kind = closed.kind else {
                section = nil
                return
            }
            for line in closed.lines
            where taskQuote(line) == nil && line.range(of: "^\\s*[-*+]\\s+\\[", options: .regularExpression) == nil {
                let quote = stripMarkers(line)
                if !quote.isEmpty {
                    add(kind, closed.heading, quote)
                    break
                }
            }
            section = nil
        }
        func flushParagraph() {
            let body = paragraph.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            paragraph = []
            guard let snapshot,
                  !body.isEmpty,
                  !(body.first == "#" && !body.contains("\n")),
                  !snapshot.contains(body)
            else { return }
            add("changed", currentHeading, body.split(separator: "\n", omittingEmptySubsequences: false).first.map(String.init) ?? body)
        }

        var lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        if lines.first?.trimmingCharacters(in: .whitespaces) == "---",
           let end = lines.indices.dropFirst().first(where: { lines[$0].trimmingCharacters(in: .whitespaces) == "---" }) {
            lines.removeSubrange(0...end)
        }

        for line in lines {
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                flushParagraph()
                inFence.toggle()
                continue
            }
            guard !inFence else { continue }
            if let headingText = atxHeadingText(line) {
                flushParagraph()
                flushSection()
                currentHeading = headingText
                section = (headingText, kind(of: headingText), [])
                continue
            }
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                flushParagraph()
            } else {
                paragraph.append(line)
            }
            if let task = taskQuote(line) {
                add("task", currentHeading, task)
            }
            section?.lines.append(line)
        }
        flushParagraph()
        flushSection()

        return order.flatMap { buckets[$0] ?? [] }.prefix(cap).map { $0 }
    }

    /// Heading text of an ATX heading line, else nil.
    static func atxHeadingText(_ line: String) -> String? {
        guard let range = line.range(of: "^#{1,6}[ \\t]+(.+?)\\s*$", options: .regularExpression) else { return nil }
        let inner = line[range]
        guard let start = inner.firstIndex(where: { !" #\t".contains($0) }) else { return nil }
        return String(inner[start...]).trimmingCharacters(in: .whitespaces)
    }

    private static func kind(of heading: String) -> String? {
        for entry in headingKinds {
            if heading.range(of: "\\b(?:\(entry.ascii))\\b", options: [.regularExpression, .caseInsensitive]) != nil {
                return entry.kind
            }
            if entry.korean.contains(where: heading.contains) { return entry.kind }
        }
        return nil
    }

    /// Unchecked task item text (`- [ ] …`), else nil.
    private static func taskQuote(_ line: String) -> String? {
        guard let match = firstMatch(of: "^\\s*[-*+]\\s+\\[ \\]\\s+(.+?)\\s*$", in: line), match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: line)
        else { return nil }
        return String(line[range]).trimmingCharacters(in: .whitespaces)
    }

    private static func firstMatch(of pattern: String, in line: String) -> NSTextCheckingResult? {
        try? NSRegularExpression(pattern: pattern).firstMatch(in: line, range: NSRange(line.startIndex..., in: line))
    }

    /// Strips leading list (`-` `*` `+`), quote (`>`) and number markers.
    private static func stripMarkers(_ line: String) -> String {
        var result = line
        while let range = result.range(of: "^\\s*(?:[-*+]|>|\\d+[.)])[ \\t]+", options: .regularExpression) {
            result.removeSubrange(range)
        }
        return result.trimmingCharacters(in: .whitespaces)
    }
}
