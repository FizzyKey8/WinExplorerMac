import Foundation

public struct PinnedFolderItem: Identifiable, Codable, Hashable {
    public var id: String { path }
    public let path: String
    public let customTitle: String?
    public let isSystemDefault: Bool

    public var url: URL {
        URL(fileURLWithPath: path, isDirectory: true)
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
        URL(fileURLWithPath: path, isDirectory: false)
    }
}

public final class QuickAccessStore: ObservableObject {
    public static let shared = QuickAccessStore()

    @Published public private(set) var pinnedFolders: [PinnedFolderItem] = []
    @Published public private(set) var recentFiles: [RecentFileRecord] = []

    private let pinnedKey = "WinExplorerMac.PinnedFolders.v1"
    private let recentsKey = "WinExplorerMac.RecentFiles.v1"

    public init() {
        loadPinnedFolders()
        loadRecentFiles()
    }

    public func updatePath(from oldURL: URL, to newURL: URL) {
        let oldPath = oldURL.cleanFileURL.path
        let newPath = newURL.cleanFileURL.path
        if let idx = recentFiles.firstIndex(where: { $0.path == oldPath }) {
            let record = recentFiles[idx]
            recentFiles[idx] = RecentFileRecord(path: newPath, accessedAt: record.accessedAt)
            saveRecentFiles()
        }
        if let idx = pinnedFolders.firstIndex(where: { $0.path == oldPath }) {
            let pinned = pinnedFolders[idx]
            pinnedFolders[idx] = PinnedFolderItem(path: newPath, customTitle: pinned.customTitle, isSystemDefault: pinned.isSystemDefault)
            savePinnedFolders()
        }
    }

    public func isPinned(_ url: URL) -> Bool {
        let stdPath = url.cleanFileURL.path
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
        let std = url.cleanFileURL
        guard !isPinned(std) else { return }
        if !FileSystemService.isCloudPath(std.path) {
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: std.path, isDirectory: &isDir), isDir.boolValue else { return }
        }

        let item = PinnedFolderItem(
            path: std.path,
            customTitle: nil,
            isSystemDefault: false
        )
        pinnedFolders.append(item)
        savePinnedFolders()
    }

    public func unpin(_ url: URL) {
        let stdPath = url.cleanFileURL.path
        pinnedFolders.removeAll { $0.path == stdPath }
        savePinnedFolders()
    }

    public func recordRecentFile(_ url: URL) {
        let std = url.cleanFileURL
        if FileSystemService.isCloudPath(std.path) {
            // Never stat or touch CloudStorage VFS nodes directly to avoid kernel hangs
            if std.hasDirectoryPath { return }
        } else {
            var st = Darwin.stat()
            guard lstat(std.path, &st) == 0 else { return }
            let isDir = (st.st_mode & S_IFMT) == S_IFDIR
            guard !isDir else { return }
        }

        recentFiles.removeAll { $0.path == std.path }
        recentFiles.insert(RecentFileRecord(path: std.path, accessedAt: Date()), at: 0)
        if recentFiles.count > 25 {
            recentFiles = Array(recentFiles.prefix(25))
        }
        saveRecentFiles()
    }

    public func removeRecentFile(_ url: URL) {
        let stdPath = url.cleanFileURL.path
        recentFiles.removeAll { $0.path == stdPath }
        saveRecentFiles()
    }

    public func clearRecents() {
        recentFiles.removeAll()
        saveRecentFiles()
    }

    private func loadPinnedFolders() {
        let home = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL
        let trashPath = home.appendingPathComponent(".Trash").path
        let trashMigrationKey = "WinExplorerMac.TrashPinnedMigration.v1"
        let cloudMigrationKey = "WinExplorerMac.CloudPinnedMigration.v1"
        let detectedCloudDrives = FileSystemService.shared.cloudDrives()

        if let data = UserDefaults.standard.data(forKey: pinnedKey),
           let decoded = try? JSONDecoder().decode([PinnedFolderItem].self, from: data),
           !decoded.isEmpty {
            var valid = decoded.filter {
                $0.path == trashPath ||
                $0.path == FileSystemService.iCloudDriveURL.path ||
                FileSystemService.isCloudPath($0.path) ||
                FileManager.default.fileExists(atPath: $0.path)
            }
            if !UserDefaults.standard.bool(forKey: trashMigrationKey) {
                UserDefaults.standard.set(true, forKey: trashMigrationKey)
                if !valid.contains(where: { $0.path == trashPath }) {
                    valid.append(PinnedFolderItem(path: trashPath, customTitle: "Basurero", isSystemDefault: true))
                }
            }
            if !UserDefaults.standard.bool(forKey: cloudMigrationKey) {
                UserDefaults.standard.set(true, forKey: cloudMigrationKey)
                for drive in detectedCloudDrives {
                    if !valid.contains(where: { $0.path == drive.url.path }) {
                        valid.append(PinnedFolderItem(path: drive.url.path, customTitle: drive.name, isSystemDefault: true))
                    }
                }
            }
            if !valid.isEmpty {
                self.pinnedFolders = valid
                savePinnedFolders()
                return
            }
        }

        // Default Windows 11 Quick Access libraries mapped to macOS user folders
        let defaults: [(String, String)] = [
            ("Desktop", "Escritorio"),
            ("Downloads", "Descargas"),
            ("Documents", "Documentos"),
            ("Pictures", "Imágenes"),
            ("Music", "Música"),
            ("Movies", "Videos"),
            (".Trash", "Basurero")
        ]

        var initialPinned = defaults.compactMap { folderName, localizedName -> PinnedFolderItem? in
            let url = home.appendingPathComponent(folderName)
            if folderName != ".Trash" && !FileManager.default.fileExists(atPath: url.path) {
                return nil
            }
            return PinnedFolderItem(path: url.path, customTitle: localizedName, isSystemDefault: true)
        }
        for drive in detectedCloudDrives {
            if !initialPinned.contains(where: { $0.path == drive.url.path }) {
                initialPinned.append(PinnedFolderItem(path: drive.url.path, customTitle: drive.name, isSystemDefault: true))
            }
        }
        self.pinnedFolders = initialPinned
        UserDefaults.standard.set(true, forKey: trashMigrationKey)
        UserDefaults.standard.set(true, forKey: cloudMigrationKey)
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
            self.recentFiles = decoded.filter { record in
                if FileSystemService.isCloudPath(record.path) {
                    return !record.path.hasSuffix("/")
                }
                var isDir: ObjCBool = false
                return FileManager.default.fileExists(atPath: record.path, isDirectory: &isDir) && !isDir.boolValue
            }
        }
    }

    private func saveRecentFiles() {
        if let data = try? JSONEncoder().encode(recentFiles) {
            UserDefaults.standard.set(data, forKey: recentsKey)
        }
    }
}
