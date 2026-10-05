import Foundation

enum KissmarkCloudFolderError: Error, Equatable {
    case icloudUnavailable
}

struct KissmarkCloudFolder {
    static let containerIdentifier = "iCloud.com.singandmong.kissmark"
    static let documentsDirectoryName = "Documents"
    static let inboxDirectoryName = "Inbox"

    var ubiquityContainerURL: URL?
    var fileManager: FileManager

    init(ubiquityContainerURL: URL?, fileManager: FileManager = .default) {
        self.ubiquityContainerURL = ubiquityContainerURL
        self.fileManager = fileManager
    }

    static var live: KissmarkCloudFolder {
        KissmarkCloudFolder(
            ubiquityContainerURL: FileManager.default.url(
                forUbiquityContainerIdentifier: containerIdentifier
            )
        )
    }

    var documentsURL: URL? {
        ubiquityContainerURL?.appendingPathComponent(Self.documentsDirectoryName, isDirectory: true)
    }

    var inboxURL: URL? {
        documentsURL?.appendingPathComponent(Self.inboxDirectoryName, isDirectory: true)
    }

    @discardableResult
    func prepareDocuments() throws -> URL {
        guard let documentsURL else { throw KissmarkCloudFolderError.icloudUnavailable }
        try fileManager.createDirectory(at: documentsURL, withIntermediateDirectories: true)
        if let inboxURL {
            try fileManager.createDirectory(at: inboxURL, withIntermediateDirectories: true)
        }
        return documentsURL
    }
}
