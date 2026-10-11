// Real WKWebView regression check against a built app's flattened Resources.
// xcrun swiftc -parse-as-library scripts/check-document-find.swift -o /tmp/kissmark-find-check
// /tmp/kissmark-find-check <Kissmark.app/Contents/Resources> <screenshot.png>
// Uses fixture text and a non-persistent website store, never user documents.
import AppKit
import WebKit

@MainActor
final class SearchProbe: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
    let resources: URL
    let output: URL
    let webView: WKWebView
    let window: NSWindow
    var finished = false
    var started = false
    var changes = 0
    var latestFind: [String: Any] = [:]

    init(resources: URL, output: URL) {
        self.resources = resources
        self.output = output
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        let text = "# 검색 검증\n\nAlpha alpha 가나다.\n\n**Alpha** 가나다.\n"
        let data = try! JSONSerialization.data(withJSONObject: ["text": text])
        let payload = String(decoding: data, as: UTF8.self)
        config.userContentController.addUserScript(WKUserScript(source: "window.__KISSMARK_INITIAL_MARKDOWN__ = (\(payload)).text; window.__KISSMARK_INITIAL_MODE__ = 'read';", injectionTime: .atDocumentStart, forMainFrameOnly: true))
        webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 900, height: 650), configuration: config)
        window = NSWindow(contentRect: webView.frame, styleMask: [.titled, .closable], backing: .buffered, defer: false)
        super.init()
        config.userContentController.add(self, name: "kissmark")
        webView.navigationDelegate = self
        window.title = "Kissmark Search QA (isolated)"
        window.contentView = webView
    }

    func start() {
        window.orderFront(nil)
        webView.loadFileURL(resources.appendingPathComponent("editor.html"), allowingReadAccessTo: resources)
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(30))
            if !finished { finish("FAIL: WebKit smoke timeout", code: 2) }
        }
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let value = message.body as? [String: Any], let type = value["type"] as? String else { return }
        if type == "change" { changes += 1 }
        if type == "find" { latestFind = value }
        guard type == "ready", !started else { return }
        started = true
        Task { @MainActor in
            do { try await exercise(); finish("PASS: real WebKit find, options, source/read/edit, refresh and nonmutation", code: 0) }
            catch { finish("FAIL: \(error)", code: 1) }
        }
    }

    func js(_ code: String, _ args: [String: Any] = [:]) async throws -> Any? {
        try await webView.callAsyncJavaScript(code, arguments: args, in: nil, contentWorld: .page)
    }

    func require(_ condition: Bool, _ label: String) throws {
        if !condition { throw NSError(domain: label, code: 1) }
    }

    func find(_ id: Int, _ query: String, caseSensitive: Bool = false, wholeWord: Bool = false, regex: Bool = false, step: Int = 0) async throws -> [String: Any] {
        let request: [String: Any] = ["id": id, "query": query, "caseSensitive": caseSensitive, "wholeWord": wholeWord, "regex": regex, "step": step]
        guard let value = try await js("return await window.KissmarkEditor.find(request);", ["request": request]) as? [String: Any] else { throw NSError(domain: "find-result-shape", code: 1) }
        return value
    }

    func exercise() async throws {
        let before = try await js("return window.KissmarkEditor.getMarkdown();") as? String
        var result = try await find(1, "alpha")
        try require(result["total"] as? Int == 3 && result["active"] as? Int == 0, "literal-count")
        result = try await find(2, "alpha", step: 1)
        try require(result["active"] as? Int == 1, "next")
        result = try await find(3, "alpha", step: -1)
        try require(result["active"] as? Int == 0, "previous")
        result = try await find(4, "Alpha", caseSensitive: true)
        try require(result["total"] as? Int == 2, "case-sensitive")
        result = try await find(5, "Al", wholeWord: true)
        try require(result["total"] as? Int == 0, "whole-word")
        result = try await find(6, "Alpha|가나다", regex: true)
        try require(result["total"] as? Int == 5, "regex-korean")
        result = try await find(7, "[", regex: true)
        try require(result["error"] as? String == "invalid-regex", "invalid-regex")
        result = try await find(8, "^", regex: true)
        try require(result["total"] as? Int == 3, "zero-width-rendered")
        _ = try await js("await window.KissmarkEditor.setViewMode('source');")
        result = try await find(9, "\\*\\*Alpha\\*\\*", regex: true)
        try require(result["total"] as? Int == 1 && result["view"] as? String == "source", "source-markdown")
        result = try await find(10, "^", regex: true)
        try require(result["total"] as? Int == 6, "zero-width-source")
        _ = try await find(11, "")
        let cleared = try await js("return document.querySelectorAll('.km-find-match').length;") as? Int
        try require(cleared == 0, "clear-highlights")
        _ = try await js("await window.KissmarkEditor.setMode('edit'); await window.KissmarkEditor.setViewMode('render');")
        let after = try await js("return window.KissmarkEditor.getMarkdown();") as? String
        try require(before == after && changes == 0, "find-must-not-edit-document")
        result = try await find(12, "alpha")
        try require(result["total"] as? Int == 3, "edit-mode-find")
        let inserted = try await js("window.KissmarkEditor.focus(); const el=document.querySelector('.ProseMirror'); const range=document.createRange(); range.selectNodeContents(el); range.collapse(false); const selection=window.getSelection(); selection.removeAllRanges(); selection.addRange(range); return document.execCommand('insertText',false,' Alpha');") as? Bool
        try require(inserted == true, "real-dom-edit")
        try await Task.sleep(for: .milliseconds(500))
        try require(latestFind["total"] as? Int == 4 && changes > 0, "edit-refreshes-find")
        _ = try await js("await window.KissmarkEditor.setMode('read');")
        result = try await find(13, "alpha", step: 1)
        try require(result["total"] as? Int == 4, "read-after-edit")
        let image = try await webView.takeSnapshot(configuration: nil)
        if let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff), let png = bitmap.representation(using: .png, properties: [:]) {
            try png.write(to: output)
        } else { throw NSError(domain: "snapshot", code: 1) }
        print("SCREENSHOT=\(output.path)")
        _ = try await js("""
            const filler = Array.from({length: 100}, (_, i) => 'Spacer ' + i).join('\\n\\n');
            await window.KissmarkEditor.setMarkdown('```js\\nconst fencedNeedle = 1;\\n```\\n\\n' + filler + '\\n\\n```js\\nconst fencedNeedle = 2;\\n```\\n');
            """)
        let codeBefore = try await js("return window.KissmarkEditor.getMarkdown();") as? String
        let changesBefore = changes
        result = try await find(14, "fencedNeedle")
        try require(result["total"] as? Int == 2, "fenced-code-count")
        try await visibleCodeMatch(block: 0)
        let offscreen = try await js("return !document.querySelectorAll('.milkdown-code-block')[1].querySelector('.cm-editor');") as? Bool
        try require(offscreen == true, "fixture-must-exercise-lazy-code-view")
        result = try await find(15, "fencedNeedle", step: 1)
        try require(result["active"] as? Int == 1, "next-code-block")
        try await visibleCodeMatch(block: 1)
        result = try await find(16, "fencedNeedle", step: -1)
        try require(result["active"] as? Int == 0, "previous-code-block")
        try await visibleCodeMatch(block: 0)
        try await waitForDOM("return !document.querySelectorAll('.milkdown-code-block')[1].querySelector('.cm-editor');", label: "offscreen-code-teardown", attempts: 150)
        _ = try await find(17, "fencedNeedle", step: 1)
        try await visibleCodeMatch(block: 1)
        _ = try await find(18, "")
        let codeAfter = try await js("return window.KissmarkEditor.getMarkdown();") as? String
        try require(codeBefore == codeAfter && changes == changesBefore, "code-find-must-not-edit")
        let codeCleared = try await js("return document.querySelectorAll('.km-find-match').length === 0;") as? Bool
        try require(codeCleared == true, "code-highlights-clear")
        print("FENCED_CODE_LAZY_REVEAL_CLEAR_NONMUTATION=PASS")
    }

    func waitForDOM(_ predicate: String, label: String, attempts: Int = 60) async throws {
        for _ in 0..<attempts {
            if try await js(predicate) as? Bool == true { return }
            try await Task.sleep(for: .milliseconds(50))
        }
        throw NSError(domain: label, code: 1)
    }

    func visibleCodeMatch(block: Int) async throws {
        try await waitForDOM("""
            const el = document.querySelectorAll('.milkdown-code-block')[\(block)]?.querySelector('.km-find-active');
            if (!el || el.textContent !== 'fencedNeedle') return false;
            const r = el.getBoundingClientRect();
            return r.width > 0 && r.top >= 0 && r.bottom <= innerHeight;
            """, label: "visible-active-code-match-\(block)")
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { finish("FAIL: WebKit navigation", code: 2) }

    func finish(_ message: String, code: Int32) {
        guard !finished else { return }
        finished = true
        print(message)
        window.orderOut(nil)
        exit(code)
    }
}

@main
struct Runner {
    @MainActor static func main() {
        guard CommandLine.arguments.count == 3 else {
            print("Usage: kissmark-find-check <Kissmark.app/Contents/Resources> <screenshot.png>")
            exit(64)
        }
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let probe = SearchProbe(resources: URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true), output: URL(fileURLWithPath: CommandLine.arguments[2]))
        probe.start()
        withExtendedLifetime(probe) { app.run() }
    }
}
