import Foundation

enum SurfaceMessage: Equatable {
    case ready(markdown: String?, mode: DocumentMode?)
    case change(markdown: String, isFinal: Bool)
    case error(message: String)
}

/// Where JavaScript is sent. WKWebView in the app, a recorder in tests.
protocol SurfaceCommands: AnyObject {
    func setMode(_ mode: DocumentMode)
    func setViewMode(_ mode: DocumentViewMode)
    func setMarkdown(_ markdown: String)
    /// `crossfade`: run the change through the surface's palette crossfade
    /// (a view transition timed like `KissmarkMotion.theme`).
    func setStyle(_ variables: [String: String], crossfade: Bool)
    func setDocumentInfo(_ info: DocumentInfo)
    func setReview(_ review: DocumentReview)
    func reload()
}
/// Builds the JS that syncs CSS custom properties on `document.documentElement`.
/// Replaces, never merges: keys absent from `next` are removed. Every key and
/// value is emitted as a JSON string literal so quoting/injection can't break out.
/// `--km-theme-scheme` is not a custom property: it becomes
/// `documentElement.dataset.kmScheme` so `color-scheme` can key off it.
enum SurfaceStyleScript {
    static let schemeKey = DocumentThemeResolver.schemeKey

    static func styleScript(applying next: [String: String], removing previous: Set<String>) -> String {
        var lines: [String] = []
        for key in previous.subtracting(next.keys).sorted() {
            if key == schemeKey {
                lines.append("delete document.documentElement.dataset.kmScheme;")
            } else {
                lines.append("document.documentElement.style.removeProperty(\(jsonLiteral(key)));")
            }
        }
        for key in next.keys.sorted() {
            if key == schemeKey {
                lines.append("document.documentElement.dataset.kmScheme = \(jsonLiteral(next[key]!));")
            } else {
                lines.append("document.documentElement.style.setProperty(\(jsonLiteral(key)), \(jsonLiteral(next[key]!)));")
            }
        }
        return lines.joined(separator: "\n")
    }

    /// Hands `body` to the surface's style queue (`KissmarkEditor.applyStyle`):
    /// updates apply in send order, and a palette one waits inside the page
    /// crossfade together with anything sent meanwhile. Before the editor
    /// exists the body simply runs.
    static func queued(_ body: String, crossfade: Bool) -> String {
        """
        (function(apply){var e=window.KissmarkEditor;if(e&&e.applyStyle){e.applyStyle(apply,\(crossfade));}else{apply();}})(function(){
        \(body)
        });
        """
    }

    /// Whether `next` repaints the page: a theme color, the scheme, or a
    /// per-element color override differs. Sizes and spacing glide on their
    /// own (registered CSS properties), so they never need the crossfade.
    static func changesPalette(from previous: [String: String], to next: [String: String]) -> Bool {
        Set(previous.keys).union(next.keys).contains { key in
            (key == schemeKey || key.hasPrefix("--km-theme-") || key.hasSuffix("-color"))
                && previous[key] != next[key]
        }
    }

    private static func jsonLiteral(_ string: String) -> String {
        guard let data = try? JSONEncoder().encode(string),
              let literal = String(data: data, encoding: .utf8) else {
            return "\"\""
        }
        return literal
    }
}


/// Protocol state machine for the Document surface: ready handshake, echo suppression,
/// ready timeout, and the one-reload budget after a WebContent crash. Knows nothing about WebKit.
@MainActor
final class SurfaceBridge {
    static let readyTimeoutSeconds: UInt64 = 5
    static let maxTerminateReloads = 1

    private weak var commands: (any SurfaceCommands)?
    private let onTextChange: (String) -> Void
    private let onError: (String?) -> Void
    private let onReady: (() -> Void)?

    private(set) var isReady = false
    private var lastPushed: String?
    private var lastMode: DocumentMode?
    /// A freshly loaded page mounts the rendered editor, so `.render` is never pushed;
    /// a queued `.source` still is, including after a crash reload.
    private var lastViewMode: DocumentViewMode = .render
    private var lastStyle: [String: String]?
    private var lastInfo: DocumentInfo?
    private var lastReview: DocumentReview?
    private var suppressNextPush = false
    private var terminateReloads = 0

