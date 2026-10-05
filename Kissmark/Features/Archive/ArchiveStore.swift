import Foundation

enum ArchiveStore {
    static func copy(_ source: URL, into archiveFolder: URL, fileManager: FileManager = .default) throws -> URL {
        let destinationFolder = archiveFolder.appendingPathComponent("Inbox/Kissmark", isDirectory: true)
        try fileManager.createDirectory(at: destinationFolder, withIntermediateDirectories: true)
        let base = source.deletingPathExtension().lastPathComponent
        let ext = source.pathExtension
        var index = 0
        var destination = destinationFolder.appendingPathComponent(source.lastPathComponent)
        while fileManager.fileExists(atPath: destination.path) {
            index += 1
            destination = destinationFolder.appendingPathComponent("\(base) (\(index)).\(ext)")
        }
        try fileManager.copyItem(at: source, to: destination)
        return destination
    }
}
