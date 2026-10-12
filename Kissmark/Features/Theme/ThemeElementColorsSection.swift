import SwiftUI

/// Settings › 테마 › 요소 색. Element color overrides remain in the stable
/// DesignOverrides store so they survive version changes while the UI ownership moves.
struct ThemeElementColorsSection: View {
    let initialScheme: ColorScheme
    @AppStorage(DesignOverrides.storageKey) private var designJSON = ""
    @State private var editingScheme: ColorScheme?

    private var overrides: DesignOverrides { DesignOverrides.decode(designJSON) }
    private var target: ColorScheme { editingScheme ?? initialScheme }

    private func setColor(_ hex: String?, for key: DesignOverrides.ElementKey) {
        var next = overrides
        var pair = next[element: key].color ?? .init()
        if target == .dark { pair.dark = hex } else { pair.light = hex }
        next[element: key].color = pair.light == nil && pair.dark == nil ? nil : pair
        designJSON = next.encoded()
    }

    var body: some View {
        Section {
            Picker("색상 편집 대상", selection: Binding(get: { target }, set: { editingScheme = $0 })) {
                Text("라이트").tag(ColorScheme.light)
                Text("다크").tag(ColorScheme.dark)
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("settings-theme-element-scheme")
            ForEach(DesignOverrides.ElementKey.allCases) { key in
                let color = overrides[element: key].color
                let hex = target == .dark ? color?.dark : color?.light
                HStack(spacing: KissmarkMetrics.iconLabelGap) {
                    Text(key.displayName)
                    Spacer()
                    ColorPicker(key.displayName, selection: Binding(
                        get: { Color(kissmarkHex: hex) ?? key.placeholderColor },
                        set: { setColor($0.kissmarkHex, for: key) }
                    ), supportsOpacity: false)
                    .labelsHidden()
                    .fixedSize()
                    .accessibilityIdentifier("settings-theme-\(key.cssName)-color")
                    Button("테마 색으로") { setColor(nil, for: key) }
                        .buttonStyle(.bordered)
                        .disabled(hex == nil)
                        .accessibilityIdentifier("settings-theme-\(key.cssName)-color-reset")
                }
            }
        } header: {
            KissmarkSettingsSectionHeader(title: "요소 색")
        } footer: {
            Text("라이트와 다크에 따로 저장하며 모든 테마에 공통으로 적용됩니다. 테마 색으로 되돌리면 선택한 화면 모드의 그 요소 색만 초기화합니다.")
        }
        .kissmarkSettingsRowInsets()
    }
}

private extension DesignOverrides.ElementKey {
    var placeholderColor: Color {
        switch self {
        case .link: .accentColor
        case .blockquote, .h5, .h6, .rule: .secondary
        default: .primary
        }
    }
}
