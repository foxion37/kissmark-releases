import Foundation
import Observation

/// One user-chosen Mirror Target folder. `nonisolated` so the plain-value model
/// can be decoded and compared off the main actor (repo convention: `DesignOverrides`).
nonisolated struct MirrorTarget: Codable, Identifiable, Equatable {
    let id: UUID
    var displayName: String
}

nonisolated enum MirrorResult: Equatable {
    case ok(Date)
    case failed(String, Date)

    var isFailure: Bool { if case .failed = self { true } else { false } }
}

/// What a manual full send could not do: targets that just started failing, and
/// Folder-relative paths of Documents that could not be read (never sent anywhere).
struct MirrorSendSummary {
    var newlyFailed: [MirrorTarget]
    var unreadable: [String]
}

nonisolated struct MirrorJob: Equatable {
    let documentURL: URL
    let text: String
    let previousDocumentURL: URL?
}

/// One-way copies of saved Documents into user-chosen Mirror Target folders.
/// ponytail: writes synchronously on the main actor (small Markdown files, local
/// File Provider folders); move to a serial actor if a slow provider shows up.
@MainActor
@Observable
final class MirrorCoordinator {
    static let storageKey = "kissmark.mirror-targets"

    private(set) var targets: [MirrorTarget]
    private(set) var lastResults: [UUID: MirrorResult] = [:]
    /// Failures reported while a workspace was stopping; the next workspace's `start()` shows them.
    private(set) var undeliveredFailures: [MirrorTarget] = []

    private let defaults: UserDefaults
    private let bookmarks: FolderBookmarks
    private let now: () -> Date
    private var lastWritten: [String: Int] = [:]

    init(defaults: UserDefaults = .standard, now: @escaping () -> Date = Date.init) {
        self.defaults = defaults
        self.bookmarks = FolderBookmarks(defaults: defaults)
        self.now = now
        if let data = defaults.data(forKey: Self.storageKey),
           let stored = try? JSONDecoder().decode([MirrorTarget].self, from: data) {
            targets = stored
        } else {
            targets = []
        }
    }

    func add(fromPicked url: URL) throws -> MirrorTarget {
        let folder = try SelectedFolder.make(fromPicked: url)
        let target = MirrorTarget(id: UUID(), displayName: folder.displayName)
        bookmarks.save(folder, as: .mirror(id: target.id))
        targets.append(target)
        persist()
        return target
    }

    func remove(_ id: UUID) {
        bookmarks.remove(.mirror(id: id))
        targets.removeAll { $0.id == id }
        lastResults[id] = nil
        lastWritten = lastWritten.filter { !$0.key.hasPrefix("\(id.uuidString)|") }
        persist()
    }

    func folderURL(of id: UUID) -> URL? {
        (try? bookmarks.load(.mirror(id: id)))?.url
    }

    @discardableResult
    func mirror(_ job: MirrorJob, from folder: SelectedFolder) -> [MirrorTarget] {
        guard let path = Self.relativePath(of: job.documentURL, in: folder.url) else { return [] }
        let previous = job.previousDocumentURL.flatMap { Self.relativePath(of: $0, in: folder.url) }
        return write([(path, job.text, previous)], from: folder, force: false)
    }

    /// True when every target's last result is `.ok` (vacuously true without targets).
    var allTargetsOK: Bool {
        targets.allSatisfy { if case .ok = lastResults[$0.id] { true } else { false } }
    }

    func deferFailures(_ failed: [MirrorTarget]) {
        undeliveredFailures += failed
    }

    func takeUndeliveredFailures() -> [MirrorTarget] {
        defer { undeliveredFailures = [] }
        return undeliveredFailures
    }

