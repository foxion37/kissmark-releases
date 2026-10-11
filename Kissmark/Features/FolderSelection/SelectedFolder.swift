import Foundation

/// A user-selected Folder plus the only place that touches security-scoped access.
struct SelectedFolder: Equatable {
    /// The granted URL: the Folder its bookmark covers, or a single Document file
    /// (single-file workspace).
    let url: URL
    let bookmarkData: Data
    /// Tree root when it differs from the granted URL. A Document picked inside an
    /// already-granted Folder's scope shows that Folder's subtree at the picked
    /// file's parent; `nil` browses `url` itself.
    let browseURL: URL?
    /// The grant covers one Document and nothing else: its parent Folder is not
    /// granted, so only that file is browsable. Never persisted.
    let isSingleFile: Bool

    var displayName: String { url.lastPathComponent }

    /// Root the Folder tree walks and new Documents are created in.
    var rootURL: URL { browseURL ?? url }

    init(url: URL, bookmarkData: Data, browseURL: URL? = nil, isSingleFile: Bool = false) {
        self.url = url
        self.bookmarkData = bookmarkData
        self.browseURL = browseURL
        self.isSingleFile = isSingleFile
    }

    /// Whether `url` is inside this grant, by path components only (no filesystem
    /// access, so it answers before the scope starts). A leading `/private` is dropped
    /// on both sides — the same rule `MirrorCoordinator.relativePath` uses, because a
    /// pick and a resolved bookmark disagree on it for `/var` and `/tmp`.
    func contains(_ url: URL) -> Bool {
        let root = Self.scopeComponents(of: self.url)
        let parts = Self.scopeComponents(of: url)
        return parts.count >= root.count && Array(parts.prefix(root.count)) == root
    }

    /// Builds a bookmark from a URL the user just picked (fileImporter / open panel).
    /// Access is started around bookmark creation so sandboxed macOS can persist the scope.
    /// `isSingleFile` marks a picked Markdown Document granted on its own.
    static func make(fromPicked url: URL, isSingleFile: Bool = false) throws -> SelectedFolder {
        let didStart = url.startAccessingSecurityScopedResource()
        defer { if didStart { url.stopAccessingSecurityScopedResource() } }
        // Security-scoped first; plain bookmark as fallback for URLs that are not scoped
        // (temp folders in tests, the iCloud ubiquity container).
        let data = try (try? url.bookmarkData(
            options: Self.creationOptions,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )) ?? url.bookmarkData(
            options: [],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        return SelectedFolder(url: url, bookmarkData: data, isSingleFile: isSingleFile)
    }

    private static func scopeComponents(of url: URL) -> [String] {
        let parts = url.standardizedFileURL.pathComponents
        guard parts.count > 2, parts[1] == "private", ["var", "tmp", "etc"].contains(parts[2]) else {
            return parts
        }
        return [parts[0]] + parts.dropFirst(2)
    }

    /// Runs `body` with access held; balanced on every exit.
    func withAccess<T>(_ body: (URL) throws -> T) rethrows -> T {
        let didStart = url.startAccessingSecurityScopedResource()
        defer { if didStart { url.stopAccessingSecurityScopedResource() } }
        return try body(url)
    }

    /// Long-lived access (a browsing session). Release explicitly; deinit releases as a backstop.
    func acquire() -> FolderAccess {
        FolderAccess(url: url)
    }

    private static var creationOptions: URL.BookmarkCreationOptions {
        #if os(macOS)
        [.withSecurityScope]
        #else
        []
        #endif
    }

    static var resolutionOptions: URL.BookmarkResolutionOptions {
        #if os(macOS)
        [.withSecurityScope]
        #else
        []
        #endif
    }
}

final class FolderAccess {
    let url: URL
    private var isActive: Bool

    fileprivate init(url: URL) {
        self.url = url
        isActive = url.startAccessingSecurityScopedResource()
    }

    func release() {
        guard isActive else { return }
        isActive = false
        url.stopAccessingSecurityScopedResource()
    }

    deinit { release() }
}

enum FolderBookmarkKind: Hashable {
    case main
    case inbox
    case archive
    case mirror(id: UUID)

    var key: String {
        switch self {
        case .main: "selected-folder-bookmark"
        case .inbox: "managed-folder-inbox"
        case .archive: "managed-folder-archive"
        case .mirror(let id): "mirror-folder-\(id.uuidString)"
        }
    }
}

/// Bookmark persistence for every Folder kind. Stale data clears itself;
/// unresolvable data (unmounted disk, stopped File Provider) is kept.
struct FolderBookmarks {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func save(_ folder: SelectedFolder, as kind: FolderBookmarkKind) {
        defaults.set(folder.bookmarkData, forKey: kind.key)
    }

    func remove(_ kind: FolderBookmarkKind) {
        defaults.removeObject(forKey: kind.key)
    }

    func load(_ kind: FolderBookmarkKind) throws -> SelectedFolder? {
        guard let data = defaults.data(forKey: kind.key) else { return nil }
        var stale = false
        do {
            let url = try URL(
                resolvingBookmarkData: data,
                options: SelectedFolder.resolutionOptions,
                relativeTo: nil,
                bookmarkDataIsStale: &stale
            )
            guard !stale else {
                remove(kind)
                return nil
            }
            return SelectedFolder(url: url, bookmarkData: data)
        } catch {
            return nil
        }
    }
}
