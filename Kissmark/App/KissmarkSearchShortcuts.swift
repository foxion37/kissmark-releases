#if os(macOS)
import AppKit
import SwiftUI

@MainActor
final class KissmarkSearchShortcuts {
    static let shared = KissmarkSearchShortcuts()
    private final class Actions {
        weak var find: DocumentFindModel?
        weak var search: DocumentSearchPresentation?
    }
    private let windows = NSMapTable<NSWindow, Actions>(keyOptions: .weakMemory, valueOptions: .strongMemory)
    private var monitor: Any?

    init() {
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let handled = MainActor.assumeIsolated { self?.handle(event, for: NSApp.keyWindow) == true }
            return handled ? nil : event
        }
    }
    deinit { if let monitor { NSEvent.removeMonitor(monitor) } }

    /// Handle before WKWebView or an inactive menu snapshot consumes the shortcut.
    /// A known search key without an owner stays disabled, rather than reaching another window.
    func handle(_ event: NSEvent, for window: NSWindow?) -> Bool {
        guard event.type == .keyDown else { return false }
        let flags = event.modifierFlags.intersection([.command, .shift, .control, .option])
        let key = event.charactersIgnoringModifiers?.lowercased()
        let actions = window.flatMap { windows.object(forKey: $0) }
        if flags.isEmpty, event.keyCode == 53, let find = actions?.find, find.isPresented {
            find.close()
            return true
        }
        if flags == .command {
            if key == "f" { actions?.find?.present(); return true }
            if key == "g" { actions?.find?.next(); return true }
        } else if flags == [.command, .shift] {
            if key == "f" { actions?.search?.present(); return true }
            if key == "g" { actions?.find?.previous(); return true }
        }
        return false
    }

    func register(window: NSWindow, find: DocumentFindModel? = nil, search: DocumentSearchPresentation? = nil) {
        let entry = windows.object(forKey: window) ?? Actions()
        if let find { entry.find = find }
        if let search { entry.search = search }
        windows.setObject(entry, forKey: window)
    }
    func unregister(window: NSWindow, find: DocumentFindModel? = nil, search: DocumentSearchPresentation? = nil) {
        guard let entry = windows.object(forKey: window) else { return }
        if let find, entry.find === find { entry.find = nil }
        if let search, entry.search === search { entry.search = nil }
        if entry.find == nil && entry.search == nil { windows.removeObject(forKey: window) }
    }
}

struct KissmarkSearchShortcutBridge: NSViewRepresentable {
    var find: DocumentFindModel? = nil
    var search: DocumentSearchPresentation? = nil
    func makeNSView(context: Context) -> BindingView {
        let view = BindingView()
        view.configure(find: find, search: search)
        return view
    }
    func updateNSView(_ view: BindingView, context: Context) { view.configure(find: find, search: search) }
    static func dismantleNSView(_ view: BindingView, coordinator: ()) { view.detach() }

    final class BindingView: NSView {
        private weak var registeredWindow: NSWindow?
        private var find: DocumentFindModel?
        private var search: DocumentSearchPresentation?
        override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); attach() }
        func configure(find: DocumentFindModel?, search: DocumentSearchPresentation?) {
            guard self.find !== find || self.search !== search else { return }
            detach()
            self.find = find
            self.search = search
            attach()
        }
        private func attach() {
            guard registeredWindow !== window else { return }
            detach()
            guard let window else { return }
            KissmarkSearchShortcuts.shared.register(window: window, find: find, search: search)
            registeredWindow = window
        }
        func detach() {
            if let registeredWindow { KissmarkSearchShortcuts.shared.unregister(window: registeredWindow, find: find, search: search) }
            registeredWindow = nil
        }
    }
}
#endif
