import SwiftUI

/// One find command for the Document surface (`KissmarkEditor.find` in `_editor-build/entry.js`).
/// `id` correlates the asynchronous answer: only the newest id is ever accepted.
/// `step`: 0 = search, 1 / -1 = next / previous match (wraps).
struct DocumentFindRequest: Equatable, Encodable, Sendable {
    var id = 0
    var query = ""
    var caseSensitive = false
    var wholeWord = false
    var regex = false
    var step = 0
}

/// The surface's answer: `active` is a 0-based index, -1 when nothing matches.
struct DocumentFindResult: Equatable, Sendable {
    var id: Int
    var total: Int
    var active: Int
    var invalidRegex: Bool
}

/// Find-in-Document state for one open Document. The Document surface performs the
/// search (rendered ProseMirror view or CodeMirror source view) and answers through
/// `receive(_:)`; nothing here touches the Markdown text.
@MainActor @Observable
final class DocumentFindModel {
    var isPresented = false
    var query = ""
    var caseSensitive = false
    var wholeWord = false
    var useRegex = false

    /// Bumped by `present()` so an already open bar takes focus again.
    private(set) var focusToken = 0
    /// Latest command; the surface sends it when its `id` changes.
    private(set) var request = DocumentFindRequest()
    private(set) var total = 0
    /// 0-based index of the active match; `nil` when there is none.
    private(set) var activeIndex: Int?
    private(set) var isInvalidRegex = false
    private var nextID = 0

    /// Shows the bar (⌘F) and re-runs a remembered query.
    func present() {
        isPresented = true
        focusToken += 1
        if !query.isEmpty { search() }
    }

    /// ⌘G. A closed bar opens on the remembered query instead of stepping.
    func next() { step(1) }

    /// ⇧⌘G.
    func previous() { step(-1) }

    /// Hides the bar and clears the highlights; the query text stays for the next ⌘F.
    func close() {
        isPresented = false
        reset()
        issue(step: 0, query: "")
    }

    /// The query or an option changed: search again from the first match.
    func search() {
        reset()
        issue(step: 0, query: query)
    }

    /// Applies the surface's answer. Returns `false` (and changes nothing) for a stale id.
    @discardableResult
    func receive(_ result: DocumentFindResult) -> Bool {
        guard result.id == request.id, isPresented else { return false }
        total = result.total
        activeIndex = result.active >= 0 && result.active < result.total ? result.active : nil
        isInvalidRegex = result.invalidRegex
        return true
    }

    private func step(_ direction: Int) {
        guard isPresented else { present(); return }
        guard !query.isEmpty else { return }
        issue(step: direction, query: query)
    }

    private func reset() {
        total = 0
        activeIndex = nil
        isInvalidRegex = false
    }

    private func issue(step: Int, query: String) {
        nextID += 1
        request = DocumentFindRequest(
            id: nextID,
            query: query,
            caseSensitive: caseSensitive,
            wholeWord: wholeWord,
            regex: useRegex,
            step: step
        )
    }
}

extension FocusedValues {
    @Entry var documentFind: DocumentFindModel?
}
