import Foundation

enum UbiquitousFileAccessError: Error, Equatable {
    case downloadInProgress
}

enum UbiquitousFileAccess {
    static func prepareForReading(_ url: URL, fileManager: FileManager = .default) throws {
        let values = try url.resourceValues(forKeys: [
            .isUbiquitousItemKey,
            .ubiquitousItemDownloadingStatusKey,
        ])
        guard values.isUbiquitousItem == true else { return }
        if values.ubiquitousItemDownloadingStatus == .current {
            return
        }
        try fileManager.startDownloadingUbiquitousItem(at: url)
        let refreshed = try url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey])
        guard refreshed.ubiquitousItemDownloadingStatus == .current else {
            throw UbiquitousFileAccessError.downloadInProgress
        }
    }
}
