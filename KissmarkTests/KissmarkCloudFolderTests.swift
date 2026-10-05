import Foundation
import Testing
@testable import Kissmark

struct KissmarkCloudFolderTests {
    @Test("Given no iCloud container When resolving Then Documents is missing")
    func documentsURLIsNilWithoutUbiquity() {
        let cloud = KissmarkCloudFolder(ubiquityContainerURL: nil)

        #expect(cloud.documentsURL == nil)
        #expect(cloud.inboxURL == nil)
        #expect(throws: KissmarkCloudFolderError.icloudUnavailable) {
            try cloud.prepareDocuments()
        }
    }

    @Test("Given an iCloud container When preparing Then Documents and Inbox exist")
    func prepareCreatesDocumentsAndInbox() throws {
        let container = FileManager.default.temporaryDirectory
            .appendingPathComponent("KissmarkCloud-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: container) }

        let cloud = KissmarkCloudFolder(ubiquityContainerURL: container)
        let documents = try cloud.prepareDocuments()

        #expect(documents.lastPathComponent == "Documents")
        #expect(cloud.inboxURL?.lastPathComponent == "Inbox")
        var isDirectory: ObjCBool = false
        #expect(FileManager.default.fileExists(atPath: documents.path, isDirectory: &isDirectory))
        #expect(isDirectory.boolValue)
        #expect(FileManager.default.fileExists(atPath: try #require(cloud.inboxURL).path))
    }

    @Test("Given no saved Folder When opening the cloud Folder Then the model selects Documents")
    func modelOpensCloudFolderWhenEmpty() throws {
        let container = FileManager.default.temporaryDirectory
            .appendingPathComponent("KissmarkCloud-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: container) }
        let cloud = KissmarkCloudFolder(ubiquityContainerURL: container)
        let model = FolderSelectionModel(bookmarks: try emptyBookmarks())

        #expect(model.openCloudFolderIfAvailable(cloud))
        #expect(model.selectedFolder?.displayName == "Documents")
        #expect(model.selectedFolder?.url.lastPathComponent == "Documents")
    }

    @Test("Given a selected Folder When opening cloud Then the current Folder stays")
    func modelDoesNotReplaceExistingFolder() throws {
        let container = FileManager.default.temporaryDirectory
            .appendingPathComponent("KissmarkCloud-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: container) }
        let existing = FileManager.default.temporaryDirectory
            .appendingPathComponent("Existing-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: existing, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: existing) }

        let model = FolderSelectionModel(bookmarks: try emptyBookmarks())
        model.handle(.selected(url: existing))
        let cloud = KissmarkCloudFolder(ubiquityContainerURL: container)

        #expect(!model.openCloudFolderIfAvailable(cloud))
        #expect(model.selectedFolder?.url == existing)
    }
}
