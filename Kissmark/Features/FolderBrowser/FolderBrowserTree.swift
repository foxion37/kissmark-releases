import SwiftUI

struct FolderBrowserTree: View {
    let folders: [FolderTreeNode]
    let documents: [FolderTreeNode]
    let selectedDocumentURL: URL?
    let isExpanded: (URL) -> Bool
    let toggleFolder: (URL) -> Void
    let selectDocument: (URL) -> Void
    var recents: [RecentDocument] = []
    var selectRecent: (RecentDocument) -> Void = { _ in }
    @Environment(\.chromePalette) private var chromePalette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// One selection wash shared by every Document row, so it glides between them.
    @Namespace private var selectionNamespace

    private var rowTransition: AnyTransition {
        reduceMotion ? .opacity : .opacity.combined(with: .offset(y: -KissmarkMotion.entranceRise))
    }

    /// Recents store the symlink-resolved NFC path, so compare in that form.
    private func isSelected(_ recent: RecentDocument) -> Bool {
        selectedDocumentURL?.resolvingSymlinksInPath().path.precomposedStringWithCanonicalMapping == recent.path
    }

    /// Every visible row of the Folder section in display order, flattened so the
    /// `LazyVStack` builds only the rows on screen, however deep the expansion goes.
    private var folderRows: [FolderTreeRow] {
        var rows: [FolderTreeRow] = []
        var pending = folders.reversed().map { FolderTreeRow(node: $0, depth: 0) }
        while let row = pending.popLast() {
            rows.append(row)
            guard row.node.kind == .folder, isExpanded(row.node.url) else { continue }
            let children = row.node.children ?? []
            let ordered = children.filter { $0.kind == .folder } + children.filter { $0.kind == .document }
            pending.append(contentsOf: ordered.reversed().map { FolderTreeRow(node: $0, depth: row.depth + 1) })
        }
        return rows
    }

    var body: some View {
        let rows = folderRows
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if !recents.isEmpty {
                    Text("최근")
                        .font(KissmarkType.caption)
                        .foregroundStyle(chromePalette?.chromeMuted ?? .secondary)
                        .padding(.horizontal, KissmarkMetrics.treeRowInlineInset)
                        .padding(.bottom, KissmarkMetrics.disclosureIconGap)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier("folder-browser-recents-header")

                    ForEach(recents, id: \.path) { recent in
                        FolderBrowserDocumentRow(
                            name: recent.title,
                            depth: 0,
                            isSelected: isSelected(recent),
                            selectionNamespace: selectionNamespace,
                            select: { selectRecent(recent) },
                            help: recent.path,
                            washID: FolderBrowserSelectionWash.recentID,
                            identifier: "folder-browser-recent",
                            icon: recent.opener == "agent" ? .bot : .fileText
                        )
                    }

                    Divider()
                        .padding(.vertical, KissmarkMetrics.sidebarSectionGap)
                }

                ForEach(rows) { row in
                    Group {
                        if row.node.kind == .folder {
                            FolderBrowserFolderRow(
                                node: row.node,
                                depth: row.depth,
                                isExpanded: isExpanded(row.node.url),
                                toggle: { toggleFolder(row.node.url) }
                            )
                        } else {
                            FolderBrowserDocumentRow(
                                name: row.node.name,
                                depth: row.depth,
                                isSelected: selectedDocumentURL == row.node.url,
                                selectionNamespace: selectionNamespace,
                                select: { selectDocument(row.node.url) }
                            )
                        }
                    }
                    .transition(rowTransition)
                }

                if !folders.isEmpty, !documents.isEmpty {
                    Divider()
                        .padding(.vertical, KissmarkMetrics.sidebarSectionGap)
                }

                ForEach(documents) { node in
                    FolderBrowserDocumentRow(
                        name: node.name,
                        depth: 0,
                        isSelected: selectedDocumentURL == node.url,
                        selectionNamespace: selectionNamespace,
                        select: { selectDocument(node.url) }
                    )
                }
            }
            .animation(KissmarkMotion.spring(reduceMotion: reduceMotion), value: rows.map(\.id))
            .animation(KissmarkMotion.spring(reduceMotion: reduceMotion), value: selectedDocumentURL)
            .padding(.horizontal, KissmarkMetrics.sidebarInset)
            .padding(.top, KissmarkMetrics.sidebarSectionGap)
            .padding(.bottom, KissmarkMetrics.emptyStateBodyActionGap)
            .foregroundStyle(chromePalette?.chromePrimary ?? .primary)
        }
        .background(Color.clear)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("folder-browser-tree")
    }
}

private struct FolderTreeRow: Identifiable {
    let node: FolderTreeNode
    let depth: Int
    var id: URL { node.url }
}

private enum FolderBrowserSelectionWash {
    static let id = "folder-browser-selection-wash"
    /// A Document shown in both 최근 and the tree draws two washes; separate ids keep them apart.
    static let recentID = "folder-browser-recent-selection-wash"
}

