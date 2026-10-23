import Foundation
import Combine
import AppKit

public final class ExplorerTabViewModel: ObservableObject, Identifiable {
    public let id: UUID
    @Published public private(set) var destination: NavigationDestination
    @Published public private(set) var backStack: [NavigationDestination] = []
    @Published public private(set) var forwardStack: [NavigationDestination] = []

    @Published public private(set) var items: [FileItem] = []
    @Published public private(set) var displayedItems: [FileItem] = []
    @Published public private(set) var isLoading: Bool = false
    @Published public var selectedURLs: Set<URL> = []
    @Published public var lastClickedURL: URL? = nil

    @Published public var searchQuery: String = "" {
        didSet {
            if oldValue != searchQuery {
                scheduleDisplayedItemsRefresh()
            }
        }
    }
    @Published public var viewMode: ExplorerViewMode = .details
    @Published public var sortField: ExplorerSortField = .name {
        didSet {
            if oldValue != sortField {
                scheduleDisplayedItemsRefresh()
            }
        }
    }
    @Published public var sortAscending: Bool = true {
        didSet {
            if oldValue != sortAscending {
                scheduleDisplayedItemsRefresh()
            }
        }
    }
    @Published public var showHiddenFiles: Bool = false
    @Published public var showFileExtensions: Bool = true

    @Published public var renamingURL: URL? = nil
    @Published public var renamingText: String = ""

    @Published public var statusMessage: String? = nil
    @Published public var errorMessage: String? = nil

