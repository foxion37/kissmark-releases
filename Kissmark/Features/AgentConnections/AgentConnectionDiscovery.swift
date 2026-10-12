#if os(macOS)
import AppKit
import SwiftUI
import KissmarkConnections

enum ConnectionDisplayState {
    case connected, disconnected, needsProbe, running, loaded, needsSessionCheck, unavailable
    var display: String {
        switch self {
        case .connected: String.kissmarkLocalized("연결됨")
        case .disconnected: String.kissmarkLocalized("연결 끊김")
        case .needsProbe: String.kissmarkLocalized("연결 확인 필요")
        case .running: String.kissmarkLocalized("실행 중")
        case .loaded: String.kissmarkLocalized("로드됨")
        case .needsSessionCheck: String.kissmarkLocalized("실행 세션 확인 필요")
        case .unavailable: String.kissmarkLocalized("확인 불가")
        }
    }
}

struct AgentConnectionDiscovery: Sendable {
    let socket: String
    nonisolated func request(_ request: BrokerRequest) async throws -> BrokerReply {
        let connection = try await Task.detached(priority: .utility) { try LocalConnection.connect(path: socket) }.value
        defer { connection.shutdown() }
        try Task.checkCancellation()
        return try await withTaskCancellationHandler {
            try await Task.detached(priority: .utility) { try connection.request(request) }.value
        } onCancel: { connection.shutdown() }
    }
}

@MainActor
@Observable
final class AgentConnectionsModel {
    private(set) var snapshot: DiscoverySnapshot?
    private(set) var selections: Set<SelectionKey> = []
    private(set) var scanning = false
    private(set) var serviceAvailable = false
    private(set) var message: String?
    private(set) var localApplications: [DiscoveryCandidate] = []
    private let store: ConnectionSelectionStore
    private let fetch: @Sendable (BrokerRequest) async throws -> BrokerReply
    @ObservationIgnored private var searchTask: Task<Void, Never>?
    private var generation = UUID()
    private var verifiedKeys: Set<SelectionKey> = []

