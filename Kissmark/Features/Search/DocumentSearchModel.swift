import Foundation

/// State of one advanced-search sheet. Every input change cancels the running search and bumps
/// `generation`; a result is applied only if its generation is still current, so a slow Folder
/// scan can never overwrite a newer query or scope.
@MainActor @Observable
final class DocumentSearchModel {
    enum Scope: Hashable { case folder, memory }
    enum Phase: Equatable { case idle, loading, loaded, failed(String) }

    var query = ""
    var scope = Scope.folder
    var project = ""
    var agent = ""
    private(set) var results: [DocumentSearchResult] = []
    private(set) var phase = Phase.idle
    var selection: DocumentSearchResult.ID?

    private let folderSearch: (String) async throws -> [DocumentSearchResult]
    private let memorySearch: (String, String, String) throws -> [DocumentSearchResult]
    private let debounce: Duration
    private var task: Task<Void, Never>?
    private var generation = 0

    init(
        debounce: Duration = .milliseconds(250),
        folderSearch: @escaping (String) async throws -> [DocumentSearchResult],
        memorySearch: @escaping (String, String, String) throws -> [DocumentSearchResult]
    ) {
        self.debounce = debounce
        self.folderSearch = folderSearch
        self.memorySearch = memorySearch
    }

    var selectedResult: DocumentSearchResult? {
        results.first { $0.id == selection }
    }

    /// Call after any input (query, scope, filters) changes; `immediately` skips the typing debounce.
    func inputChanged(immediately: Bool = false) {
        task?.cancel()
        generation += 1
        results = []
        selection = nil
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            phase = .idle
            task = nil
            return
        }
        phase = .loading
        let mine = generation
        let scope = scope
        let project = project.trimmingCharacters(in: .whitespacesAndNewlines)
        let agent = agent.trimmingCharacters(in: .whitespacesAndNewlines)
        task = Task {
            do {
                if !immediately { try await Task.sleep(for: debounce) }
                let found: [DocumentSearchResult]
                switch scope {
                case .folder: found = try await folderSearch(query)
                // ponytail: SQLite read on the main actor; move off-main if a store ever gets large.
                case .memory: found = try memorySearch(query, project, agent)
                }
                guard mine == generation, !Task.isCancelled else { return }
                results = found
                selection = found.first?.id
                phase = .loaded
            } catch is CancellationError {
                return
            } catch let error as FolderDocumentSearchError {
                guard mine == generation, !Task.isCancelled else { return }
                results = error.results
                selection = results.first?.id
                phase = .failed(error.localizedDescription)
            } catch {
                guard mine == generation, !Task.isCancelled else { return }
                phase = .failed(error.localizedDescription)
            }
        }
    }

    func moveSelection(by offset: Int) {
        guard !results.isEmpty else { return }
        let current = results.firstIndex { $0.id == selection } ?? (offset > 0 ? -1 : results.count)
        selection = results[min(max(current + offset, 0), results.count - 1)].id
    }

    /// Return in the query field: open the highlighted result of the finished search, otherwise search now.
    /// Returns the result to open, if any.
    func submit() -> DocumentSearchResult? {
        if let selected = selectedResult, phase != .loading { return selected }
        inputChanged(immediately: true)
        return nil
    }

    func cancel() {
        task?.cancel()
        generation += 1
    }
}
