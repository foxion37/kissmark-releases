import SwiftUI

/// Settings › 디자인. Edits the text size and `DesignOverrides`; every change applies
/// to the open Document immediately.
struct DesignSettingsView: View {
    @AppStorage(DesignOverrides.storageKey) private var designJSON = ""
    @AppStorage(KissmarkTextSize.storageKey) private var textSizeID = KissmarkTextSize.medium.rawValue
    @AppStorage(KissmarkTextAlignment.storageKey) private var textAlignID = KissmarkTextAlignment.start.rawValue
    @AppStorage(KissmarkEnglishFont.storageKey) private var englishFontID = KissmarkEnglishFont.system.rawValue
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var editingScheme: ColorScheme = .light
    @State private var expandedElements: Set<DesignOverrides.ElementKey> = []

    private var overrides: DesignOverrides { DesignOverrides.decode(designJSON) }

    private func update(_ change: (inout DesignOverrides) -> Void) {
        var next = overrides
        change(&next)
        designJSON = next.encoded()
    }

    var body: some View {
        Form {
            Section {
                Picker("글자 크기", selection: $textSizeID) {
                    ForEach(KissmarkTextSize.allCases) { size in
                        Text(size.displayName).tag(size.rawValue)
                    }
                }
                .accessibilityIdentifier("settings-text-size-picker")
                Picker("정렬", selection: $textAlignID) {
                    ForEach(KissmarkTextAlignment.allCases) { alignment in
                        Text(alignment.displayName).tag(alignment.rawValue)
                    }
                }
                .accessibilityIdentifier("settings-design-alignment")
            } header: {
                KissmarkSettingsSectionHeader(title: "본문")
            } footer: {
                Text("글자 크기는 읽기와 편집 모두에 적용됩니다. 정렬은 문서 전체에 적용되고, 어절 단위로 줄이 바뀝니다.")
            }
            .kissmarkSettingsRowInsets()

            Section {
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
                KissmarkSettingsSectionHeader(title: "글꼴")
            } footer: {
                Text("한글은 Pretendard, 코드는 Jetendard로 표시됩니다. 영문 글꼴 선택은 앱을 다시 열면 적용됩니다.")
            }
            .kissmarkSettingsRowInsets()

            Section {
                ForEach(DesignOverrides.SpacingField.allCases) { field in spacingRow(field) }
                Button("간격 기본값으로") {
                    withAnimation(KissmarkMotion.spring(reduceMotion: reduceMotion)) {
                        update { $0.spacing = .init() }
                    }
                }
                    .accessibilityIdentifier("settings-design-spacing-reset")
                    .disabled(overrides.spacing == .init())
            } header: {
                KissmarkSettingsSectionHeader(title: "간격")
            } footer: {
                Text("바를 움직여 일정한 단위로 조절합니다. 다섯 표시는 참고 체크포인트이며 그 사이 값도 선택할 수 있습니다. 행간은 배수, 장폭은 ch, 나머지는 em입니다.")
            }
            .kissmarkSettingsRowInsets()

            Section {
                Picker("색상 편집 대상", selection: $editingScheme) {
                    Text("라이트").tag(ColorScheme.light)
                    Text("다크").tag(ColorScheme.dark)
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("settings-design-scheme")

                ForEach(DesignOverrides.ElementKey.allCases) { key in
                    DisclosureGroup(key.displayName, isExpanded: expansionBinding(key)) { elementControls(key) }
                }
            } header: {
                KissmarkSettingsSectionHeader(title: "요소")
            } footer: {
                Text("색은 라이트와 다크에 따로 저장됩니다.")
            }
            .kissmarkSettingsRowInsets()

            Section {
                Button("모두 초기화", role: .destructive) {
                    withAnimation(KissmarkMotion.spring(reduceMotion: reduceMotion)) { designJSON = "" }
                }
                    .accessibilityIdentifier("settings-design-reset-all")
                    .disabled(overrides.isEmpty)
            }
        }
        .formStyle(.grouped)
        .kissmarkSettingsNavigationTitle("디자인")
        .onAppear { editingScheme = colorScheme }
    }

    /// Element accordions open and close with the shared spring.
    private func expansionBinding(_ key: DesignOverrides.ElementKey) -> Binding<Bool> {
        Binding(
            get: { expandedElements.contains(key) },
            set: { isExpanded in
                withAnimation(KissmarkMotion.spring(reduceMotion: reduceMotion)) {
                    if isExpanded {
                        expandedElements.insert(key)
                    } else {
                        expandedElements.remove(key)
                    }
                }
            }
        )
    }

    /// One compact row: name left, actual value right, then a full-width numeric slider.
    private func spacingRow(_ field: DesignOverrides.SpacingField) -> some View {
        let spacing = overrides.spacing
        let value = field.effectiveValue(in: spacing)
        let checkpoints = field.checkpoints
        let title = String.kissmarkLocalized(field.title)
        return VStack(alignment: .leading, spacing: KissmarkMetrics.settingsSliderRowGap) {
            HStack {
                Text(title)
                Spacer()
                Text(field.display(value))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("\(spacingID(field))-value")
            }
            SettingsSpacingSlider(
                value: Binding(
                    get: { field.effectiveValue(in: overrides.spacing) },
                    set: { next in update { field.set(value: next, in: &$0.spacing) } }
                ),
                step: field.step,
                checkpoints: checkpoints,
                label: title
            )
            .frame(maxWidth: .infinity)
            .accessibilityIdentifier(spacingID(field))
            .accessibilityLabel(title)
            .accessibilityValue(field.display(value))
            GeometryReader { geometry in
                let inset = KissmarkMetrics.settingsSliderTrackInset
                let width = max(0, geometry.size.width - inset * 2)
                let labelWidth = min(KissmarkMetrics.settingsSliderLegendLabelWidth, geometry.size.width / 10)
                ForEach(checkpoints.indices, id: \.self) { index in
                    let x = inset + width * CGFloat(Double(index) / 4)
                    Text(String.kissmarkLocalized(DesignOverrides.SpacingField.checkpointNames[index]))
                        .font(KissmarkType.font(.caption2))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(width: labelWidth)
                        .position(
                            x: min(max(x, labelWidth / 2), geometry.size.width - labelWidth / 2),
                            y: geometry.size.height / 2 - KissmarkMetrics.settingsSliderLegendLift
                        )
                }
            }
            .frame(height: KissmarkMetrics.settingsSliderLegendHeight)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }


    private func spacingID(_ field: DesignOverrides.SpacingField) -> String {
        switch field {
        case .lineHeight: "settings-design-line-height"
        case .letterSpacing: "settings-design-letter-spacing"
        case .codeLetterSpacing: "settings-design-code-letter-spacing"
        case .measure: "settings-design-measure"
        case .paragraphSpacing: "settings-design-paragraph-spacing"
        case .indent: "settings-design-indent"
        }
    }

    /// Slider plus its value ("자동" while the model holds `nil`), for the per-element
    /// 크기 row.
    @ViewBuilder
    private func valueSlider(
        _ title: LocalizedStringKey,
        id: String,
        value: Double?,
        fallback: Double,
        range: ClosedRange<Double>,
        step: Double,
        display: @escaping (Double) -> String,
        set: @escaping (Double) -> Void
    ) -> some View {
        LabeledContent(title) {
            HStack {
                Slider(
                    value: Binding(get: { value ?? fallback }, set: set),
                    in: range,
                    step: step
                )
                .accessibilityIdentifier(id)
                // The number rolls as it changes; "자동" and a number crossfade.
                ZStack(alignment: .trailing) {
                    if let value {
                        Text(display(value))
                            .contentTransition(reduceMotion ? .opacity : .numericText(value: value))
                            .transition(.opacity)
                    } else {
                        Text("자동")
                            .transition(.opacity)
                    }
                }
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .animation(KissmarkMotion.snappy(reduceMotion: reduceMotion), value: value)
            }
        }
    }

    @ViewBuilder
    private func elementControls(_ key: DesignOverrides.ElementKey) -> some View {
        let element = overrides[element: key]
        if key.supportsSize {
            valueSlider(
                "크기",
                id: "settings-design-\(key.cssName)-size",
                value: element.sizeScale,
                fallback: DesignOverrides.displayDefaultSizeScale,
                range: DesignOverrides.sizeScaleRange,
                step: DesignOverrides.sizeScaleStep,
                display: { "×\($0.formatted(.number.precision(.fractionLength(0...2))))" },
                set: { newValue in update { $0[element: key].sizeScale = newValue } }
            )
        }
        if key.supportsWeight {
            Picker(
                "굵기",
                selection: Binding(
                    get: { element.weight.flatMap { DesignOverrides.weights.contains($0) ? $0 : nil } ?? 0 },
                    set: { w in update { $0[element: key].weight = w == 0 ? nil : w } }
                )
            ) {
                Text("자동").tag(0)
                ForEach(DesignOverrides.weights, id: \.self) { Text(String($0)).tag($0) }
            }
            .accessibilityIdentifier("settings-design-\(key.cssName)-weight")
        }
        ColorPicker(
            "색",
            selection: Binding(
                get: { Color(kissmarkHex: editingScheme == .dark ? element.color?.dark : element.color?.light) ?? key.placeholderColor },
                set: { color in
                    let hex = color.kissmarkHex
                    update {
                        var pair = $0[element: key].color ?? .init()
                        if editingScheme == .dark { pair.dark = hex } else { pair.light = hex }
                        $0[element: key].color = pair
                    }
                }
            ),
            supportsOpacity: false
        )
        .accessibilityIdentifier("settings-design-\(key.cssName)-color")
        Button("기본값으로") {
            withAnimation(KissmarkMotion.spring(reduceMotion: reduceMotion)) {
                update { $0[element: key] = .init() }
            }
        }
            .accessibilityIdentifier("settings-design-\(key.cssName)-reset")
            .disabled(element == .init())
    }
}

private extension DesignOverrides.ElementKey {
    /// Shown in the picker while no color override exists; not written anywhere.
    var placeholderColor: Color {
        switch self {
        case .link: .accentColor
        case .blockquote, .h5, .h6, .rule: .secondary
        default: .primary
        }
    }
}

extension Color {
    init?(kissmarkHex hex: String?) {
        guard let hex, DesignOverrides.isHexColor(hex), let value = UInt32(hex.dropFirst(), radix: 16) else { return nil }
        self.init(
            .sRGB,
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }

    var kissmarkHex: String {
        let resolved = resolve(in: EnvironmentValues())
        func byte(_ c: Float) -> Int { Int((min(max(c, 0), 1) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", byte(resolved.red), byte(resolved.green), byte(resolved.blue))
    }
}
