import Foundation
import AppKit
import ImageIO
import QuickLookThumbnailing

private actor CloudPreviewConcurrencyLimiter {
    private let maxConcurrent = 8
    private var active = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func acquire() async {
        if active < maxConcurrent {
            active += 1
            return
        }
        await withCheckedContinuation { cont in
            waiters.append(cont)
        }
    }

    func release() {
        if !waiters.isEmpty {
            let next = waiters.removeLast()
            next.resume()
        } else {
            active = max(0, active - 1)
        }
    }
}

public final class ThumbnailService {
    public static let shared = ThumbnailService()

    private let cache = NSCache<NSString, NSImage>()
    private let workQueue = DispatchQueue(label: "com.winexplorermac.thumbnails", qos: .userInitiated, attributes: .concurrent)
    private let cloudLimiter = CloudPreviewConcurrencyLimiter()
    private let cloudSession: URLSession = {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 10
        cfg.timeoutIntervalForResource = 15
        cfg.httpMaximumConnectionsPerHost = 8
        return URLSession(configuration: cfg)
    }()
    private let cloudPreviewCacheDir = URL(fileURLWithPath: "/tmp/WinExplorerMac_CloudPreviews", isDirectory: true)

    private init() {
        cache.countLimit = 900
        try? FileManager.default.createDirectory(at: cloudPreviewCacheDir, withIntermediateDirectories: true)
    }

    public func cacheKey(for item: FileItem, targetSize: CGFloat) -> NSString {
        let bucket = targetSize <= 28 ? 64 : (targetSize <= 64 ? 160 : 320)
        if let fileId = item.cloudFileId, !fileId.isEmpty {
            return "cloud|\(fileId)|\(bucket)" as NSString
        }
        let modTime = item.modificationDate?.timeIntervalSince1970 ?? 0
        return "\(item.url.path)|\(Int(modTime))|\(bucket)" as NSString
    }

    public func cachedThumbnail(for item: FileItem, targetSize: CGFloat) -> NSImage? {
        cache.object(forKey: cacheKey(for: item, targetSize: targetSize))
    }

    public func loadThumbnailAsync(for item: FileItem, targetSize: CGFloat) async -> NSImage? {
        let key = cacheKey(for: item, targetSize: targetSize)
        if let cached = cache.object(forKey: key) {
            return cached
        }

        let maxPixelSize: Int = targetSize <= 28 ? 64 : (targetSize <= 64 ? 160 : 320)

        // Cloud virtual image with Claro drive preview endpoint
        if item.isCloudDataless {
            guard item.isImage, let fileId = item.cloudFileId, !fileId.isEmpty else {
                return nil
            }
            return await loadClaroDrivePreview(fileId: fileId, maxPixelSize: maxPixelSize, cacheKey: key)
        }

        return await withCheckedContinuation { continuation in
            loadThumbnail(for: item, targetSize: targetSize) { img in
                continuation.resume(returning: img)
            }
        }
    }

    private func loadClaroDrivePreview(fileId: String, maxPixelSize: Int, cacheKey: NSString) async -> NSImage? {
        if Task.isCancelled { return nil }
        let diskFile = cloudPreviewCacheDir.appendingPathComponent("\(fileId).img")

        // 1. Check disk cache first (no network needed)
        if FileManager.default.fileExists(atPath: diskFile.path),
           let data = try? Data(contentsOf: diskFile),
           let img = Self.generateImageThumbnailFromData(data, maxPixelSize: maxPixelSize) {
            cache.setObject(img, forKey: cacheKey)
            return img
        }

        // 2. Limit concurrent HTTP preview downloads so fast scrolling cancels offscreen tasks
        await cloudLimiter.acquire()
        defer {
            Task { await cloudLimiter.release() }
        }

        if Task.isCancelled { return nil }
        if let cached = cache.object(forKey: cacheKey) {
            return cached
        }

        guard let creds = FileSystemService.shared.claroDriveCredentials(),
              let previewURL = URL(string: "\(creds.serverUrl)/index.php/core/preview?fileId=\(fileId)&x=256&y=256&a=1") else {
            return nil
        }

        var req = URLRequest(url: previewURL)
        let auth = Data("\(creds.user):\(creds.password)".utf8).base64EncodedString()
        req.setValue("Basic \(auth)", forHTTPHeaderField: "Authorization")
        req.setValue(creds.userAgent, forHTTPHeaderField: "User-Agent")

        for attempt in 0..<2 {
            if Task.isCancelled { return nil }
            do {
                let (data, response) = try await cloudSession.data(for: req)
                if let http = response as? HTTPURLResponse {
                    if (200...299).contains(http.statusCode), !data.isEmpty {
                        try? data.write(to: diskFile, options: .atomic)
                        if let img = Self.generateImageThumbnailFromData(data, maxPixelSize: maxPixelSize) {
                            cache.setObject(img, forKey: cacheKey)
                            return img
                        }
                        return nil
                    } else if http.statusCode == 503 && attempt == 0 {
                        try? await Task.sleep(nanoseconds: 250_000_000)
                        continue
                    }
                }
                return nil
            } catch {
                return nil
            }
        }
        return nil
    }

    public func loadThumbnail(for item: FileItem, targetSize: CGFloat, completion: @escaping (NSImage?) -> Void) {
        if item.isCloudDataless {
            if item.isImage, item.cloudFileId != nil {
                Task {
                    let loaded = await loadThumbnailAsync(for: item, targetSize: targetSize)
                    await MainActor.run {
                        completion(loaded)
                    }
                }
            } else {
                completion(nil)
            }
            return
        }
        let key = cacheKey(for: item, targetSize: targetSize)
        if let cached = cache.object(forKey: key) {
            completion(cached)
            return
        }

        let maxPixelSize: Int = targetSize <= 28 ? 64 : (targetSize <= 64 ? 160 : 320)
        let fileURL = item.url

        if item.isImage {
            workQueue.async { [weak self] in
                let generated = Self.generateImageThumbnail(at: fileURL, maxPixelSize: maxPixelSize)
                if let generated {
                    self?.cache.setObject(generated, forKey: key)
                }
                DispatchQueue.main.async {
                    completion(generated)
                }
            }
        } else if item.isQuickLookThumbnailSupported {
            let scale = NSScreen.main?.backingScaleFactor ?? 2.0
            let qlSize = CGSize(width: max(32, targetSize), height: max(32, targetSize))
            let request = QLThumbnailGenerator.Request(
                fileAt: fileURL,
                size: qlSize,
                scale: scale,
                representationTypes: .thumbnail
            )
            QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { [weak self] representation, _ in
                let image = representation?.nsImage
                if let image {
                    self?.cache.setObject(image, forKey: key)
                }
                DispatchQueue.main.async {
                    completion(image)
                }
            }
        } else {
            completion(nil)
        }
    }

    private static func generateImageThumbnailFromData(_ data: Data, maxPixelSize: Int) -> NSImage? {
        if let source = CGImageSourceCreateWithData(data as CFData, nil) {
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
            ]
            if let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) {
                return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
            }
        }
        return NSImage(data: data)
    }

    private static func generateImageThumbnail(at url: URL, maxPixelSize: Int) -> NSImage? {
        if let source = CGImageSourceCreateWithURL(url as CFURL, nil) {
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
            ]
            if let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) {
                return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
            }
        }
        return NSImage(contentsOf: url)
    }
}
