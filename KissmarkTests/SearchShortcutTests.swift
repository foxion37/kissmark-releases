#if os(macOS)
import AppKit
import Testing
@testable import Kissmark

@MainActor
struct SearchShortcutTests {
    private func window() -> NSWindow {
        let window = NSWindow(contentRect: .zero, styleMask: [], backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        return window
    }
    private func key(_ text: String, _ flags: NSEvent.ModifierFlags = .command) throws -> NSEvent {
        try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags,
            timestamp: 0, windowNumber: 0, context: nil, characters: text,
            charactersIgnoringModifiers: text, isARepeat: false,
            keyCode: text == "\u{1b}" ? 53 : text.lowercased() == "f" ? 3 : 5))
    }

    @Test func keysOnlyAffectTheirOwningWindow() throws {
        let router = KissmarkSearchShortcuts()
        let first = window(), second = window()
        defer { first.close(); second.close() }
        let find = DocumentFindModel(), other = DocumentFindModel()
        let search = DocumentSearchPresentation()
        router.register(window: first, find: find, search: search)
        router.register(window: second, find: other)
        #expect(try router.handle(key("f"), for: first))
        #expect(find.isPresented && !other.isPresented)
        find.query = "needle"
        #expect(try router.handle(key("g"), for: first))
        #expect(find.request.step == 1)
        #expect(try router.handle(key("G", [.command, .shift]), for: first))
        #expect(find.request.step == -1)
        #expect(try router.handle(key("F", [.command, .shift]), for: first))
        #expect(search.isPresented)
        find.close()
        #expect(try router.handle(key("f"), for: second))
        #expect(!find.isPresented && other.isPresented)
        other.close()
        #expect(try router.handle(key("f"), for: nil))
        #expect(!find.isPresented && !other.isPresented)
    }

    @Test func departedDocumentCannotEraseReplacementOrReceiveKeys() throws {
        let router = KissmarkSearchShortcuts(), window = window()
        defer { window.close() }
        let old = DocumentFindModel(), current = DocumentFindModel()
        let search = DocumentSearchPresentation()
        router.register(window: window, find: old, search: search)
        router.register(window: window, find: current)
        router.unregister(window: window, find: old)
        #expect(try router.handle(key("f"), for: window))
        #expect(current.isPresented && !old.isPresented)
        current.close()
        router.unregister(window: window, find: current)
        #expect(try router.handle(key("f"), for: window))
        #expect(!current.isPresented && !old.isPresented)
        #expect(try router.handle(key("f", [.command, .shift]), for: window))
        #expect(search.isPresented)
    }

    @Test func escapeClosesOnlyVisibleFindAndOtherModifiersPassThrough() throws {
        let router = KissmarkSearchShortcuts(), window = window()
        defer { window.close() }
        let find = DocumentFindModel()
        router.register(window: window, find: find)
        #expect(try !router.handle(key("f", [.command, .option]), for: window))
        #expect(!find.isPresented)
        #expect(try !router.handle(key("\u{1b}", []), for: window))
        find.present()
        #expect(try router.handle(key("\u{1b}", []), for: window))
        #expect(!find.isPresented)
    }
}
#endif
