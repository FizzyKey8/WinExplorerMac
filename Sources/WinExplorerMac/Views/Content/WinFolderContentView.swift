import SwiftUI
import AppKit

public struct Win11FolderContentView: View {
    @ObservedObject var windowVM: ExplorerWindowViewModel
    @ObservedObject var tab: ExplorerTabViewModel
    @ObservedObject var clipboard: FileClipboardService
    @Environment(\.colorScheme) private var colorScheme

    @State private var itemFrames: [URL: CGRect] = [:]
    @State private var globalMarqueeRect: CGRect? = nil
    @State private var containerOrigin: CGPoint = .zero
    @State private var dragInitialSelection: Set<URL> = []

    public init(windowVM: ExplorerWindowViewModel, tab: ExplorerTabViewModel, clipboard: FileClipboardService) {
        self.windowVM = windowVM
        self.tab = tab
        self.clipboard = clipboard
    }

    private func handleDragChanged(start: CGPoint, current: CGPoint) {
        if globalMarqueeRect == nil {
            dragInitialSelection = tab.selectedURLs
        }
        let rect = CGRect(
            x: min(start.x, current.x),
            y: min(start.y, current.y),
            width: abs(current.x - start.x),
            height: abs(current.y - start.y)
        )
        self.globalMarqueeRect = rect

        var newlySelected = Set<URL>()
        for (url, frame) in itemFrames {
            if frame.intersects(rect) {
                newlySelected.insert(url)
            }
        }

        if NSEvent.modifierFlags.contains(.command) || NSEvent.modifierFlags.contains(.shift) {
            tab.selectedURLs = dragInitialSelection.symmetricDifference(newlySelected)
        } else {
            tab.selectedURLs = newlySelected
        }
        if let first = newlySelected.first {
            tab.lastClickedURL = first
        }
    }

    private func handleDragEnded() {
        self.globalMarqueeRect = nil
        self.dragInitialSelection = []
    }

