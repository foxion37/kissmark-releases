import Foundation

extension Notification.Name {
    /// Opens the Folder picker (empty state, File menu, or Settings-adjacent entry).
    static let kissmarkChooseFolder = Notification.Name("kissmark.chooseFolder")

    /// Requests the single-file workspace's parent grant, not a different root Folder.
    static let kissmarkOpenParentFolder = Notification.Name("kissmark.openParentFolder")

    /// Runs 텍스트 정리 on the open Document surface (Edit Mode only; a no-op otherwise).
    static let kissmarkCleanTypography = Notification.Name("kissmark.cleanTypography")

    /// Reads the Folder tree and the open Document from disk again (⌘R).
    static let kissmarkReload = Notification.Name("kissmark.reload")
}
