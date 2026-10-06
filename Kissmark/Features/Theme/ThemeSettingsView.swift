import SwiftUI

/// Settings › 테마. Chooses the Appearance (시스템/라이트/다크), the Document palette,
/// and an accent color (ADR 0021).
struct ThemeSettingsView: View {
    @AppStorage(KissmarkAppearance.storageKey) private var appearanceID = KissmarkAppearance.system.rawValue
    @AppStorage(DocumentTheme.storageKey) private var themeID = DocumentTheme.system.rawValue
    @AppStorage(ThemeAccentOverrides.storageKey) private var accentJSON = ""
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The selection wash glides between theme rows through this namespace.
    @Namespace private var selectionNamespace

    private var theme: DocumentTheme { DocumentTheme(rawValue: themeID) ?? .system }
    /// The scheme Appearance resolves to; the window is already pinned to it, so `colorScheme` is the fallback for 시스템.
    private var scheme: ColorScheme {
        KissmarkAppearance.effectiveScheme(KissmarkAppearance(rawValue: appearanceID) ?? .system, systemScheme: colorScheme)
    }
    private var systemPalette: ThemePalette { DocumentThemeResolver.systemPalette(for: scheme) }
    private var palette: ThemePalette { DocumentThemeResolver.palette(theme: theme, scheme: scheme, system: systemPalette) }
    private var accentHex: String {
        ThemeAccentOverrides.decode(accentJSON).accent(for: theme, scheme: scheme) ?? palette.accent
    }

    /// The wash glides with the spring; under Reduce Motion the check still fades.
    private var selectionAnimation: Animation {
        KissmarkMotion.spring(reduceMotion: reduceMotion) ?? KissmarkMotion.snappy(reduceMotion: reduceMotion)
    }

    private var accentBinding: Binding<Color> {
        Binding(
            get: { Color(kissmarkHex: accentHex) ?? .accentColor },
            set: { setAccent($0.kissmarkHex) }
        )
    }

    private func setAccent(_ color: String?) {
        var accents = ThemeAccentOverrides.decode(accentJSON)
        accents.setAccent(color, for: theme, scheme: scheme)
        accentJSON = accents.encoded()
    }

