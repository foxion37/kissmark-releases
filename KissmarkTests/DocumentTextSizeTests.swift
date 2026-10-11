import Testing
@testable import Kissmark

struct DocumentTextSizeTests {
    private static let oldSmallScale = 0.9

    @Test func smallShrinksOneToTwoPixelsFromOldSmallAtBothBodySizes() {
        for body in [18.0, 17.0] {
            let drop = body * Self.oldSmallScale - body * KissmarkTextSize.small.scale
            #expect(drop >= 1 && drop <= 2)
        }
    }

    @Test func xSmallIsOneToTwoPixelsBelowSmallAtBothBodySizes() {
        for body in [18.0, 17.0] {
            let drop = body * KissmarkTextSize.small.scale - body * KissmarkTextSize.xSmall.scale
            #expect(drop >= 1 && drop <= 2.001)
        }
    }

    @Test func scalesIncreaseInDeclaredOrderAndMediumIsBaseline() {
        let scales = KissmarkTextSize.allCases.map(\.scale)
        #expect(scales == scales.sorted())
        #expect(Set(scales).count == scales.count)
        #expect(KissmarkTextSize.medium.scale == 1.0)
    }

    @Test func previouslySavedRawIdsStillDecode() {
        #expect(KissmarkTextSize(rawValue: "small") == .small)
        #expect(KissmarkTextSize(rawValue: "medium") == .medium)
        #expect(KissmarkTextSize(rawValue: "large") == .large)
        #expect(KissmarkTextSize(rawValue: "xLarge") == .xLarge)
        #expect(KissmarkTextSize(rawValue: "xSmall") == .xSmall)
    }
}
