import CoreGraphics
import Testing
@testable import Kissmark

struct KissmarkSidebarPresentationTests {
    @Test func responsiveBreakpointsCompressInTheAgreedOrder() {
        #expect(KissmarkMetrics.minimumWindowWidth < KissmarkMetrics.sidebarAutoCollapseWidth)
        #expect(KissmarkMetrics.sidebarAutoCollapseWidth < KissmarkMetrics.toolbarOverflowWidth)
    }

    @Test func acceptedDesignContractUsesPrototypeABaselines() {
        #expect(KissmarkMetrics.toolbarItemGap == 12)
        #expect(KissmarkMetrics.sidebarInset == 12)
        #expect(KissmarkMetrics.treeIndent == 16)
        #expect(KissmarkMetrics.disclosureGlyphSize == 12)
        #expect(KissmarkMetrics.treeIconSize == 16)
        #expect(KissmarkMetrics.folderControlRadius == 8)
        #expect(KissmarkMetrics.emptyStateIconSize == 32)
        #expect((0.9 ... 1.1).contains(KissmarkMetrics.toolbarPlusOpticalScale))
        #expect((0.9 ... 1.1).contains(KissmarkMetrics.toolbarArchiveOpticalScale))
        #expect((0.9 ... 1.1).contains(KissmarkMetrics.toolbarCloseOpticalScale))
        #expect((0.9 ... 1.1).contains(KissmarkMetrics.toolbarLockOpticalScale))
        #expect(KissmarkMetrics.sidebarWidth(idiom: .mac).max == 360)
        #expect(KissmarkMetrics.sidebarWidth(idiom: .pad).min == 240)
    }

    @Test func widthCollapseRestoresTheUserChoiceWhenWidened() {
        var presentation = KissmarkSidebarPresentation()

        presentation.update(forWindowWidth: KissmarkMetrics.sidebarAutoCollapseWidth - 1)
        #expect(!presentation.isVisible)
        #expect(presentation.userWantsVisible)
        #expect(presentation.isTemporarilyCollapsed)

        presentation.update(forWindowWidth: KissmarkMetrics.sidebarAutoCollapseWidth + 1)
        #expect(presentation.isVisible)
        #expect(presentation.userWantsVisible)
        #expect(!presentation.isTemporarilyCollapsed)
    }

    @Test func userHiddenSidebarStaysHiddenAcrossResize() {
        var presentation = KissmarkSidebarPresentation()
        presentation.toggle()

        #expect(!presentation.isVisible)
        #expect(!presentation.userWantsVisible)

        presentation.update(forWindowWidth: KissmarkMetrics.minimumWindowWidth)
        presentation.update(forWindowWidth: KissmarkMetrics.toolbarOverflowWidth + 1)

        #expect(!presentation.isVisible)
        #expect(!presentation.userWantsVisible)
        #expect(!presentation.isTemporarilyCollapsed)
    }

    @Test func userCanReopenSidebarWhileItIsTemporarilyCollapsed() {
        var presentation = KissmarkSidebarPresentation()
        presentation.update(forWindowWidth: KissmarkMetrics.sidebarAutoCollapseWidth - 1)

        presentation.toggle()

        #expect(presentation.isVisible)
        #expect(presentation.userWantsVisible)
        #expect(!presentation.isTemporarilyCollapsed)
    }
}