    var body: some View {
        let accents = ThemeAccentOverrides.decode(accentJSON)
        Form {
            Section {
                Picker("화면 모드", selection: $appearanceID) {
                    ForEach(KissmarkAppearance.allCases) { appearance in
                        Text(appearance.displayName).tag(appearance.rawValue)
                    }
                }
                .accessibilityIdentifier("settings-appearance-picker")
            } header: {
                Text("화면 모드")
            } footer: {
                Text("화면 모드는 창과 문서 화면에 함께 적용됩니다.")
            }
            .kissmarkSettingsRowInsets()

            Section {
                let choices = DocumentTheme.choices(for: scheme)
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(choices) { candidate in
                        themeRow(candidate, accent: accents.accent(for: candidate, scheme: scheme))
                        if candidate != choices.last {
                            Divider()
                        }
                    }
                }
                // Wins over the window's slower palette crossfade for the rows themselves.
                .animation(selectionAnimation, value: themeID)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("settings-theme-picker")
            } header: {
                Text("화면 테마")
            } footer: {
                Text("선택한 테마는 문서와 창, 사이드바, 설정 창에 적용됩니다. 모든 테마가 위의 화면 모드에 맞춰 라이트와 다크 색상으로 바뀝니다.")
            }
            .kissmarkSettingsRowInsets()

            Section {
                LabeledContent("적용 대상") {
                    HStack(spacing: KissmarkMetrics.iconLabelGap) {
                        Text(theme.displayName(for: scheme))
                        Text(String.kissmarkLocalized(scheme == .dark ? "다크" : "라이트"))
                    }
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("settings-accent-scope")
                }
                HStack(spacing: KissmarkMetrics.iconLabelGap) {
                    Text("포인트 컬러")
                    Spacer()
                    ColorPicker("포인트 컬러", selection: accentBinding, supportsOpacity: false)
                        .labelsHidden()
                        .fixedSize()
                        .accessibilityIdentifier("settings-accent-color")
                        .accessibilityValue(Text(accentHex))
                    Button("테마 색으로") { setAccent(nil) }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("settings-accent-reset")
                }
            } header: {
                Text("포인트 컬러")
            } footer: {
                Text("현재 테마의 현재 화면 모드에만 저장합니다. 선택한 색을 그대로 사용하며 다른 테마와 다른 화면 모드의 색은 바꾸지 않습니다. 테마 색으로 되돌리면 이 설정만 초기화합니다.")
            }
            .kissmarkSettingsRowInsets()
        }
        .formStyle(.grouped)
        .kissmarkSettingsNavigationTitle("테마")
    }

    private func themeRow(_ candidate: DocumentTheme, accent: String?) -> some View {
        let selected = candidate.variant(for: scheme) == theme.variant(for: scheme)
        return Button {
            // Re-tapping the row that is already shown keeps the saved pick (e.g. a Catppuccin flavor).
            guard !selected else { return }
            withAnimation(selectionAnimation) {
                themeID = candidate.rawValue
            }
        } label: {
            HStack(spacing: KissmarkMetrics.iconLabelGap) {
                Text(candidate.displayName(for: scheme))
                    .foregroundStyle(.primary)
                Spacer(minLength: 0)
                ThemeSwatchRow(palette: candidate.palette(for: scheme) ?? systemPalette, accent: accent)
                // The hidden mark reserves the frame so rows never shift.
                ZStack {
                    checkmark.hidden()
                    if selected {
                        checkmarkEntering
                    }
                }
            }
            .padding(.vertical, KissmarkMetrics.settingsThemeRowVerticalInset)
            .background { selectionWash(selected) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(candidate.displayName(for: scheme)))
        .accessibilityValue(Text(selected ? "selected" : ""))
        .accessibilityIdentifier("settings-theme-\(candidate.rawValue)")
    }

    private var checkmark: some View {
        Image(systemName: "checkmark")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.tint)
    }

    /// SF Symbols 7 draws the mark on; earlier systems pop it in. Reduce Motion fades.
    @ViewBuilder
    private var checkmarkEntering: some View {
        if reduceMotion {
            checkmark.transition(.opacity)
        } else if #available(macOS 26, iOS 26, *) {
            checkmark.transition(.symbolEffect(.drawOn))
        } else {
            checkmark.transition(.scale(scale: KissmarkMotion.popScale).combined(with: .opacity))
        }
    }

    /// Only the selected row draws the wash. It extends into the row's inline inset
    /// so the text keeps its place. Under Reduce Motion it fades instead of gliding.
    @ViewBuilder
    private func selectionWash(_ selected: Bool) -> some View {
        if selected {
            let wash = RoundedRectangle(cornerRadius: KissmarkMetrics.treeSelectionRadius, style: .continuous)
                .fill(Color.accentColor.opacity(KissmarkMetrics.treeSelectionOpacity))
                .padding(.horizontal, -KissmarkMetrics.treeRowInlineInset)
            if reduceMotion {
                wash
            } else {
                wash.matchedGeometryEffect(id: ThemeSelectionWash.id, in: selectionNamespace)
            }
        }
    }
}

private enum ThemeSelectionWash {
    static let id = "settings-theme-selection-wash"
}

private struct ThemeSwatchRow: View {
    let palette: ThemePalette
    let accent: String?

    private var swatches: [String] {
        [palette.bg, palette.bgElevated, palette.text, accent ?? palette.accent, palette.border]
    }

    var body: some View {
        HStack(spacing: 3) {
            ForEach(Array(swatches.enumerated()), id: \.offset) { _, hex in
                Circle()
                    .fill(Color(kissmarkHex: hex) ?? .clear)
                    .frame(width: KissmarkMetrics.themeSwatchSize, height: KissmarkMetrics.themeSwatchSize)
                    .overlay {
                        Circle().strokeBorder(Color.primary.opacity(0.15), lineWidth: 0.5)
                    }
            }
        }
        .accessibilityHidden(true)
    }
}
