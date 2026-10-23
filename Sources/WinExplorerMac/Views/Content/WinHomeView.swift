import SwiftUI

public struct Win11HomeView: View {
    @ObservedObject var windowVM: ExplorerWindowViewModel
    @ObservedObject var tab: ExplorerTabViewModel
    @ObservedObject var quickAccess: QuickAccessStore
    @Environment(\.colorScheme) private var colorScheme

    @State private var isQuickAccessExpanded: Bool = true
    @State private var isFavoritesExpanded: Bool = true
    @State private var isRecentsExpanded: Bool = true

    // Mouse drag marquee selection states
    @State private var globalMarqueeRect: CGRect? = nil
    @State private var dragInitialSelection: Set<URL> = []
    @State private var itemFrames: [URL: CGRect] = [:]
    @State private var containerOrigin: CGPoint = .zero

    private let columns = [
        GridItem(.adaptive(minimum: 220, maximum: 260), spacing: 12)
    ]

    public init(windowVM: ExplorerWindowViewModel, tab: ExplorerTabViewModel, quickAccess: QuickAccessStore) {
        self.windowVM = windowVM
        self.tab = tab
        self.quickAccess = quickAccess
    }

    private func handleDragChanged(start: CGPoint, current: CGPoint) {
        if dragInitialSelection.isEmpty && globalMarqueeRect == nil {
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
        ScrollViewReader { scrollProxy in
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

                    VStack(alignment: .leading, spacing: 22) {
                        // Section 1: Acceso rápido (Pinned folders cards like Windows 11 Home)
                        DisclosureGroup(isExpanded: $isQuickAccessExpanded) {
                            LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
                                ForEach(quickAccess.pinnedFolders) { pinned in
                                    quickAccessCard(for: pinned)
                                        .id(pinned.url)
                                }
                            }
                            .padding(.top, 10)
                        } label: {
                            Text("Acceso rápido")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.primary)
                        }

                        Divider()

                        // Section 2: Recientes (Recent files visited/opened)
                        DisclosureGroup(isExpanded: $isRecentsExpanded) {
                            if quickAccess.recentFiles.isEmpty {
                                HStack(spacing: 12) {
                                    Image(systemName: "clock.arrow.circlepath")
                                        .font(.system(size: 20))
                                        .foregroundStyle(.secondary)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Aún no hay archivos recientes")
                                            .font(.system(size: 12.5, weight: .medium))
                                        Text("Los archivos que abras desde el explorador aparecerán aquí para un acceso inmediato.")
                                            .font(.system(size: 11.5))
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .padding(.vertical, 18)
                            } else {
                                switch tab.viewMode {
                                case .extraLargeIcons, .largeIcons, .mediumIcons:
                                    let cellWidth = tab.viewMode.gridCellWidth
                                    let gridCols = [GridItem(.adaptive(minimum: cellWidth, maximum: cellWidth + 24), spacing: 10)]
                                    LazyVGrid(columns: gridCols, alignment: .leading, spacing: 12) {
                                        ForEach(quickAccess.recentFiles) { record in
                                            let fileItem = FileSystemService.shared.makeFileItem(from: record)
                                            Win11GridItemCell(
                                                windowVM: windowVM,
                                                tab: tab,
                                                item: fileItem,
                                                isCut: windowVM.clipboard.isItemCut(fileItem.url),
                                                onDragChanged: handleDragChanged,
                                                onDragEnded: handleDragEnded
                                            )
                                            .id(fileItem.url)
                                            .zIndex(tab.renamingURL == fileItem.url ? 999 : 0)
                                        }
                                    }
                                    .padding(.top, 8)

                                case .list:
                                    let listCols = [GridItem(.adaptive(minimum: 230, maximum: 280), spacing: 8)]
                                    LazyVGrid(columns: listCols, alignment: .leading, spacing: 4) {
                                        ForEach(quickAccess.recentFiles) { record in
                                            let fileItem = FileSystemService.shared.makeFileItem(from: record)
                                            Win11ListItemRow(
                                                windowVM: windowVM,
                                                tab: tab,
                                                item: fileItem,
                                                isCut: windowVM.clipboard.isItemCut(fileItem.url),
                                                onDragChanged: handleDragChanged,
                                                onDragEnded: handleDragEnded
                                            )
                                            .id(fileItem.url)
                                            .zIndex(tab.renamingURL == fileItem.url ? 999 : 0)
                                        }
                                    }
                                    .padding(.top, 8)

                                case .details:
                                    VStack(spacing: 0) {
                                        HStack {
                                            Text("Nombre")
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                            Text("Fecha de acceso")
                                                .frame(width: 150, alignment: .leading)
                                            Text("Ubicación")
                                                .frame(width: 240, alignment: .leading)
                                        }
                                        .font(.system(size: 11.5, weight: .medium))
                                        .foregroundStyle(.secondary)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)

                                        Divider()

                                        ForEach(quickAccess.recentFiles) { record in
                                            let fileItem = FileSystemService.shared.makeFileItem(from: record)
                                            recentFileRow(item: fileItem, accessedAt: record.accessedAt)
                                                .id(fileItem.url)
                                                .zIndex(tab.renamingURL == fileItem.url ? 999 : 0)
                                        }
                                    }
                                    .padding(.top, 8)
                                }
                            }
                        } label: {
                            HStack(spacing: 10) {
                                Text("Recientes")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(.primary)

                                Spacer()

                                // Quick view mode switcher buttons right in the Recientes section
                                HStack(spacing: 2) {
                                    Button {
                                        tab.viewMode = .details
                                    } label: {
                                        Image(systemName: "tablecells")
                                            .font(.system(size: 11.5))
                                            .foregroundStyle(tab.viewMode == .details ? Win11Theme.accentBlue(colorScheme) : .secondary)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 3)
                                            .background(tab.viewMode == .details ? Win11Theme.selectionFill(colorScheme) : Color.clear, in: RoundedRectangle(cornerRadius: 4))
                                    }
                                    .buttonStyle(.plain)
                                    .help("Detalles (lista con fecha y ubicación)")

                                    Button {
                                        tab.viewMode = .largeIcons
                                    } label: {
                                        Image(systemName: "square.grid.2x2")
                                            .font(.system(size: 11.5))
                                            .foregroundStyle((tab.viewMode == .largeIcons || tab.viewMode == .extraLargeIcons || tab.viewMode == .mediumIcons) ? Win11Theme.accentBlue(colorScheme) : .secondary)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 3)
                                            .background((tab.viewMode == .largeIcons || tab.viewMode == .extraLargeIcons || tab.viewMode == .mediumIcons) ? Win11Theme.selectionFill(colorScheme) : Color.clear, in: RoundedRectangle(cornerRadius: 4))
                                    }
                                    .buttonStyle(.plain)
                                    .help("Iconos grandes")
                                }
                                .padding(.trailing, 4)

                                if !quickAccess.recentFiles.isEmpty {
                                    Button("Borrar historial") {
                                        quickAccess.clearRecents()
                                    }
                                    .buttonStyle(.plain)
                                    .font(.system(size: 11.5))
                                    .foregroundStyle(Win11Theme.accentBlue(colorScheme))
                                }
                            }
                        }
                    }
                    .padding(20)
                }
                .frame(maxWidth: .infinity, minHeight: 500, alignment: .topLeading)
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
            .onChange(of: tab.lastClickedURL) { _, targetURL in
                if let targetURL {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        scrollProxy.scrollTo(targetURL, anchor: nil)
                    }
                }
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
    }

    private func quickAccessCard(for pinned: PinnedFolderItem) -> some View {
        let isSelected = tab.selectedURLs.contains(pinned.url)
        let fileItem = FileSystemService.shared.makeFileItem(from: pinned.url)

        return HStack(spacing: 12) {
            if let fileItem {
                Win11ItemIconView(item: fileItem, size: 42)
            } else {
                Win11FolderIconView(size: 42)
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Text(pinned.title)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                    Image(systemName: "pin.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(45))
                }

                Text(pinned.locationSubtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(isSelected ? Win11Theme.selectionFill(colorScheme) : Win11Theme.cardBackground(colorScheme))
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(
                            isSelected ? Win11Theme.selectionBorder(colorScheme) : Win11Theme.subtleBorder(colorScheme),
                            lineWidth: 1
                        )
                )
        )
        .background(
            GeometryReader { geo in
                Color.clear.preference(
                    key: ItemGlobalFrameKey.self,
                    value: [pinned.url: geo.frame(in: .global)]
                )
            }
        )
        .overlay(
            Win11MouseHandlerView(
                onSingleClick: { modifiers in
                    if modifiers.contains(.shift) || modifiers.contains(.command) {
                        if tab.selectedURLs.contains(pinned.url) {
                            tab.selectedURLs.remove(pinned.url)
                        } else {
                            tab.selectedURLs.insert(pinned.url)
                        }
                    } else {
                        tab.selectedURLs = [pinned.url]
                    }
                    tab.lastClickedURL = pinned.url
                },
                onDoubleClick: {
                    tab.navigate(to: .directory(pinned.url))
                },
                onRightClick: { point in
                    if let fileItem {
                        windowVM.presentContextMenu(for: fileItem, at: point)
                    }
                },
                onDragChanged: handleDragChanged,
                onDragEnded: handleDragEnded
            )
        )
    }

    private func recentFileRow(item: FileItem, accessedAt: Date) -> some View {
        let isSelected = tab.selectedURLs.contains(item.url)
        let isRenaming = tab.renamingURL == item.url

        return HStack {
            HStack(spacing: 10) {
                Win11ItemIconView(item: item, size: 20)
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
                    Text(item.displayName(showExtensions: tab.showFileExtensions))
                        .font(.system(size: 12.5))
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(item.modificationDate.map { FileItem.formatDate($0) } ?? FileItem.formatDate(accessedAt))
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .frame(width: 150, alignment: .leading)

            Text(displayLocation(for: item.url))
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(width: 240, alignment: .leading)
        }
        .padding(.horizontal, 10)
        .frame(height: 32)
        .background(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(isSelected ? Win11Theme.selectionFill(colorScheme) : Color.clear)
        )
        .background(
            GeometryReader { geo in
                Color.clear.preference(
                    key: ItemGlobalFrameKey.self,
                    value: [item.url: geo.frame(in: .global)]
                )
            }
        )
        .overlay {
            if !isRenaming {
                Win11MouseHandlerView(
                    onSingleClick: { modifiers in
                        if modifiers.contains(.shift) || modifiers.contains(.command) {
                            if tab.selectedURLs.contains(item.url) {
                                tab.selectedURLs.remove(item.url)
                            } else {
                                tab.selectedURLs.insert(item.url)
                            }
                        } else {
                            tab.selectedURLs = [item.url]
                        }
                        tab.lastClickedURL = item.url
                    },
                    onDoubleClick: {
                        windowVM.openItem(item)
                    },
                    onRightClick: { point in
                        windowVM.presentContextMenu(for: item, at: point)
                    },
                    onDragChanged: handleDragChanged,
                    onDragEnded: handleDragEnded
                )
            }
        }
    }

    private func displayLocation(for url: URL) -> String {
        let parent = url.deletingLastPathComponent().cleanFileURL
        let home = FileManager.default.homeDirectoryForCurrentUser.cleanFileURL
        if parent.path == FileSystemService.iCloudDriveURL.path {
            return "iCloud Drive"
        }
        if parent.path.hasPrefix(FileSystemService.iCloudDriveURL.path) {
            let relative = String(parent.path.dropFirst(FileSystemService.iCloudDriveURL.path.count))
            return "iCloud Drive" + relative
        }
        if parent.path.hasPrefix(FileSystemService.cloudStorageRootURL.path) {
            let relative = String(parent.path.dropFirst(FileSystemService.cloudStorageRootURL.path.count + 1))
            let parts = relative.split(separator: "/", maxSplits: 1).map(String.init)
            if let provider = parts.first {
                let friendlyName = FileSystemService.parseCloudProviderFolderName(provider).name
                if parts.count > 1 {
                    return "\(friendlyName) > \(parts[1])"
                }
                return friendlyName
            }
        }
        if parent.path.hasPrefix(home.path) {
            let relative = String(parent.path.dropFirst(home.path.count))
            return "~" + relative
        }
        return parent.path
    }
}