    private var directoryMonitorSource: DispatchSourceFileSystemObject?
    private var directoryFileDescriptor: Int32 = -1
    private var loadTask: Task<Void, Never>?
    private var filterSortTask: Task<Void, Never>?
    private var monitorDebounceWorkItem: DispatchWorkItem?

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
        loadTask?.cancel()
        filterSortTask?.cancel()
        monitorDebounceWorkItem?.cancel()
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
            return url.cleanFileURL.path != "/"
        }
    }

    public static func filterAndSort(
        items: [FileItem],
        searchQuery: String,
        sortField: ExplorerSortField,
        sortAscending: Bool
    ) -> [FileItem] {
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

        let useFastCompare = filtered.count > 2500

        return filtered.sorted { lhs, rhs in
            // Folders always grouped first like Windows 11 Explorer
            if lhs.isDirectory != rhs.isDirectory {
                return lhs.isDirectory && !rhs.isDirectory
            }

            let comparison: ComparisonResult
            switch sortField {
            case .name:
                comparison = useFastCompare
                    ? lhs.name.caseInsensitiveCompare(rhs.name)
                    : lhs.name.localizedStandardCompare(rhs.name)
            case .dateModified:
                let lDate = lhs.modificationDate ?? .distantPast
                let rDate = rhs.modificationDate ?? .distantPast
                if lDate == rDate {
                    comparison = useFastCompare
                        ? lhs.name.caseInsensitiveCompare(rhs.name)
                        : lhs.name.localizedStandardCompare(rhs.name)
                } else {
                    comparison = lDate < rDate ? .orderedAscending : .orderedDescending
                }
            case .type:
                comparison = useFastCompare
                    ? lhs.fileTypeDescription.caseInsensitiveCompare(rhs.fileTypeDescription)
                    : lhs.fileTypeDescription.localizedStandardCompare(rhs.fileTypeDescription)
            case .size:
                if lhs.size == rhs.size {
                    comparison = useFastCompare
                        ? lhs.name.caseInsensitiveCompare(rhs.name)
                        : lhs.name.localizedStandardCompare(rhs.name)
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

    private func scheduleDisplayedItemsRefresh() {
        filterSortTask?.cancel()
        let currentItems = self.items
        let query = self.searchQuery
        let field = self.sortField
        let ascending = self.sortAscending

        if currentItems.count <= 400 {
            self.displayedItems = Self.filterAndSort(
                items: currentItems,
                searchQuery: query,
                sortField: field,
                sortAscending: ascending
            )
            return
        }

        filterSortTask = Task.detached(priority: .userInitiated) { [weak self] in
            let sorted = Self.filterAndSort(
                items: currentItems,
                searchQuery: query,
                sortField: field,
                sortAscending: ascending
            )
            guard !Task.isCancelled else { return }
            await MainActor.run { [weak self] in
                guard let self = self, !Task.isCancelled else { return }
                self.displayedItems = sorted
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
            let std = url.cleanFileURL

            // Check if inside iCloud Drive or a CloudStorage provider for clean Windows 11 cloud breadcrumbs
            for cloud in FileSystemService.shared.cloudDrives() {
                let cloudRoot = cloud.url.cleanFileURL
                if std.path == cloudRoot.path || std.path.hasPrefix(cloudRoot.path + "/") {
                    var segments: [(String, NavigationDestination)] = [
                        (cloud.name, .directory(cloudRoot))
                    ]
                    let relative = String(std.path.dropFirst(cloudRoot.path.count))
                    let subComponents = relative.split(separator: "/").map(String.init)
                    var runningURL = cloudRoot
                    for sub in subComponents {
                        runningURL = runningURL.appendingPathComponent(sub, isDirectory: true)
                        segments.append((NavigationDestination.localizedFolderName(for: runningURL), .directory(runningURL)))
                    }
                    return segments
                }
            }

            // Also check if inside an iCloud app container Documents folder
            if std.path.hasPrefix(FileSystemService.mobileDocumentsRootURL.path + "/") {
                var segments: [(String, NavigationDestination)] = [
                    ("iCloud Drive", .directory(FileSystemService.iCloudDriveURL))
                ]
                let relative = String(std.path.dropFirst(FileSystemService.mobileDocumentsRootURL.path.count))
                let parts = relative.split(separator: "/").map(String.init)
                if parts.count >= 2 && parts[1] == "Documents" {
                    let docsRoot = FileSystemService.mobileDocumentsRootURL
                        .appendingPathComponent(parts[0])
                        .appendingPathComponent("Documents")
                    segments.append((NavigationDestination.localizedFolderName(for: docsRoot), .directory(docsRoot)))
                    var runningURL = docsRoot
                    for sub in parts.dropFirst(2) {
                        runningURL = runningURL.appendingPathComponent(sub)
                        segments.append((sub, .directory(runningURL)))
                    }
                    return segments
                }
            }

            var segments: [(String, NavigationDestination)] = [("Este equipo", .thisPC)]
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
        if ["basurero", "papelera", "papelera de reciclaje", "trash", "~/.trash"].contains(trimmed.lowercased()) {
            navigate(to: .directory(FileSystemService.trashDirectoryURL))
            return
        }
        if ["icloud", "icloud drive"].contains(trimmed.lowercased()) {
            navigate(to: .directory(FileSystemService.iCloudDriveURL))
            return
        }
        if ["clarodrive", "claro drive"].contains(trimmed.lowercased()),
           let claro = FileSystemService.shared.cloudDrives().first(where: { $0.isClaroDrive }) {
            navigate(to: .directory(claro.url))
            return
        }

        let expanded = (trimmed as NSString).expandingTildeInPath
        let targetURL = URL(fileURLWithPath: expanded, isDirectory: true).cleanFileURL
        if FileSystemService.isCloudPath(targetURL.path) && targetURL.pathExtension.isEmpty {
            navigate(to: .directory(targetURL))
            return
        }
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
            let std = url.cleanFileURL
            if std.path == "/" {
                navigate(to: .thisPC)
            } else if std == FileSystemService.iCloudDriveURL ||
                      std.deletingLastPathComponent().cleanFileURL == FileSystemService.cloudStorageRootURL {
                navigate(to: .home)
            } else if std.lastPathComponent == "Documents",
                      std.deletingLastPathComponent().deletingLastPathComponent().cleanFileURL == FileSystemService.mobileDocumentsRootURL {
                navigate(to: .directory(FileSystemService.iCloudDriveURL))
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
    private func loadCurrentDestination(clearExisting: Bool = true) {
        loadTask?.cancel()
        filterSortTask?.cancel()
        monitorDebounceWorkItem?.cancel()
        stopDirectoryMonitor()

        switch destination {
        case .home, .thisPC:
            isLoading = false
            items = []
            displayedItems = []
        case .directory(let url):
            if clearExisting {
                items = []
                displayedItems = []
            }
            isLoading = true

            let includeHidden = showHiddenFiles
            let initialQuery = searchQuery
            let initialSortField = sortField
            let initialSortAscending = sortAscending

            loadTask = Task.detached(priority: .userInitiated) { [weak self] in
                var accumulated: [FileItem] = []
                accumulated.reserveCapacity(256)
                var isFirstBatch = true
                var lastPublishTime = CFAbsoluteTimeGetCurrent()

                do {
                    try FileSystemService.shared.streamContentsOfDirectory(
                        at: url,
                        includeHidden: includeHidden,
                        firstBatchSize: 150,
                        subsequentBatchSize: 500
                    ) { batch, isComplete in
                        if Task.isCancelled { return false }
                        accumulated.append(contentsOf: batch)

                        let now = CFAbsoluteTimeGetCurrent()
                        let shouldPublishNow = isFirstBatch || isComplete || (now - lastPublishTime >= 0.14)

                        if shouldPublishNow {
                            isFirstBatch = false
                            lastPublishTime = now
                            let snapshot = accumulated
                            let sortedSnapshot: [FileItem]
                            if isComplete || snapshot.count <= 800 {
                                sortedSnapshot = Self.filterAndSort(
                                    items: snapshot,
                                    searchQuery: initialQuery,
                                    sortField: initialSortField,
                                    sortAscending: initialSortAscending
                                )
                            } else {
                                sortedSnapshot = snapshot
                            }

                            DispatchQueue.main.async { [weak self] in
                                guard let self = self,
                                      case .directory(let currentURL) = self.destination,
                                      currentURL.cleanFileURL.path == url.cleanFileURL.path else { return }
                                self.items = snapshot
                                if isComplete || snapshot.count <= 800 {
                                    // If user changed sort/search while loading, re-evaluate with latest parameters
                                    if self.searchQuery == initialQuery &&
                                       self.sortField == initialSortField &&
                                       self.sortAscending == initialSortAscending {
                                        self.displayedItems = sortedSnapshot
                                    } else {
                                        self.scheduleDisplayedItemsRefresh()
                                    }
                                } else {
                                    self.displayedItems = sortedSnapshot
                                }
                                if isComplete {
                                    self.isLoading = false
                                    self.startDirectoryMonitor(for: url)
                                }
                            }
                        }
                        return !Task.isCancelled
                    }
                } catch {
                    if Task.isCancelled { return }
                    DispatchQueue.main.async { [weak self] in
                        guard let self = self,
                              case .directory(let currentURL) = self.destination,
                              currentURL.cleanFileURL.path == url.cleanFileURL.path else { return }
                        self.isLoading = false
                        self.items = []
                        self.displayedItems = []
                        self.errorMessage = "No se pudo abrir la carpeta '\(url.lastPathComponent)': \(error.localizedDescription)"
                    }
                }
            }
        }
    }

    private func startDirectoryMonitor(for url: URL) {
        guard !FileSystemService.isCloudPath(url.path) else { return }
        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else { return }
        directoryFileDescriptor = fd

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .rename, .delete],
            queue: DispatchQueue.main
        )

        source.setEventHandler { [weak self] in
            guard let self = self else { return }
            guard self.renamingURL == nil, !self.isLoading else { return }
            self.monitorDebounceWorkItem?.cancel()
            let work = DispatchWorkItem { [weak self] in
                guard let self = self, self.renamingURL == nil else { return }
                if case .directory = self.destination {
                    self.loadCurrentDestination(clearExisting: false)
                }
            }
            self.monitorDebounceWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45, execute: work)
        }

        source.setCancelHandler {
            close(fd)
        }

        source.resume()
        directoryMonitorSource = source
    }

    private func stopDirectoryMonitor() {
        monitorDebounceWorkItem?.cancel()
        monitorDebounceWorkItem = nil
        directoryMonitorSource?.cancel()
        directoryMonitorSource = nil
        directoryFileDescriptor = -1
    }
}
