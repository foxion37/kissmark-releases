import Foundation

// The Folder types are nonisolated so the sidebar can list Folders off the main actor.
nonisolated struct FolderBrowserItem: Identifiable, Equatable {
    nonisolated enum Kind: Equatable { case folder, document }
    let url: URL
    let kind: Kind
    var id: URL { url }
    var name: String { url.lastPathComponent }
}

/// Tree node for the sidebar. Documents use `children == nil` (leaf). Folders always
/// have a non-nil array, empty until the workspace has loaded that Folder.
nonisolated struct FolderTreeNode: Identifiable, Hashable {
    let url: URL
    let kind: FolderBrowserItem.Kind
    var children: [FolderTreeNode]?
    var id: URL { url }
    var name: String {
        kind == .document ? url.deletingPathExtension().lastPathComponent : url.lastPathComponent
    }
}

nonisolated enum FolderBrowserError: Error, Equatable { case outsideSelectedFolder, invalidDocumentName }

nonisolated struct FolderBrowserStore {
    private let fileManager: FileManager
    init(fileManager: FileManager = .default) { self.fileManager = fileManager }

    func contents(of directory: URL, within root: URL) throws -> [FolderBrowserItem] {
        guard contains(directory, within: root) else { throw FolderBrowserError.outsideSelectedFolder }
        let urls = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        )
        return try urls.compactMap { url in
            let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey])
            guard values.isSymbolicLink != true else { return nil }
            if values.isDirectory == true { return FolderBrowserItem(url: url, kind: .folder) }
            let isPlaceholder = url.pathExtension.lowercased() == "icloud"
            if isPlaceholder {
                try? fileManager.startDownloadingUbiquitousItem(at: url)
            }
            let documentURL = isPlaceholder ? url.deletingPathExtension() : url
            guard values.isRegularFile == true || isPlaceholder else { return nil }
            guard ["md", "markdown"].contains(documentURL.pathExtension.lowercased()) else { return nil }
            return FolderBrowserItem(url: documentURL, kind: .document)
        }.sorted { lhs, rhs in
            if lhs.kind != rhs.kind { return lhs.kind == .folder }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    /// Direct children of one Folder as sidebar nodes. Child Folders are not read; each one
    /// is listed on its own when the sidebar expands it.
    func children(of directory: URL, within root: URL) throws -> [FolderTreeNode] {
        try contents(of: directory, within: root).map { item in
            FolderTreeNode(url: item.url, kind: item.kind, children: item.kind == .folder ? [] : nil)
        }
    }

    @MainActor
    func createDocument(named name: String, in directory: URL, within root: URL) throws -> DocumentFileSnapshot {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains("/"), !trimmed.contains("\\") else { throw FolderBrowserError.invalidDocumentName }
        let filename = trimmed.lowercased().hasSuffix(".md") ? trimmed : "\(trimmed).md"
        let url = directory.appendingPathComponent(filename)
        guard contains(url, within: root) else { throw FolderBrowserError.outsideSelectedFolder }
        return try DocumentFileStore(fileManager: fileManager).saveAs("", to: url)
    }

    private func contains(_ url: URL, within root: URL) -> Bool {
        let rootPath = root.standardizedFileURL.path.hasSuffix("/") ? root.standardizedFileURL.path : root.standardizedFileURL.path + "/"
        let path = url.standardizedFileURL.path
        return path == String(rootPath.dropLast()) || path.hasPrefix(rootPath)
    }
}
