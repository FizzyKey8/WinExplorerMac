import Foundation
import Combine

public final class CloudDownloadManager: ObservableObject {
    public static let shared = CloudDownloadManager()

    /// Item key -> download progress fraction (0.0 to 1.0)
    @Published public private(set) var activeDownloads: [String: Double] = [:]

    /// Item keys that are downloaded and available locally
    @Published public private(set) var downloadedKeys: Set<String> = []

    /// Item keys that have been explicitly evicted to cloud-only
    @Published public private(set) var evictedKeys: Set<String> = []

    private let lock = NSLock()
    private var lastUIUpdate: [String: CFAbsoluteTime] = [:]
    private let openedCacheDir = URL(fileURLWithPath: "/tmp/WinExplorerMac_CloudOpened", isDirectory: true)

    private init() {
        scanOpenedCache()
    }

    public func key(for item: FileItem) -> String {
        if let fid = item.cloudFileId, !fid.isEmpty {
            return fid
        }
        return String(abs(item.url.path.hashValue))
    }

    public func isDownloaded(item: FileItem) -> Bool {
        let k = key(for: item)
        let hashK = String(abs(item.url.path.hashValue))

        lock.lock()
        if evictedKeys.contains(k) || evictedKeys.contains(hashK) {
            lock.unlock()
            return false
        }
        let isKnownDownloaded = downloadedKeys.contains(k) || downloadedKeys.contains(hashK)
        lock.unlock()

        if isKnownDownloaded {
            return true
        }

        // Fast memory check without disk I/O
        if !item.isCloudDataless && FileSystemService.isCloudPath(item.url.path) {
            return true
        }

        return false
    }

    public func progress(for item: FileItem) -> Double? {
        let k = key(for: item)
        lock.lock()
        defer { lock.unlock() }
        return activeDownloads[k]
    }

    public func updateProgress(for item: FileItem, fraction: Double) {
        let k = key(for: item)
        let now = CFAbsoluteTimeGetCurrent()
        lock.lock()
        let last = lastUIUpdate[k] ?? 0
        let shouldNotify = (now - last >= 0.15) || (fraction >= 1.0) || (fraction <= 0.05)
        activeDownloads[k] = fraction
        if shouldNotify {
            lastUIUpdate[k] = now
        }
        lock.unlock()

        if shouldNotify {
            DispatchQueue.main.async { [weak self] in
                self?.objectWillChange.send()
            }
        }
    }

    public func finishDownload(for item: FileItem) {
        let k = key(for: item)
        let hashK = String(abs(item.url.path.hashValue))
        lock.lock()
        activeDownloads.removeValue(forKey: k)
        lastUIUpdate.removeValue(forKey: k)
        evictedKeys.remove(k)
        evictedKeys.remove(hashK)
        downloadedKeys.insert(k)
        downloadedKeys.insert(hashK)
        lock.unlock()
        DispatchQueue.main.async { [weak self] in
            self?.objectWillChange.send()
        }
    }

    public func cancelDownload(for item: FileItem) {
        let k = key(for: item)
        lock.lock()
        activeDownloads.removeValue(forKey: k)
        lastUIUpdate.removeValue(forKey: k)
        lock.unlock()
        DispatchQueue.main.async { [weak self] in
            self?.objectWillChange.send()
        }
    }

    public func evict(url: URL) {
        let k = String(abs(url.path.hashValue))
        lock.lock()
        downloadedKeys.remove(k)
        evictedKeys.insert(k)
        activeDownloads.removeValue(forKey: k)
        lastUIUpdate.removeValue(forKey: k)
        lock.unlock()

        let itemFolder = openedCacheDir.appendingPathComponent(k)
        Task.detached(priority: .background) {
            try? FileManager.default.removeItem(at: itemFolder)
        }

        DispatchQueue.main.async { [weak self] in
            self?.objectWillChange.send()
        }
    }

    public func evict(item: FileItem) {
        let k = key(for: item)
        let hashK = String(abs(item.url.path.hashValue))
        lock.lock()
        downloadedKeys.remove(k)
        downloadedKeys.remove(hashK)
        evictedKeys.insert(k)
        evictedKeys.insert(hashK)
        activeDownloads.removeValue(forKey: k)
        activeDownloads.removeValue(forKey: hashK)
        lastUIUpdate.removeValue(forKey: k)
        lastUIUpdate.removeValue(forKey: hashK)
        lock.unlock()

        let itemFolder1 = openedCacheDir.appendingPathComponent(k)
        let itemFolder2 = openedCacheDir.appendingPathComponent(hashK)
        Task.detached(priority: .background) {
            try? FileManager.default.removeItem(at: itemFolder1)
            try? FileManager.default.removeItem(at: itemFolder2)
        }

        DispatchQueue.main.async { [weak self] in
            self?.objectWillChange.send()
        }
    }

    public func evictAll(items: [FileItem]) {
        lock.lock()
        var foldersToClean: [URL] = []
        for item in items {
            let k = key(for: item)
            let hashK = String(abs(item.url.path.hashValue))
            downloadedKeys.remove(k)
            downloadedKeys.remove(hashK)
            evictedKeys.insert(k)
            evictedKeys.insert(hashK)
            activeDownloads.removeValue(forKey: k)
            activeDownloads.removeValue(forKey: hashK)
            lastUIUpdate.removeValue(forKey: k)
            lastUIUpdate.removeValue(forKey: hashK)
            foldersToClean.append(openedCacheDir.appendingPathComponent(k))
            foldersToClean.append(openedCacheDir.appendingPathComponent(hashK))
        }
        lock.unlock()

        let foldersList = foldersToClean
        Task.detached(priority: .background) {
            for folder in foldersList {
                try? FileManager.default.removeItem(at: folder)
            }
        }

        DispatchQueue.main.async { [weak self] in
            self?.objectWillChange.send()
        }
    }

    public func evictAll() {
        lock.lock()
        downloadedKeys.removeAll()
        activeDownloads.removeAll()
        lastUIUpdate.removeAll()
        lock.unlock()

        let cacheDir = openedCacheDir
        Task.detached(priority: .background) {
            try? FileManager.default.removeItem(at: cacheDir)
            try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        }

        DispatchQueue.main.async { [weak self] in
            self?.objectWillChange.send()
        }
    }

    private func scanOpenedCache() {
        guard let subdirs = try? FileManager.default.contentsOfDirectory(atPath: openedCacheDir.path) else { return }
        for sub in subdirs {
            let subPath = openedCacheDir.appendingPathComponent(sub)
            if let files = try? FileManager.default.contentsOfDirectory(atPath: subPath.path), !files.isEmpty {
                downloadedKeys.insert(sub)
            }
        }
    }
}
