import Foundation

public struct PinnedFolderItem: Identifiable, Codable, Hashable {
    public var id: String { path }
    public let path: String
    public let customTitle: String?
    public let isSystemDefault: Bool

    public var url: URL {
        URL(fileURLWithPath: path)
    }

    public var title: String {
        if let customTitle, !customTitle.isEmpty {
            return customTitle
        }
        return NavigationDestination.localizedFolderName(for: url)
    }

    public var locationSubtitle: String {
        let parent = url.deletingLastPathComponent().path
        return parent.isEmpty ? "Este equipo" : parent
    }
}

public struct RecentFileRecord: Identifiable, Codable, Hashable {
    public var id: String { path }
    public let path: String
    public let accessedAt: Date

    public var url: URL {
        URL(fileURLWithPath: path)
    }
}

public final class QuickAccessStore: ObservableObject {
    @Published public private(set) var pinnedFolders: [PinnedFolderItem] = []
    @Published public private(set) var recentFiles: [RecentFileRecord] = []

    private let pinnedKey = "Win11ExplorerMac.PinnedFolders.v1"
    private let recentsKey = "Win11ExplorerMac.RecentFiles.v1"

    public init() {
        loadPinnedFolders()
        loadRecentFiles()
    }

    public func isPinned(_ url: URL) -> Bool {
        let stdPath = url.standardizedFileURL.path
        return pinnedFolders.contains { $0.path == stdPath }
    }

    public func togglePin(for url: URL) {
        if isPinned(url) {
            unpin(url)
        } else {
            pin(url)
        }
    }

    public func pin(_ url: URL) {
        let std = url.standardizedFileURL
        guard !isPinned(std) else { return }
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: std.path, isDirectory: &isDir), isDir.boolValue else { return }

        let item = PinnedFolderItem(
            path: std.path,
            customTitle: nil,
            isSystemDefault: false
        )
        pinnedFolders.append(item)
        savePinnedFolders()
    }

    public func unpin(_ url: URL) {
        let stdPath = url.standardizedFileURL.path
        pinnedFolders.removeAll { $0.path == stdPath }
        savePinnedFolders()
    }

    public func recordRecentFile(_ url: URL) {
        let std = url.standardizedFileURL
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: std.path, isDirectory: &isDir), !isDir.boolValue else { return }

        recentFiles.removeAll { $0.path == std.path }
        recentFiles.insert(RecentFileRecord(path: std.path, accessedAt: Date()), at: 0)
        if recentFiles.count > 25 {
            recentFiles = Array(recentFiles.prefix(25))
        }
        saveRecentFiles()
    }

    public func removeRecentFile(_ url: URL) {
        let stdPath = url.standardizedFileURL.path
        recentFiles.removeAll { $0.path == stdPath }
        saveRecentFiles()
    }

    public func clearRecents() {
        recentFiles.removeAll()
        saveRecentFiles()
    }

    private func loadPinnedFolders() {
        if let data = UserDefaults.standard.data(forKey: pinnedKey),
           let decoded = try? JSONDecoder().decode([PinnedFolderItem].self, from: data),
           !decoded.isEmpty {
            self.pinnedFolders = decoded.filter { FileManager.default.fileExists(atPath: $0.path) }
            if !self.pinnedFolders.isEmpty {
                return
            }
        }

        // Default Windows 11 Quick Access libraries mapped to macOS user folders
        let home = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL
        let defaults: [(String, String)] = [
            ("Desktop", "Escritorio"),
            ("Downloads", "Descargas"),
            ("Documents", "Documentos"),
            ("Pictures", "Imágenes"),
            ("Music", "Música"),
            ("Movies", "Videos")
        ]

        self.pinnedFolders = defaults.compactMap { folderName, localizedName in
            let url = home.appendingPathComponent(folderName)
            guard FileManager.default.fileExists(atPath: url.path) else { return nil }
            return PinnedFolderItem(path: url.path, customTitle: localizedName, isSystemDefault: true)
        }
        savePinnedFolders()
    }

    private func savePinnedFolders() {
        if let data = try? JSONEncoder().encode(pinnedFolders) {
            UserDefaults.standard.set(data, forKey: pinnedKey)
        }
    }

    private func loadRecentFiles() {
        if let data = UserDefaults.standard.data(forKey: recentsKey),
           let decoded = try? JSONDecoder().decode([RecentFileRecord].self, from: data) {
            self.recentFiles = decoded.filter { FileManager.default.fileExists(atPath: $0.path) }
        }
    }

    private func saveRecentFiles() {
        if let data = try? JSONEncoder().encode(recentFiles) {
            UserDefaults.standard.set(data, forKey: recentsKey)
        }
    }
}
