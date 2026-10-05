import Foundation

struct DocumentFileSnapshot: Equatable {
    let url: URL
    let text: String
    let version: DocumentFileVersion
}

struct DocumentFileVersion: Equatable {
    let modificationDate: Date
    let fileSize: UInt64
    /// File creation date, when the filesystem reports one (the Document Info Bar's 생성일).
    let creationDate: Date?

    init(modificationDate: Date, fileSize: UInt64, creationDate: Date? = nil) {
        self.modificationDate = modificationDate
        self.fileSize = fileSize
        self.creationDate = creationDate
    }
}

enum DocumentFileStoreError: Error, Equatable {
    case changedExternally
    case invalidName
    case destinationExists
}

struct DocumentFileStore {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func load(from url: URL) throws -> DocumentFileSnapshot {
        try UbiquitousFileAccess.prepareForReading(url, fileManager: fileManager)
        let text = try String(contentsOf: url, encoding: .utf8)
        return DocumentFileSnapshot(url: url, text: text, version: try version(of: url))
    }

    func save(
        _ text: String,
        to url: URL,
        expecting expectedVersion: DocumentFileVersion?
    ) throws -> DocumentFileVersion {
        if let expectedVersion, try version(of: url) != expectedVersion {
            throw DocumentFileStoreError.changedExternally
        }
        try text.write(to: url, atomically: true, encoding: .utf8)
        return try version(of: url)
    }

    func saveAs(_ text: String, to url: URL) throws -> DocumentFileSnapshot {
        try text.write(to: url, atomically: true, encoding: .utf8)
        return try load(from: url)
    }

    /// Renames a Document file in place (same directory). `proposedName` is the
    /// display title without requiring an extension; the original extension is kept.
    func rename(_ url: URL, toProposedName proposedName: String) throws -> DocumentFileSnapshot {
        let trimmed = proposedName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains("/"), !trimmed.contains("\\") else {
            throw DocumentFileStoreError.invalidName
        }

        let ext = url.pathExtension.isEmpty ? "md" : url.pathExtension
        let base: String
        if trimmed.lowercased().hasSuffix(".\(ext.lowercased())") {
            base = String(trimmed.dropLast(ext.count + 1))
        } else {
            base = trimmed
        }
        guard !base.isEmpty else { throw DocumentFileStoreError.invalidName }

        let destination = url.deletingLastPathComponent().appendingPathComponent("\(base).\(ext)")
        if destination.standardizedFileURL == url.standardizedFileURL {
            return try load(from: url)
        }
        guard !fileManager.fileExists(atPath: destination.path) else {
            throw DocumentFileStoreError.destinationExists
        }
        try fileManager.moveItem(at: url, to: destination)
        return try load(from: destination)
    }

    private func version(of url: URL) throws -> DocumentFileVersion {
        let attributes = try fileManager.attributesOfItem(atPath: url.path)
        return DocumentFileVersion(
            modificationDate: attributes[.modificationDate] as? Date ?? .distantPast,
            fileSize: (attributes[.size] as? NSNumber)?.uint64Value ?? 0,
            creationDate: attributes[.creationDate] as? Date
        )
    }
}
