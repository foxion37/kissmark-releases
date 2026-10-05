import SwiftUI
import WebKit
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Shared Document surface for Read Mode and Edit Mode (one WKWebView + Milkdown).
struct DocumentSurfaceView: View {
    @Binding var text: String
    var mode: DocumentMode
    var viewMode: DocumentViewMode = .render
    /// Document info for the surface's in-flow `#docinfo` header (`nil` = nothing pushed).
    var info: DocumentInfo?
    /// Called when the user toggles the info accordion in the surface.
    var onInfoExpanded: ((Bool) -> Void)? = nil
    /// 검토 card payload (`nil` = nothing pushed), its accordion toggle, and its actions.
    var review: DocumentReview? = nil
    var onReviewExpanded: ((Bool) -> Void)? = nil
    var onReviewAction: ((ReviewAction) -> Void)? = nil
    @State private var surfaceError: String?
    @State private var surfaceOpacity = 0.0
    @State private var isSurfaceReady = false
    @State private var surfaceTransitionTask: Task<Void, Never>?
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(KissmarkTextSize.storageKey) private var textSizeID = KissmarkTextSize.medium.rawValue
    @AppStorage(KissmarkTextAlignment.storageKey) private var textAlignID = KissmarkTextAlignment.start.rawValue
    @AppStorage(DesignOverrides.storageKey) private var designJSON = ""
    @AppStorage(DocumentTheme.storageKey) private var themeID = DocumentTheme.system.rawValue
    @AppStorage(ThemeAccentOverrides.storageKey) private var accentJSON = ""

    private var theme: DocumentTheme { DocumentTheme(rawValue: themeID) ?? .system }
    private var accentHex: String {
        ThemeAccentOverrides.decode(accentJSON).accent(for: theme, scheme: colorScheme) ?? ""
    }
    private var systemPalette: ThemePalette { DocumentThemeResolver.systemPalette(for: colorScheme) }
    private var paperColor: Color {
        Color(kissmarkHex: DocumentThemeResolver.palette(theme: theme, scheme: colorScheme, system: systemPalette).bg) ?? Color.clear
    }

