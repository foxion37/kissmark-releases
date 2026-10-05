#if os(macOS)
import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Only the declared Markdown type, never public.text or public.plain-text.
struct MarkdownDefaultAppSettings: View {
    private static let markdownType = UTType(importedAs: "net.daringfireball.markdown", conformingTo: .plainText)
    private static let applicationURL = Bundle.main.bundleURL.resolvingSymlinksInPath()

    @State private var currentApplicationName = ""
    @State private var isDefault = false
    @State private var isSetting = false
    @State private var errorMessage: String?

    var body: some View {
        Section {
            LabeledContent("현재 기본 앱") {
                Text(currentApplicationName)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("settings-markdown-default-app")
            }
            Button {
                Task { await setAsDefault() }
            } label: {
                if isSetting {
                    Text("설정 중…")
                } else if isDefault {
                    Text("Kissmark가 기본 앱입니다")
                } else {
                    Text("Markdown 기본 앱으로 설정")
                }
            }
            .buttonStyle(.bordered)
            .disabled(isSetting || isDefault)
            .accessibilityIdentifier("settings-set-markdown-default")
            if let errorMessage {
                Text(errorMessage)
                    .font(KissmarkType.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("settings-markdown-default-error")
            }
        } header: {
            Text("Markdown 기본 앱")
        } footer: {
            Text(".md와 .markdown 파일을 Finder에서 열 때 Kissmark를 사용합니다. 일반 텍스트 파일의 기본 앱은 바꾸지 않습니다.")
        }
        .onAppear(perform: refresh)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refresh()
        }
    }

    private func refresh() {
        let shortType = UTType(filenameExtension: "md")
        let longType = UTType(filenameExtension: "markdown")
        let shortApp = shortType.flatMap { NSWorkspace.shared.urlForApplication(toOpen: $0) }
        let longApp = shortType == longType
            ? shortApp : longType.flatMap { NSWorkspace.shared.urlForApplication(toOpen: $0) }
        let none = String.kissmarkLocalized("지정된 앱 없음")
        let shortName = shortApp?.deletingPathExtension().lastPathComponent ?? none
        let longName = longApp?.deletingPathExtension().lastPathComponent ?? none
        currentApplicationName = shortApp == longApp
            ? shortName : ".md: \(shortName), .markdown: \(longName)"
        let shortIsDefault = shortApp?.resolvingSymlinksInPath() == Self.applicationURL
        isDefault = shortIsDefault && (shortApp == longApp || longApp?.resolvingSymlinksInPath() == Self.applicationURL)
    }

    private func setAsDefault() async {
        guard !isSetting else { return }
        isSetting = true
        errorMessage = nil
        defer { isSetting = false }
        do {
            try await NSWorkspace.shared.setDefaultApplication(at: Self.applicationURL, toOpen: Self.markdownType)
        } catch {
            errorMessage = String.kissmarkLocalized("기본 앱을 변경하지 못했습니다.") + " " + error.localizedDescription
        }
        refresh()
        if errorMessage == nil, !isDefault {
            errorMessage = String.kissmarkLocalized("일부 Markdown 파일의 연결이 변경되지 않았습니다. Finder의 정보 가져오기에서 연결 앱을 확인하세요.")
        }
    }
}
#endif
