import SwiftUI

/// Chrome icons from **Lucide** (the icon set used by shadcn/ui).
/// Assets live in `Assets.xcassets/Lucide` as template SVGs.
enum KissmarkLucide: String, CaseIterable, Identifiable {
    case folder
    case folderOpen = "folder-open"
    case panelLeft = "panel-left"
    case plus
    case lock
    case lockOpen = "lock-open"
    case archive
    case x
    case chevronRight = "chevron-right"
    case settings
    case fileText = "file-text"
    case chevronsUpDown = "chevrons-up-down"
    case code
    case copy
    case bot

    var id: String { rawValue }

    /// Asset catalog name (`lucide.folder-open`, …).
    var assetName: String { "lucide.\(rawValue)" }

    var image: Image {
        Image(assetName)
            .renderingMode(.template)
    }
}

/// Sized Lucide glyph for toolbar / sidebar chrome.
struct KissmarkLucideImage: View {
    let icon: KissmarkLucide
    var pointSize: CGFloat = KissmarkMetrics.toolbarIconPointSize
    var opticalScale: CGFloat = 1

    var body: some View {
        icon.image
            .resizable()
            .scaledToFit()
            .frame(
                width: pointSize * opticalScale,
                height: pointSize * opticalScale
            )
            .accessibilityHidden(true)
    }
}
