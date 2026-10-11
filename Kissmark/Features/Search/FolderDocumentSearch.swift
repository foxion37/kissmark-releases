import Foundation

/// A Folder search that could not read everything. `results` are the hits from what
/// was readable; `failures` are `path: reason` lines. Never reported as an empty success.
nonisolated struct FolderDocumentSearchError: Error, LocalizedError {
    let results: [DocumentSearchResult]
    let failures: [String]

    var errorDescription: String? {
        String.kissmarkLocalized("읽지 못한 항목 \(failures.count)개: \(failures.prefix(3).joined(separator: ", "))")
    }
}

enum FolderDocumentSearch {
    /// Title or body contains `query` (literal, case-insensitive, canonical Unicode), across every
    /// Markdown Document under the Folder root, opened or not. A single-file grant searches
    /// that file only, never its siblings. Blank query returns no results.
    /// Throws `CancellationError` when cancelled and `FolderDocumentSearchError` on unreadable items.
    @MainActor
    static func search(folder: SelectedFolder, query: String) async throws -> [DocumentSearchResult] {
        try Task.checkCancellation()
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return [] }
        let root = folder.rootURL
        let singleFile = folder.isSingleFile ? folder.url : nil
        // The security scope is owned by SelectedFolder and held until the worker has stopped.
        let access = folder.acquire()
        defer { access.release() }
        let worker = Task.detached(priority: .userInitiated) {
            try scan(root: root, singleFile: singleFile, query: query)
        }
        return try await withTaskCancellationHandler {
            try await worker.value
        } onCancel: {
            worker.cancel()
        }
    }

    private nonisolated static func scan(root: URL, singleFile: URL?, query: String) throws -> [DocumentSearchResult] {
        var documents: [URL] = []
        var failures: [String] = []
        if let singleFile {
            documents = [singleFile]
        } else {
            let store = FolderBrowserStore()
            var pending = [root]
            while let directory = pending.popLast() {
                try Task.checkCancellation()
                do {
                    for item in try store.contents(of: directory, within: root) {
                        if item.kind == .folder { pending.append(item.url) } else { documents.append(item.url) }
                    }
                } catch {
                    failures.append("\(directory.lastPathComponent): \(error.localizedDescription)")
                }
            }
        }

        var results: [DocumentSearchResult] = []
        for url in documents {
            try Task.checkCancellation()
            let title = url.deletingPathExtension().lastPathComponent.precomposedStringWithCanonicalMapping
            do {
                let body = try String(contentsOf: url, encoding: .utf8)
                let titleHit = DocumentSearchResult.match(of: query, in: title) != nil
                guard titleHit || DocumentSearchResult.match(of: query, in: body) != nil else { continue }
                results.append(DocumentSearchResult(
                    path: url.path, title: title, snippet: DocumentSearchResult.snippet(of: query, in: body)
                ))
            } catch {
                failures.append("\(url.lastPathComponent): \(error.localizedDescription)")
            }
        }
        results.sort {
            let order = $0.path.localizedStandardCompare($1.path)
            return order == .orderedSame ? $0.path < $1.path : order == .orderedAscending
        }
        guard failures.isEmpty else { throw FolderDocumentSearchError(results: results, failures: failures) }
        return results
    }
}