private struct FolderBrowserFolderRow: View {
    let node: FolderTreeNode
    let depth: Int
    let isExpanded: Bool
    let toggle: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.chromePalette) private var chromePalette
    @State private var isHovered = false

    private var hoverColor: Color { chromePalette?.chromePrimary ?? .primary }

    var body: some View {
        Button {
            toggle()
        } label: {
            HStack(spacing: 0) {
                KissmarkLucideImage(
                    icon: .chevronRight,
                    pointSize: KissmarkMetrics.disclosureGlyphSize
                )
                .frame(
                    width: KissmarkMetrics.disclosureSlotSize,
                    height: KissmarkMetrics.disclosureSlotSize
                )
                .rotationEffect(.degrees(isExpanded ? 90 : 0))
                .animation(KissmarkMotion.snappy(reduceMotion: reduceMotion), value: isExpanded)
                .padding(.trailing, KissmarkMetrics.disclosureIconGap)

                // Both glyphs stay mounted so folder ↔ folderOpen crossfades.
                ZStack {
                    KissmarkLucideImage(icon: .folder, pointSize: KissmarkMetrics.treeIconSize)
                        .opacity(isExpanded ? 0 : 1)
                    KissmarkLucideImage(icon: .folderOpen, pointSize: KissmarkMetrics.treeIconSize)
                        .opacity(isExpanded ? 1 : 0)
                }
                .animation(KissmarkMotion.snappy(reduceMotion: reduceMotion), value: isExpanded)
                .padding(.trailing, KissmarkMetrics.iconLabelGap)

                Text(node.name)
                    .font(KissmarkType.font(.body))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .accessibilityIdentifier("folder-browser-folder")

                Spacer(minLength: 0)
            }
            .padding(.horizontal, KissmarkMetrics.treeRowInlineInset)
            .padding(.leading, CGFloat(depth) * KissmarkMetrics.treeIndent)
            .frame(maxWidth: .infinity, minHeight: KissmarkMetrics.treeRowHeight, alignment: .leading)
            .background {
                RoundedRectangle(
                    cornerRadius: KissmarkMetrics.treeSelectionRadius,
                    style: .continuous
                )
                .fill(hoverColor.opacity(KissmarkMetrics.treeHoverOpacity))
                .opacity(isHovered ? 1 : 0)
                .animation(KissmarkMotion.fade(reduceMotion: reduceMotion), value: isHovered)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .onKeyPress(.rightArrow) {
            guard !isExpanded else { return .ignored }
            toggle()
            return .handled
        }
        .onKeyPress(.leftArrow) {
            guard isExpanded else { return .ignored }
            toggle()
            return .handled
        }
        .accessibilityLabel(Text(node.name))
        .accessibilityValue(Text(isExpanded ? "expanded" : "collapsed"))
    }
}

private struct FolderBrowserDocumentRow: View {
    let name: String
    let depth: Int
    let isSelected: Bool
    let selectionNamespace: Namespace.ID
    let select: () -> Void
    var help: String?
    var washID = FolderBrowserSelectionWash.id
    var identifier = "folder-browser-document"
    var icon: KissmarkLucide = .fileText
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.chromePalette) private var chromePalette
    @State private var isHovered = false

    var body: some View {
        Button(action: select) {
            HStack(spacing: 0) {
                Color.clear
                    .frame(
                        width: KissmarkMetrics.disclosureSlotSize,
                        height: KissmarkMetrics.disclosureSlotSize
                    )
                    .padding(.trailing, KissmarkMetrics.disclosureIconGap)

                KissmarkLucideImage(
                    icon: icon,
                    pointSize: KissmarkMetrics.treeIconSize
                )
                .padding(.trailing, KissmarkMetrics.iconLabelGap)

                Text(name)
                    .font(KissmarkType.font(.body))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .accessibilityIdentifier(identifier)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, KissmarkMetrics.treeRowInlineInset)
            .padding(.leading, CGFloat(depth) * KissmarkMetrics.treeIndent)
            .frame(maxWidth: .infinity, minHeight: KissmarkMetrics.treeRowHeight, alignment: .leading)
            .background {
                RoundedRectangle(
                    cornerRadius: KissmarkMetrics.treeSelectionRadius,
                    style: .continuous
                )
                .fill((chromePalette?.chromePrimary ?? .primary).opacity(KissmarkMetrics.treeHoverOpacity))
                .opacity(isHovered && !isSelected ? 1 : 0)
                .animation(KissmarkMotion.fade(reduceMotion: reduceMotion), value: isHovered)

                // Only the selected row draws the wash; the tree's spring slides it
                // from the previous row through the shared namespace.
                if isSelected {
                    RoundedRectangle(
                        cornerRadius: KissmarkMetrics.treeSelectionRadius,
                        style: .continuous
                    )
                    .fill(chromePalette?.chromeAccentSoft ?? Color.accentColor.opacity(KissmarkMetrics.treeSelectionOpacity))
                    .matchedGeometryEffect(id: washID, in: selectionNamespace)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .accessibilityLabel(Text(name))
        .accessibilityValue(Text(isSelected ? "selected" : ""))
        .help(help ?? "")
    }
}
