import Foundation
import AppKit
import ImageIO
import AVFoundation
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

        // Cloud virtual items
        if item.isCloudDataless {
            guard (item.isImage || item.isVideo) else {
                return nil
            }
            let cacheId = (item.cloudFileId?.isEmpty == false) ? item.cloudFileId! : String(abs(item.url.path.hashValue))

            // 1. Check disk cache first
            let diskFile = cloudPreviewCacheDir.appendingPathComponent("\(cacheId).img")
            if FileManager.default.fileExists(atPath: diskFile.path),
               let data = try? Data(contentsOf: diskFile),
               let img = Self.generateImageThumbnailFromData(data, maxPixelSize: maxPixelSize) {
                cache.setObject(img, forKey: key)
                return img
            }

            // 2. Images: fetch high-speed preview from Claro drive
            if item.isImage, let fileId = item.cloudFileId, !fileId.isEmpty {
                if let img = await loadClaroDrivePreview(fileId: fileId, maxPixelSize: maxPixelSize, cacheKey: key) {
                    return img
                }
            }

            // 3. Videos: extract keyframe either from opened cache or directly over HTTP range requests
            if item.isVideo {
                // Check if already opened/downloaded in /tmp/WinExplorerMac_CloudOpened/<cacheId>/
                let openedDir = URL(fileURLWithPath: "/tmp/WinExplorerMac_CloudOpened/\(cacheId)", isDirectory: true)
                if let files = try? FileManager.default.contentsOfDirectory(at: openedDir, includingPropertiesForKeys: nil),
                   let firstVid = files.first(where: { !["img", "txt"].contains($0.pathExtension.lowercased()) }) {
                    if let generated = Self.generateVideoThumbnail(at: firstVid, maxPixelSize: maxPixelSize) {
                        cache.setObject(generated, forKey: key)
                        if let data = Self.jpegData(from: generated) {
                            try? data.write(to: diskFile, options: .atomic)
                        }
                        return generated
                    }
                }

                // Extract first keyframe directly over HTTP range requests using AVURLAsset
                if let remoteURL = FileSystemService.shared.claroDriveEncodedWebDavURL(for: item.url),
                   let creds = FileSystemService.shared.claroDriveCredentials() {
                    let authData = Data("\(creds.user):\(creds.password)".utf8).base64EncodedString()
                    let headers: [String: String] = [
                        "Authorization": "Basic \(authData)",
                        "User-Agent": creds.userAgent
                    ]
                    if let generated = await Self.generateRemoteVideoThumbnail(remoteURL: remoteURL, headers: headers, maxPixelSize: maxPixelSize) {
                        cache.setObject(generated, forKey: key)
                        if let data = Self.jpegData(from: generated) {
                            try? data.write(to: diskFile, options: .atomic)
                        }
                        return generated
                    }
                }
            }

            return nil
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
            if (item.isImage || item.isVideo) {
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
        } else if item.isVideo {
            workQueue.async { [weak self] in
                if let generated = Self.generateVideoThumbnail(at: fileURL, maxPixelSize: maxPixelSize) {
                    self?.cache.setObject(generated, forKey: key)
                    DispatchQueue.main.async {
                        completion(generated)
                    }
                } else {
                    self?.generateQuickLookThumbnail(at: fileURL, targetSize: targetSize, key: key, completion: completion)
                }
            }
        } else if item.isQuickLookThumbnailSupported {
            generateQuickLookThumbnail(at: fileURL, targetSize: targetSize, key: key, completion: completion)
        } else {
            completion(nil)
        }
    }

    private func generateQuickLookThumbnail(at fileURL: URL, targetSize: CGFloat, key: NSString, completion: @escaping (NSImage?) -> Void) {
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
    }

    public static func generateVideoThumbnail(at url: URL, maxPixelSize: Int) -> NSImage? {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: maxPixelSize * 2, height: maxPixelSize * 2)
        generator.requestedTimeToleranceBefore = .positiveInfinity
        generator.requestedTimeToleranceAfter = .positiveInfinity

        let candidateTimes = [
            CMTime(seconds: 1.0, preferredTimescale: 600),
            CMTime(seconds: 0.1, preferredTimescale: 600),
            CMTime.zero
        ]
        for time in candidateTimes {
            if let cgImage = try? generator.copyCGImage(at: time, actualTime: nil) {
                return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
            }
        }
        return nil
    }

    private static func generateRemoteVideoThumbnail(remoteURL: URL, headers: [String: String], maxPixelSize: Int) async -> NSImage? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let asset = AVURLAsset(url: remoteURL, options: ["AVURLAssetHTTPHeaderFieldsKey": headers])
                let generator = AVAssetImageGenerator(asset: asset)
                generator.appliesPreferredTrackTransform = true
                generator.maximumSize = CGSize(width: maxPixelSize * 2, height: maxPixelSize * 2)
                generator.requestedTimeToleranceBefore = .positiveInfinity
                generator.requestedTimeToleranceAfter = .positiveInfinity

                let candidateTimes = [
                    CMTime(seconds: 1.0, preferredTimescale: 600),
                    CMTime(seconds: 0.1, preferredTimescale: 600),
                    CMTime.zero
                ]
                for time in candidateTimes {
                    if let cgImage = try? generator.copyCGImage(at: time, actualTime: nil) {
                        let img = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
                        continuation.resume(returning: img)
                        return
                    }
                }
                continuation.resume(returning: nil)
            }
        }
    }

    public static func jpegData(from image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .jpeg, properties: [.compressionFactor: 0.88])
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
