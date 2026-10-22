import Foundation
import SwiftUI
import AppKit

public struct ContextMenuRequest: Identifiable {
    public let id = UUID()
    public let targetItem: FileItem?
    public let locationInWindow: CGPoint
}

public final class ExplorerWindowViewModel: ObservableObject {
    @Published public var tabs: [ExplorerTabViewModel]
    @Published public var activeTabId: UUID
    @Published public var sidePaneMode: ExplorerSidePaneMode = .none
    @Published public var isSidebarVisible: Bool = true

    @Published public var clipboard = FileClipboardService()
    @Published public var quickAccess = QuickAccessStore()
    @Published public var volumes: [VolumeInfo] = []

    // Custom Windows 11 Context Menu & Modals
    @Published public var activeContextMenu: ContextMenuRequest? = nil
    @Published public var propertiesTargetItem: FileItem? = nil
    @Published public var extractZipSourceURL: URL? = nil
    @Published public var isEditingAddressBar: Bool = false

    public init() {
        let initialTab = ExplorerTabViewModel(initialDestination: .home)
        self.tabs = [initialTab]
        self.activeTabId = initialTab.id
        refreshVolumes()
    }

    public var activeTab: ExplorerTabViewModel {
        tabs.first(where: { $0.id == activeTabId }) ?? tabs[0]
    }

    public func refreshVolumes() {
        volumes = FileSystemService.shared.mountedVolumes()
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
    public func openItem(_ item: FileItem, inNewTab: Bool = false) {
        activeContextMenu = nil
        if item.isDirectory {
            if inNewTab {
                createNewTab(at: .directory(item.url), activate: true)
            } else {
                activeTab.navigate(to: .directory(item.url))
            }
        } else {
            quickAccess.recordRecentFile(item.url)
            FileSystemService.shared.openItem(item.url)
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
