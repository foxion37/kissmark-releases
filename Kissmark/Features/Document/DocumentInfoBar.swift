import Foundation

/// The document info payload Swift pushes into the surface's in-flow `#docinfo`
/// header (`window.KissmarkEditor.setDocumentInfo`). Dates are preformatted by Swift in
/// the launch UI language; labels (path / save state / modified / created) are rendered by JS.
/// Idempotent: JS ignores a push whose `expanded` and values already match.
struct DocumentInfo: Equatable, Codable {
    var path: String
    var saveState: String
    var saveLabel: String
    var modified: String
    var created: String
    var expanded: Bool
}

/// Save-state mapping for the in-flow document info header. The floating SwiftUI
/// overlay was removed (1.5): the info now lives inside the Document DOM.
enum DocumentInfoBar {
    /// Remembered app setting: expanded by default.
    static let expansionStorageKey = "kissmark.document-info.expanded"

    enum SaveState: Equatable {
        case saved
        case saving
        case failed

        var text: String {
            switch self {
            case .saved: String.kissmarkLocalized("저장됨")
            case .saving: String.kissmarkLocalized("저장 중")
            case .failed: String.kissmarkLocalized("저장 실패")
            }
        }

        /// Wire value the surface JS switches on.
        var wireValue: String {
            switch self {
            case .saved: "saved"
            case .saving: "saving"
            case .failed: "failed"
            }
        }
    }

    /// 저장 실패 wins over a pending write: the last disk result is what the user needs.
    static func saveState(isDirty: Bool, mode: DocumentMode, hasSaveError: Bool) -> SaveState {
        if hasSaveError { return .failed }
        if isDirty, mode == .edit { return .saving }
        return .saved
    }
}