    private var pendingText = ""
    private var pendingMode: DocumentMode = .read
    private var pendingViewMode: DocumentViewMode = .render
    private var pendingStyle: [String: String] = [:]
    private var pendingInfo: DocumentInfo?
    private var pendingReview: DocumentReview?

    init(
        commands: SurfaceCommands,
        onTextChange: @escaping (String) -> Void,
        onError: @escaping (String?) -> Void,
        onReady: (() -> Void)? = nil
    ) {
        self.commands = commands
        self.onTextChange = onTextChange
        self.onError = onError
        self.onReady = onReady
    }

    func didStartLoading() {
        isReady = false
        lastPushed = nil
        lastMode = nil
        lastViewMode = .render
        lastStyle = nil
        lastInfo = nil
        lastReview = nil
        suppressNextPush = false
    }

    func update(text: String, mode: DocumentMode, viewMode: DocumentViewMode, style: [String: String]) {
        pendingText = text
        pendingMode = mode
        pendingViewMode = viewMode
        pendingStyle = style
        guard isReady else { return }
        pushIfNeeded()
    }

    /// Queues the document info; callable before the surface is ready.
    func update(info: DocumentInfo) {
        pendingInfo = info
        guard isReady else { return }
        pushIfNeeded()
    }

    /// Queues the 검토 card payload; callable before the surface is ready.
    func update(review: DocumentReview) {
        pendingReview = review
        guard isReady else { return }
        pushIfNeeded()
    }

    func receive(_ message: SurfaceMessage) {
        switch message {
        case .ready(let markdown, let mode):
            isReady = true
            terminateReloads = 0
            onError(nil)
            if let markdown { lastPushed = markdown }
            if let mode { lastMode = mode }
            pushIfNeeded()
            onReady?()
        case .change(let markdown, let isFinal):
            guard pendingMode == .edit || isFinal else { return }
            lastPushed = markdown
            // A final change that repeats the text we already have must not swallow
            // the next real push (the mode echo that follows it).
            if markdown != pendingText { suppressNextPush = true }
            onTextChange(markdown)
        case .error(let message):
            onError(message)
        }
    }

    func processDidTerminate() {
        isReady = false
        if terminateReloads < Self.maxTerminateReloads {
            terminateReloads += 1
            didStartLoading()
            commands?.reload()
            return
        }
        onError(.kissmarkLocalized("편집기 프로세스가 종료되었습니다. 앱 샌드박스의 network.client 권한을 확인하세요."))
    }

    func readyTimedOut() {
        guard !isReady else { return }
        onError(.kissmarkLocalized("편집기가 \(Int(Self.readyTimeoutSeconds))초 안에 준비되지 않았습니다."))
    }

    private func pushIfNeeded() {
        if lastMode != pendingMode {
            lastMode = pendingMode
            commands?.setMode(pendingMode)
        }
        if lastViewMode != pendingViewMode {
            lastViewMode = pendingViewMode
            commands?.setViewMode(pendingViewMode)
        }
        if lastStyle != pendingStyle {
            // The first push after a load re-states the bootstrap style: nothing to fade from.
            let crossfade = lastStyle.map { SurfaceStyleScript.changesPalette(from: $0, to: pendingStyle) } ?? false
            lastStyle = pendingStyle
            commands?.setStyle(pendingStyle, crossfade: crossfade)
        }
        if lastInfo != pendingInfo, let info = pendingInfo {
            lastInfo = info
            commands?.setDocumentInfo(info)
        }
        if lastReview != pendingReview, let review = pendingReview {
            lastReview = review
            commands?.setReview(review)
        }
        if suppressNextPush {
            suppressNextPush = false
            return
        }
        if lastPushed != pendingText {
            lastPushed = pendingText
            commands?.setMarkdown(pendingText)
        }
    }
}
