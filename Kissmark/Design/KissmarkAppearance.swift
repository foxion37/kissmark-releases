import SwiftUI
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
import Combine
#endif

/// App + Document appearance. One control drives window chrome and the Flexoki
/// Document surface (ADR 0009).
enum KissmarkAppearance: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    static let storageKey = "kissmark.appearance"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: return String.kissmarkLocalized("시스템")
        case .light: return String.kissmarkLocalized("라이트")
        case .dark: return String.kissmarkLocalized("다크")
        }
    }

    /// `nil` follows the OS appearance.
    var preferredColorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    /// The scheme a window is pinned to for the 모양 setting. On macOS 시스템
    /// resolves to the live system scheme: `.preferredColorScheme(nil)` stops
    /// following the system once a window has been pinned to an explicit scheme,
    /// so the system's own scheme is applied instead and re-applied on every
    /// system switch. On iOS `nil` keeps following the system.
    static func pinnedScheme(
        _ appearance: KissmarkAppearance,
        systemScheme: ColorScheme? = nil
    ) -> ColorScheme? {
        switch appearance {
        case .light: return .light
        case .dark: return .dark
        case .system:
            #if os(macOS)
            return systemScheme ?? KissmarkSystemAppearanceObserver.shared.systemScheme
            #else
            return nil
            #endif
        }
    }

    /// The scheme the UI actually shows: an explicit 라이트/다크 wins; 시스템 uses
    /// `systemScheme`. Themes adapt to this, never the other way round.
    static func effectiveScheme(_ appearance: KissmarkAppearance, systemScheme: ColorScheme) -> ColorScheme {
        appearance.preferredColorScheme ?? systemScheme
    }
}

#if os(macOS)
/// The system's current Light/Dark scheme, kept live by observing
/// `NSApp.effectiveAppearance` (app-level: a window's `preferredColorScheme`
/// pin never touches it, so the observation cannot feed back into itself).
@MainActor
final class KissmarkSystemAppearanceObserver: ObservableObject {
    static let shared = KissmarkSystemAppearanceObserver()

    @Published private(set) var systemScheme: ColorScheme

    private var observation: NSKeyValueObservation?

    private init() {
        systemScheme = Self.scheme(of: NSApplication.shared.effectiveAppearance)
        observation = NSApplication.shared.observe(\.effectiveAppearance) { app, _ in
            let scheme = Self.scheme(of: app.effectiveAppearance)
            DispatchQueue.main.async {
                MainActor.assumeIsolated { Self.shared.systemScheme = scheme }
            }
        }
    }

    private nonisolated static func scheme(of appearance: NSAppearance) -> ColorScheme {
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? .dark : .light
    }
}
#endif

/// Notes-style body text size for the Document surface.
enum KissmarkTextSize: String, CaseIterable, Identifiable {
    case xSmall
    case small
    case medium
    case large
    case xLarge

    static let storageKey = "kissmark.textSize"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .xSmall: return String.kissmarkLocalized("아주 작게")
        case .small: return String.kissmarkLocalized("작게")
        case .medium: return String.kissmarkLocalized("중간 (기본)")
        case .large: return String.kissmarkLocalized("크게")
        case .xLarge: return String.kissmarkLocalized("아주 크게")
        }
    }

    /// Multiplier applied to the root rem (`html` font-size) in reader.css;
    /// `--km-font-size` and the derived heading tokens follow it.
    var scale: Double {
        switch self {
        case .xSmall: return 13.0 / 18.0
        case .small: return 15.0 / 18.0
        case .medium: return 1.0
        case .large: return 21.0 / 18.0
        case .xLarge: return 24.0 / 18.0
        }
    }
}

/// Document paragraph alignment (`--km-text-align` in reader.css).
enum KissmarkTextAlignment: String, CaseIterable, Identifiable {
    case start
    case justify

