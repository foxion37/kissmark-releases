import Foundation
import Observation

enum DocumentMode: Hashable {
    case read
    case edit
}

/// Which surface the Document shows in the same WKWebView: the rendered editor or the
/// Markdown source (frontmatter included). A newly opened Document starts in `.render`.
enum DocumentViewMode: Hashable {
    case render
    case source
}

enum DocumentCloseRequest: Equatable {
    case close
    case confirmDiscard
}

@MainActor
@Observable
final class DocumentSession: Identifiable, Hashable {
    let id = UUID()
    private(set) var sourceURL: URL?
    private(set) var title: String
    private(set) var originalText: String
    var text: String {
        didSet {
            guard !suppressAutosave, text != oldValue else { return }
            if mode == .edit {
                scheduleAutosave()
            } else {
                // Only the surface's final Lock change arrives while locked.
                flushToDisk()
                if !isDirty { onLockedWrite?() }
            }
        }
    }
    private(set) var version: DocumentFileVersion?
    var mode: DocumentMode
    /// Rendered editor or Markdown source. Read/Edit decides editability; this only picks
    /// the surface. Opening a Document always starts rendered.
    var viewMode: DocumentViewMode = .render
    /// Fired after a Read-Mode text change that reached the disk (the surface's `final` Lock change
    /// lands after the lock flush). Owners use it to mirror; the session knows nothing about mirroring.
    @ObservationIgnored var onLockedWrite: (() -> Void)?
    private(set) var saveError: DocumentFileStoreError?
    private(set) var renameError: DocumentFileStoreError?

    private var autosaveTask: Task<Void, Never>?
    private var suppressAutosave = false

    var isDirty: Bool { text != originalText }

    static func == (lhs: DocumentSession, rhs: DocumentSession) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    init(snapshot: DocumentFileSnapshot) {
        sourceURL = snapshot.url
        title = snapshot.url.deletingPathExtension().lastPathComponent
        originalText = snapshot.text
        text = snapshot.text
        version = snapshot.version
        mode = .read
    }

    init(newDocumentNamed title: String = String.kissmarkLocalized("제목 없음"), text: String = "") {
        sourceURL = nil
        self.title = title
        originalText = ""
        self.text = text
        version = nil
        mode = .edit
    }

    /// Lock / unlock the Document surface. Locking flushes pending edits first.
    func setMode(_ newMode: DocumentMode, using store: DocumentFileStore? = nil) {
        if mode == .edit, newMode == .read {
            flushToDisk(using: store)
        }
        mode = newMode
    }

    func scheduleAutosave(delayNanoseconds: UInt64 = 400_000_000, using store: DocumentFileStore? = nil) {
        guard mode == .edit, sourceURL != nil else { return }
        autosaveTask?.cancel()
        autosaveTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: delayNanoseconds)
            guard let self, !Task.isCancelled else { return }
            self.flushToDisk(using: store)
        }
    }

    /// Writes pending edits immediately (lock, close, or archive).
    func flushToDisk(using store: DocumentFileStore? = nil) {
        autosaveTask?.cancel()
        autosaveTask = nil
        guard isDirty else { return }
        save(using: store ?? DocumentFileStore())
    }

    func save(using store: DocumentFileStore) {
        guard let sourceURL else { return }
        do {
            version = try store.save(text, to: sourceURL, expecting: version)
            originalText = text
            saveError = nil
        } catch let error as DocumentFileStoreError {
            saveError = error
        } catch {
            saveError = nil
        }
    }

    /// Renames the on-disk Document (or the unsaved draft title when there is no file yet).
    @discardableResult
    func rename(to proposedName: String, using store: DocumentFileStore? = nil) -> Bool {
        let trimmed = proposedName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            renameError = .invalidName
            return false
        }

        guard let sourceURL else {
            title = trimmed
            renameError = nil
            return true
        }

        do {
            let snapshot = try (store ?? DocumentFileStore()).rename(sourceURL, toProposedName: trimmed)
            self.sourceURL = snapshot.url
            title = snapshot.url.deletingPathExtension().lastPathComponent
            version = snapshot.version
            renameError = nil
            return true
        } catch let error as DocumentFileStoreError {
            renameError = error
            return false
        } catch {
            renameError = .invalidName
            return false
        }
    }

    func requestClose(using store: DocumentFileStore? = nil) -> DocumentCloseRequest {
        flushToDisk(using: store)
        return isDirty ? .confirmDiscard : .close
    }

    func discardChanges() {
        autosaveTask?.cancel()
        autosaveTask = nil
        suppressAutosave = true
        text = originalText
        suppressAutosave = false
        saveError = nil
    }

    func dismissSaveError() {
        saveError = nil
    }

    func dismissRenameError() {
        renameError = nil
    }
}