    init(store: ConnectionSelectionStore? = nil, fetch: (@Sendable (BrokerRequest) async throws -> BrokerReply)? = nil) {
        self.store = store ?? ConnectionSelectionStore(file: AgentConnectionFiles.support.appendingPathComponent("discovery/selections.json"))
        let discovery = AgentConnectionDiscovery(socket: AgentConnectionFiles.socket)
        self.fetch = fetch ?? { try await discovery.request($0) }
    }
    var rows: [SelectionKey] { selections.sorted { $0.id < $1.id } }
    var candidates: [DiscoveryCandidate] {
        let discovered = snapshot?.candidates ?? []
        let transports = (snapshot?.instances ?? []).map { DiscoveryCandidate(key: $0.key, instance: $0.id.uuidString, runtime: .running) }
        return discovered + transports + localApplications.filter { local in !discovered.contains { $0.key == local.key && $0.instance == nil } }
    }
    @discardableResult
    func startSearch() -> Task<Void, Never> {
        cancelSearch()
        let requestGeneration = UUID(); generation = requestGeneration
        scanning = true; message = nil
        localApplications = ConnectionClient.allCases.compactMap { client in
            guard let id = client.bundleID, NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) != nil else { return nil }
            return DiscoveryCandidate(key: SelectionKey(client: client))
        }
        let task = Task {
            do {
                let reply = try await fetch(BrokerRequest(.discover))
                guard !Task.isCancelled, generation == requestGeneration else { return }
                accept(reply)
            } catch {
                guard !Task.isCancelled, generation == requestGeneration else { return }
                serviceAvailable = (error as? ConnectionFailure) == .busy
                message = Self.explanation(error)
            }
            if generation == requestGeneration { scanning = false }
        }
        searchTask = task
        return task
    }
    func cancelSearch() {
        generation = UUID(); searchTask?.cancel(); searchTask = nil; scanning = false
    }
    private func accept(_ reply: BrokerReply) {
        guard let updated = reply.snapshot else { message = String.kissmarkLocalized("검색 결과 형식을 확인할 수 없습니다."); return }
        // 화면에 그려지는 내용이 이전 스냅샷과 같으면 아무것도 대입하지 않는다.
        // @Observable는 같은 값의 대입도 재렌더링을 일으키고, 폴링이 5초마다
        // 들어오므로 무변화 대입은 설정 창 전체의 주기적 버벅임이 된다.
        if let current = snapshot,
           current.installationID == updated.installationID,
           current.candidates == updated.candidates,
           current.providers == updated.providers,
           current.instances == updated.instances,
           serviceAvailable, message == nil {
            return
        }
        if snapshot?.installationID != updated.installationID {
            selections = store.load(for: updated.installationID)
            verifiedKeys.removeAll()
        }
        for instance in updated.instances where instance.isConnected() { verifiedKeys.insert(instance.key) }
        snapshot = updated; serviceAvailable = true; message = nil
    }
    func add(_ key: SelectionKey) {
        guard serviceAvailable else { message = String.kissmarkLocalized("먼저 CLI 설치에서 검색 기능을 준비하세요."); return }
        guard let id = snapshot?.installationID else { message = String.kissmarkLocalized("검색 결과를 받은 뒤 추가할 수 있습니다."); return }
        var updated = selections; updated.insert(key)
        save(updated, installationID: id)
    }
    func remove(_ key: SelectionKey) {
        guard let id = snapshot?.installationID else { return }
        var updated = selections; updated.remove(key)
        save(updated, installationID: id)
    }
    private func save(_ updated: Set<SelectionKey>, installationID: UUID) {
        do { try store.save(updated, installationID: installationID); selections = updated }
        catch { message = String.kissmarkLocalized("이 Mac의 연결 목록을 저장하지 못했습니다.") }
    }
    func refresh() async {
        guard !scanning else { return }
        let requestGeneration = generation
        do {
            let reply = try await fetch(BrokerRequest(.snapshot))
            guard !Task.isCancelled, !scanning, generation == requestGeneration else { return }
            accept(reply)
            for instance in snapshot?.instances ?? [] where selections.contains(instance.key) {
                await probe(instance.id)
            }
        } catch {
            guard !Task.isCancelled, generation == requestGeneration else { return }
            if serviceAvailable || message == nil { serviceAvailable = false; message = Self.explanation(error) }
        }
    }
    func probe(_ id: UUID) async {
        guard let installationID = snapshot?.installationID else { return }
        do {
            let reply = try await fetch(BrokerRequest(.probe, instanceID: id))
            guard !Task.isCancelled, snapshot?.installationID == installationID,
                  let updated = reply.instance, updated.id == id,
                  let index = snapshot?.instances.firstIndex(where: { $0.id == id }) else { return }
            if snapshot?.instances[index] != updated {
                snapshot?.instances[index] = updated
            }
            if updated.isConnected() { verifiedKeys.insert(updated.key) }
        } catch {
            guard (error as? ConnectionFailure) != .busy else { return }
            if snapshot?.installationID == installationID, let index = snapshot?.instances.firstIndex(where: { $0.id == id }),
               snapshot?.instances[index].lastPeerResponse != nil {
                snapshot?.instances[index].lastPeerResponse = nil
            }
        }
    }
    func reloadCodex() async {
        do {
            _ = try await fetch(BrokerRequest(.reloadCodex))
            message = String.kissmarkLocalized("Codex에 MCP 다시 불러오기를 요청했습니다. 실제 연결 응답은 별도로 확인합니다.")
        } catch { message = Self.explanation(error) }
    }
    func state(for key: SelectionKey) -> ConnectionDisplayState {
        guard serviceAvailable else { return .unavailable }
        let instances = snapshot?.instances.filter { $0.key == key } ?? []
        if instances.contains(where: { $0.isConnected() }) { return .connected }
        if !instances.isEmpty { return .needsProbe }
        if verifiedKeys.contains(key) { return .disconnected }
        let live = snapshot?.candidates.filter { $0.key == key && $0.instance != nil } ?? []
        if let captured = snapshot?.capturedAt, Date().timeIntervalSince(captured) < ConnectionProtocol.freshness {
            if live.contains(where: { $0.runtime == .running }) { return .running }
            if live.contains(where: { $0.runtime == .loaded }) { return .loaded }
        }
        if snapshot?.providers.contains(where: { $0.client == key.client && $0.status == .available }) == true { return .needsSessionCheck }
        return .unavailable
    }
    static func explanation(_ error: Error) -> String {
        switch error as? ConnectionFailure {
        case .unavailable: String.kissmarkLocalized("연결 검색 기능에 연결할 수 없습니다. CLI 설치에서 검색 기능을 준비하거나 다시 검색하세요.")
        case .timeout: String.kissmarkLocalized("검색 응답 시간이 초과됐습니다.")
        case .unsafeEndpoint: String.kissmarkLocalized("연결 검색 기능의 소유자 또는 접근 권한을 확인할 수 없습니다.")
        case .accessDenied: String.kissmarkLocalized("연결 검색 기능 또는 클라이언트 경로에 접근할 권한이 없습니다.")
        case .oversized: String.kissmarkLocalized("검색 결과가 허용된 크기를 초과했습니다. 성공한 빈 결과로 처리하지 않습니다.")
        case .pathTooLong: String.kissmarkLocalized("로컬 통신 경로가 너무 깁니다.")
        case .busy: String.kissmarkLocalized("다른 검색이 진행 중입니다. 잠시 후 다시 검색하세요.")
        case .versionMismatch: String.kissmarkLocalized("앱과 연결 검색 기능의 버전이 다릅니다. CLI 설치에서 검색 기능을 다시 준비하세요.")
        default: String.kissmarkLocalized("검색 결과를 확인할 수 없습니다. 설치 안내와 진단을 확인하세요.")
        }
    }
}
#endif
