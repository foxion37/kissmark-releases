#if os(macOS)
import AppKit
import SwiftUI
import KissmarkConnections

struct AgentConnectionsSettingsView: View {
    @State private var model = AgentConnectionsModel()
    @State private var searching = false
    @State private var installing = false
    @State private var installingClient: ConnectionClient = .claudeCode
    @State private var installingProfile = ""
    @State private var removing: SelectionKey?
    @State private var reloadingCodex = false
    @State private var expanded: Set<SelectionKey> = []
    @State private var diagnosticsExpanded = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: KissmarkMetrics.settingsRowGap) {
                    HStack(spacing: KissmarkMetrics.settingsRowGap) {
                        Button("연결 검색") { searching = true }
                            .accessibilityIdentifier("settings-connections-search")
                        Button("CLI 설치…") { installing = true }
                            .accessibilityIdentifier("settings-connections-cli-install")
                        Spacer(minLength: 0)
                    }
                    if model.rows.isEmpty {
                        VStack(alignment: .leading, spacing: KissmarkMetrics.settingsRowGap) {
                            Text("추가한 연결이 없습니다.").font(KissmarkType.font(.body, weight: .medium))
                            Text("이 Mac에서 검색한 후보를 직접 추가하세요.")
                                .font(KissmarkType.caption).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .kissmarkSettingsRowInsets()
            ForEach(model.rows) { key in
                Section {
                    DisclosureGroup(isExpanded: expansionBinding(key)) {
                        VStack(alignment: .leading, spacing: KissmarkMetrics.settingsContentGap) {
                            connectionDetails(key)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    } label: {
                        HStack {
                            Text(title(key))
                            Spacer()
                            Text(model.state(for: key).display).foregroundStyle(.secondary)
                                .accessibilityIdentifier("settings-connection-state-\(key.id)")
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityAction { expansionBinding(key).wrappedValue.toggle() }
                    }
                    .accessibilityIdentifier("settings-connection-row-\(key.id)")
                }
            }
            .kissmarkSettingsRowInsets()
            Section {
                // 공개 행: 진단 라벨이 왼쪽, 꺽쇠는 오른쪽 끝에서 아래로 회전한다.
                // macOS 26의 DisclosureGroup 라벨은 본문보다 작게 렌더링되므로
                // 라벨 폰트를 행과 같은 본문으로 명시한다.
                Button {
                    withAnimation(KissmarkMotion.spring(reduceMotion: reduceMotion)) {
                        diagnosticsExpanded.toggle()
                    }
                } label: {
                    HStack {
                        Text("진단")
                            .font(KissmarkType.font(.body, weight: .medium))
                        Spacer(minLength: 0)
                        KissmarkLucideImage(
                            icon: .chevronRight,
                            pointSize: KissmarkMetrics.settingsDisclosureGlyphSize
                        )
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(diagnosticsExpanded ? 90 : 0))
                        .animation(KissmarkMotion.snappy(reduceMotion: reduceMotion), value: diagnosticsExpanded)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityValue(Text(diagnosticsExpanded ? "expanded" : "collapsed"))
                .accessibilityIdentifier("settings-connections-diagnostics")

                if diagnosticsExpanded {
                    VStack(alignment: .leading, spacing: KissmarkMetrics.settingsContentGap) {
                        LabeledContent("연결 검색 기능", value: model.serviceAvailable ? String.kissmarkLocalized("응답 확인됨") : String.kissmarkLocalized("확인 필요"))
                        if let message = model.message { Text(message).font(KissmarkType.caption).foregroundStyle(.secondary) }
                        if let snapshot = model.snapshot {
                            ForEach(snapshot.providers) { provider in
                                LabeledContent(provider.client.title, value: providerText(provider))
                            }
                        }
                        Button("검색") { searching = true }
                            .accessibilityIdentifier("settings-connections-diagnostics-search")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .transition(.opacity)
                }
            }
            .kissmarkSettingsRowInsets()
        }
        .formStyle(.grouped)
        .font(KissmarkType.font(.body))
        .kissmarkSettingsNavigationTitle("연결")
        .task {
            while !Task.isCancelled {
                await model.refresh()
                do { try await Task.sleep(for: .seconds(ConnectionProtocol.refreshInterval)) }
                catch { break }
            }
        }
        .sheet(isPresented: $searching) { searchSheet }
        .sheet(isPresented: $installing) {
            ConnectionInstallSheet(client: installingClient, needsSetup: !model.serviceAvailable, profile: installingProfile)
        }
        .confirmationDialog("연결 목록에서 제거할까요?", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }), presenting: removing) { key in
            Button("목록에서 제거", role: .destructive) { model.remove(key) }
        } message: { _ in
            Text("이 Mac의 목록에서만 숨깁니다. 에이전트의 MCP 설정을 삭제하거나 실행 중인 세션을 종료하지 않습니다.")
        }
        .confirmationDialog("Codex MCP 설정을 다시 불러올까요?", isPresented: $reloadingCodex) {
            Button("다시 불러오기") { Task { await model.reloadCodex() } }
        } message: {
            Text("검색한 로컬 Codex 서버의 모든 로드된 스레드에 적용됩니다. 특정 대화 하나만 바꾸는 작업이 아닙니다. 새 대화를 시작하거나 프롬프트를 보내지는 않습니다.")
        }
    }
    private func expansionBinding(_ key: SelectionKey) -> Binding<Bool> {
        Binding(get: { expanded.contains(key) }, set: { isExpanded in
            withAnimation(KissmarkMotion.spring(reduceMotion: reduceMotion)) {
                if isExpanded { expanded.insert(key) } else { expanded.remove(key) }
            }
        })
    }
    private func title(_ key: SelectionKey) -> String {
        key.client.title + (key.profile.map { " (\($0))" } ?? "")
    }
    private func providerText(_ provider: ProviderOutcome) -> String {
        switch provider.status {
        case .available: String.kissmarkLocalized("검색 완료")
        case .unsupported: String.kissmarkLocalized("실행 세션 검색 미지원")
        case .unavailable: String.kissmarkLocalized("실행 파일 또는 로컬 서버 확인 필요")
        case .failed: String.kissmarkLocalized("검색 실패") + (provider.reason.map { ", \($0.rawValue)" } ?? "")
        case .cancelled: String.kissmarkLocalized("검색 취소됨")
        }
    }
    @ViewBuilder
    private func connectionDetails(_ key: SelectionKey) -> some View {
        let instances = model.snapshot?.instances.filter { $0.key == key } ?? []
        if instances.isEmpty {
            Text("응답을 확인한 Kissmark MCP 연결이 없습니다. 설치와 실행 여부만으로 연결됐다고 표시하지 않습니다.")
                .font(KissmarkType.caption).foregroundStyle(.secondary)
        }
        ForEach(instances) { instance in
            LabeledContent(String.kissmarkLocalized("MCP 인스턴스 \(String(instance.id.uuidString.prefix(8)))"), value: instance.isConnected() && model.serviceAvailable ? ConnectionDisplayState.connected.display : ConnectionDisplayState.needsProbe.display)
            LabeledContent("등록 범위", value: instance.scope == .user ? String.kissmarkLocalized("사용자 공통") : instance.scope == .project ? String.kissmarkLocalized("프로젝트") : ConnectionDisplayState.unavailable.display)
            Button("연결 확인") { Task { await model.probe(instance.id) } }
                .disabled(!model.serviceAvailable)
                .accessibilityIdentifier("settings-connection-probe-\(instance.id.uuidString)")
        }
        let sessions = model.snapshot?.candidates.filter { $0.key == key && $0.instance != nil } ?? []
        ForEach(sessions) { session in
            LabeledContent(session.runtime == .loaded ? String.kissmarkLocalized("로드된 스레드") : String.kissmarkLocalized("발견한 실행 인스턴스"), value: String((session.instance ?? "").suffix(20)))
        }
        if !sessions.isEmpty {
            Text("실행 세션과 MCP 연결은 별도 정보입니다. 직접 대응이 확인되지 않은 세션에 연결됐다고 표시하지 않습니다.")
                .font(KissmarkType.caption).foregroundStyle(.secondary)
        }
        if let date = AgentConnectionFiles.lastHandshake(key.client) {
            LabeledContent("과거 MCP 초기화", value: date.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(KissmarkLocalization.locale)))
        }
        Text(reloadHint(key.client)).font(KissmarkType.caption).foregroundStyle(.secondary)
        if key.client == .codex, model.serviceAvailable,
           model.snapshot?.providers.contains(where: { $0.client == .codex && $0.status == .available }) == true {
            Button("Codex MCP 다시 불러오기…") { reloadingCodex = true }
        }
        HStack(spacing: KissmarkMetrics.settingsRowGap) {
            Button("CLI 설치 안내…") { installingClient = key.client; installingProfile = key.profile ?? ""; installing = true }
            Spacer()
            Button("목록에서 제거…") { removing = key }
                .accessibilityIdentifier("settings-connection-remove-\(key.id)")
        }
    }
    /// CLI 설치 시트와 같은 grouped Form 스타일. List 대신 Form 섹션을 쓰므로
    /// 여백·행 구성이 다른 설정면과 일치하고, 행 클릭이 선택처럼 보이지 않는다.
    private var searchSheet: some View {
        Form {
            Section {
                HStack(spacing: KissmarkMetrics.settingsRowGap) {
                    Button(model.scanning ? String.kissmarkLocalized("검색 취소") : String.kissmarkLocalized("다시 검색")) {
                        if model.scanning { model.cancelSearch() } else { model.startSearch() }
                    }
                    if model.scanning { ProgressView().controlSize(.small) }
                    Spacer(minLength: 0)
                    Button("CLI 설치…") { searching = false; installing = true }
                }
                if let message = model.message {
                    Text(message).font(KissmarkType.caption).foregroundStyle(.secondary)
                }
            } header: {
                Text("연결 검색")
            } footer: {
                Text("이 Mac만 검색합니다. 대화 내용이나 인증 정보를 수집하지 않으며, 추가는 설치 또는 연결 성공을 뜻하지 않습니다.")
            }
            Section {
                if model.scanning, model.candidates.isEmpty {
                    Text("검색 중입니다…").font(KissmarkType.font(.body)).foregroundStyle(.secondary)
                } else if !model.scanning, model.candidates.isEmpty, model.message == nil {
                    Text(model.serviceAvailable ? String.kissmarkLocalized("확인된 후보가 없습니다.") : String.kissmarkLocalized("연결 검색 기능 준비가 필요합니다. CLI 설치에서 준비하세요."))
                        .font(KissmarkType.font(.body))
                }
                candidateRows(model.candidates.filter { $0.instance != nil })
            } header: {
                Text("실행 중이거나 로드된 후보")
            }
            Section {
                candidateRows(model.candidates.filter { $0.instance == nil })
            } header: {
                Text("설치된 도구")
            }
            if let snapshot = model.snapshot {
                Section {
                    ForEach(snapshot.providers) { provider in
                        LabeledContent(provider.client.title, value: providerText(provider))
                    }
                } header: {
                    Text("검색 범위")
                }
            }
        }
        .formStyle(.grouped)
        .font(KissmarkType.font(.body))
        .safeAreaInset(edge: .top, spacing: 0) {
            HStack {
                Text("연결 검색").font(KissmarkType.font(.headline))
                Spacer()
                Button("닫기") { searching = false }.keyboardShortcut(.cancelAction)
            }
            .padding(KissmarkMetrics.settingsSheetInset)
        }
        .frame(minWidth: KissmarkMetrics.settingsMinimumSize.width, minHeight: KissmarkMetrics.settingsMinimumSize.height)
        .onAppear { model.startSearch() }
        .onDisappear { model.cancelSearch() }
    }
    @ViewBuilder
    private func candidateRows(_ candidates: [DiscoveryCandidate]) -> some View {
        ForEach(candidates) { candidate in
            LabeledContent {
                HStack(spacing: KissmarkMetrics.settingsRowGap) {
                    if let instance = candidate.instance {
                        Text(String(instance.suffix(20)))
                            .font(KissmarkType.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text(candidate.runtime == .installed ? String.kissmarkLocalized("설치됨") : candidate.runtime == .loaded ? ConnectionDisplayState.loaded.display : ConnectionDisplayState.running.display)
                        .font(KissmarkType.font(.body))
                        .foregroundStyle(.secondary)
                    Button(model.selections.contains(candidate.key) ? String.kissmarkLocalized("추가됨") : String.kissmarkLocalized("추가")) { model.add(candidate.key) }
                        .disabled(!model.serviceAvailable || model.snapshot == nil || model.selections.contains(candidate.key))
                        .accessibilityIdentifier("settings-connection-add-\(candidate.id)")
                }
            } label: {
                VStack(alignment: .leading, spacing: 0) {
                    Text(title(candidate.key)).font(KissmarkType.font(.body))
                    if let instance = candidate.instance {
                        Text(String(instance.suffix(20)))
                            .font(KissmarkType.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
    private func reloadHint(_ client: ConnectionClient) -> String {
        switch client {
        case .omp: String.kissmarkLocalized("등록 후 해당 OMP 세션에서 /mcp reload를 실행하세요. Collab 검색은 공유가 켜진 세션만 찾습니다.")
        case .codex: String.kissmarkLocalized("접근 가능한 로컬 app-server의 로드된 스레드만 검색합니다. 등록 후 새 세션이나 클라이언트의 MCP 다시 불러오기가 필요합니다.")
        case .claudeCode: String.kissmarkLocalized("등록 후 새 Claude Code 세션에서 /mcp로 확인하세요. 기존 세션을 강제로 바꾸지 않습니다.")
        default: String.kissmarkLocalized("해당 앱에서 설치 승인을 마치고 MCP 서버를 시작하거나 다시 불러오세요. 앱 프로세스가 실행 중이어도 개별 대화가 연결된 것은 아닙니다.")
        }
    }
}

private struct ConnectionInstallSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State var client: ConnectionClient
    @State var needsSetup: Bool
    @State private var scope = "user"
    @State private var project: URL?
    @State var profile: String
    @State private var copied = false
    private var command: String? {
        if needsSetup { return ConnectionEncoding.setupCommand(helper: AgentConnectionFiles.helper, language: KissmarkLocalization.languageCode) }
        return ConnectionEncoding.installCommand(helper: AgentConnectionFiles.helper, client: client, scope: scope, project: project, profile: profile, language: KissmarkLocalization.languageCode)
    }
    var body: some View {
        Form {
            Section {
                Picker("설치 작업", selection: $needsSetup) {
                    Text("검색 기능 준비").tag(true)
                    Text("에이전트 MCP 등록").tag(false)
                }
                if needsSetup {
                    Text("현재 사용자용 연결 검색 기능과 CLI 경로를 준비합니다. 검색 기능은 로그인 시 실행되며 에이전트 MCP 설정은 바꾸지 않습니다. 터미널에서 내용을 확인하고 yes로 승인합니다.")
                } else {
                    Picker("에이전트", selection: $client) { ForEach(ConnectionClient.allCases, id: \.self) { Text($0.title).tag($0) } }
                    Picker("등록 범위", selection: $scope) {
                        Text("사용자 공통 (global)").tag("user")
                        if client != .claudeDesktop { Text("특정 프로젝트").tag("project") }
                    }
                    if scope == "project" {
                        LabeledContent("프로젝트", value: project?.lastPathComponent ?? String.kissmarkLocalized("선택 필요"))
                        Button("프로젝트 선택…") {
                            let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.allowsMultipleSelection = false
                            if panel.runModal() == .OK { project = panel.url }
                        }
                    }
                    if client == .omp, scope == "user" { TextField("OMP 프로필 (선택)", text: $profile) }
                    Text("선택한 에이전트의 kissmark 항목만 등록합니다. global은 모든 에이전트에 일괄 설치한다는 뜻이 아닙니다. GUI 도구는 공식 설치창에서 추가 승인이 필요합니다.")
                }
            }
            Section("터미널에서 직접 실행") {
                if let command {
                    Text(command).font(.system(.body, design: .monospaced)).textSelection(.enabled)
                    Button(copied ? String.kissmarkLocalized("복사됨") : String.kissmarkLocalized("명령 복사")) {
                        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(command, forType: .string); copied = true
                    }
                    .accessibilityIdentifier("settings-connections-copy-install")
                } else { Text("지원되는 범위와 프로젝트를 선택하세요.").foregroundStyle(.secondary) }
                Text("이 화면은 설치 명령을 실행하거나 터미널을 자동으로 열지 않습니다.").font(KissmarkType.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .font(KissmarkType.font(.body))
        .safeAreaInset(edge: .top, spacing: 0) {
            HStack {
                Text("CLI 설치").font(KissmarkType.font(.headline))
                Spacer()
                Button("닫기") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            .padding(KissmarkMetrics.settingsSheetInset)
        }
        .frame(minWidth: KissmarkMetrics.settingsMinimumSize.width, minHeight: KissmarkMetrics.settingsMinimumSize.height)
        .onChange(of: client) { _, newValue in if newValue == .claudeDesktop { scope = "user" }; copied = false }
        .onChange(of: command) { _, _ in copied = false }
    }
}
#endif