    @discardableResult
    func mirrorAll(from folder: SelectedFolder) -> MirrorSendSummary {
        // A target inside the Folder is skipped when writing; skipping its subtree here too
        // keeps its own copies from being sent back out to the other targets.
        let insideFolder = Set(targets.compactMap { try? bookmarks.load(.mirror(id: $0.id))?.url }.map(Self.canonicalPath))
        var unreadable: [String] = []
        let files = folder.withAccess { root -> [(path: String, text: String, previous: String?)] in
            let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants],
                errorHandler: { url, _ in
                    // An unlistable subfolder hides its Documents; report it rather than skip silently.
                    unreadable.append(Self.relativePath(of: url, in: root).map { $0 + "/" } ?? url.lastPathComponent)
                    return true
                }
            )
            var result: [(path: String, text: String, previous: String?)] = []
            while let url = enumerator?.nextObject() as? URL {
                if url.hasDirectoryPath, insideFolder.contains(Self.canonicalPath(url)) {
                    enumerator?.skipDescendants()
                    continue
                }
                guard ["md", "markdown"].contains(url.pathExtension.lowercased()),
                      (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true,
                      let path = Self.relativePath(of: url, in: root) else { continue }
                guard let text = try? String(contentsOf: url, encoding: .utf8) else {
                    unreadable.append(path)
                    continue
                }
                result.append((path: path, text: text, previous: nil))
            }
            return result
        }
        return MirrorSendSummary(newlyFailed: write(files, from: folder, force: true), unreadable: unreadable)
    }

    // MARK: - Internals

    private func write(_ files: [(path: String, text: String, previous: String?)], from folder: SelectedFolder, force: Bool) -> [MirrorTarget] {
        var newlyFailed: [MirrorTarget] = []
        let folderRoot = Self.canonicalPath(folder.url)
        for target in targets {
            let wasFailing = lastResults[target.id]?.isFailure == true
            let result: MirrorResult
            do {
                guard let targetFolder = try bookmarks.load(.mirror(id: target.id)) else {
                    throw MirrorError.message(String.kissmarkLocalized("미러 폴더를 다시 고르세요."))
                }
                try targetFolder.withAccess { root in
                    let targetRoot = Self.canonicalPath(root)
                    // Either direction overlaps: a target above the Folder would write onto the source.
                    if Self.isInside(targetRoot, folderRoot) || Self.isInside(folderRoot, targetRoot) {
                        throw MirrorError.message(String.kissmarkLocalized("미러 폴더가 Folder와 겹칩니다."))
                    }
                    for file in files {
                        try writeOne(file, into: root, targetRoot: targetRoot, folderRoot: folderRoot, targetID: target.id, force: force)
                    }
                }
                result = .ok(now())
            } catch {
                result = .failed((error as? MirrorError)?.text ?? error.localizedDescription, now())
                if !wasFailing { newlyFailed.append(target) }
            }
            lastResults[target.id] = result
        }
        return newlyFailed
    }

    private func writeOne(
        _ file: (path: String, text: String, previous: String?),
        into root: URL, targetRoot: String, folderRoot: String, targetID: UUID, force: Bool
    ) throws {
        let key = "\(targetID.uuidString)|\(file.path)"
        let destination = root.appendingPathComponent(file.path)
        // Session dedupe on the text hash, not the text itself: keeps the map small.
        // ponytail: a hash collision skips one stale write; store the text if that ever matters.
        let fingerprint = file.text.hashValue
        if force || lastWritten[key] != fingerprint {
            try FileManager.default.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try Self.requireContained(destination.deletingLastPathComponent(), targetRoot: targetRoot, folderRoot: folderRoot)
            // A symlinked or special file at the destination could redirect the write.
            if let values = try? destination.resourceValues(forKeys: [.isRegularFileKey]), values.isRegularFile != true {
                throw MirrorError.message(String.kissmarkLocalized("미러 폴더의 같은 이름 항목이 일반 파일이 아닙니다."))
            }
            try file.text.write(to: destination, atomically: true, encoding: .utf8)
            lastWritten[key] = fingerprint
        }
        if let previous = file.previous, previous != file.path {
            let old = root.appendingPathComponent(previous)
            // `isRegularFileKey` does not follow a final symlink, so links and FIFOs are left alone.
            if (try? old.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true {
                try Self.requireContained(old.deletingLastPathComponent(), targetRoot: targetRoot, folderRoot: folderRoot)
                try FileManager.default.removeItem(at: old)
            }
            lastWritten["\(targetID.uuidString)|\(previous)"] = nil
        }
    }

    /// Folder-relative path, or nil if the URL is not strictly inside the Folder.
    /// Compares components after dropping a leading `/private` on both sides: `folder.url`
    /// and the enumerated/bookmark-resolved Document URLs disagree on it in both directions
    /// (`/private/var` ↔ `/var`, `/private/tmp` ↔ `/tmp`), and `standardizedFileURL` cannot
    /// help — it strips the prefix only for paths that still exist. No filesystem access.
    static func relativePath(of url: URL, in folder: URL) -> String? {
        let root = normalizedComponents(of: folder)
        let parts = normalizedComponents(of: url)
        guard parts.count > root.count, Array(parts.prefix(root.count)) == root else { return nil }
        let relative = parts.dropFirst(root.count)
        guard !relative.contains(".."), !relative.contains(".") else { return nil }
        return relative.joined(separator: "/")
    }

    /// `pathComponents` with a leading `/private` dropped when it wraps a symlinked
    /// system root (`var`, `tmp`, `etc`); e.g. `/private/var/tmp/X` → `/var/tmp/X`.
    /// Pure string rule, so `/private/Users/...` is left alone.
    private static func normalizedComponents(of url: URL) -> [String] {
        let parts = url.pathComponents
        guard parts.count > 2, parts[1] == "private", ["var", "tmp", "etc"].contains(parts[2]) else { return parts }
        return [parts[0]] + parts.dropFirst(2)
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(targets) {
            defaults.set(data, forKey: Self.storageKey)
        }
    }

    /// Real path of an existing directory (resolves symlinks — including a final one, which
    /// `canonicalPathKey` alone leaves in place — and `/var` ↔ `/private/var`).
    /// A vanished directory falls back to the standardized path.
    private static func canonicalPath(_ url: URL) -> String {
        let resolved = url.resolvingSymlinksInPath()
        return (try? resolved.resourceValues(forKeys: [.canonicalPathKey]).canonicalPath) ?? resolved.standardizedFileURL.path
    }

    private static func isInside(_ path: String, _ root: String) -> Bool {
        path == root || path.hasPrefix(root.hasSuffix("/") ? root : root + "/")
    }

    /// A directory symlink inside the target can point anywhere; the real parent must stay in the
    /// target and out of the Folder.
    private static func requireContained(_ directory: URL, targetRoot: String, folderRoot: String) throws {
        let real = canonicalPath(directory)
        guard isInside(real, targetRoot), !isInside(real, folderRoot) else {
            throw MirrorError.message(String.kissmarkLocalized("미러 폴더 안의 링크가 바깥을 가리킵니다."))
        }
    }

    private enum MirrorError: Error {
        case message(String)
        var text: String { switch self { case .message(let t): t } }
    }
}