    public var body: some View {
        ZStack {
            // Background click / right-click area (for empty folder space)
            Win11MouseHandlerView(
                onSingleClick: { _ in
                    windowVM.dismissContextMenu()
                    tab.clearSelection()
                },
                onDoubleClick: nil,
                onRightClick: { point in
                    windowVM.presentContextMenu(for: nil, at: point)
                },
                onDragChanged: handleDragChanged,
                onDragEnded: handleDragEnded
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if tab.displayedItems.isEmpty {
                emptyFolderState
                    .allowsHitTesting(false)
            } else {
                switch tab.viewMode {
                case .extraLargeIcons, .largeIcons, .mediumIcons:
                    gridIconsView
                case .list:
                    compactListView
                case .details:
                    detailsTableView
                }
            }
        }
        .overlay(alignment: .topTrailing) {
            if tab.isLoading && !tab.displayedItems.isEmpty {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Cargando archivos (\(tab.items.count))...")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(
                    Capsule()
                        .stroke(Win11Theme.subtleBorder(colorScheme), lineWidth: 1)
                )
                .padding(.top, 10)
                .padding(.trailing, 14)
                .allowsHitTesting(false)
            }
        }
        .overlay {
            // Windows 11 translucent blue marquee drag selection box
            if let globalRect = globalMarqueeRect {
                let localRect = globalRect.offsetBy(dx: -containerOrigin.x, dy: -containerOrigin.y)
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color(red: 0.05, green: 0.52, blue: 0.95).opacity(0.18))
                    .overlay(
                        RoundedRectangle(cornerRadius: 1)
                            .stroke(Color(red: 0.05, green: 0.52, blue: 0.95).opacity(0.75), lineWidth: 1)
                    )
                    .frame(width: max(0, localRect.width), height: max(0, localRect.height))
                    .position(x: localRect.midX, y: localRect.midY)
                    .allowsHitTesting(false)
            }
        }
        .onPreferenceChange(ItemGlobalFrameKey.self) { frames in
            self.itemFrames = frames
        }
        .background(
            GeometryReader { geo in
                Color.clear
                    .onAppear {
                        containerOrigin = geo.frame(in: .global).origin
                        if geo.size.width > 50 {
                            tab.contentWidth = geo.size.width
                        }
                    }
                    .onChange(of: geo.frame(in: .global).origin) { _, newOrigin in
                        containerOrigin = newOrigin
                    }
                    .onChange(of: geo.size.width) { _, newWidth in
                        if newWidth > 50 {
                            tab.contentWidth = newWidth
                        }
                    }
            }
        )
        .background(Win11Theme.contentBackground(colorScheme))
    }

    // MARK: - Empty Folder View
    private var emptyFolderState: some View {
        VStack(spacing: 12) {
            if tab.isLoading {
                ProgressView()
                    .controlSize(.regular)
                Text("Cargando elementos de la carpeta...")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
            } else {
                Win11FolderIconView(size: 56)
                    .opacity(0.75)
                Text(tab.searchQuery.isEmpty ? "Esta carpeta está vacía." : "Ningún elemento coincide con tu búsqueda.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - 1. Grid View (Extra Large, Large, Medium Icons)
    private var gridIconsView: some View {
        let cellWidth = tab.viewMode.gridCellWidth
        let columns = [GridItem(.adaptive(minimum: cellWidth, maximum: cellWidth + 24), spacing: 10)]

        return ScrollViewReader { scrollProxy in
            ScrollView(.vertical) {
                ZStack(alignment: .topLeading) {
                    // Background mouse handler covering entire scrollable canvas
                    Win11MouseHandlerView(
                        onSingleClick: { _ in
                            windowVM.dismissContextMenu()
                            tab.clearSelection()
                        },
                        onDoubleClick: nil,
                        onRightClick: { point in
                            windowVM.presentContextMenu(for: nil, at: point)
                        },
                        onDragChanged: handleDragChanged,
                        onDragEnded: handleDragEnded
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
                        ForEach(tab.displayedItems) { item in
                            Win11GridItemCell(
                                windowVM: windowVM,
                                tab: tab,
                                item: item,
                                isCut: clipboard.isItemCut(item.url),
                                onDragChanged: handleDragChanged,
                                onDragEnded: handleDragEnded
                            )
                            .id(item.url)
                            .zIndex(tab.renamingURL == item.url ? 999 : 0)
                        }
                    }
                    .padding(16)
                }
                .frame(maxWidth: .infinity, minHeight: 500, alignment: .topLeading)
            }
            .onChange(of: tab.lastClickedURL) { _, targetURL in
                if let targetURL {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        scrollProxy.scrollTo(targetURL, anchor: nil)
                    }
                }
            }
        }
    }

    // MARK: - 2. Compact List View
    private var compactListView: some View {
        let columns = [GridItem(.adaptive(minimum: 230, maximum: 280), spacing: 8)]

        return ScrollViewReader { scrollProxy in
            ScrollView(.vertical) {
                ZStack(alignment: .topLeading) {
                    Win11MouseHandlerView(
                        onSingleClick: { _ in
                            windowVM.dismissContextMenu()
                            tab.clearSelection()
                        },
                        onDoubleClick: nil,
                        onRightClick: { point in
                            windowVM.presentContextMenu(for: nil, at: point)
                        },
                        onDragChanged: handleDragChanged,
                        onDragEnded: handleDragEnded
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    LazyVGrid(columns: columns, alignment: .leading, spacing: 4) {
                        ForEach(tab.displayedItems) { item in
                            Win11ListItemRow(
                                windowVM: windowVM,
                                tab: tab,
                                item: item,
                                isCut: clipboard.isItemCut(item.url),
                                onDragChanged: handleDragChanged,
                                onDragEnded: handleDragEnded
                            )
                            .id(item.url)
                            .zIndex(tab.renamingURL == item.url ? 999 : 0)
                        }
                    }
                    .padding(14)
                }
                .frame(maxWidth: .infinity, minHeight: 500, alignment: .topLeading)
            }
            .onChange(of: tab.lastClickedURL) { _, targetURL in
                if let targetURL {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        scrollProxy.scrollTo(targetURL, anchor: nil)
                    }
                }
            }
        }
    }

    // MARK: - 3. Windows 11 Details View (Sortable Columns)
    private var detailsTableView: some View {
        VStack(spacing: 0) {
            // Column Headers
            HStack(spacing: 0) {
                sortableHeaderButton(title: "Nombre", field: .name)
                    .frame(minWidth: 260, maxWidth: .infinity, alignment: .leading)

                sortableHeaderButton(title: "Fecha de modificación", field: .dateModified)
                    .frame(width: 155, alignment: .leading)

                sortableHeaderButton(title: "Tipo", field: .type)
                    .frame(width: 155, alignment: .leading)

                sortableHeaderButton(title: "Tamaño", field: .size)
                    .frame(width: 100, alignment: .trailing)
            }
            .padding(.horizontal, 14)
            .frame(height: 30)
            .background(Win11Theme.contentBackground(colorScheme))
            .overlay(alignment: .bottom) {
                Divider().opacity(0.6)
            }

            // Rows
            ScrollViewReader { scrollProxy in
                ScrollView(.vertical) {
                    ZStack(alignment: .topLeading) {
                        Win11MouseHandlerView(
                            onSingleClick: { _ in
                                windowVM.dismissContextMenu()
                                tab.clearSelection()
                            },
                            onDoubleClick: nil,
                            onRightClick: { point in
                                windowVM.presentContextMenu(for: nil, at: point)
                            },
                            onDragChanged: handleDragChanged,
                            onDragEnded: handleDragEnded
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                        LazyVStack(spacing: 1) {
                            ForEach(tab.displayedItems) { item in
                                Win11DetailsTableRow(
                                    windowVM: windowVM,
                                    tab: tab,
                                    item: item,
                                    isCut: clipboard.isItemCut(item.url),
                                    onDragChanged: handleDragChanged,
                                    onDragEnded: handleDragEnded
                                )
                                .id(item.url)
                                .zIndex(tab.renamingURL == item.url ? 999 : 0)
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                    }
                    .frame(maxWidth: .infinity, minHeight: 500, alignment: .topLeading)
                }
                .onChange(of: tab.lastClickedURL) { _, targetURL in
                    if let targetURL {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            scrollProxy.scrollTo(targetURL, anchor: nil)
                        }
                    }
                }
            }
        }
    }

    private func sortableHeaderButton(title: String, field: ExplorerSortField) -> some View {
        Button {
            tab.toggleSort(by: field)
        } label: {
            HStack(spacing: 5) {
                Text(title)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(.secondary)
                if tab.sortField == field {
                    Image(systemName: tab.sortAscending ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Win11Theme.accentBlue(colorScheme))
                }
            }
            .padding(.vertical, 5)
            .padding(.horizontal, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Grid Item Cell
struct Win11GridItemCell: View {
    let windowVM: ExplorerWindowViewModel
    @ObservedObject var tab: ExplorerTabViewModel
    let item: FileItem
    let isCut: Bool
    var onDragChanged: ((CGPoint, CGPoint) -> Void)? = nil
    var onDragEnded: (() -> Void)? = nil

    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovered: Bool = false
    @ObservedObject private var downloadManager = CloudDownloadManager.shared

    private var isSelected: Bool {
        tab.selectedURLs.contains(item.url)
    }

    private var isRenaming: Bool {
        tab.renamingURL == item.url
    }

    private var isTextCoveredByRenaming: Bool {
        guard let renamingURL = tab.renamingURL, renamingURL != item.url else { return false }
        guard let renamingIndex = tab.displayedItems.firstIndex(where: { $0.url == renamingURL }),
              let myIndex = tab.displayedItems.firstIndex(where: { $0.url == item.url }) else {
            return false
        }
        if abs(myIndex - renamingIndex) == 1 {
            let cols = max(1, tab.currentColumns)
            let renamingRow = renamingIndex / cols
            let myRow = myIndex / cols
            if cols > 1 && renamingRow != myRow {
                return false
            }
            return true
        }
        return false
    }

    var body: some View {
        VStack(spacing: 5) {
            ZStack(alignment: .topLeading) {
                Win11ItemIconView(item: item, size: tab.viewMode.iconSize)
                    .opacity((item.isHidden || isCut) ? 0.50 : 1.0)
                    .frame(maxWidth: .infinity)

                // Windows 11 selection checkbox on hover or selection
                if (isHovered || isSelected) && !isRenaming && !isTextCoveredByRenaming {
                    Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                        .font(.system(size: 13))
                        .foregroundStyle(isSelected ? Win11Theme.accentBlue(colorScheme) : .secondary)
                        .padding(2)
                }
            }

            if let progress = downloadManager.progress(for: item) {
                VStack(spacing: 3) {
                    ProgressView(value: max(0.02, min(1.0, progress)))
                        .progressViewStyle(.linear)
                        .tint(Color(red: 0.05, green: 0.52, blue: 0.95))
                        .frame(width: max(44, tab.viewMode.gridCellWidth - 28))
                    Text("\(Int(progress * 100))%")
                        .font(.system(size: 9.5, weight: .bold))
                        .foregroundStyle(Color(red: 0.05, green: 0.52, blue: 0.95))
                }
                .padding(.top, 1)
            } else if isRenaming {
                Win11RenameTextField(
                    text: $tab.renamingText,
                    alignment: .center,
                    onCommit: { tab.commitRenameIfNeeded() },
                    onCancel: { tab.cancelRename() }
                )
                .padding(.horizontal, 5)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(colorScheme == .dark ? Color(red: 0.11, green: 0.11, blue: 0.13) : Color.white)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .stroke(Win11Theme.accentBlue(colorScheme), lineWidth: 1.5)
                )
                .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.65 : 0.2), radius: 6, x: 0, y: 2)
                .frame(minWidth: max(90, tab.viewMode.gridCellWidth - 16), maxWidth: max(180, tab.viewMode.gridCellWidth + 50))
            } else {
                Text(item.displayName(showExtensions: tab.showFileExtensions))
                    .font(.system(size: 12))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .foregroundStyle(.primary)
                    .opacity(isTextCoveredByRenaming ? 0 : 1)
            }
        }
        .padding(8)
        .frame(width: isRenaming ? max(180, tab.viewMode.gridCellWidth + 50) : tab.viewMode.gridCellWidth)
        .zIndex(isRenaming ? 50 : 0)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(isRenaming ? Color.clear : cellBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke((isSelected && !isRenaming) ? Win11Theme.selectionBorder(colorScheme) : Color.clear, lineWidth: 1)
                )
        )
        .background(
            GeometryReader { geo in
                Color.clear.preference(
                    key: ItemGlobalFrameKey.self,
                    value: [item.url: geo.frame(in: .global)]
                )
            }
        )
        .onHover { hovering in
            isHovered = hovering
        }
        .overlay {
            if !isRenaming {
                Win11MouseHandlerView(
                    onSingleClick: { modifiers in
                        windowVM.dismissContextMenu()
                        tab.handleItemClick(item, modifiers: modifiers)
                    },
                    onDoubleClick: {
                        windowVM.openItem(item)
                    },
                    onRightClick: { point in
                        windowVM.presentContextMenu(for: item, at: point)
                    },
                    onDragChanged: onDragChanged,
                    onDragEnded: onDragEnded
                )
            }
        }
    }

    private var cellBackground: Color {
        if isSelected {
            return Win11Theme.selectionFill(colorScheme)
        } else if isHovered {
            return Win11Theme.hoverFill(colorScheme)
        }
        return Color.clear
    }
}

// MARK: - Compact List Row
struct Win11ListItemRow: View {
    let windowVM: ExplorerWindowViewModel
    @ObservedObject var tab: ExplorerTabViewModel
    let item: FileItem
    let isCut: Bool
    var onDragChanged: ((CGPoint, CGPoint) -> Void)? = nil
    var onDragEnded: (() -> Void)? = nil

    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovered: Bool = false
    @ObservedObject private var downloadManager = CloudDownloadManager.shared

    private var isSelected: Bool {
        tab.selectedURLs.contains(item.url)
    }

    private var isRenaming: Bool {
        tab.renamingURL == item.url
    }

    var body: some View {
        HStack(spacing: 8) {
            Win11ItemIconView(item: item, size: 20)
                .opacity((item.isHidden || isCut) ? 0.50 : 1.0)

            if isRenaming {
                Win11RenameTextField(
                    text: $tab.renamingText,
                    alignment: .left,
                    onCommit: { tab.commitRenameIfNeeded() },
                    onCancel: { tab.cancelRename() }
                )
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(colorScheme == .dark ? Color(red: 0.11, green: 0.11, blue: 0.13) : Color.white)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .stroke(Win11Theme.accentBlue(colorScheme), lineWidth: 1.5)
                )
                .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.5 : 0.2), radius: 4, x: 0, y: 1)
                .frame(minWidth: 160, maxWidth: 600)
            } else {
                HStack(spacing: 6) {
                    Text(item.displayName(showExtensions: tab.showFileExtensions))
                        .font(.system(size: 12))
                        .lineLimit(1)

                    if let progress = downloadManager.progress(for: item) {
                        HStack(spacing: 4) {
                            ProgressView(value: max(0.02, min(1.0, progress)))
                                .progressViewStyle(.linear)
                                .tint(Color(red: 0.05, green: 0.52, blue: 0.95))
                                .frame(width: 45)
                            Text("\(Int(progress * 100))%")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(Color(red: 0.05, green: 0.52, blue: 0.95))
                        }
                    }
                }
            }
            Spacer()
        }
        .padding(.horizontal, 8)
        .frame(height: 28)
        .background(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(isSelected ? Win11Theme.selectionFill(colorScheme) : (isHovered ? Win11Theme.hoverFill(colorScheme) : Color.clear))
        )
        .background(
            GeometryReader { geo in
                Color.clear.preference(
                    key: ItemGlobalFrameKey.self,
                    value: [item.url: geo.frame(in: .global)]
                )
            }
        )
        .onHover { hovering in
            isHovered = hovering
        }
        .overlay {
            if !isRenaming {
                Win11MouseHandlerView(
                    onSingleClick: { modifiers in
                        windowVM.dismissContextMenu()
                        tab.handleItemClick(item, modifiers: modifiers)
                    },
                    onDoubleClick: {
                        windowVM.openItem(item)
                    },
                    onRightClick: { point in
                        windowVM.presentContextMenu(for: item, at: point)
                    },
                    onDragChanged: onDragChanged,
                    onDragEnded: onDragEnded
                )
            }
        }
    }
}

// MARK: - Details Table Row
private struct Win11DetailsTableRow: View {
    let windowVM: ExplorerWindowViewModel
    @ObservedObject var tab: ExplorerTabViewModel
    let item: FileItem
    let isCut: Bool
    var onDragChanged: ((CGPoint, CGPoint) -> Void)? = nil
    var onDragEnded: (() -> Void)? = nil

    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovered: Bool = false
    @ObservedObject private var downloadManager = CloudDownloadManager.shared

    private var isSelected: Bool {
        tab.selectedURLs.contains(item.url)
    }

    private var isRenaming: Bool {
        tab.renamingURL == item.url
    }

    var body: some View {
        HStack(spacing: 0) {
            // Name Column
            HStack(spacing: 9) {
                Win11ItemIconView(item: item, size: 19)
                    .opacity((item.isHidden || isCut) ? 0.50 : 1.0)

                if isRenaming {
                    Win11RenameTextField(
                        text: $tab.renamingText,
                        alignment: .left,
                        onCommit: { tab.commitRenameIfNeeded() },
                        onCancel: { tab.cancelRename() }
                    )
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(colorScheme == .dark ? Color(red: 0.11, green: 0.11, blue: 0.13) : Color.white)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .stroke(Win11Theme.accentBlue(colorScheme), lineWidth: 1.5)
                    )
                    .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.5 : 0.2), radius: 4, x: 0, y: 1)
                    .frame(minWidth: 200, maxWidth: .infinity, alignment: .leading)
                } else {
                    HStack(spacing: 6) {
                        Text(item.displayName(showExtensions: tab.showFileExtensions))
                            .font(.system(size: 12.5))
                            .lineLimit(1)
                            .opacity(item.isHidden ? 0.65 : 1.0)

                        if let progress = downloadManager.progress(for: item) {
                            HStack(spacing: 4) {
                                ProgressView(value: max(0.02, min(1.0, progress)))
                                    .progressViewStyle(.linear)
                                    .tint(Color(red: 0.05, green: 0.52, blue: 0.95))
                                    .frame(width: 50)
                                Text("\(Int(progress * 100))%")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(Color(red: 0.05, green: 0.52, blue: 0.95))
                            }
                        }
                    }
                }
            }
            .frame(minWidth: 260, maxWidth: .infinity, alignment: .leading)

            // Date Modified Column
            Text(item.formattedModificationDate)
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .frame(width: 155, alignment: .leading)

            // Type Column
            Text(item.fileTypeDescription)
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(width: 155, alignment: .leading)

            // Size Column
            Text(item.formattedSize)
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .frame(width: 100, alignment: .trailing)
        }
        .padding(.horizontal, 10)
        .frame(height: 30)
        .background(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(rowBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .stroke(isSelected ? Win11Theme.selectionBorder(colorScheme) : Color.clear, lineWidth: 1)
                )
        )
        .background(
            GeometryReader { geo in
                Color.clear.preference(
                    key: ItemGlobalFrameKey.self,
                    value: [item.url: geo.frame(in: .global)]
                )
            }
        )
        .onHover { hovering in
            isHovered = hovering
        }
        .overlay {
            if !isRenaming {
                Win11MouseHandlerView(
                    onSingleClick: { modifiers in
                        windowVM.dismissContextMenu()
                        tab.handleItemClick(item, modifiers: modifiers)
                    },
                    onDoubleClick: {
                        windowVM.openItem(item)
                    },
                    onRightClick: { point in
                        windowVM.presentContextMenu(for: item, at: point)
                    },
                    onDragChanged: onDragChanged,
                    onDragEnded: onDragEnded
                )
            }
        }
    }

    private var rowBackground: Color {
        if isSelected {
            return Win11Theme.selectionFill(colorScheme)
        } else if isHovered {
            return Win11Theme.hoverFill(colorScheme)
        }
        return Color.clear
    }
}

public struct ItemGlobalFrameKey: PreferenceKey {
    public static var defaultValue: [URL: CGRect] = [:]
    public static func reduce(value: inout [URL: CGRect], nextValue: () -> [URL: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}

