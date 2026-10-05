import CoreGraphics

struct KissmarkSidebarPresentation: Equatable {
    private(set) var userWantsVisible = true
    private(set) var isTemporarilyCollapsed = false

    var isVisible: Bool {
        userWantsVisible && !isTemporarilyCollapsed
    }

    mutating func update(forWindowWidth width: CGFloat) {
        guard width > 0 else { return }
        isTemporarilyCollapsed =
            userWantsVisible && width < KissmarkMetrics.sidebarAutoCollapseWidth
    }

    mutating func toggle() {
        userWantsVisible = !isVisible
        isTemporarilyCollapsed = false
    }
}
