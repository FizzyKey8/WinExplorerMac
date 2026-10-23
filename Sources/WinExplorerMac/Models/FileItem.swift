import Foundation
import AppKit
import UniformTypeIdentifiers

public extension URL {
    /// Purely lexical file URL normalization that never touches the filesystem or blocks on dataless CloudStorage vnodes.
    var cleanFileURL: URL {
        let rawPath = self.path
        if rawPath.isEmpty || rawPath == "/" {
            return URL(fileURLWithPath: "/", isDirectory: true)
        }
        var trimmed = rawPath
        while trimmed.count > 1 && trimmed.hasSuffix("/") {
            trimmed.removeLast()
        }
        return URL(fileURLWithPath: trimmed, isDirectory: self.hasDirectoryPath)
    }
}

public struct FileItem: Identifiable, Hashable {
    public let id: URL
    public let url: URL
    public let name: String
    public let fileExtension: String
    public let isDirectory: Bool
    public let isHidden: Bool
    public let isSymlink: Bool
    public let size: Int64
    public let creationDate: Date?
    public let modificationDate: Date?
    public let lastAccessDate: Date?
    public let fileTypeDescription: String
    public let posixPermissions: Int
    public let isCloudDataless: Bool
    public let cloudFileId: String?

    public init(
        url: URL,
        name: String? = nil,
        isDirectory: Bool = false,
        isHidden: Bool = false,
        isSymlink: Bool = false,
        size: Int64 = 0,
        creationDate: Date? = nil,
        modificationDate: Date? = nil,
        lastAccessDate: Date? = nil,
        fileTypeDescription: String? = nil,
        posixPermissions: Int = 0o755,
        isCloudDataless: Bool = false,
        cloudFileId: String? = nil
    ) {
        let clean = URL(fileURLWithPath: url.path, isDirectory: isDirectory)
        self.id = clean
        self.url = clean
        self.name = name ?? url.lastPathComponent
        self.fileExtension = url.pathExtension.lowercased()
        self.isDirectory = isDirectory
        self.isHidden = isHidden
        self.isSymlink = isSymlink
        self.size = size
        self.creationDate = creationDate
        self.modificationDate = modificationDate
        self.lastAccessDate = lastAccessDate
        if let fileTypeDescription {
            self.fileTypeDescription = fileTypeDescription
        } else if isDirectory {
            self.fileTypeDescription = "Carpeta de archivos"
        } else if !url.pathExtension.isEmpty {
            self.fileTypeDescription = "Archivo \(url.pathExtension.uppercased())"
        } else {
            self.fileTypeDescription = "Archivo"
        }
        self.posixPermissions = posixPermissions
        self.isCloudDataless = isCloudDataless
        self.cloudFileId = cloudFileId
    }

    public func displayName(showExtensions: Bool) -> String {
        if isDirectory || showExtensions || fileExtension.isEmpty {
            return name
        }
        return url.deletingPathExtension().lastPathComponent
    }

    public var formattedSize: String {
        if isDirectory {
            return ""
        }
        let kb = Double(size) / 1024.0
        if kb < 1 {
            return size == 0 ? "0 KB" : "1 KB"
        } else if kb < 1024 {
            return String(format: "%.0f KB", ceil(kb))
        } else {
            let mb = kb / 1024.0
            if mb < 1024 {
                return String(format: "%.1f MB", mb)
            } else {
                let gb = mb / 1024.0
                return String(format: "%.2f GB", gb)
            }
        }
    }

    public var detailedByteSize: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        let bytesStr = formatter.string(from: NSNumber(value: size)) ?? "\(size)"
        return "\(formattedSize.isEmpty ? "0 KB" : formattedSize) (\(bytesStr) bytes)"
    }

    public var formattedModificationDate: String {
        guard let date = modificationDate else { return "—" }
        return Self.win11DateFormatter.string(from: date)
    }

    public var formattedCreationDate: String {
        guard let date = creationDate else { return "—" }
        return Self.win11DateFormatter.string(from: date)
    }

    public var isArchiveZip: Bool {
        fileExtension == "zip"
    }

    public var isImage: Bool {
        ["png", "jpg", "jpeg", "gif", "webp", "heic", "heif", "bmp", "tiff", "tif", "svg", "ico", "avif", "icns"].contains(fileExtension)
    }

    public var isQuickLookThumbnailSupported: Bool {
        ["pdf", "mp4", "mov", "m4v", "avi", "mkv"].contains(fileExtension)
    }

    public var isTextPreviewable: Bool {
        [
            "txt", "md", "json", "xml", "yaml", "yml", "csv", "log", "ini", "conf",
            "swift", "py", "js", "ts", "tsx", "jsx", "html", "css", "sh", "zsh", "c", "cpp", "h", "rs", "go", "java"
        ].contains(fileExtension)
    }

    private static let iconCache = NSCache<NSString, NSImage>()

    public var systemIcon: NSImage {
        if fileExtension == "app" && !isCloudDataless {
            return NSWorkspace.shared.icon(forFile: url.path)
        }
        let key = (fileExtension.isEmpty ? "__generic_data__" : fileExtension) as NSString
        if let cached = Self.iconCache.object(forKey: key) {
            return cached
        }
        let icon: NSImage
        if !fileExtension.isEmpty, let utType = UTType(filenameExtension: fileExtension) {
            icon = NSWorkspace.shared.icon(for: utType)
        } else {
            icon = NSWorkspace.shared.icon(for: .data)
        }
        Self.iconCache.setObject(icon, forKey: key)
        return icon
    }

    public var parentPath: String {
        url.deletingLastPathComponent().path
    }

    private static let win11DateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.locale = Locale(identifier: "es_ES")
        df.dateFormat = "dd/MM/yyyy HH:mm"
        return df
    }()
}
