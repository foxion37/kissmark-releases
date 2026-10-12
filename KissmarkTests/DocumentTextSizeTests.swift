import Testing
@testable import Kissmark

struct DocumentTextSizeTests {
    /// The pre-2.3.8 default body scale (18px at the wide viewport).
    private static let oldMediumScale = 1.0

    /// 픽셀 수치는 18px 참조 뷰포트(≥600px) 기준. 좁은 뷰포트는 같은 비율로
    /// 축소되므로 픽셀 차이가 아니라 비율로 검증한다.
    @Test func mediumShrinksFourPixelsFromTheOldDefaultAtTheReferenceViewport() {
        let drop = 18.0 * Self.oldMediumScale - 18.0 * KissmarkTextSize.medium.scale
        #expect(abs(drop - 4) < 0.1)
    }

    @Test func largeMatchesTheOldDefaultAndXLargeMatchesTheOldLarge() {
        #expect(KissmarkTextSize.large.scale == 1.0)
        #expect(KissmarkTextSize.xLarge.scale == 21.0 / 18.0)
    }

    @Test func stepsKeepTheirProportionsAcrossViewports() {
        // 좁은 뷰포트(17px 기준)에서도 같은 비율로 축소된다.
        let wideDrop = 18.0 * (KissmarkTextSize.medium.scale - KissmarkTextSize.small.scale)
        let narrowDrop = 17.0 * (KissmarkTextSize.medium.scale - KissmarkTextSize.small.scale)
        #expect(abs(narrowDrop - wideDrop * 17.0 / 18.0) < 0.001)
    }

    @Test func smallIsOneToTwoPixelsBelowMediumAtTheReferenceViewport() {
        let drop = 18.0 * KissmarkTextSize.medium.scale - 18.0 * KissmarkTextSize.small.scale
        #expect(drop >= 1 && drop <= 2.001)
    }

    @Test func xSmallIsOneToTwoPixelsBelowSmallAtTheReferenceViewport() {
        let drop = 18.0 * KissmarkTextSize.small.scale - 18.0 * KissmarkTextSize.xSmall.scale
        #expect(drop >= 1 && drop <= 2.001)
    }

    @Test func scalesIncreaseInDeclaredOrder() {
        let scales = KissmarkTextSize.allCases.map(\.scale)
        #expect(scales == scales.sorted())
        #expect(Set(scales).count == scales.count)
    }

    @Test func previouslySavedRawIdsStillDecode() {
        #expect(KissmarkTextSize(rawValue: "small") == .small)
        #expect(KissmarkTextSize(rawValue: "medium") == .medium)
        #expect(KissmarkTextSize(rawValue: "large") == .large)
        #expect(KissmarkTextSize(rawValue: "xLarge") == .xLarge)
        #expect(KissmarkTextSize(rawValue: "xSmall") == .xSmall)
    }
}