    static let storageKey = "kissmark.textAlign"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .start: return String.kissmarkLocalized("좌측 정렬")
        case .justify: return String.kissmarkLocalized("양끝 맞춤")
        }
    }

    /// The CSS `text-align` value the surface pushes as `--km-text-align`.
    var cssValue: String { rawValue }
}

/// 텍스트 정리 (Text Lint) toggle. When off, the 편집 메뉴 command no-ops (ADR 0025).
enum KissmarkTextLint {
    static let storageKey = "kissmark.textLint"
}

/// Shared settings section header used by the Typography and Theme panes.
struct KissmarkSettingsSectionHeader: View {
    let title: LocalizedStringKey
    @Environment(\.chromePalette) private var chromePalette

    var body: some View {
        Text(title)
            .font(KissmarkType.font(.caption, weight: .semibold))
            .foregroundStyle(chromePalette?.chromePrimary ?? Color.primary)
            .textCase(nil)
    }
}

#if os(macOS)
extension View {
    @ViewBuilder
    func kissmarkSettingsNavigationTitle(_ title: LocalizedStringKey) -> some View {
        self
    }

    func kissmarkSettingsRowInsets() -> some View {
        listRowInsets(KissmarkMetrics.settingsRowInsets)
    }
}
#else
extension View {
    @ViewBuilder
    func kissmarkSettingsNavigationTitle(_ title: LocalizedStringKey) -> some View {
        navigationTitle(title)
    }

    func kissmarkSettingsRowInsets() -> some View {
        listRowInsets(KissmarkMetrics.settingsRowInsets)
    }
}
#endif

nonisolated enum SettingsSection: Int, CaseIterable, Identifiable {
    case general, typography, theme, connections, shortcuts, mirror

    var id: Int { rawValue }
    var title: LocalizedStringKey {
        switch self {
        case .general: "일반"
        case .typography: "타이포그래피"
        case .theme: "테마"
        case .connections: "연결"
        case .shortcuts: "단축키"
        case .mirror: "미러"
        }
    }
}

/// Settings root. macOS has resizable tabs, including local agent connections.
/// iOS uses navigation rows for the shared sections (ADR 0021).
///
/// On macOS Settings is its own `Window` scene, outside `AppRootView`, so it
/// resolves the theme itself. The 화면 모드 (Appearance) always decides the scheme;
/// the selected theme adapts its palette to it, and every tab's Form background,
/// text, and accent follow. 시스템 keeps the native Settings look. iOS inherits
/// all of it from the presenter.
struct KissmarkSettingsView: View {
    #if os(macOS)
    @Environment(\.dismiss) private var dismiss
    @State private var selection = SettingsSection.general
    @AppStorage(KissmarkAppearance.storageKey) private var appearanceID = KissmarkAppearance.system.rawValue
    @AppStorage(DocumentTheme.storageKey) private var themeID = DocumentTheme.system.rawValue
    @AppStorage(ThemeAccentOverrides.storageKey) private var accentJSON = ""
    @ObservedObject private var systemAppearance = KissmarkSystemAppearanceObserver.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var theme: DocumentTheme { DocumentTheme(rawValue: themeID) ?? .system }
    private var accentHex: String {
        ThemeAccentOverrides.decode(accentJSON).accent(for: theme, scheme: scheme) ?? ""
    }

    /// 모양 = 시스템 resolves to the live system scheme; the observer keeps it current.
    private var appearanceScheme: ColorScheme? {
        KissmarkAppearance.pinnedScheme(
            KissmarkAppearance(rawValue: appearanceID) ?? .system,
            systemScheme: systemAppearance.systemScheme
        )
    }

    /// Same resolution as `AppRootView`: the theme accent or the user's override;
    /// `nil` keeps the system accent.
    private var themeAccent: Color? {
        DocumentThemeResolver.chromeAccentHex(theme: theme, scheme: scheme, override: accentHex)
            .flatMap { Color(kissmarkHex: $0) }
    }

