import SwiftUI

struct KissmarkSearchCommands: Commands {
    var body: some Commands {
        CommandGroup(after: .textEditing) {
            KissmarkSearchCommandItems()
        }
    }
}

/// Resolve focused values in the menu's View context, like the Settings command.
private struct KissmarkSearchCommandItems: View {
    @FocusedValue(\.documentFind) private var documentFind: DocumentFindModel?
    @FocusedValue(\.documentSearch) private var documentSearch: DocumentSearchPresentation?

    var body: some View {
        Group {
            Divider()
            // Keep the target resolved for this menu action across focus changes.
            Button(String.kissmarkLocalized("문서에서 찾기…")) { [documentFind] in documentFind?.present() }
                .keyboardShortcut("f", modifiers: .command)
                .disabled(documentFind == nil)
            Button(String.kissmarkLocalized("다음 찾기")) { [documentFind] in documentFind?.next() }
                .keyboardShortcut("g", modifiers: .command)
                .disabled(documentFind == nil)
            Button(String.kissmarkLocalized("이전 찾기")) { [documentFind] in documentFind?.previous() }
                .keyboardShortcut("g", modifiers: [.command, .shift])
                .disabled(documentFind == nil)
            Button(String.kissmarkLocalized("문서 검색…")) { [documentSearch] in documentSearch?.present() }
                .keyboardShortcut("f", modifiers: [.command, .shift])
                .disabled(documentSearch == nil)
        }
    }
}
