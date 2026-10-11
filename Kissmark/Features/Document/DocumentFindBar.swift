import SwiftUI

/// Find bar above the Document surface: query, Match Case / Whole Word / Regular
/// Expression, "n/total" status, previous / next, close. Return = next, Escape = close.
struct DocumentFindBar: View {
    @Bindable var model: DocumentFindModel
    @FocusState private var isQueryFocused: Bool
    @Environment(\.chromePalette) private var chromePalette

    var body: some View {
        VStack(alignment: .leading, spacing: KissmarkMetrics.iconLabelGap) {
            Text("문서 내 검색")
                .font(KissmarkType.font(.headline))
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("document-find-heading")
            HStack(spacing: KissmarkMetrics.iconLabelGap) {
                TextField("문서에서 찾기", text: $model.query)
                    .textFieldStyle(.roundedBorder)
                    .font(KissmarkType.font(.body))
                    .focused($isQueryFocused)
                    .onSubmit { model.next() }
                    .onKeyPress(.escape) {
                        model.close()
                        return .handled
                    }
                    .accessibilityLabel(Text("문서에서 찾기"))
                    .accessibilityIdentifier("document-find-query")
                Text(status)
                    .font(KissmarkType.font(.caption))
                    .foregroundStyle(model.isInvalidRegex ? Color.red : Color.secondary)
                    .lineLimit(1)
                    .monospacedDigit()
                    .accessibilityIdentifier("document-find-status")
                Button("닫기") { model.close() }
                    .accessibilityLabel(Text("찾기 닫기"))
                    .accessibilityIdentifier("document-find-close")
            }
            HStack(spacing: KissmarkMetrics.iconLabelGap) {
                Toggle(isOn: $model.caseSensitive) { Text("Aa") }
                    .accessibilityLabel(Text("대소문자 구분"))
                    .accessibilityIdentifier("document-find-case")
                Toggle(isOn: $model.wholeWord) { Text("단어") }
                    .accessibilityLabel(Text("단어 단위"))
                    .accessibilityIdentifier("document-find-word")
                Toggle(isOn: $model.useRegex) { Text(".*") }
                    .accessibilityLabel(Text("정규식"))
                    .accessibilityIdentifier("document-find-regex")
                Spacer(minLength: KissmarkMetrics.iconLabelGap)
                Button("이전") { model.previous() }
                    .accessibilityLabel(Text("이전 결과"))
                    .accessibilityIdentifier("document-find-previous")
                    .disabled(model.total == 0)
                Button("다음") { model.next() }
                    .accessibilityLabel(Text("다음 결과"))
                    .accessibilityIdentifier("document-find-next")
                    .disabled(model.total == 0)
            }
        }
        .toggleStyle(.button)
        .font(KissmarkType.font(.caption))
        .padding(.horizontal, KissmarkMetrics.sidebarInset)
        .padding(.vertical, KissmarkMetrics.iconLabelGap)
        .background {
            if let chromePalette {
                chromePalette.chromeElevatedBackground
            } else {
                Rectangle().fill(.regularMaterial)
            }
        }
        .overlay(alignment: .bottom) { Divider().kissmarkChromeDivider(chromePalette) }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("document-find-bar")
        .onAppear { isQueryFocused = true }
        .onChange(of: model.focusToken) { _, _ in isQueryFocused = true }
        .onChange(of: model.query) { _, _ in model.search() }
        .onChange(of: model.caseSensitive) { _, _ in model.search() }
        .onChange(of: model.wholeWord) { _, _ in model.search() }
        .onChange(of: model.useRegex) { _, _ in model.search() }
    }

    private var status: String {
        if model.query.isEmpty { return "" }
        if model.isInvalidRegex { return .kissmarkLocalized("올바르지 않은 정규식") }
        guard let active = model.activeIndex else { return .kissmarkLocalized("결과 없음") }
        return .kissmarkLocalized("\(active + 1)/\(model.total)")
    }
}
