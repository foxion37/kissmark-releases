import SwiftUI
import CoreText
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Hangul-first type tokens. Face is Pretendard Variable (OFL) — the family
/// Karrot SEED ships. Sizes follow Toss product roles (28 / 22 / 18 / 17 / 13).
/// Body leading is Karrot-article 17/26, not Toss UI-label 17/24.
/// Toss Product Sans and Karrot Sans are proprietary and are not bundled.
enum KissmarkType {
    static let familyName = "Pretendard Variable"

    static let bodySize: CGFloat = 17
    static let h1Size: CGFloat = 28
    static let h2Size: CGFloat = 22
    static let h3Size: CGFloat = 18
    static let captionSize: CGFloat = 13

    static let bodyLineHeight: CGFloat = 1.7
    static let h1LineHeight: CGFloat = 1.5
    static let h2LineHeight: CGFloat = 1.36
    static let h3LineHeight: CGFloat = 1.44
    static let captionLineHeight: CGFloat = 1.52

    static let bodyLetterSpacingEm: CGFloat = -0.02
    static let h1LetterSpacingEm: CGFloat = -0.03
    static let h2LetterSpacingEm: CGFloat = -0.028
    static let h3LetterSpacingEm: CGFloat = -0.024
    static let captionLetterSpacingEm: CGFloat = -0.012

    // Chrome text is one step lighter than the system default for its role
    // (1.5): caption medium→regular, control medium→regular, title semibold→medium.
    static let captionWeight: Font.Weight = .regular
    static let controlWeight: Font.Weight = .regular
    static let chromeTitleWeight: Font.Weight = .medium

    static func tracking(for size: CGFloat) -> CGFloat {
        size * letterSpacingEm(for: size)
    }

    static func letterSpacingEm(for size: CGFloat) -> CGFloat {
        switch size {
        case h1Size: return h1LetterSpacingEm
        case h2Size: return h2LetterSpacingEm
        case h3Size: return h3LetterSpacingEm
        case captionSize: return captionLetterSpacingEm
        default: return bodyLetterSpacingEm
        }
    }

    static var caption: Font {
        font(size: captionSize, weight: captionWeight)
    }

    static var usesInter: Bool {
        KissmarkLocalization.languageCode == "en" && KissmarkEnglishFont.active == .inter && interAvailable
    }

    static var webBodyFontFamily: String? {
        guard KissmarkLocalization.languageCode == "en" else { return nil }
        return usesInter
            ? "\"Inter Variable\", \"Pretendard Variable\", -apple-system, BlinkMacSystemFont, sans-serif"
            : "\"Pretendard Hangul\", -apple-system, BlinkMacSystemFont, \"Segoe UI\", sans-serif"
    }

    static let interAvailable: Bool = {
        guard KissmarkLocalization.languageCode == "en", KissmarkEnglishFont.active == .inter else { return false }
        for name in ["InterVariable", "InterVariable-Italic"] {
            guard let url = Bundle.main.url(forResource: name, withExtension: "ttf", subdirectory: "Fonts")
                    ?? Bundle.main.url(forResource: name, withExtension: "ttf") else { return false }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
        #if os(macOS)
        return NSFont(name: "InterVariable", size: NSFont.systemFontSize) != nil
            && NSFont(name: "InterVariableItalic", size: NSFont.systemFontSize) != nil
        #else
        return UIFont(name: "InterVariable", size: UIFont.systemFontSize) != nil
            && UIFont(name: "InterVariableItalic", size: UIFont.systemFontSize) != nil
        #endif
    }()

    static func registerFontsIfNeeded() { _ = interAvailable }

    static func font(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        guard usesInter else { return .system(size: size, weight: weight) }
        registerFontsIfNeeded()
        return .custom("InterVariable", fixedSize: size).weight(weight)
    }

    static func font(_ style: Font.TextStyle, weight: Font.Weight? = nil) -> Font {
        let base: Font
        if usesInter {
            registerFontsIfNeeded()
            base = .custom("InterVariable", size: nativePointSize(style), relativeTo: style)
                .weight(style == .headline ? .semibold : .regular)
        } else {
            base = .system(style)
        }
        return weight.map { base.weight($0) } ?? base
    }

    private static func nativePointSize(_ style: Font.TextStyle) -> CGFloat {
        #if os(macOS)
        let native: NSFont.TextStyle
        #else
        let native: UIFont.TextStyle
        #endif
        switch style {
        case .largeTitle: native = .largeTitle
        case .title: native = .title1
        case .title2: native = .title2
        case .title3: native = .title3
        case .headline: native = .headline
        case .subheadline: native = .subheadline
        case .callout: native = .callout
        case .footnote: native = .footnote
        case .caption: native = .caption1
        case .caption2: native = .caption2
        default: native = .body
        }
        #if os(macOS)
        return NSFont.preferredFont(forTextStyle: native).pointSize
        #else
        return UIFontDescriptor.preferredFontDescriptor(
            withTextStyle: native,
            compatibleWith: UITraitCollection(preferredContentSizeCategory: .large)
        ).pointSize
        #endif
    }
}
