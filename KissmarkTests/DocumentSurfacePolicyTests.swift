import Foundation
import Testing
@testable import Kissmark

@MainActor
struct DocumentSurfacePolicyTests {

    @Test("Document surface HTML stays local-only")
    func documentSurfaceHTMLIsLocal() throws {
        let url = try #require(Bundle.main.url(forResource: "editor", withExtension: "html"))
        let html = try String(contentsOf: url, encoding: .utf8)
        #expect(!html.contains("https://"))
        #expect(!html.contains("cdn."))
    }

    @Test("Editor bundle assets are present for WYSIWYG Edit Mode")
    func editorAssetsPresent() {
        #expect(Bundle.main.url(forResource: "editor", withExtension: "html") != nil)
        #expect(Bundle.main.url(forResource: "editor.bundle", withExtension: "js") != nil)
        #expect(Bundle.main.url(forResource: "editor.bundle", withExtension: "css") != nil)
        #expect(Bundle.main.url(forResource: "reader", withExtension: "css") != nil)
    }

    @Test("Editor navigation allows only local file URLs")
    func editorBlocksRemoteNavigation() {
        #expect(EditorNavigationPolicy.allows(URL(fileURLWithPath: "/tmp/editor.html")))
        #expect(!EditorNavigationPolicy.allows(URL(string: "https://example.com")))
        #expect(!EditorNavigationPolicy.allows(URL(string: "http://localhost:3000")))
        #expect(!EditorNavigationPolicy.allows(URL(string: "javascript:alert(1)")))
        #expect(!EditorNavigationPolicy.allows(URL(string: "about:blank")))
        #expect(!EditorNavigationPolicy.allows(nil))
    }

    @Test("Editor HTML CSP forbids network and remote script loads")
    func editorHTMLHasRestrictiveCSP() throws {
        let url = try #require(Bundle.main.url(forResource: "editor", withExtension: "html"))
        let html = try String(contentsOf: url, encoding: .utf8)
        #expect(html.contains("Content-Security-Policy"))
        #expect(html.contains("default-src 'none'"))
        #expect(html.contains("script-src 'self'"))
        #expect(html.contains("connect-src 'none'"))
        #expect(html.contains("img-src 'none'"))
        #expect(!html.contains("https://"))
        #expect(!html.contains("cdn."))
    }

    @Test("Reader fixture route needs both DEBUG and the UI test gate")
    func readerFixtureRouteIsGated() {
        let arguments = ["Kissmark", "-ui-test-state", "reader-fixture"]
        #expect(AppLaunchRoute.resolve(arguments: arguments, environment: [:], isDebug: true) == .folderSelection)
        #expect(AppLaunchRoute.resolve(arguments: arguments, environment: ["KISSMARK_UI_TEST": "1"], isDebug: false) == .folderSelection)
        #expect(AppLaunchRoute.resolve(arguments: arguments, environment: ["KISSMARK_UI_TEST": "1"], isDebug: true) == .readerFixture)
        #expect(AppLaunchRoute.resolve(arguments: ["Kissmark", "-KISSMARK_UI_TEST", "1", "-ui-test-state", "editor-fixture"], environment: [:], isDebug: true) == .editorFixture)
        #expect(AppLaunchRoute.resolve(arguments: ["Kissmark", "-ui-test-state", "editor-fixture"], environment: ["KISSMARK_UI_TEST": "1"], isDebug: true) == .editorFixture)
    }
}
