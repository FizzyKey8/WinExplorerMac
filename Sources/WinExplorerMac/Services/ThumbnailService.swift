import Foundation
import AppKit
import ImageIO
import QuickLookThumbnailing

public final class ThumbnailService {
    public static let shared = ThumbnailService()

    private let cache = NSCache<NSString, NSImage>()
    private let workQueue = DispatchQueue(label: "com.winexplorermac.thumbnails", qos: .userInitiated, attributes: .concurrent)

    private init() {
        cache.countLimit = 600
    }

    public func cacheKey(for item: FileItem, targetSize: CGFloat) -> NSString {
        let bucket = targetSize <= 28 ? 64 : (targetSize <= 64 ? 160 : 320)
        let modTime = item.modificationDate?.timeIntervalSince1970 ?? 0
        return "\(item.url.path)|\(Int(modTime))|\(bucket)" as NSString
    }

    public func cachedThumbnail(for item: FileItem, targetSize: CGFloat) -> NSImage? {
        cache.object(forKey: cacheKey(for: item, targetSize: targetSize))
    }

    public func loadThumbnail(for item: FileItem, targetSize: CGFloat, completion: @escaping (NSImage?) -> Void) {
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