    var body: some View {
        ZStack {
            // Paper sits behind the (initially transparent) surface so no white
            // or window-colored frame shows before the editor reports ready.
            paperColor

            DocumentSurfaceRepresentable(
                text: $text,
                mode: mode,
                viewMode: viewMode,
                info: info,
                review: review,
                onReviewExpanded: onReviewExpanded,
                onReviewAction: onReviewAction,
                onInfoExpanded: onInfoExpanded,
                textSize: KissmarkTextSize(rawValue: textSizeID) ?? .medium,
                textAlign: KissmarkTextAlignment(rawValue: textAlignID) ?? .start,
                design: DesignOverrides.decode(designJSON),
                theme: theme,
                accentHex: accentHex,
                colorScheme: colorScheme,
                isReady: $isSurfaceReady,
                surfaceError: $surfaceError
            )
            .opacity(surfaceOpacity)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(mode == .read ? "document-reader" : "document-editor")

            if let surfaceError {
                VStack(spacing: 12) {
                    Text("문서 화면을 불러오지 못했습니다")
                        .font(KissmarkType.font(.headline))
                    Text(surfaceError)
                        .font(KissmarkType.font(.caption))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(24)
                .frame(maxWidth: 360)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                .accessibilityIdentifier("document-surface-error")
            }
        }
        .onAppear {
            // Re-appearing after a ready must not stay transparent: the fade-in
            // only runs on the false → true edge.
            if isSurfaceReady { surfaceOpacity = 1 }
            if !designJSON.isEmpty, DesignOverrides.decode(designJSON).isEmpty {
                designJSON = ""
            }
        }
        .onChange(of: isSurfaceReady) { _, ready in
            guard ready else { return }
            surfaceTransitionTask?.cancel()
            surfaceTransitionTask = nil
            withAnimation(KissmarkMotion.documentOpen(reduceMotion: reduceMotion)) {
                surfaceOpacity = 1
            }
        }
        .onChange(of: mode) { _, _ in
            // The surface itself never reloads on Lock/Unlock; this is only the dip.
            surfaceTransitionTask?.cancel()
            guard isSurfaceReady else { return }
            surfaceOpacity = KissmarkMotion.documentSurfaceTransitionOpacity
            surfaceTransitionTask = Task { @MainActor in
                do {
                    try await Task.sleep(
                        nanoseconds: KissmarkMotion.documentSurfaceFadeDelayNanoseconds
                    )
                } catch {
                    return
                }
                guard !Task.isCancelled else { return }
                withAnimation(KissmarkMotion.documentOpen(reduceMotion: reduceMotion)) {
                    surfaceOpacity = 1
                }
            }
        }
        .onDisappear {
            surfaceTransitionTask?.cancel()
            surfaceTransitionTask = nil
        }
    }
}

#if os(macOS)
private typealias PlatformViewRepresentable = NSViewRepresentable
private typealias PlatformColor = NSColor
#else
private typealias PlatformViewRepresentable = UIViewRepresentable
private typealias PlatformColor = UIColor
#endif

private struct DocumentSurfaceRepresentable: PlatformViewRepresentable {
    @Binding var text: String
    var mode: DocumentMode
    var viewMode: DocumentViewMode
    var info: DocumentInfo?
    var review: DocumentReview?
    var onReviewExpanded: ((Bool) -> Void)?
    var onReviewAction: ((ReviewAction) -> Void)?
    var onInfoExpanded: ((Bool) -> Void)?
    var textSize: KissmarkTextSize
    var textAlign: KissmarkTextAlignment
    var design: DesignOverrides
    var theme: DocumentTheme
    var accentHex: String
    var colorScheme: ColorScheme
    @Binding var isReady: Bool
    @Binding var surfaceError: String?

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, isReady: $isReady, surfaceError: $surfaceError)
    }

    #if os(macOS)
    func makeNSView(context: Context) -> WKWebView { makeWebView(context: context) }
    func updateNSView(_ webView: WKWebView, context: Context) { update(webView, context: context) }
    #else
    func makeUIView(context: Context) -> WKWebView { makeWebView(context: context) }
    func updateUIView(_ webView: WKWebView, context: Context) { update(webView, context: context) }
    #endif

    private var systemPalette: ThemePalette {
        DocumentThemeResolver.systemPalette(for: colorScheme)
    }

    private var style: [String: String] {
        var vars = DocumentThemeResolver.cssVariables(
            theme: theme,
            accentHex: accentHex,
            scheme: colorScheme,
            system: systemPalette
        )
        vars.merge(design.cssVariables(for: colorScheme)) { _, user in user }
        vars["--km-font-scale"] = String(textSize.scale)
        vars["--km-text-align"] = textAlign.cssValue
        if let family = KissmarkType.webBodyFontFamily { vars["--km-font-body"] = family }
        return vars
    }

    private var paperHex: String {
        DocumentThemeResolver.palette(theme: theme, scheme: colorScheme, system: systemPalette).bg
    }

    private func update(_ webView: WKWebView, context: Context) {
        context.coordinator.onInfoExpanded = onInfoExpanded
        context.coordinator.onReviewExpanded = onReviewExpanded
        context.coordinator.onReviewAction = onReviewAction
        context.coordinator.update(text: text, mode: mode, viewMode: viewMode, style: style, info: info, review: review)
        applyPaperColor(to: webView)
    }

    private func makeWebView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        configuration.websiteDataStore = .nonPersistent()
        configuration.userContentController.add(context.coordinator, name: "kissmark")

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        context.coordinator.onInfoExpanded = onInfoExpanded
        context.coordinator.onReviewExpanded = onReviewExpanded
        context.coordinator.onReviewAction = onReviewAction
        applyPaperColor(to: webView)
        context.coordinator.attach(
            webView,
            initialText: text,
            initialMode: mode,
            initialViewMode: viewMode,
            initialStyle: style,
            initialInfo: info,
            initialReview: review
        )
        return webView
    }

    private func applyPaperColor(to webView: WKWebView) {
        let paper = PlatformColor(Color(kissmarkHex: paperHex) ?? .clear)
        #if os(macOS)
        webView.setValue(false, forKey: "drawsBackground")
        webView.underPageBackgroundColor = paper
        #else
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.underPageBackgroundColor = paper
        #endif
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler, SurfaceCommands {
        private(set) var bridge: SurfaceBridge!
        private let textBinding: Binding<String>
        private let isReady: Binding<Bool>
        private let surfaceError: Binding<String?>
        private weak var webView: WKWebView?
        var onInfoExpanded: ((Bool) -> Void)?
        var onReviewExpanded: ((Bool) -> Void)?
        var onReviewAction: ((ReviewAction) -> Void)?
        private var readyTimeoutTask: Task<Void, Never>?
        /// Runs 텍스트 정리 (Edit Mode only — the surface's JS guards the mode).
        /// The 일반 tab's toggle gates the whole feature.
        @AppStorage(KissmarkTextLint.storageKey) private var isTextLintEnabled = true
        private var lintObserver: NSObjectProtocol?
        private var bootstrap: (
            text: String,
            mode: DocumentMode,
            viewMode: DocumentViewMode,
            style: [String: String],
            info: DocumentInfo?,
            review: DocumentReview?
        ) = ("", .read, .render, [:], nil, nil)
        private var appliedStyleKeys: Set<String> = []

        init(text: Binding<String>, isReady: Binding<Bool>, surfaceError: Binding<String?>) {
            textBinding = text
            self.isReady = isReady
            self.surfaceError = surfaceError
            super.init()
            bridge = SurfaceBridge(
                commands: self,
                onTextChange: { [textBinding] in textBinding.wrappedValue = $0 },
                onError: { [surfaceError] in surfaceError.wrappedValue = $0 },
                onReady: { [isReady] in isReady.wrappedValue = true }
            )
        }

        func attach(
            _ webView: WKWebView,
            initialText: String,
            initialMode: DocumentMode,
            initialViewMode: DocumentViewMode,
            initialStyle: [String: String],
            initialInfo: DocumentInfo?,
            initialReview: DocumentReview?
        ) {
            self.webView = webView
            lintObserver = NotificationCenter.default.addObserver(
                forName: .kissmarkCleanTypography, object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.cleanTypography() }
            }
            update(text: initialText, mode: initialMode, viewMode: initialViewMode, style: initialStyle, info: initialInfo, review: initialReview)
            loadSurface()
        }

        deinit {
            if let lintObserver {
                NotificationCenter.default.removeObserver(lintObserver)
            }
        }

        /// Keeps the bootstrap payload in sync with the latest Swift state so a
        /// reload after WebContent termination remounts the current document.
        func update(
            text: String,
            mode: DocumentMode,
            viewMode: DocumentViewMode,
            style: [String: String],
            info: DocumentInfo?,
            review: DocumentReview?
        ) {
            bootstrap = (text, mode, viewMode, style, info, review)
            bridge.update(text: text, mode: mode, viewMode: viewMode, style: style)
            if let info { bridge.update(info: info) }
            if let review { bridge.update(review: review) }
        }

        // MARK: SurfaceCommands

        func setMode(_ mode: DocumentMode) {
            evaluate("window.KissmarkEditor && window.KissmarkEditor.setMode('\(mode == .read ? "read" : "edit")');")
        }

        func setViewMode(_ mode: DocumentViewMode) {
            evaluate("window.KissmarkEditor && window.KissmarkEditor.setViewMode('\(mode == .source ? "source" : "render")');")
        }

        func setMarkdown(_ markdown: String) {
            evaluate("""
            (function(){
              var raw = atob('\(Self.base64(markdown))');
              var bytes = Uint8Array.from(raw, function(c){ return c.charCodeAt(0); });
              var text = new TextDecoder('utf-8').decode(bytes);
              if (window.KissmarkEditor) { window.KissmarkEditor.setMarkdown(text); }
            })();
            """)
        }

        func setStyle(_ variables: [String: String], crossfade: Bool) {
            let body = SurfaceStyleScript.styleScript(applying: variables, removing: appliedStyleKeys)
            evaluate(SurfaceStyleScript.queued(body, crossfade: crossfade))
            appliedStyleKeys = Set(variables.keys)
        }

        func setDocumentInfo(_ info: DocumentInfo) {
            guard let data = try? JSONEncoder().encode(info),
                  let json = String(data: data, encoding: .utf8) else { return }
            evaluate("window.KissmarkEditor && window.KissmarkEditor.setDocumentInfo(\(json));")
        }

        func setReview(_ review: DocumentReview) {
            guard let data = try? JSONEncoder().encode(review),
                  let json = String(data: data, encoding: .utf8) else { return }
            evaluate("window.KissmarkEditor && window.KissmarkEditor.setReview(\(json));")
        }

        func reload() {
            loadSurface()
        }

        /// 텍스트 정리: the surface's JS replaces banned punctuation in prose
        /// (never code) as one undoable transaction and reports the change back
        /// through the normal `change` path, so Autosave picks it up. The
        /// 일반 tab's toggle turns the whole feature off.
        func cleanTypography() {
            guard isTextLintEnabled else { return }
            evaluate("window.KissmarkEditor && window.KissmarkEditor.cleanTypography();")
        }

        // MARK: Loading

        private func loadSurface() {
            guard let webView else { return }
            guard let pageURL = Bundle.main.url(forResource: "editor", withExtension: "html", subdirectory: "Editor")
                    ?? Bundle.main.url(forResource: "editor", withExtension: "html") else {
                surfaceError.wrappedValue = .kissmarkLocalized("editor.html을 찾을 수 없습니다.")
                return
            }
            let parent = pageURL.deletingLastPathComponent()
            let accessRoot = parent.lastPathComponent == "Editor" ? parent.deletingLastPathComponent() : parent
            let styleStatements = SurfaceStyleScript.styleScript(applying: bootstrap.style, removing: [])
            appliedStyleKeys = Set(bootstrap.style.keys)
            let script = WKUserScript(
                source: """
                (function(){
                  window.__KISSMARK_INITIAL_MODE__ = '\(bootstrap.mode == .read ? "read" : "edit")';
                  window.__KISSMARK_UI__ = \(Self.uiJSON);
                  if (document.documentElement) { \(styleStatements) }
                  try {
                    var raw = atob('\(Self.base64(bootstrap.text))');
                    var bytes = Uint8Array.from(raw, function(c){ return c.charCodeAt(0); });
                    window.__KISSMARK_INITIAL_MARKDOWN__ = new TextDecoder('utf-8').decode(bytes);
                  } catch (e) {
                    window.__KISSMARK_INITIAL_MARKDOWN__ = '';
                  }
                })();
                """,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true
            )
            webView.configuration.userContentController.removeAllUserScripts()
            webView.configuration.userContentController.addUserScript(script)
            bridge.didStartLoading()
            scheduleReadyTimeout()
            webView.loadFileURL(pageURL, allowingReadAccessTo: accessRoot)
        }

        private func scheduleReadyTimeout() {
            readyTimeoutTask?.cancel()
            readyTimeoutTask = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: SurfaceBridge.readyTimeoutSeconds * 1_000_000_000)
                guard let self, !Task.isCancelled else { return }
                self.bridge.readyTimedOut()
            }
        }

        private func evaluate(_ js: String) {
            webView?.evaluateJavaScript(js, completionHandler: nil)
        }

        /// Native-resolved editor copy; a JSON object literal is valid JavaScript.
        private static let uiJSON: String = {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
            guard let data = try? encoder.encode(DocumentUILocalization.current),
                  let json = String(data: data, encoding: .utf8) else { return "{}" }
            return json
        }()

        private static func base64(_ text: String) -> String {
            text.data(using: .utf8)?.base64EncodedString() ?? ""
        }

        private static func pointID(_ body: [String: Any]) -> Int64? {
            (body["id"] as? NSNumber)?.int64Value
        }

        // MARK: WKScriptMessageHandler

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "kissmark",
                  let body = message.body as? [String: Any],
                  let type = body["type"] as? String else { return }
            switch type {
            case "ready":
                readyTimeoutTask?.cancel()
                readyTimeoutTask = nil
                let mode = (body["mode"] as? String).map { $0 == "read" ? DocumentMode.read : .edit }
                bridge.receive(.ready(markdown: body["markdown"] as? String, mode: mode))
            case "change":
                guard let markdown = body["markdown"] as? String else { return }
                bridge.receive(.change(markdown: markdown, isFinal: (body["final"] as? Bool) == true))
            case "error":
                bridge.receive(.error(message: body["message"] as? String ?? .kissmarkLocalized("편집기 오류")))
            case "infoExpanded":
                guard let expanded = body["expanded"] as? Bool else { return }
                onInfoExpanded?(expanded)
            case "reviewCheck", "reviewUncheck":
                guard let id = Self.pointID(body) else { return }
                onReviewAction?(type == "reviewCheck" ? .check(id: id) : .uncheck(id: id))
            case "reviewComment":
                guard let id = Self.pointID(body), let comment = body["comment"] as? String else { return }
                onReviewAction?(.comment(id: id, comment: comment))
            case "reviewComplete":
                onReviewAction?(.complete)
            case "reviewExpanded":
                guard let expanded = body["expanded"] as? Bool else { return }
                onReviewExpanded?(expanded)
            default:
                break
            }
        }

        // MARK: WKNavigationDelegate

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            decisionHandler(EditorNavigationPolicy.allows(navigationAction.request.url) ? .allow : .cancel)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            bridge.receive(.error(message: error.localizedDescription))
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            bridge.receive(.error(message: error.localizedDescription))
        }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            bridge.processDidTerminate()
        }
    }
}
