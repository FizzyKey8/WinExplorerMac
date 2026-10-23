import SwiftUI
import AppKit

public struct Win11FolderContentView: View {
    @ObservedObject var windowVM: ExplorerWindowViewModel
    @ObservedObject var tab: ExplorerTabViewModel
    @ObservedObject var clipboard: FileClipboardService
    @Environment(\.colorScheme) private var colorScheme

    public init(windowVM: ExplorerWindowViewModel, tab: ExplorerTabViewModel, clipboard: FileClipboardService) {
        self.windowVM = windowVM
        self.tab = tab
        self.clipboard = clipboard
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
                }
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

        return ScrollView(.vertical) {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
                ForEach(tab.displayedItems) { item in
                    Win11GridItemCell(
                        windowVM: windowVM,
                        tab: tab,
                        item: item,
                        isCut: clipboard.isItemCut(item.url)
                    )
                }
            }
            .padding(16)
        }
    }

    // MARK: - 2. Compact List View
    private var compactListView: some View {
        let columns = [GridItem(.adaptive(minimum: 230, maximum: 280), spacing: 8)]

        return ScrollView(.vertical) {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 4) {
                ForEach(tab.displayedItems) { item in
                    Win11ListItemRow(
                        windowVM: windowVM,
                        tab: tab,
                        item: item,
                        isCut: clipboard.isItemCut(item.url)
                    )
                }
            }
            .padding(14)
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
            ScrollView(.vertical) {
                LazyVStack(spacing: 1) {
                    ForEach(tab.displayedItems) { item in
                        Win11DetailsTableRow(
                            windowVM: windowVM,
                            tab: tab,
                            item: item,
                            isCut: clipboard.isItemCut(item.url)
                        )
                    }

                    // Bottom empty area inside scroll view that still responds to right-click on folder background
                    Win11MouseHandlerView(
                        onSingleClick: { _ in
                            windowVM.dismissContextMenu()
                            tab.clearSelection()
                        },
                        onDoubleClick: nil,
                        onRightClick: { point in
                            windowVM.presentContextMenu(for: nil, at: point)
                        }
                    )
                    .frame(minHeight: 120)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
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
private struct Win11GridItemCell: View {
    let windowVM: ExplorerWindowViewModel
    @ObservedObject var tab: ExplorerTabViewModel
    let item: FileItem
    let isCut: Bool

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
        VStack(spacing: 5) {
            ZStack(alignment: .topLeading) {
                Win11ItemIconView(item: item, size: tab.viewMode.iconSize)
                    .opacity((item.isHidden || isCut) ? 0.50 : 1.0)
                    .frame(maxWidth: .infinity)

                // Windows 11 selection checkbox on hover or selection
                if isHovered || isSelected {
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
                TextField("", text: $tab.renamingText)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11.5))
                    .multilineTextAlignment(.center)
                    .onSubmit {
                        tab.commitRenameIfNeeded()
                    }
                    .onExitCommand {
                        tab.cancelRename()
                    }
            } else {
                Text(item.displayName(showExtensions: tab.showFileExtensions))
                    .font(.system(size: 12))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .foregroundStyle(.primary)
            }
        }
        .padding(8)
        .frame(width: tab.viewMode.gridCellWidth)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(cellBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(isSelected ? Win11Theme.selectionBorder(colorScheme) : Color.clear, lineWidth: 1)
                )
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
                    }
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
private struct Win11ListItemRow: View {
    let windowVM: ExplorerWindowViewModel
    @ObservedObject var tab: ExplorerTabViewModel
    let item: FileItem
    let isCut: Bool

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
                TextField("", text: $tab.renamingText)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12))
                    .onSubmit {
                        tab.commitRenameIfNeeded()
                    }
                    .onExitCommand {
                        tab.cancelRename()
                    }
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
                    }
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
                    TextField("", text: $tab.renamingText)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12))
                        .onSubmit {
                            tab.commitRenameIfNeeded()
                        }
                        .onExitCommand {
                            tab.cancelRename()
                        }
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
                    }
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
