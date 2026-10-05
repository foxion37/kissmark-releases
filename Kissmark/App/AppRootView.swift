//
//  AppRootView.swift
//  Kissmark
//
//  Created by 김성규 on 7/14/26.
//

import SwiftUI
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#endif

struct AppRootView: View {
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(KissmarkAppearance.storageKey) private var appearanceID = KissmarkAppearance.system.rawValue
    @AppStorage(DocumentTheme.storageKey) private var themeID = DocumentTheme.system.rawValue
    @AppStorage(ThemeAccentOverrides.storageKey) private var accentJSON = ""
    #if os(macOS)
    @ObservedObject private var systemAppearance = KissmarkSystemAppearanceObserver.shared

    /// 모양 = 시스템 resolves to the live system scheme; the observer keeps it current.
    private var appearanceScheme: ColorScheme? {
        KissmarkAppearance.pinnedScheme(
            KissmarkAppearance(rawValue: appearanceID) ?? .system,
            systemScheme: systemAppearance.systemScheme
        )
    }
    #endif
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var model: FolderSelectionModel
    @State private var isFolderImporterPresented = false
    @State private var isEditorFixturePresented = true
    @Environment(KissmarkUpdateController.self) private var updateController
    @Environment(MirrorCoordinator.self) private var mirror

    private var theme: DocumentTheme { DocumentTheme(rawValue: themeID) ?? .system }
    private var accentHex: String {
        ThemeAccentOverrides.decode(accentJSON).accent(for: theme, scheme: effectiveScheme) ?? ""
    }

    /// The Appearance scheme the window is actually shown in; the theme adapts to it.
    private var effectiveScheme: ColorScheme {
        #if os(macOS)
        KissmarkAppearance.effectiveScheme(
            KissmarkAppearance(rawValue: appearanceID) ?? .system,
            systemScheme: systemAppearance.systemScheme
        )
        #else
        KissmarkAppearance.effectiveScheme(
            KissmarkAppearance(rawValue: appearanceID) ?? .system,
            systemScheme: colorScheme
        )
        #endif
    }

    /// The theme accent (or the user's override); `nil` keeps the system accent.
    private var chromeAccent: Color? {
        DocumentThemeResolver.chromeAccentHex(theme: theme, scheme: effectiveScheme, override: accentHex)
            .flatMap { Color(kissmarkHex: $0) }
    }

    init() {
        #if DEBUG
        let uiTestModel = Self.makeUITestModel()
        let initialModel = uiTestModel ?? FolderSelectionModel()
        #else
        let uiTestModel: FolderSelectionModel? = nil
        let initialModel = FolderSelectionModel()
        #endif
        if uiTestModel == nil {
            initialModel.restoreSavedFolder()
        }
        _model = State(initialValue: initialModel)
    }