    private var scheme: ColorScheme {
        KissmarkAppearance.effectiveScheme(
            KissmarkAppearance(rawValue: appearanceID) ?? .system,
            systemScheme: systemAppearance.systemScheme
        )
    }

    private var palette: ThemePalette? { theme.palette(for: scheme) }
    #endif

    var body: some View {
        #if os(macOS)
        VStack(spacing: 0) {
            settingsHeader
            Divider().kissmarkChromeDivider(palette)
            Group {
                switch selection {
                case .general: themedPane(KissmarkGeneralSettingsView())
                case .typography: themedPane(DesignSettingsView())
                case .theme: themedPane(ThemeSettingsView())
                case .connections: themedPane(AgentConnectionsSettingsView())
                case .shortcuts: themedPane(ShortcutsSettingsView())
                case .mirror: themedPane(MirrorSettingsView())
                }
            }
            .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .top)
            .background(palette?.chromeBackground ?? .clear)
        }
        .frame(
            minWidth: KissmarkMetrics.settingsMinimumSize.width,
            idealWidth: KissmarkMetrics.settingsDefaultSize.width,
            maxWidth: .infinity,
            minHeight: KissmarkMetrics.settingsMinimumSize.height,
            idealHeight: KissmarkMetrics.settingsDefaultSize.height,
            maxHeight: .infinity
        )
        .background(palette?.chromeBackground ?? .clear)
        .preferredColorScheme(appearanceScheme)
        .tint(themeAccent)
        .environment(\.chromePalette, palette)
        .environment(\.locale, KissmarkLocalization.locale)
        .font(KissmarkType.font(.body))
        .background(KissmarkSettingsWindowConfigurator())
        .onAppear {
            if !AppLaunchRoute.isUITestGate(),
               ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil,
               NSClassFromString("XCTestCase") == nil {
                ThemeAccentOverrides.migrateLegacy(in: .standard, theme: theme, scheme: scheme)
            }
        }
        .animation(KissmarkMotion.theme(reduceMotion: reduceMotion), value: themeID)
        .animation(KissmarkMotion.theme(reduceMotion: reduceMotion), value: accentHex)
        .animation(KissmarkMotion.theme(reduceMotion: reduceMotion), value: appearanceID)
        #else
        KissmarkGeneralSettingsView()
        #endif
    }

    #if os(macOS)
    private var settingsHeader: some View {
        HStack(spacing: KissmarkMetrics.settingsRowGap) {
            HStack(spacing: KissmarkMetrics.settingsHeaderInset) {
                ForEach(SettingsSection.allCases) { section in
                    headerLabel(section)
                }
            }
            .padding(KissmarkMetrics.settingsHeaderInset)
            .overlay {
                Capsule().strokeBorder(
                    Color.secondary.opacity(KissmarkMetrics.iconButtonOutlineOpacity),
                    lineWidth: KissmarkMetrics.iconButtonOutlineWidth
                )
            }
            Spacer(minLength: KissmarkMetrics.settingsHeaderLabelPad)
            KissmarkIconButton(
                title: "닫기",
                lucide: .x,
                accessibilityIdentifier: "settings-header-close",
                action: dismiss.callAsFunction
            )
        }
        .padding(.vertical, KissmarkMetrics.settingsHeaderVerticalPad)
        .padding(.horizontal, KissmarkMetrics.settingsHeaderBlockPad)
    }

    private func headerLabel(_ section: SettingsSection) -> some View {
        Button {
            guard selection != section else { return }
            withAnimation(KissmarkMotion.spring(reduceMotion: reduceMotion)) {
                selection = section
            }
        } label: {
            Text(section.title)
                .font(KissmarkType.font(.body))
                .foregroundStyle(selection == section ? (palette?.chromePrimary ?? .primary) : (palette?.chromeMuted ?? .secondary))
                .padding(.horizontal, KissmarkMetrics.settingsHeaderLabelPad)
                .frame(maxHeight: .infinity)
                .background {
                    if selection == section {
                        Capsule().kissmarkGlass(in: Capsule())
                        Capsule().fill((palette?.chromePrimary ?? .primary).opacity(KissmarkMetrics.treeSelectionOpacity / 2))
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(height: KissmarkMetrics.toolbarButtonSize)
        .accessibilityAddTraits(selection == section ? [.isSelected] : [])
        .accessibilityIdentifier("settings-section-\(String(describing: section).lowercased())")
    }

    private func themedPane<Content: View>(_ content: Content) -> some View {
        content
            .scrollContentBackground(palette == nil ? .automatic : .hidden)
            .foregroundStyle(palette.map { AnyShapeStyle($0.chromePrimary) } ?? AnyShapeStyle(.primary))
            .frame(maxWidth: KissmarkMetrics.settingsContentMaxWidth)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(palette?.chromeBackground ?? .clear)
    }
    #endif
}

/// Settings › 일반. Folder paths, app/update state, and the 텍스트 정리 toggle.
/// 글자 크기·정렬 live in the 디자인 tab; 화면 모드 lives in 테마.
struct KissmarkGeneralSettingsView: View {
    @AppStorage(KissmarkTextLint.storageKey) private var isTextLintEnabled = true
    @State private var language = KissmarkLanguage.preference(in: .standard, domain: Bundle.main.bundleIdentifier ?? "")
    @AppStorage(KissmarkEnglishFont.storageKey) private var englishFontID = KissmarkEnglishFont.system.rawValue
    @State private var inboxPath: String = ""
    @State private var archivePath: String = ""
    @State private var folderToConfigure: FolderBookmarkKind?
    @Environment(KissmarkUpdateController.self) private var updateController
    @Environment(\.openURL) private var openURL
    private let store = FolderBookmarks()

    var body: some View {
        @Bindable var updates = updateController
        Form {
            Section {
                Picker("앱 언어", selection: $language) {
                    ForEach(KissmarkLanguage.allCases) { language in
                        Text(language.displayName).tag(language)
                    }
                }
                .accessibilityIdentifier("settings-language")
                Picker("영문 글꼴", selection: $englishFontID) {
                    ForEach(KissmarkEnglishFont.allCases) { font in
                        Text(font.displayName).tag(font.rawValue)
                    }
                }
                .accessibilityIdentifier("settings-english-font")
                if KissmarkLocalization.languageCode == "en", KissmarkEnglishFont.active == .inter,
                   !KissmarkType.interAvailable {
                    Text("Inter 글꼴을 불러오지 못해 OS 기본 글꼴을 사용합니다.")
                        .font(KissmarkType.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("언어")
            } footer: {
                Text("선택한 언어와 영문 글꼴은 앱을 다시 열면 적용됩니다.")
            }
            #if os(iOS)
            Section {
                NavigationLink("타이포그래피") { DesignSettingsView() }
                    .accessibilityIdentifier("settings-typography-link")
                NavigationLink("테마") { ThemeSettingsView() }
                    .accessibilityIdentifier("settings-theme-link")
                NavigationLink("단축키") { ShortcutsSettingsView() }
                    .accessibilityIdentifier("settings-shortcuts-link")
            }
            #endif

            Section {
                Toggle("텍스트 정리", isOn: $isTextLintEnabled)
                    .accessibilityIdentifier("settings-text-lint-toggle")
            } header: {
                Text("텍스트 정리")
            } footer: {
                Text("편집 메뉴의 텍스트 정리(⌘⇧L)가 본문의 em 대시와 인 대시를 하이픈으로, 가운뎃점을 쉼표로 바꿉니다. 코드 블록과 인라인 코드는 건드리지 않고, 편집 모드에서만 동작하며 실행 취소(⌘Z)할 수 있습니다. 끄면 명령이 동작하지 않습니다.")
            }

            Section {
                pathRow(
                    title: "받은 편지함",
                    path: inboxPath,
                    empty: String.kissmarkLocalized("아직 없음"),
                    accessibilityID: "settings-inbox-path"
                ) {
                    folderToConfigure = .inbox
                }
                pathRow(
                    title: "보관 폴더",
                    path: archivePath,
                    empty: String.kissmarkLocalized("아직 없음. Obsidian 폴더를 고르세요"),
                    accessibilityID: "settings-archive-path"
                ) {
                    folderToConfigure = .archive
                }
                #if os(iOS)
                NavigationLink("미러") { MirrorSettingsView() }
                    .accessibilityIdentifier("settings-mirror-link")
                #endif
            } header: {
                Text("폴더")
            } footer: {
                Text("기본 Folder는 iCloud Kissmark입니다. 보관은 문서를 보관 폴더로 복사하고 원본은 남깁니다.")
            }
            #if os(macOS)
            MarkdownDefaultAppSettings()
            #endif
            Section {
                LabeledContent("버전") {
                    Text(KissmarkAppVersion.display)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("settings-app-version")
                }
                Toggle("업데이트 확인", isOn: $updates.isEnabled)
                    .accessibilityIdentifier("settings-updates-enabled")
                if let message = updateController.errorMessage {
                    Text(message)
                        .font(KissmarkType.caption)
                        .foregroundStyle(.secondary)
                } else if updateController.check?.isUpdateAvailable == true {
                    Text("새 버전 \(updateController.check?.latest?.marketingVersion ?? "")")
                        .font(KissmarkType.caption)
                        .foregroundStyle(.secondary)
                }
                Button(String.kissmarkLocalized(updateController.check?.isUpdateAvailable == true ? "업데이트" : "업데이트 확인")) {
                    if updateController.check?.isUpdateAvailable == true,
                       let url = updateController.check?.latest?.htmlURL {
                        openURL(url)
                    } else {
                        Task { await updateController.refresh() }
                    }
                }
                .disabled(updateController.isChecking || !updateController.isEnabled)
                .accessibilityIdentifier("settings-check-updates")
            } header: {
                Text("앱")
            } footer: {
                Text("Mac과 iPhone은 같은 GitHub 배포를 확인합니다. iPhone 앱 스토어 배포 전에는 저장소 릴리스로 업데이트합니다.")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("설정")
        .onAppear { reloadPaths() }
        .onChange(of: language) { _, selected in selected.store(in: .standard) }
        .fileImporter(
            isPresented: Binding(
                get: { folderToConfigure != nil },
                set: { if !$0 { folderToConfigure = nil } }
            ),
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            guard case .success(let urls) = result,
                  urls.count == 1,
                  let kind = folderToConfigure,
                  let selected = try? SelectedFolder.make(fromPicked: urls[0]) else {
                folderToConfigure = nil
                return
            }
            store.save(selected, as: kind)
            folderToConfigure = nil
            reloadPaths()
        }
    }

    @ViewBuilder
    private func pathRow(
        title: LocalizedStringKey,
        path: String,
        empty: String,
        accessibilityID: String,
        choose: @escaping () -> Void
    ) -> some View {
        LabeledContent(title) {
            HStack(spacing: 12) {
                Text(path.isEmpty ? empty : path)
                    .font(KissmarkType.font(.caption))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .frame(maxWidth: 220, alignment: .trailing)
                    .textSelection(.enabled)
                    .accessibilityIdentifier(accessibilityID)
                Button("선택…", action: choose)
                    .buttonStyle(.bordered)
            }
        }
    }

    private func reloadPaths() {
        inboxPath = (try? store.load(.inbox))?.url.path
            ?? KissmarkCloudFolder.live.inboxURL?.path
            ?? ""
        archivePath = (try? store.load(.archive))?.url.path ?? ""
    }
}

