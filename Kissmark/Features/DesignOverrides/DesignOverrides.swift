import SwiftUI

/// User Design Overrides for the Document surface. `nil` everywhere = reader.css defaults.
/// The only mapping to CSS lives in `cssVariables(for:)`.
///
/// New stored properties must be decoded with `decodeIfPresent` in `init(from:)`;
/// a default value alone does not make a stored key optional, and the surface clears
/// `storageKey` when the stored JSON fails to decode — so a `decode` for a key an
/// older value does not carry would wipe the user's overrides instead of ignoring it.
///
/// `nonisolated` so the plain-value model can be built and read from the
/// representable (and tests) without hopping to the main actor.
nonisolated struct DesignOverrides: Codable, Equatable {
    struct Spacing: Codable, Equatable {
        var lineHeight: Double?
        var letterSpacingEm: Double?
        /// Code tracking, its own channel: it never follows the body 자간
        /// (`letterSpacingEm`); `nil` means the 0 baseline.
        var codeLetterSpacingEm: Double?
        var measureCh: Double?
        var paragraphSpacingEm: Double?
        var indentEm: Double?
        /// Settings › 코드: code block line height (ratio) and measure (`ch`;
        /// `nil` = the text column).
        var codeLineHeight: Double?
        var codeMeasureCh: Double?
    }

    /// Settings › 코드 choices that are not sliders. `nil` = shipped default
    /// (bundled Jetendard; long lines wrap).
    struct Code: Codable, Equatable {
        /// Font family name of an installed font; it leads the mono stack.
        var fontFamily: String?
        var wrapsLines: Bool?
    }

    struct SchemeColor: Codable, Equatable {
        var light: String?
        var dark: String?
    }

    struct Element: Codable, Equatable {
        var sizeScale: Double?
        var weight: Int?
        var color: SchemeColor?
    }

    enum ElementKey: String, CaseIterable, Codable, Identifiable {
        case body, h1, h2, h3, h4, h5, h6, codeBlock, inlineCode, blockquote, table, link, rule

        var id: String { rawValue }

        var cssName: String {
            switch self {
            case .codeBlock: "code-block"
            case .inlineCode: "inline-code"
            default: rawValue
            }
        }

        var supportsSize: Bool { ![.link, .rule].contains(self) }
        var supportsWeight: Bool { [.body, .h1, .h2, .h3, .h4, .h5, .h6, .link].contains(self) }

        var displayName: LocalizedStringKey {
            switch self {
            case .body: "본문"
            case .h1: "제목 1"
            case .h2: "제목 2"
            case .h3: "제목 3"
            case .h4: "제목 4"
            case .h5: "제목 5"
            case .h6: "제목 6"
            case .codeBlock: "코드 블록"
            case .inlineCode: "인라인 코드"
            case .blockquote: "인용"
            case .table: "표"
            case .link: "링크"
            case .rule: "구분선"
            }
        }
    }

    static let storageKey = "kissmark.design-overrides"
    static let lineHeightRange: ClosedRange<Double> = 1.2...2.2
    static let letterSpacingRange: ClosedRange<Double> = -0.05...0.05
    /// Code tracking shares the body's range; it is a separate stored value.
    static let codeLetterSpacingRange: ClosedRange<Double> = -0.05...0.05
    static let codeLineHeightRange: ClosedRange<Double> = 1.2...2.2
    static let codeMeasureRange: ClosedRange<Double> = 40...120
    /// The shipped mono stack (reader.css `--km-font-mono`) a chosen family falls back to.
    static let monoFallbackStack = "\"Jetendard\", ui-monospace, SFMono-Regular, Menlo, Consolas, monospace"
    static let measureRange: ClosedRange<Double> = 40...120
    static let paragraphSpacingRange: ClosedRange<Double> = 0...2
    static let indentRange: ClosedRange<Double> = 0.5...2.0
    static let sizeScaleRange: ClosedRange<Double> = 0.7...2.0
    static let sizeScaleStep = 0.05
    static let weights = [300, 400, 500, 550, 600, 700]

    /// Slider position shown while a per-element size is "자동" (`nil`); display only,
    /// the model stays `nil` until the user moves the control.
    static let displayDefaultSizeScale = 1.0

    /// Numeric sliders use a regular step. Five named checkpoints are reference marks,
    /// not the only allowed values. Opening Settings never rewrites an existing value.
    nonisolated enum SpacingField: String, CaseIterable, Identifiable {
        case lineHeight, letterSpacing, codeLetterSpacing, measure, paragraphSpacing, indent, codeLineHeight, codeMeasure

        /// 디자인 › 간격 rows and 코드 rows; each tab resets only its own.
        static let body: [Self] = [.lineHeight, .letterSpacing, .measure, .paragraphSpacing, .indent]
        static let code: [Self] = [.codeLineHeight, .codeLetterSpacing, .codeMeasure]

        var id: String { rawValue }

        static let checkpointNames: [String.LocalizationValue] = ["매우 좁게", "좁게", "기본", "넓게", "매우 넓게"]

        var title: String.LocalizationValue {
            switch self {
            case .lineHeight, .codeLineHeight: "행간"
            case .letterSpacing, .codeLetterSpacing: "자간"
            case .measure, .codeMeasure: "장폭"
            case .paragraphSpacing: "문단 간격"
            case .indent: "들여쓰기"
            }
        }

        /// Line height is a unitless ratio; the measure is in `ch`; the rest are `em`.
        var unit: String {
            switch self {
            case .lineHeight, .codeLineHeight: ""
            case .measure, .codeMeasure: "ch"
            default: "em"
            }
        }

        /// All reference marks are reachable on the numeric grid; 기본 is the CSS baseline.
        var checkpoints: [Double] {
            switch self {
            case .lineHeight: [1.2, 1.4, 1.7, 2, 2.2]
            case .codeLineHeight: [1.2, 1.4, 1.55, 1.8, 2.2]
            case .letterSpacing, .codeLetterSpacing: [-0.05, -0.02, 0, 0.02, 0.05]
            case .measure: [40, 50, 66, 90, 120]
            case .codeMeasure: [40, 60, 80, 100, 120]
            case .paragraphSpacing: [0, 0.5, 1.05, 1.5, 2]
            case .indent: [0.5, 1, 1.4, 1.7, 2]
            }
        }

        var baseline: Double { checkpoints[2] }

        var range: ClosedRange<Double> {
            switch self {
            case .lineHeight: DesignOverrides.lineHeightRange
            case .letterSpacing: DesignOverrides.letterSpacingRange
            case .codeLetterSpacing: DesignOverrides.codeLetterSpacingRange
            case .measure: DesignOverrides.measureRange
            case .paragraphSpacing: DesignOverrides.paragraphSpacingRange
            case .indent: DesignOverrides.indentRange
            case .codeLineHeight: DesignOverrides.codeLineHeightRange
            case .codeMeasure: DesignOverrides.codeMeasureRange
            }
        }

        var step: Double {
            switch self {
            case .indent: 0.1
            case .lineHeight, .codeLineHeight: 0.05
            case .letterSpacing, .codeLetterSpacing: 0.005
            case .measure, .codeMeasure: 2
            case .paragraphSpacing: 0.05
            }
        }

        private var keyPath: WritableKeyPath<Spacing, Double?> {
            switch self {
            case .lineHeight: \.lineHeight
            case .letterSpacing: \.letterSpacingEm
            case .codeLetterSpacing: \.codeLetterSpacingEm
            case .measure: \.measureCh
            case .paragraphSpacing: \.paragraphSpacingEm
            case .indent: \.indentEm
            case .codeLineHeight: \.codeLineHeight
            case .codeMeasure: \.codeMeasureCh
            }
        }

        func value(in spacing: Spacing) -> Double? { spacing[keyPath: keyPath] }

        /// The value actually shown: the stored one, else the baseline.
        func effectiveValue(in spacing: Spacing) -> Double { value(in: spacing) ?? baseline }

        /// Quantize only user edits, never values read from older JSON.
        func set(value: Double, in spacing: inout Spacing) {
            guard value.isFinite else { return }
            let bounds = range
            let clamped = min(max(value, bounds.lowerBound), bounds.upperBound)
            let grid = bounds.lowerBound + ((clamped - bounds.lowerBound) / step).rounded() * step
            let rounded = (min(max(grid, bounds.lowerBound), bounds.upperBound) * 1000).rounded() / 1000
            spacing[keyPath: keyPath] = abs(rounded - baseline) < 1e-9 ? nil : rounded
        }

        func clear(in spacing: inout Spacing) { spacing[keyPath: keyPath] = nil }

        func display(_ value: Double) -> String {
            value.formatted(.number.precision(.fractionLength(0...3))) + unit
        }
    }

    var spacing = Spacing()
    var elements: [String: Element] = [:]
    var code = Code()

    /// Synthesized `encode` keeps writing both keys; decoding tolerates their absence so
    /// a value written by an older or narrower version still loads its overrides.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        spacing = try container.decodeIfPresent(Spacing.self, forKey: .spacing) ?? Spacing()
        elements = try container.decodeIfPresent([String: Element].self, forKey: .elements) ?? [:]
        code = try container.decodeIfPresent(Code.self, forKey: .code) ?? Code()
    }

    init() {}

    subscript(element key: ElementKey) -> Element {
        get { elements[key.rawValue] ?? Element() }
        set { elements[key.rawValue] = newValue == Element() ? nil : newValue }
    }

    var isEmpty: Bool { self == DesignOverrides() }

    /// 타이포그래피 › 모두 초기화: every override is cleared except the element
    /// colors, which belong to Settings › 테마.
    func keepingOnlyElementColors() -> DesignOverrides {
        var kept = DesignOverrides()
        kept.elements = elements.compactMapValues { $0.color.map { Element(color: $0) } }
        return kept
    }

    static func decode(_ raw: String) -> DesignOverrides {
        guard let data = raw.data(using: .utf8),
              let value = try? JSONDecoder().decode(DesignOverrides.self, from: data) else {
            return DesignOverrides()
        }
        return value
    }

    func encoded() -> String {
        guard !isEmpty, let data = try? JSONEncoder().encode(self) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }

    /// Line height, letter spacing, paragraph spacing, indent and sizes are bare
    /// numbers: `reader.css` registers them (`@property … <number>`) so a change
    /// interpolates, and applies the `em` there. The measure keeps its `ch`
    /// because its "자동" default is not one number (100% or 45rem by width).
    func cssVariables(for scheme: ColorScheme) -> [String: String] {
        var vars: [String: String] = [:]
        if let v = spacing.lineHeight { vars["--km-user-line-height"] = Self.number(v, in: Self.lineHeightRange) }
        if let v = spacing.letterSpacingEm { vars["--km-user-letter-spacing"] = Self.number(v, in: Self.letterSpacingRange) }
        if let v = spacing.codeLetterSpacingEm {
            vars["--km-user-code-letter-spacing"] = Self.number(v, in: Self.codeLetterSpacingRange)
        }
        if let v = spacing.measureCh { vars["--km-user-measure"] = Self.number(v, in: Self.measureRange) + "ch" }
        if let v = spacing.paragraphSpacingEm { vars["--km-user-paragraph-spacing"] = Self.number(v, in: Self.paragraphSpacingRange) }
        if let v = spacing.indentEm { vars["--km-user-indent"] = Self.number(v, in: Self.indentRange) }
        if let v = spacing.codeLineHeight {
            vars["--km-user-code-line-height"] = Self.number(v, in: Self.codeLineHeightRange)
        }
        if let v = spacing.codeMeasureCh {
            vars["--km-user-code-measure"] = Self.number(v, in: Self.codeMeasureRange) + "ch"
        }
        if code.wrapsLines == false { vars["--km-code-white-space"] = "pre" }
        if let family = Self.cssFamily(code.fontFamily) {
            vars["--km-font-mono"] = "\(family), \(Self.monoFallbackStack)"
        }

        for key in ElementKey.allCases {
            let element = self[element: key]
            let prefix = "--km-user-\(key.cssName)"
            if key.supportsSize, let v = element.sizeScale {
                vars["\(prefix)-size"] = Self.number(v, in: Self.sizeScaleRange)
            }
            if key.supportsWeight, let w = element.weight, Self.weights.contains(w) {
                vars["\(prefix)-weight"] = String(w)
            }
            let hex = scheme == .dark ? element.color?.dark : element.color?.light
            if let hex, Self.isHexColor(hex) {
                vars["\(prefix)-color"] = hex.uppercased()
            }
        }
        return vars
    }

    private static func number(_ value: Double, in range: ClosedRange<Double>) -> String {
        let clamped = min(max(value, range.lowerBound), range.upperBound)
        let rounded = (clamped * 1000).rounded() / 1000
        return rounded == rounded.rounded() ? String(Int(rounded)) : String(rounded)
    }

    /// A quoted CSS family name, or `nil` for blank input. Quotes and
    /// backslashes are escaped; control characters are dropped.
    static func cssFamily(_ name: String?) -> String? {
        guard let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        var escaped = ""
        for scalar in trimmed.unicodeScalars where !CharacterSet.controlCharacters.contains(scalar) {
            if scalar == "\\" || scalar == "\"" { escaped.append("\\") }
            escaped.unicodeScalars.append(scalar)
        }
        return "\"\(escaped)\""
    }

    static func isHexColor(_ value: String) -> Bool {
        value.count == 7 && value.first == "#"
            && value.dropFirst().allSatisfy { $0.isASCII && $0.isHexDigit }
    }
}