    var body: some View {
        Group {
            switch AppLaunchRoute.resolve() {
            case .readerFixture:
                EditorFixtureScreen { isEditorFixturePresented = false }
            case .editorFixture:
                if isEditorFixturePresented {
                    EditorFixtureScreen { isEditorFixturePresented = false }
                } else {
                    // Closing the fixture returns to the normal Folder shell
                    // so Choose Folder stays available (no dead-end screen).
                    folderSelectionBody
                }
            case .folderSelection:
                folderSelectionBody
            }
        }
        .environment(\.locale, KissmarkLocalization.locale)
        .font(KissmarkType.font(.body))
        #if os(macOS)
        .preferredColorScheme(appearanceScheme)
        #else
        .preferredColorScheme((KissmarkAppearance(rawValue: appearanceID) ?? .system).preferredColorScheme)
        #endif
        .tint(chromeAccent)
        .environment(\.chromePalette, theme.palette(for: effectiveScheme))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("app-root")
        #if os(macOS)
        // Launch size fits the Document column on every main window, including the
        // empty state before a Folder is chosen (once per window).
        .background(FolderBrowserWindowConfigurator())
        #endif
        .accessibilityValue(effectiveScheme == .dark ? "dark" : "light")
        .task {
            // Test hosts share the app container; only a normal launch migrates preferences.
            if !AppLaunchRoute.isUITestGate(),
               ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil,
               NSClassFromString("XCTestCase") == nil {
                ThemeAccentOverrides.migrateLegacy(in: .standard, theme: theme, scheme: effectiveScheme)
            }
            await updateController.refresh()
        }
        .onReceive(NotificationCenter.default.publisher(for: .kissmarkChooseFolder)) { _ in
            isFolderImporterPresented = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .kissmarkOpenParentFolder)) { _ in
            model.requestParentGrant()
        }
        // Files handed over by LaunchServices (Finder, `open`, kissmark-mcp) open in
        // this window instead of spawning a new one per file.
        .onOpenURL { url in
            guard url.isFileURL else { return }
            model.openExternal(url)
        }
        .handlesExternalEvents(preferring: ["*"], allowing: ["*"])
        .fileImporter(
            isPresented: $isFolderImporterPresented,
            allowedContentTypes: FolderPickerContentTypes.types,
            allowsMultipleSelection: false,
            onCompletion: { result in
                model.handle(FolderImportOutcome.map(result))
            },
            onCancellation: {
                model.handle(.cancelled)
            }
        )
        .modifier(FolderGrantPresenter(model: model))
        .alert(
            model.error?.title ?? "",
            isPresented: Binding(
                get: { model.error != nil },
                set: { isPresented in
                    if !isPresented {
                        model.dismissError()
                    }
                }
            ),
            presenting: model.error
        ) { _ in
            Button("확인") {
                model.dismissError()
            }
        } message: { error in
            Text(error.message)
                .accessibilityIdentifier("folder-picker-error-alert")
        }
        // Chrome colors crossfade with the Document's own theme transition.
        .animation(KissmarkMotion.theme(reduceMotion: reduceMotion), value: themeID)
        .animation(KissmarkMotion.theme(reduceMotion: reduceMotion), value: accentHex)
        .animation(KissmarkMotion.theme(reduceMotion: reduceMotion), value: appearanceID)
    }

    @ViewBuilder
    private var folderSelectionBody: some View {
        if let folder = model.selectedFolder {
            FolderBrowserView(
                folder: folder,
                initialDocumentURL: model.pendingDocumentURL,
                mirror: mirror,
                consumeDocumentRequest: { _ = model.consumePendingDocument() },
                openExternalDocument: { model.openExternal($0) },
                requestReload: { model.requestReload(reopening: $0) }
            )
                // The browsed root, not the scope owner: a pick inside a held Folder
                // re-roots the tree at the Document's parent. ⌘R bumps the generation,
                // which rebuilds the whole browser from disk.
                .id("\(folder.rootURL.path)#\(model.reloadGeneration)")
                .onAppear { _ = model.consumePendingDocument() }
        } else {
            KissmarkEmptyState(
                icon: .folderOpen,
                title: "폴더나 파일을 여세요",
                message: "폴더를 고르거나 Markdown 파일을 열면 됩니다. 같은 Apple ID라면 Mac과 iPhone이 iCloud Kissmark 폴더를 함께 씁니다.",
                actionTitle: "열기",
                actionIcon: .folder,
                actionAccessibilityIdentifier: "choose-folder-button"
            ) {
                isFolderImporterPresented = true
            }
            .padding(KissmarkMetrics.documentPadding(idiom: .current))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    #if DEBUG
    /// UI-test runs share the app container with the user's installed copy, so their
    /// picks persist into a throwaway suite, never the real Folder bookmark.
    private static var uiTestBookmarks: FolderBookmarks {
        FolderBookmarks(defaults: UserDefaults(suiteName: "kissmark.ui-test")!)
    }

    private static func makeUITestModel(
        arguments: [String] = ProcessInfo.processInfo.arguments,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> FolderSelectionModel? {
        guard AppLaunchRoute.isUITestGate(arguments: arguments, environment: environment),
              let argumentIndex = arguments.firstIndex(of: "-ui-test-state"),
              arguments.indices.contains(argumentIndex + 1) else {
            return nil
        }

        switch arguments[argumentIndex + 1] {
        case "selected":
            return FolderSelectionModel(selectedFolder: makeUITestFolder(named: "KM_Selected_A"), bookmarks: uiTestBookmarks)
        case "picker-failure":
            let model = FolderSelectionModel(selectedFolder: makeUITestFolder(named: "KM_Selected_A"), bookmarks: uiTestBookmarks)
            model.handle(.failed)
            return model
        case "folder-browser", "folder-browser-shell":
            let folderURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("KissmarkUITestFolder", isDirectory: true)
            try? FileManager.default.removeItem(at: folderURL)
            try? FileManager.default.createDirectory(
                at: folderURL,
                withIntermediateDirectories: true
            )
            try? "# Layout QA\n\nToolbar and sidebar fixture.\n".write(
                to: folderURL.appendingPathComponent("Layout QA.md"),
                atomically: true,
                encoding: .utf8
            )
            let spacingFolderURL = folderURL.appendingPathComponent("Spacing QA", isDirectory: true)
            try? FileManager.default.createDirectory(
                at: spacingFolderURL,
                withIntermediateDirectories: true
            )
            try? "# Nested Layout QA\n".write(
                to: spacingFolderURL.appendingPathComponent("Nested Layout QA.md"),
                atomically: true,
                encoding: .utf8
            )
            let thirdLevelURL = spacingFolderURL.appendingPathComponent("깊은 폴더", isDirectory: true)
            try? FileManager.default.createDirectory(
                at: thirdLevelURL,
                withIntermediateDirectories: true
            )
            try? "# Third Level QA\n".write(
                to: thirdLevelURL.appendingPathComponent("아주 긴 한국어 문서 이름과 English Document Name.md"),
                atomically: true,
                encoding: .utf8
            )
            try? FileManager.default.createDirectory(
                at: folderURL.appendingPathComponent("Empty Folder", isDirectory: true),
                withIntermediateDirectories: true
            )
            return FolderSelectionModel(
                selectedFolder: SelectedFolder(url: folderURL, bookmarkData: Data()),
                bookmarks: uiTestBookmarks
            )
        case "review":
            // Korean report with 결정 / 위험 / 할 일 sections: rule points for the 검토 card.
            let folderURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("KissmarkUITestReviewFolder", isDirectory: true)
            try? FileManager.default.removeItem(at: folderURL)
            try? FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
            try? """
            # 작업 보고서

            ## 결정

            검토 카드는 문서 정보 카드 아래에 둔다.

            ## 위험

            본문 강조가 일부 문장과 맞지 않을 수 있다.

            ## 할 일

            - [ ] 릴리스 노트 작성

            """.write(
                to: folderURL.appendingPathComponent("작업-보고서.md"),
                atomically: true,
                encoding: .utf8
            )
            return FolderSelectionModel(
                selectedFolder: SelectedFolder(url: folderURL, bookmarkData: Data()),
                bookmarks: uiTestBookmarks
            )
        case "tree-perf":
            // DEBUG perf fixture: 300 folders x 20 documents, for expand-latency
            // measurement (run with KISSMARK_TREE_PERF=1 in the environment).
            let folderURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("KissmarkTreePerfFolder", isDirectory: true)
            try? FileManager.default.removeItem(at: folderURL)
            try? FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
            for folderIndex in 0..<300 {
                let folder = folderURL.appendingPathComponent("폴더 \(String(format: "%03d", folderIndex))", isDirectory: true)
                try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                for documentIndex in 0..<20 {
                    try? "# 문서 \(folderIndex)-\(documentIndex)\n".write(
                        to: folder.appendingPathComponent("문서 \(String(format: "%03d", folderIndex))-\(String(format: "%02d", documentIndex)).md"),
                        atomically: true,
                        encoding: .utf8
                    )
                }
            }
            return FolderSelectionModel(
                selectedFolder: SelectedFolder(url: folderURL, bookmarkData: Data()),
                bookmarks: uiTestBookmarks
            )
        case "none", "reader-fixture", "editor-fixture":
            // Force a clean Folder-selection shell; never restore bookmarks under UI tests.
            return FolderSelectionModel(bookmarks: uiTestBookmarks)
        default:
            return FolderSelectionModel(bookmarks: uiTestBookmarks)
        }
    }

    private static func makeUITestFolder(named name: String) -> SelectedFolder {
        let folderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(name, isDirectory: true)
        try? FileManager.default.removeItem(at: folderURL)
        try? FileManager.default.createDirectory(
            at: folderURL,
            withIntermediateDirectories: true
        )
        return SelectedFolder(url: folderURL, bookmarkData: Data())
    }
    #endif
}

#Preview {
    AppRootView()
        .environment(KissmarkUpdateController())
        .environment(MirrorCoordinator())
}

/// Presents the one parent-Folder grant prompt a picked Document needs: a directory-only
/// `NSOpenPanel` fixed to the parent on macOS, a folder-only `fileImporter` with the
/// parent pre-selected on iOS. Never shown twice for the same pick; a cancelled prompt
/// leaves the Document open as a single-file workspace.
private struct FolderGrantPresenter: ViewModifier {
    let model: FolderSelectionModel

    func body(content: Content) -> some View {
        #if os(macOS)
        content.onChange(of: model.pendingGrant) { _, request in
            guard let request else { return }
            presentParentPanel(for: request)
        }
        #else
        content
            .onChange(of: model.pendingGrant) { _, request in
                presentedRequest = request
            }
            .fileImporter(
                isPresented: Binding(
                    get: { presentedRequest != nil },
                    set: { if !$0 { presentedRequest = nil } }
                ),
                allowedContentTypes: [.folder],
                allowsMultipleSelection: false,
                onCompletion: { model.handleGrant(FolderImportOutcome.map($0)) },
                onCancellation: { model.handleGrant(.cancelled) }
            )
            .fileDialogDefaultDirectory(presentedRequest?.directory)
            .fileDialogMessage("현재 문서가 들어 있는 폴더를 선택하세요. 다른 폴더를 탐색하려면 취소 후 폴더 메뉴의 ‘다른 폴더 열기’를 선택하세요.")
        #endif
    }

    #if os(macOS)
    private func presentParentPanel(for request: FolderGrantRequest) {
        let panel = NSOpenPanel()
        panel.directoryURL = request.directory
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.prompt = String.kissmarkLocalized("이 폴더 허용")
        panel.message = String.kissmarkLocalized("현재 문서가 들어 있는 폴더를 선택하세요. 다른 폴더를 탐색하려면 취소 후 폴더 메뉴의 ‘다른 폴더 열기’를 선택하세요.")
        panel.begin { response in
            Task { @MainActor in
                if response == .OK {
                    model.handleGrant(FolderImportOutcome.map(.success(panel.urls)))
                } else {
                    model.handleGrant(.cancelled)
                }
            }
        }
    }
    #else
    /// iOS keeps its own presentation state: dismissing the sheet must not clear the
    /// model's request before `onCompletion` reads it.
    @State private var presentedRequest: FolderGrantRequest?
    #endif
}
