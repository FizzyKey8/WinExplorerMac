import Foundation
import Combine
import AppKit

public final class ExplorerTabViewModel: ObservableObject, Identifiable {
    public let id: UUID
    @Published public private(set) var destination: NavigationDestination
    @Published public private(set) var backStack: [NavigationDestination] = []
    @Published public private(set) var forwardStack: [NavigationDestination] = []

    @Published public private(set) var items: [FileItem] = []
    @Published public var selectedURLs: Set<URL> = []
    @Published public var lastClickedURL: URL? = nil

    @Published public var searchQuery: String = ""
    @Published public var viewMode: ExplorerViewMode = .details
    @Published public var sortField: ExplorerSortField = .name
    @Published public var sortAscending: Bool = true
    @Published public var showHiddenFiles: Bool = false
    @Published public var showFileExtensions: Bool = true

    @Published public var renamingURL: URL? = nil
    @Published public var renamingText: String = ""

    @Published public var statusMessage: String? = nil
    @Published public var errorMessage: String? = nil

    private var directoryMonitorSource: DispatchSourceFileSystemObject?
    private var directoryFileDescriptor: Int32 = -1

    public init(
        id: UUID = UUID(),
        initialDestination: NavigationDestination = .home,
        viewMode: ExplorerViewMode = .details,
        showHiddenFiles: Bool = false,
        showFileExtensions: Bool = true
    ) {
        self.id = id
        self.destination = initialDestination
        self.viewMode = viewMode
        self.showHiddenFiles = showHiddenFiles
        self.showFileExtensions = showFileExtensions
        loadCurrentDestination()
    }

    deinit {
        stopDirectoryMonitor()
    }

    // MARK: - Computed Properties
    public var title: String {
        destination.displayTitle
    }

    public var currentDirectoryURL: URL? {
        if case .directory(let url) = destination {
            return url
        }
        return nil
    }

    public var canGoBack: Bool {
        !backStack.isEmpty
    }

    public var canGoForward: Bool {
        !forwardStack.isEmpty
    }

    public var canGoUp: Bool {
        switch destination {
        case .home:
            return false
        case .thisPC:
            return true
        case .directory(let url):
            return url.standardizedFileURL.path != "/"
        }
    }

    public var displayedItems: [FileItem] {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let filtered: [FileItem]
        if query.isEmpty {
            filtered = items
        } else {
            filtered = items.filter {
                $0.name.lowercased().contains(query) ||
                $0.fileTypeDescription.lowercased().contains(query)
            }
        }

        return filtered.sorted { lhs, rhs in
            // Folders always grouped first like Windows 11 Explorer
            if lhs.isDirectory != rhs.isDirectory {
                return lhs.isDirectory && !rhs.isDirectory
            }

            let comparison: ComparisonResult
            switch sortField {
            case .name:
                comparison = lhs.name.localizedStandardCompare(rhs.name)
            case .dateModified:
                let lDate = lhs.modificationDate ?? .distantPast
                let rDate = rhs.modificationDate ?? .distantPast
                if lDate == rDate {
                    comparison = lhs.name.localizedStandardCompare(rhs.name)
                } else {
                    comparison = lDate < rDate ? .orderedAscending : .orderedDescending
                }
            case .type:
                comparison = lhs.fileTypeDescription.localizedStandardCompare(rhs.fileTypeDescription)
            case .size:
                if lhs.size == rhs.size {
                    comparison = lhs.name.localizedStandardCompare(rhs.name)
                } else {
                    comparison = lhs.size < rhs.size ? .orderedAscending : .orderedDescending
                }
            }

            if sortAscending {
                return comparison == .orderedAscending
            } else {
                return comparison == .orderedDescending
            }
        }
    }

    public var selectedFileItems: [FileItem] {
        items.filter { selectedURLs.contains($0.url) }
    }

    public var selectedTotalBytes: Int64 {
        selectedFileItems.filter { !$0.isDirectory }.reduce(0) { $0 + $1.size }
    }

    public var breadcrumbSegments: [(title: String, destination: NavigationDestination)] {
        switch destination {
        case .home:
            return [("Inicio", .home)]
        case .thisPC:
            return [("Este equipo", .thisPC)]
        case .directory(let url):
            var segments: [(String, NavigationDestination)] = [("Este equipo", .thisPC)]
            let std = url.standardizedFileURL
            let components = std.pathComponents
            var currentPath = ""
            for component in components {
                if component == "/" {
                    currentPath = "/"
                    segments.append(("Macintosh HD (C:)", .directory(URL(fileURLWithPath: "/"))))
                } else {
                    if currentPath == "/" {
                        currentPath = "/\(component)"
                    } else {
                        currentPath += "/\(component)"
                    }
                    let segURL = URL(fileURLWithPath: currentPath)
                    segments.append((NavigationDestination.localizedFolderName(for: segURL), .directory(segURL)))
                }
            }
            return segments
        }
    }

    // MARK: - Navigation
    public func navigate(to newDestination: NavigationDestination, recordHistory: Bool = true) {
        if newDestination == destination {
            reload()
            return
        }
        commitRenameIfNeeded()
        if recordHistory {
            backStack.append(destination)
            forwardStack.removeAll()
        }
        destination = newDestination
        selectedURLs.removeAll()
        lastClickedURL = nil
        searchQuery = ""
        loadCurrentDestination()
    }

