import Foundation

enum EditorNavigationPolicy {
    /// Edit Mode allows only local `file:` loads for the bundled editor page.
    /// Every remote or non-file navigation is cancelled.
    static func allows(_ url: URL?) -> Bool {
        guard let url else { return false }
        return url.isFileURL
    }
}
