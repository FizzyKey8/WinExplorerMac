import Foundation

/// Persistent store that saves and restores user view mode preferences (Large Icons, Details, List, etc.)
/// and sort preferences (Name, Date Modified, Type, Size, and ascending/descending)
/// on a per-folder basis, surviving application restarts.
public final class FolderViewSettingsStore {
    public static let shared = FolderViewSettingsStore()
    private let storageKey = "WinExplorerMac.FolderViewSettings"
    private let sortStorageKey = "WinExplorerMac.FolderSortSettings"
    private var cache: [String: String] = [:]
    private var sortCache: [String: (field: ExplorerSortField, ascending: Bool)] = [:]
    private let lock = NSLock()

    private init() {
        if let saved = UserDefaults.standard.dictionary(forKey: storageKey) as? [String: String] {
            self.cache = saved
        }
        if let savedSort = UserDefaults.standard.dictionary(forKey: sortStorageKey) as? [String: [String: Any]] {
            for (k, dict) in savedSort {
                if let fieldRaw = dict["field"] as? String,
                   let field = ExplorerSortField(rawValue: fieldRaw),
                   let ascending = dict["ascending"] as? Bool {
                    self.sortCache[k] = (field: field, ascending: ascending)
                }
            }
        }
    }

    public func key(for destination: NavigationDestination) -> String {
        switch destination {
        case .home:
            return "__system_home__"
        case .thisPC:
            return "__system_this_pc__"
        case .directory(let url):
            return url.cleanFileURL.path
        }
    }

    public func viewMode(for destination: NavigationDestination) -> ExplorerViewMode? {
        lock.lock()
        defer { lock.unlock() }
        let k = key(for: destination)
        guard let raw = cache[k] else { return nil }
        return ExplorerViewMode(rawValue: raw)
    }

    public func setViewMode(_ mode: ExplorerViewMode, for destination: NavigationDestination) {
        lock.lock()
        let k = key(for: destination)
        // If unchanged, skip writing
        if cache[k] == mode.rawValue {
            lock.unlock()
            return
        }
        cache[k] = mode.rawValue
        let copy = cache
        lock.unlock()

        UserDefaults.standard.set(copy, forKey: storageKey)
    }

    public func sortSettings(for destination: NavigationDestination) -> (field: ExplorerSortField, ascending: Bool)? {
        lock.lock()
        defer { lock.unlock() }
        let k = key(for: destination)
        return sortCache[k]
    }

    public func setSortSettings(field: ExplorerSortField, ascending: Bool, for destination: NavigationDestination) {
        lock.lock()
        let k = key(for: destination)
        if let current = sortCache[k], current.field == field, current.ascending == ascending {
            lock.unlock()
            return
        }
        sortCache[k] = (field: field, ascending: ascending)

        var plistDict: [String: [String: Any]] = [:]
        for (path, setting) in sortCache {
            plistDict[path] = ["field": setting.field.rawValue, "ascending": setting.ascending]
        }
        lock.unlock()

        UserDefaults.standard.set(plistDict, forKey: sortStorageKey)
    }
}