    public func navigateToPathString(_ rawInput: String) {
        let trimmed = rawInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if trimmed.lowercased() == "inicio" || trimmed.lowercased() == "home" {
            navigate(to: .home)
            return
        }
        if trimmed.lowercased() == "este equipo" || trimmed.lowercased() == "this pc" || trimmed.lowercased() == "c:" {
            navigate(to: .thisPC)
            return
        }

        let expanded = (trimmed as NSString).expandingTildeInPath
        let targetURL = URL(fileURLWithPath: expanded).standardizedFileURL
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: targetURL.path, isDirectory: &isDir) {
            if isDir.boolValue {
                navigate(to: .directory(targetURL))
            } else {
                FileSystemService.shared.openItem(targetURL)
            }
        } else {
            errorMessage = "Windows no puede encontrar '\(trimmed)'. Comprueba la ortografía e inténtalo de nuevo."
        }
    }

    public func goBack() {
        guard let previous = backStack.popLast() else { return }
        forwardStack.append(destination)
        destination = previous
        selectedURLs.removeAll()
        searchQuery = ""
        loadCurrentDestination()
    }

    public func goForward() {
        guard let next = forwardStack.popLast() else { return }
        backStack.append(destination)
        destination = next
        selectedURLs.removeAll()
        searchQuery = ""
        loadCurrentDestination()
    }

    public func goUp() {
        switch destination {
        case .home:
            break
        case .thisPC:
            navigate(to: .home)
        case .directory(let url):
            let std = url.standardizedFileURL
            if std.path == "/" {
                navigate(to: .thisPC)
            } else {
                navigate(to: .directory(std.deletingLastPathComponent()))
            }
        }
    }

    public func reload() {
        loadCurrentDestination()
    }

    public func toggleSort(by field: ExplorerSortField) {
        if sortField == field {
            sortAscending.toggle()
        } else {
            sortField = field
            sortAscending = true
        }
    }

    // MARK: - Selection Logic
    public func handleItemClick(_ item: FileItem, modifiers: NSEvent.ModifierFlags) {
        commitRenameIfNeeded()
        if modifiers.contains(.command) {
            if selectedURLs.contains(item.url) {
                selectedURLs.remove(item.url)
            } else {
                selectedURLs.insert(item.url)
            }
            lastClickedURL = item.url
        } else if modifiers.contains(.shift), let anchor = lastClickedURL {
            let currentList = displayedItems.map { $0.url }
            if let startIdx = currentList.firstIndex(of: anchor),
               let endIdx = currentList.firstIndex(of: item.url) {
                let lower = min(startIdx, endIdx)
                let upper = max(startIdx, endIdx)
                selectedURLs = Set(currentList[lower...upper])
            } else {
                selectedURLs = [item.url]
                lastClickedURL = item.url
            }
        } else {
            selectedURLs = [item.url]
            lastClickedURL = item.url
        }
    }

    public func selectAll() {
        selectedURLs = Set(displayedItems.map { $0.url })
    }

    public func clearSelection() {
        commitRenameIfNeeded()
        selectedURLs.removeAll()
    }

    // MARK: - Inline Rename
    public func beginRename(for item: FileItem? = nil) {
        let targetURL = item?.url ?? (selectedURLs.count == 1 ? selectedURLs.first : nil)
        guard let url = targetURL else { return }
        renamingURL = url
        renamingText = url.lastPathComponent
    }

    public func commitRenameIfNeeded() {
        guard let targetURL = renamingURL else { return }
        let proposedName = renamingText.trimmingCharacters(in: .whitespacesAndNewlines)
        renamingURL = nil
        renamingText = ""

        guard !proposedName.isEmpty, proposedName != targetURL.lastPathComponent else { return }
        do {
            let newURL = try FileSystemService.shared.renameItem(at: targetURL, to: proposedName)
            selectedURLs = [newURL]
            reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func cancelRename() {
        renamingURL = nil
        renamingText = ""
    }

    // MARK: - Directory Loading & Live FileSystem Monitoring
    private func loadCurrentDestination() {
        stopDirectoryMonitor()
        switch destination {
        case .home, .thisPC:
            items = []
        case .directory(let url):
            do {
                items = try FileSystemService.shared.contentsOfDirectory(
                    at: url,
                    includeHidden: showHiddenFiles
                )
                startDirectoryMonitor(for: url)
            } catch {
                items = []
                errorMessage = "No se pudo abrir la carpeta '\(url.lastPathComponent)': \(error.localizedDescription)"
            }
        }
    }

    private func startDirectoryMonitor(for url: URL) {
        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else { return }
        directoryFileDescriptor = fd

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .rename, .delete, .attrib],
            queue: DispatchQueue.main
        )

        source.setEventHandler { [weak self] in
            guard let self = self else { return }
            if self.renamingURL == nil {
                if case .directory(let currentURL) = self.destination {
                    if let updated = try? FileSystemService.shared.contentsOfDirectory(
                        at: currentURL,
                        includeHidden: self.showHiddenFiles
                    ) {
                        self.items = updated
                    }
                }
            }
        }

        source.setCancelHandler {
            close(fd)
        }

        source.resume()
        directoryMonitorSource = source
    }

    private func stopDirectoryMonitor() {
        directoryMonitorSource?.cancel()
        directoryMonitorSource = nil
        directoryFileDescriptor = -1
    }
}
