import Foundation
import Combine

public final class CloudDownloadManager: ObservableObject {
    public static let shared = CloudDownloadManager()

    /// Item key -> download progress fraction (0.0 to 1.0)
    @Published public private(set) var activeDownloads: [String: Double] = [:]

    /// Item keys that are downloaded and available locally
    @Published public private(set) var downloadedKeys: Set<String> = []

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
        // 1. Check if the file is in a cloud storage folder and is resident locally on the file system
        if FileSystemService.isCloudPath(item.url.path) {
            var st = Darwin.stat()
            if lstat(item.url.path, &st) == 0 {
                let isDataless = (st.st_flags & 0x40000000) != 0 || (st.st_blocks == 0 && st.st_size > 0)
                if !isDataless {
                    return true
                }
            }
        }

        if !item.isCloudDataless && FileSystemService.isCloudPath(item.url.path) {
            return true
        }
        let k = key(for: item)
        lock.lock()
        let downloaded = downloadedKeys.contains(k)
        lock.unlock()
        if downloaded { return true }

        let itemPath = openedCacheDir.appendingPathComponent(k).appendingPathComponent(item.name).path
        if FileManager.default.fileExists(atPath: itemPath) {
            lock.lock()
            downloadedKeys.insert(k)
            lock.unlock()
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
        lock.lock()
        activeDownloads.removeValue(forKey: k)
        lastUIUpdate.removeValue(forKey: k)
        downloadedKeys.insert(k)
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
