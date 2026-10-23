import Foundation
import SwiftUI
import Combine
import AppKit

public struct ContextMenuRequest: Identifiable {
    public let id = UUID()
    public let targetItem: FileItem?
    public let locationInWindow: CGPoint
}

public final class ExplorerWindowViewModel: ObservableObject {
    @Published public var tabs: [ExplorerTabViewModel] {
        didSet {
            bindTabObservers()
        }
    }
    @Published public var activeTabId: UUID
    @Published public var sidePaneMode: ExplorerSidePaneMode = .none
    @Published public var isSidebarVisible: Bool = true

    @Published public var clipboard = FileClipboardService()
    @Published public var quickAccess = QuickAccessStore()
    @Published public var volumes: [VolumeInfo] = []
    @Published public var cloudDrives: [CloudDriveInfo] = []

    // Custom Windows 11 Context Menu & Modals
    @Published public var activeContextMenu: ContextMenuRequest? = nil
    @Published public var propertiesTargetItem: FileItem? = nil
    @Published public var extractZipSourceURL: URL? = nil
    @Published public var isEditingAddressBar: Bool = false

    private var tabCancellables: [UUID: AnyCancellable] = [:]
    private var serviceCancellables = Set<AnyCancellable>()

    public init() {
        let initialTab = ExplorerTabViewModel(initialDestination: .home)
        self.tabs = [initialTab]
        self.activeTabId = initialTab.id
        bindTabObservers()
        clipboard.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &serviceCancellables)
        ThemeManager.shared.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &serviceCancellables)
        refreshVolumes()

        NotificationCenter.default.addObserver(
            forName: .win11NavigateToURL,
            object: nil,
            queue: .main
        ) { [weak self] notif in
            guard let self else { return }
            guard let dirURL = notif.userInfo?["directory"] as? URL else { return }
            let selectURL = notif.userInfo?["select"] as? URL
            self.navigateActiveTab(to: dirURL, selecting: selectURL)
        }
    }

    public func navigateActiveTab(to directoryURL: URL, selecting fileURL: URL? = nil) {
        let dest = NavigationDestination.directory(directoryURL.cleanFileURL)
        if activeTab.destination != dest {
            activeTab.navigate(to: dest)
        }
        if let fileURL {
            let clean = fileURL.cleanFileURL
            activeTab.selectedURLs = [clean]
            activeTab.lastClickedURL = clean
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                self?.activeTab.selectedURLs = [clean]
                self?.activeTab.lastClickedURL = clean
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.activeTab.selectedURLs = [clean]
                self?.activeTab.lastClickedURL = clean
            }
        } else {
            activeTab.selectedURLs.removeAll()
            activeTab.lastClickedURL = nil
        }
    }

    private func bindTabObservers() {
        let currentIds = Set(tabs.map(\.id))
        tabCancellables = tabCancellables.filter { currentIds.contains($0.key) }
        for tab in tabs where tabCancellables[tab.id] == nil {
            tabCancellables[tab.id] = tab.objectWillChange.sink { [weak self] _ in
                self?.objectWillChange.send()
            }
        }
    }

    public var activeTab: ExplorerTabViewModel {
        tabs.first(where: { $0.id == activeTabId }) ?? tabs[0]
    }

    public func refreshVolumes() {
        volumes = FileSystemService.shared.mountedVolumes()
        cloudDrives = FileSystemService.shared.cloudDrives()
    }

    // MARK: - Tab Management (Windows 11 Tabs)
    public func createNewTab(at destination: NavigationDestination = .home, activate: Bool = true) {
        let inheritedTab = activeTab
        let newTab = ExplorerTabViewModel(
            initialDestination: destination,
            viewMode: inheritedTab.viewMode,
            showHiddenFiles: inheritedTab.showHiddenFiles,
            showFileExtensions: inheritedTab.showFileExtensions
        )
        tabs.append(newTab)
        if activate {
            activeTabId = newTab.id
        }
    }

    public func duplicateTab(_ tab: ExplorerTabViewModel) {
        let duplicated = ExplorerTabViewModel(
            initialDestination: tab.destination,
            viewMode: tab.viewMode,
            showHiddenFiles: tab.showHiddenFiles,
            showFileExtensions: tab.showFileExtensions
        )
        if let index = tabs.firstIndex(where: { $0.id == tab.id }) {
            tabs.insert(duplicated, at: index + 1)
        } else {
            tabs.append(duplicated)
        }
        activeTabId = duplicated.id
    }

    public func closeTab(id: UUID) {
        guard tabs.count > 1 else {
            // If last tab is closed, reset it to Home
            activeTab.navigate(to: .home)
            return
        }
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        let wasActive = (activeTabId == id)
        tabs.remove(at: index)
        if wasActive {
            let nextIndex = min(index, tabs.count - 1)
            activeTabId = tabs[nextIndex].id
        }
    }

    public func closeOtherTabs(keepingId: UUID) {
        tabs.removeAll { $0.id != keepingId }
        activeTabId = keepingId
    }

    public func selectTab(id: UUID) {
        activeContextMenu = nil
        activeTabId = id
    }

    // MARK: - File Operations on Active Tab
    public func navigateArrows(direction: ArrowKeyDirection, extendSelection: Bool) {
        activeContextMenu = nil
        let tab = activeTab
        switch tab.destination {
        case .directory:
            tab.navigateArrows(direction: direction, extendSelection: extendSelection)
        case .home:
            navigateHomeArrows(direction: direction, extendSelection: extendSelection)
        case .thisPC:
            var thisPCItems: [FileItem] = []
            for vol in volumes {
                if let fi = FileSystemService.shared.makeFileItem(from: vol.url, customDisplayName: vol.name) {
                    thisPCItems.append(fi)
                }
            }
            for cloud in cloudDrives {
                if let fi = FileSystemService.shared.makeFileItem(from: cloud.url, customDisplayName: cloud.name) {
                    thisPCItems.append(fi)
                }
            }
            let driveCols = max(1, Int((max(200, tab.contentWidth - 40) + 14) / (270 + 14)))
            tab.navigateArrows(direction: direction, extendSelection: extendSelection, itemsOverride: thisPCItems, columns: driveCols)
        }
    }

    public func navigateHomeArrows(direction: ArrowKeyDirection, extendSelection: Bool) {
        let tab = activeTab
        let pinnedItems: [FileItem] = quickAccess.pinnedFolders.compactMap {
            FileSystemService.shared.makeFileItem(from: $0.url)
        }
        let recentItems: [FileItem] = quickAccess.recentFiles.compactMap {
            FileSystemService.shared.makeFileItem(from: $0.url)
        }

        guard !pinnedItems.isEmpty || !recentItems.isEmpty else { return }

        // Determine column count for Pinned folders (220-260px wide + 12 spacing)
        let availableWidth = max(200, tab.contentWidth - 40)
        let pinnedCols = max(1, Int((availableWidth + 12) / (220 + 12)))

        // Determine column count for Recent files
        let recentCols: Int
        switch tab.viewMode {
        case .details:
            recentCols = 1
        case .list:
            recentCols = max(1, Int((availableWidth + 8) / (230 + 8)))
        case .extraLargeIcons, .largeIcons, .mediumIcons:
            let cellW = tab.viewMode.gridCellWidth
            recentCols = max(1, Int((availableWidth + 10) / (cellW + 10)))
        }

        let currentURL = tab.lastClickedURL ?? tab.selectedURLs.first
        let pinnedIndex = currentURL.flatMap { url in pinnedItems.firstIndex(where: { $0.url == url }) }
        let recentIndex = currentURL.flatMap { url in recentItems.firstIndex(where: { $0.url == url }) }

        let targetItem: FileItem

        if let pIdx = pinnedIndex {
            // Inside Pinned Folders
            switch direction {
            case .left:
                if pIdx > 0 {
                    targetItem = pinnedItems[pIdx - 1]
                } else {
                    return
                }
            case .right:
                if pIdx < pinnedItems.count - 1 {
                    targetItem = pinnedItems[pIdx + 1]
                } else {
                    return
                }
            case .up:
                if pIdx - pinnedCols >= 0 {
                    targetItem = pinnedItems[pIdx - pinnedCols]
                } else {
                    return
                }
            case .down:
                if pIdx + pinnedCols < pinnedItems.count {
                    targetItem = pinnedItems[pIdx + pinnedCols]
                } else if !recentItems.isEmpty {
                    let colPos = pIdx % pinnedCols
                    let targetRecent = min(recentItems.count - 1, colPos)
                    targetItem = recentItems[targetRecent]
                } else {
                    return
                }
            }
        } else if let rIdx = recentIndex {
            // Inside Recent Files
            switch direction {
            case .left:
                if rIdx > 0 {
                    targetItem = recentItems[rIdx - 1]
                } else {
                    return
                }
            case .right:
                if rIdx < recentItems.count - 1 {
                    targetItem = recentItems[rIdx + 1]
                } else {
                    return
                }
            case .down:
                if recentCols <= 1 {
                    if rIdx + 1 < recentItems.count {
                        targetItem = recentItems[rIdx + 1]
                    } else {
                        return
                    }
                } else {
                    if rIdx + recentCols < recentItems.count {
                        targetItem = recentItems[rIdx + recentCols]
                    } else {
                        return
                    }
                }
            case .up:
                if recentCols <= 1 {
                    if rIdx > 0 {
                        targetItem = recentItems[rIdx - 1]
                    } else if !pinnedItems.isEmpty {
                        let lastRowStart = (pinnedItems.count - 1) / pinnedCols * pinnedCols
                        targetItem = pinnedItems[min(pinnedItems.count - 1, lastRowStart)]
                    } else {
                        return
                    }
                } else {
                    if rIdx - recentCols >= 0 {
                        targetItem = recentItems[rIdx - recentCols]
                    } else if !pinnedItems.isEmpty {
                        let colPos = rIdx % recentCols
                        let lastRowStart = (pinnedItems.count - 1) / pinnedCols * pinnedCols
                        let target = min(pinnedItems.count - 1, lastRowStart + (colPos % pinnedCols))
                        targetItem = pinnedItems[target]
                    } else {
                        return
                    }
                }
            }
        } else {
            // No selection yet
            switch direction {
            case .up, .left:
                targetItem = recentItems.last ?? pinnedItems.last!
            case .down, .right:
                targetItem = pinnedItems.first ?? recentItems.first!
            }
        }

        tab.selectedURLs = [targetItem.url]
        tab.lastClickedURL = targetItem.url
    }

    public func openCurrentSelection() {
        activeContextMenu = nil
        let tab = activeTab

        if tab.renamingURL != nil {
            tab.commitRenameIfNeeded()
            return
        }

        if tab.selectedURLs.isEmpty, let lastURL = tab.lastClickedURL {
            tab.selectedURLs.insert(lastURL)
        }

        guard !tab.selectedURLs.isEmpty else { return }

        var itemsToOpen: [FileItem] = []
        for item in tab.displayedItems where tab.selectedURLs.contains(item.url) {
            itemsToOpen.append(item)
        }

        if itemsToOpen.isEmpty {
            for pinned in quickAccess.pinnedFolders where tab.selectedURLs.contains(pinned.url) {
                if let fileItem = FileSystemService.shared.makeFileItem(from: pinned.url) {
                    itemsToOpen.append(fileItem)
                }
            }
            for recent in quickAccess.recentFiles where tab.selectedURLs.contains(recent.url) {
                if let fileItem = FileSystemService.shared.makeFileItem(from: recent.url) {
                    itemsToOpen.append(fileItem)
                }
            }
        }

        if itemsToOpen.isEmpty {
            for vol in volumes where tab.selectedURLs.contains(vol.url) {
                if let fileItem = FileSystemService.shared.makeFileItem(from: vol.url, customDisplayName: vol.name) {
                    itemsToOpen.append(fileItem)
                }
            }
            for cloud in cloudDrives where tab.selectedURLs.contains(cloud.url) {
                if let fileItem = FileSystemService.shared.makeFileItem(from: cloud.url, customDisplayName: cloud.name) {
                    itemsToOpen.append(fileItem)
                }
            }
        }

        if itemsToOpen.isEmpty {
            for url in tab.selectedURLs {
                if let fileItem = FileSystemService.shared.makeFileItem(from: url) {
                    itemsToOpen.append(fileItem)
                }
            }
        }

        if itemsToOpen.count == 1, let single = itemsToOpen.first, single.isDirectory {
            openItem(single)
            return
        }

        for item in itemsToOpen {
            openItem(item)
        }
    }

    public func openItem(_ item: FileItem, inNewTab: Bool = false, withApplication appURL: URL? = nil) {
        activeContextMenu = nil
        if item.isDirectory {
            if inNewTab {
                createNewTab(at: .directory(item.url), activate: true)
            } else {
                activeTab.navigate(to: .directory(item.url))
            }
        } else {
            let tab = activeTab
            DispatchQueue.main.async { [weak self] in
                self?.quickAccess.recordRecentFile(item.url)
            }
            FileSystemService.shared.openFileItem(
                item,
                withApplication: appURL,
                onStatus: { [weak tab] msg in
                    tab?.statusMessage = msg
                },
                onError: { [weak tab] err in
                    tab?.errorMessage = err
                }
            )
        }
    }

    public func createNewItem(_ template: NewItemTemplate) {
        activeContextMenu = nil
        guard let dir = activeTab.currentDirectoryURL else { return }
        do {
            let newURL = try FileSystemService.shared.createNewItem(in: dir, template: template)
            activeTab.reload()
            activeTab.selectedURLs = [newURL]
            if let createdItem = FileSystemService.shared.makeFileItem(from: newURL) {
                activeTab.beginRename(for: createdItem)
            }
        } catch {
            activeTab.errorMessage = error.localizedDescription
        }
    }

    public func copySelection() {
        activeContextMenu = nil
        let urls = Array(activeTab.selectedURLs)
        guard !urls.isEmpty else { return }
        clipboard.copy(urls)
        activeTab.statusMessage = "\(urls.count) elemento(s) copiado(s) al portapapeles"
    }

    public func cutSelection() {
        activeContextMenu = nil
        let urls = Array(activeTab.selectedURLs)
        guard !urls.isEmpty else { return }
        clipboard.cut(urls)
        activeTab.statusMessage = "\(urls.count) elemento(s) cortado(s)"
        objectWillChange.send()
    }

    public func pasteIntoCurrentDirectory(targetFolderOverride: URL? = nil) {
        activeContextMenu = nil
        guard let destinationDir = targetFolderOverride ?? activeTab.currentDirectoryURL else { return }
        let payload = clipboard.currentItemsForPaste()
        guard !payload.urls.isEmpty else { return }

        do {
            let pastedURLs = try FileSystemService.shared.copyOrMoveItems(
                payload.urls,
                to: destinationDir,
                isCutOperation: payload.isCut
            )
            clipboard.completeCutOperationIfNeeded()
            for tab in tabs {
                tab.reload()
            }
            activeTab.selectedURLs = Set(pastedURLs)
            activeTab.statusMessage = "\(pastedURLs.count) elemento(s) pegado(s)"
        } catch {
            activeTab.errorMessage = error.localizedDescription
        }
    }

    public func moveSelectedToTrash() {
        activeContextMenu = nil
        let urls = Array(activeTab.selectedURLs)
        guard !urls.isEmpty else { return }
        do {
            try FileSystemService.shared.moveToTrash(urls)
            activeTab.selectedURLs.removeAll()
            activeTab.reload()
        } catch {
            activeTab.errorMessage = error.localizedDescription
        }
    }

    public func compressSelectedToZip() {
        activeContextMenu = nil
        guard let dir = activeTab.currentDirectoryURL else { return }
        let urls = Array(activeTab.selectedURLs)
        guard !urls.isEmpty else { return }
        do {
            let zipURL = try ArchiveService.shared.compressToZip(items: urls, in: dir)
            activeTab.reload()
            activeTab.selectedURLs = [zipURL]
            if let zipItem = FileSystemService.shared.makeFileItem(from: zipURL) {
                activeTab.beginRename(for: zipItem)
            }
        } catch {
            activeTab.errorMessage = error.localizedDescription
        }
    }

    public func promptExtractZip(for url: URL) {
        activeContextMenu = nil
        extractZipSourceURL = url
    }

    public func showProperties(for item: FileItem? = nil) {
        activeContextMenu = nil
        if let item {
            propertiesTargetItem = item
            return
        }
        if let firstSelected = activeTab.selectedFileItems.first {
            propertiesTargetItem = firstSelected
            return
        }
        if let currentDir = activeTab.currentDirectoryURL,
           let dirItem = FileSystemService.shared.makeFileItem(from: currentDir) {
            propertiesTargetItem = dirItem
        }
    }

    public func shareItems(_ urls: [URL]) {
        activeContextMenu = nil
        guard !urls.isEmpty,
              let contentView = NSApp.keyWindow?.contentView else { return }
        let picker = NSSharingServicePicker(items: urls)
        picker.show(relativeTo: .zero, of: contentView, preferredEdge: .minY)
    }

    // MARK: - Cloud Storage Free Up Space / Download
    public func freeUpSpaceForSelection() {
        activeContextMenu = nil
        let tab = activeTab
        let items = tab.selectedFileItems
        guard !items.isEmpty else { return }

        // Instantly transition badges to blue cloud (0ms delay, no beachball)
        CloudDownloadManager.shared.evictAll(items: items)
        tab.statusMessage = "Liberando espacio de \(items.count) elemento(s)..."

        Task.detached(priority: .userInitiated) {
            for item in items {
                try? FileSystemService.shared.freeUpCloudSpace(at: item.url)
            }
            await MainActor.run {
                tab.statusMessage = "Espacio liberado. Los archivos están en la nube."
            }
        }
    }

    public func freeUpSpaceForCurrentFolder() {
        activeContextMenu = nil
        let tab = activeTab
        guard let dir = tab.currentDirectoryURL else { return }

        // Instantly transition all items in current folder to blue cloud
        CloudDownloadManager.shared.evictAll(items: tab.items)
        tab.statusMessage = "Liberando espacio de esta carpeta..."

        Task.detached(priority: .userInitiated) {
            try? FileSystemService.shared.freeUpCloudSpace(at: dir)
            await MainActor.run {
                tab.statusMessage = "Espacio liberado para toda la carpeta."
            }
        }
    }

    public func downloadSelection() {
        activeContextMenu = nil
        let tab = activeTab
        let items = tab.selectedFileItems.filter { !CloudDownloadManager.shared.isDownloaded(item: $0) }
        guard !items.isEmpty else { return }

        for item in items {
            FileSystemService.shared.openFileItem(
                item,
                withApplication: nil,
                onStatus: { [weak tab] msg in
                    tab?.statusMessage = msg
                },
                onError: { [weak tab] err in
                    tab?.errorMessage = err
                }
            )
        }
    }

    // MARK: - Context Menu Trigger
    public func presentContextMenu(for item: FileItem?, at location: CGPoint) {
        if let item {
            if !activeTab.selectedURLs.contains(item.url) {
                activeTab.selectedURLs = [item.url]
                activeTab.lastClickedURL = item.url
            }
        }
        withAnimation(.easeOut(duration: 0.12)) {
            activeContextMenu = ContextMenuRequest(targetItem: item, locationInWindow: location)
        }
    }

    public func dismissContextMenu() {
        if activeContextMenu != nil {
            withAnimation(.easeOut(duration: 0.1)) {
                activeContextMenu = nil
            }
        }
    }
}
