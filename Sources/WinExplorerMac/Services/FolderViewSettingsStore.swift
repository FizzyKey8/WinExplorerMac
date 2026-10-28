import Foundation

/// Persistent store that saves and restores user view mode preferences (Large Icons, Details, List, etc.)
/// on a per-folder basis, surviving application restarts.
public final class FolderViewSettingsStore {
    public static let shared = FolderViewSettingsStore()
    private let storageKey = "WinExplorerMac.FolderViewSettings"
    private var cache: [String: String] = [:]
    private let lock = NSLock()

    private init() {
        if let saved = UserDefaults.standard.dictionary(forKey: storageKey) as? [String: String] {
            self.cache = saved
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
}
