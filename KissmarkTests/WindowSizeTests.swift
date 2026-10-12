import Foundation
import Testing
@testable import Kissmark

@MainActor
struct WindowSizeTests {
    @Test("The launch width fits the Document column plus the sidebar lane and handle slack")
    func launchWidthFitsTheDocumentColumn() {
        let width = KissmarkWindowChrome.defaultContentWidth(sidebarWidth: 260, textScale: 1)

        // The shipped defaults: sidebar + 1pt separator + (720 + 2 * 28) * 1 + 2 * 40.
        #expect(width == 1117)
    }

    @Test("The window keeps room for Crepe's block handle beside the column")
    func launchWidthKeepsBlockHandleSlack() {
        let width = KissmarkWindowChrome.defaultContentWidth(sidebarWidth: 260, textScale: 1)
        let column = KissmarkMetrics.documentColumnWidth(textScale: 1)

        #expect(
            width - column - KissmarkMetrics.sidebarDividerWidth - 260
                == 2 * KissmarkMetrics.documentColumnSlack
        )
        // Two 32pt handle items plus their 2pt gap, minus the column's own padding.
        #expect(
            KissmarkMetrics.defaultDocumentHorizontalPadding + KissmarkMetrics.documentColumnSlack >= 66
        )
    }

    @Test("Text size scales the column and the padding, never the sidebar or the slack")
    func textSizeScalesOnlyTheColumn() {
        let width = KissmarkWindowChrome.defaultContentWidth(sidebarWidth: 220, textScale: 2)

        #expect(
            width == 220 + KissmarkMetrics.sidebarDividerWidth + (720 + 2 * 28) * 2
                + 2 * KissmarkMetrics.documentColumnSlack
        )
    }

    @Test("Explicit measures keep the formula honest")
    func explicitMeasureKeepsTheFormulaHonest() {
        let width = KissmarkWindowChrome.defaultContentWidth(
            sidebarWidth: 50,
            textScale: 1,
            measure: 100,
            horizontalPadding: 10,
            columnSlack: 0
        )

        #expect(width == 50 + KissmarkMetrics.sidebarDividerWidth + 120)
    }

    @Test("A roomy screen keeps the wanted size")
    func roomyScreenKeepsTheWantedSize() {
        let wanted = CGSize(width: 1037, height: 720)

        let clamped = KissmarkWindowChrome.clampedContentSize(
            wanted,
            to: CGSize(width: 1440, height: 900),
            minimum: CGSize(width: 430, height: 600)
        )

        #expect(clamped == wanted)
    }

    @Test("A small screen caps the size and the window minimum wins over an even smaller one")
    func smallScreenCapsTheSize() {
        let minimum = CGSize(width: 430, height: 600)
        let wanted = CGSize(width: 1037, height: 720)

        let capped = KissmarkWindowChrome.clampedContentSize(
            wanted,
            to: CGSize(width: 800, height: 500),
            minimum: minimum
        )

        #expect(capped.width == 800)
        #expect(capped.height == minimum.height, "the window minimum wins over a shorter usable area")
    }

    @Test("The stored sidebar width round-trips and clamps into the macOS limits")
    func storedSidebarWidthRoundTrips() throws {
        let name = "KM_Window_\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        defer { defaults.removePersistentDomain(forName: name) }

        #expect(KissmarkWindowChrome.storedSidebarWidth(defaults: defaults) == nil)

        KissmarkWindowChrome.storeSidebarWidth(300, defaults: defaults)
        let stored = try #require(KissmarkWindowChrome.storedSidebarWidth(defaults: defaults))

        #expect(stored == 300)
        #expect(KissmarkMetrics.clampedSidebarWidth(stored, idiom: .mac) == 300)
        #expect(KissmarkMetrics.clampedSidebarWidth(10, idiom: .mac) == 220)
        #expect(KissmarkMetrics.clampedSidebarWidth(9_999, idiom: .mac) == 360)
    }

    #if os(macOS)
    @Test("A 장폭 override widens or narrows the launch window with the column")
    func measureOverrideDrivesLaunchWidth() throws {
        let name = "KM_Window_\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        defer { defaults.removePersistentDomain(forName: name) }
        let roomy = CGSize(width: 5_000, height: 3_000)

        let base = KissmarkWindowChrome.launchContentSize(defaults: defaults, visibleFrame: roomy).width
        defaults.set(#"{"spacing":{"measureCh":120},"elements":{}}"#, forKey: DesignOverrides.storageKey)
        let wide = KissmarkWindowChrome.launchContentSize(defaults: defaults, visibleFrame: roomy).width
        defaults.set(#"{"spacing":{"measureCh":40},"elements":{}}"#, forKey: DesignOverrides.storageKey)
        let narrow = KissmarkWindowChrome.launchContentSize(defaults: defaults, visibleFrame: roomy).width

        // 글자 크기 중간이 더 이상 스케일 1.0이 아니므로 기대 delta에도 스케일이 곱해진다.
        let expectedDelta = (120 * KissmarkMetrics.documentMeasureChWidth - KissmarkMetrics.defaultDocumentMeasure)
            * KissmarkTextSize.medium.scale
        #expect(abs((wide - base) - expectedDelta) < 0.01)
        #expect(narrow < base)
    }
    #endif
}
