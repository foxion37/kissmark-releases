import SwiftUI

/// Advanced search: Folder (title + body of every Markdown Document under the browsed root,
/// or just the picked file in a single-file workspace) or Memory (Documents opened before).
struct DocumentSearchSheet: View {
    @State private var model: DocumentSearchModel
    @FocusState private var isQueryFocused: Bool
    @Environment(\.chromePalette) private var chromePalette
    private let isSingleFile: Bool
    private let choose: (DocumentSearchResult, DocumentSearchModel.Scope) -> Void
    private let close: () -> Void
    private let queryChanged: (String) -> Void

    init(
        model: DocumentSearchModel,
        initialQuery: String,
        isSingleFile: Bool,
        choose: @escaping (DocumentSearchResult, DocumentSearchModel.Scope) -> Void,
        queryChanged: @escaping (String) -> Void,
        close: @escaping () -> Void
    ) {
        model.query = initialQuery
        _model = State(initialValue: model)
        self.isSingleFile = isSingleFile
        self.choose = choose
        self.queryChanged = queryChanged
        self.close = close
    }

    private var muted: Color { chromePalette?.chromeMuted ?? .secondary }

    var body: some View {
        VStack(alignment: .leading, spacing: KissmarkMetrics.sidebarSectionGap) {
            HStack {
                Text("문서 검색").font(KissmarkType.font(.headline))
                Spacer()
                Button("닫기") { model.cancel(); close() }
                    .keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("document-search-close")
            }
            TextField("제목과 본문 검색", text: Binding(
                get: { model.query },
                set: { model.query = $0; queryChanged($0) }
            ))
                .textFieldStyle(.roundedBorder)
                .focused($isQueryFocused)
                .onSubmit { if let result = model.submit() { choose(result, model.scope) } }
                .onKeyPress(.downArrow) { model.moveSelection(by: 1); return .handled }
                .onKeyPress(.upArrow) { model.moveSelection(by: -1); return .handled }
                .onChange(of: model.query) { model.inputChanged() }
                .accessibilityIdentifier("document-search-query")
            Picker("범위", selection: $model.scope) {
                Text(isSingleFile ? "이 문서" : "폴더").tag(DocumentSearchModel.Scope.folder)
                Text("열어 본 문서").tag(DocumentSearchModel.Scope.memory)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .onChange(of: model.scope) { model.inputChanged(immediately: true) }
            .accessibilityLabel("검색 범위")
            .accessibilityIdentifier("document-search-scope")
            if model.scope == .memory {
                HStack(spacing: KissmarkMetrics.sidebarSectionGap) {
                    TextField("프로젝트 (정확히 일치)", text: $model.project)
                        .accessibilityIdentifier("document-search-project")
                    TextField("에이전트 (정확히 일치)", text: $model.agent)
                        .accessibilityIdentifier("document-search-agent")
                }
                .textFieldStyle(.roundedBorder)
                .onChange(of: model.project) { model.inputChanged() }
                .onChange(of: model.agent) { model.inputChanged() }
            }
            status
            resultList
        }
        .padding(KissmarkMetrics.settingsSheetInset)
        #if os(macOS)
        .frame(
            minWidth: KissmarkMetrics.settingsMinimumSize.width,
            minHeight: KissmarkMetrics.settingsMinimumSize.height
        )
        #endif
        .onAppear {
            isQueryFocused = true
            if !model.query.isEmpty { model.inputChanged(immediately: true) }
        }
        .onDisappear { model.cancel() }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("document-search-sheet")
    }

    @ViewBuilder
    private var status: some View {
        Group {
            switch model.phase {
            case .idle:
                Text("검색어를 입력하세요.")
            case .loading:
                HStack(spacing: KissmarkMetrics.sidebarSectionGap) {
                    ProgressView().controlSize(.small)
                    Text("검색 중…")
                }
            case .loaded:
                if model.results.isEmpty {
                    Text("일치하는 문서가 없습니다.")
                } else {
                    Text("\(model.results.count)개 결과")
                }
            case .failed(let message):
                VStack(alignment: .leading, spacing: KissmarkMetrics.treeRowInlineInset) {
                    if model.results.isEmpty {
                        Text("검색하지 못했습니다.")
                    } else {
                        Text("일부 항목을 읽지 못했습니다.")
                        Text("\(model.results.count)개 결과")
                    }
                    Text(message)
                }
            }
        }
        .font(KissmarkType.caption)
        .foregroundStyle(model.phase.isFailure ? (chromePalette?.chromePrimary ?? .primary) : muted)
        .accessibilityIdentifier("document-search-status")
    }

    private var resultList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(model.results) { result in
                        row(result)
                    }
                }
            }
            .onChange(of: model.selection) { _, id in
                if let id { proxy.scrollTo(id) }
            }
        }
        .accessibilityIdentifier("document-search-results")
    }

    private func row(_ result: DocumentSearchResult) -> some View {
        let isSelected = model.selection == result.id
        return Button {
            model.selection = result.id
            choose(result, model.scope)
        } label: {
            VStack(alignment: .leading, spacing: KissmarkMetrics.hoverHintGap) {
                Text(result.title).font(KissmarkType.font(.body, weight: .medium)).lineLimit(1)
                if !result.snippet.isEmpty {
                    Text(result.snippet).font(KissmarkType.caption).lineLimit(2)
                }
                Text(result.path)
                    .font(KissmarkType.caption)
                    .foregroundStyle(muted)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let provenance = provenance(result) {
                    Text(provenance).font(KissmarkType.caption).foregroundStyle(muted)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, KissmarkMetrics.sidebarSectionGap)
            .padding(.horizontal, KissmarkMetrics.folderControlInlineInset)
            .background(
                RoundedRectangle(cornerRadius: KissmarkMetrics.treeSelectionRadius)
                    .fill((chromePalette?.chromePrimary ?? .primary).opacity(isSelected ? KissmarkMetrics.treeSelectionOpacity : 0))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .id(result.id)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("document-search-result")
    }

    private func provenance(_ result: DocumentSearchResult) -> String? {
        let parts = [result.project, result.agent].compactMap { $0 }.filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }
}

private extension DocumentSearchModel.Phase {
    var isFailure: Bool {
        if case .failed = self { return true }
        return false
    }
}

/// Collapsible sidebar input. Its parent owns header spacing and visibility.
/// Return or the magnifier opens the sheet seeded with `query`.
struct DocumentSearchField: View {
    @Binding var query: String
    let submit: () -> Void
    @Environment(\.chromePalette) private var chromePalette
    @FocusState private var isFocused: Bool

    private var controlHeight: CGFloat {
        KissmarkIdiom.current == .mac ? KissmarkMetrics.folderControlHeight : KissmarkMetrics.minTapTarget
    }
    var body: some View {
        HStack(spacing: KissmarkMetrics.iconLabelGap) {
            TextField("문서 검색…", text: $query)
                .textFieldStyle(.plain)
                .font(KissmarkType.font(.body))
                .focused($isFocused)
                .onSubmit(submit)
                .accessibilityIdentifier("folder-browser-search-query")
            Button(action: submit) {
                KissmarkLucideImage(icon: .fileSearch, pointSize: KissmarkMetrics.folderControlIconSize)
                    .foregroundStyle(chromePalette?.chromeMuted ?? .secondary)
                    .frame(width: controlHeight, height: controlHeight)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("문서 검색")
            .accessibilityIdentifier("folder-browser-search-button")
        }
        .padding(.leading, KissmarkMetrics.folderControlInlineInset)
        .frame(height: controlHeight)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: KissmarkMetrics.folderControlRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: KissmarkMetrics.folderControlRadius, style: .continuous)
                .strokeBorder(
                    Color.secondary.opacity(KissmarkMetrics.iconButtonOutlineOpacity),
                    lineWidth: KissmarkMetrics.iconButtonOutlineWidth
                )
        }
        .padding(.horizontal, KissmarkMetrics.sidebarInset)
        .onAppear { isFocused = true }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("document-search-field")
    }
}
