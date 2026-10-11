import SwiftUI

/// Per-workspace flag for the advanced search sheet. The focused-scene command flips it;
/// `FolderBrowserView` owns one per window and presents the sheet.
@MainActor @Observable
final class DocumentSearchPresentation {
    var isPresented = false
    var isFieldVisible = false
    /// Survives sheet dismissal: the sidebar field and the sheet edit the same text.
    var query = ""

    func present() {
        isPresented = true
    }
}

extension FocusedValues {
    @Entry var documentSearch: DocumentSearchPresentation?
}
