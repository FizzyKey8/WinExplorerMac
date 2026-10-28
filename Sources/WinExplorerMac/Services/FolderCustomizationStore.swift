import Foundation
import SwiftUI
import AppKit

extension Notification.Name {
    public static let folderCustomizationChanged = Notification.Name("WinExplorerFolderCustomizationChanged")
}

public enum FolderCustomColor: String, CaseIterable, Identifiable, Codable {
    case yellow = "yellow"
    case blue = "blue"
    case green = "green"
    case red = "red"
    case purple = "purple"
    case pink = "pink"
    case orange = "orange"
    case teal = "teal"
    case graphite = "graphite"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .yellow: return "Amarillo (Predeterminado)"
        case .blue: return "Azul"
        case .green: return "Verde"
        case .red: return "Rojo"
        case .purple: return "Púrpura"
        case .pink: return "Rosa"
        case .orange: return "Naranja"
        case .teal: return "Turquesa"
        case .graphite: return "Grafito"
        }
    }

    public var swatchColor: Color {
        switch self {
        case .yellow: return Color(red: 0.99, green: 0.75, blue: 0.16)
        case .blue: return Color(red: 0.0, green: 0.50, blue: 0.88)
        case .green: return Color(red: 0.16, green: 0.68, blue: 0.38)
        case .red: return Color(red: 0.90, green: 0.24, blue: 0.24)
        case .purple: return Color(red: 0.58, green: 0.32, blue: 0.82)
        case .pink: return Color(red: 0.92, green: 0.35, blue: 0.60)
        case .orange: return Color(red: 0.95, green: 0.50, blue: 0.15)
        case .teal: return Color(red: 0.08, green: 0.68, blue: 0.70)
        case .graphite: return Color(red: 0.42, green: 0.45, blue: 0.50)
        }
    }

    public var backTabColors: [Color] {
        switch self {
        case .yellow:
            return [Color(red: 0.98, green: 0.74, blue: 0.15), Color(red: 0.90, green: 0.61, blue: 0.06)]
        case .blue:
            return [Color(red: 0.0, green: 0.52, blue: 0.88), Color(red: 0.0, green: 0.42, blue: 0.78)]
        case .green:
            return [Color(red: 0.16, green: 0.68, blue: 0.38), Color(red: 0.11, green: 0.56, blue: 0.30)]
        case .red:
            return [Color(red: 0.92, green: 0.26, blue: 0.26), Color(red: 0.80, green: 0.18, blue: 0.18)]
        case .purple:
            return [Color(red: 0.58, green: 0.32, blue: 0.82), Color(red: 0.48, green: 0.24, blue: 0.72)]
        case .pink:
            return [Color(red: 0.92, green: 0.35, blue: 0.60), Color(red: 0.82, green: 0.25, blue: 0.50)]
        case .orange:
            return [Color(red: 0.95, green: 0.50, blue: 0.15), Color(red: 0.85, green: 0.40, blue: 0.08)]
        case .teal:
            return [Color(red: 0.08, green: 0.68, blue: 0.70), Color(red: 0.04, green: 0.56, blue: 0.58)]
        case .graphite:
            return [Color(red: 0.42, green: 0.45, blue: 0.50), Color(red: 0.32, green: 0.35, blue: 0.40)]
        }
    }

    public var backBodyColors: [Color] {
        switch self {
        case .yellow:
            return [Color(red: 0.95, green: 0.67, blue: 0.09), Color(red: 0.86, green: 0.56, blue: 0.04)]
        case .blue:
            return [Color(red: 0.0, green: 0.46, blue: 0.82), Color(red: 0.0, green: 0.36, blue: 0.72)]
        case .green:
            return [Color(red: 0.13, green: 0.60, blue: 0.33), Color(red: 0.09, green: 0.49, blue: 0.25)]
        case .red:
            return [Color(red: 0.84, green: 0.22, blue: 0.22), Color(red: 0.72, green: 0.14, blue: 0.14)]
        case .purple:
            return [Color(red: 0.52, green: 0.28, blue: 0.76), Color(red: 0.42, green: 0.20, blue: 0.64)]
        case .pink:
            return [Color(red: 0.85, green: 0.30, blue: 0.54), Color(red: 0.74, green: 0.20, blue: 0.44)]
        case .orange:
            return [Color(red: 0.88, green: 0.44, blue: 0.10), Color(red: 0.78, green: 0.34, blue: 0.05)]
        case .teal:
            return [Color(red: 0.06, green: 0.60, blue: 0.62), Color(red: 0.03, green: 0.48, blue: 0.50)]
        case .graphite:
            return [Color(red: 0.36, green: 0.39, blue: 0.44), Color(red: 0.26, green: 0.29, blue: 0.34)]
        }
    }

    public var frontPlateColors: [Color] {
        switch self {
        case .yellow:
            return [Color(red: 1.0, green: 0.86, blue: 0.36), Color(red: 0.99, green: 0.75, blue: 0.16)]
        case .blue:
            return [Color(red: 0.18, green: 0.64, blue: 0.98), Color(red: 0.0, green: 0.50, blue: 0.88)]
        case .green:
            return [Color(red: 0.28, green: 0.79, blue: 0.48), Color(red: 0.15, green: 0.68, blue: 0.37)]
        case .red:
            return [Color(red: 0.98, green: 0.42, blue: 0.42), Color(red: 0.90, green: 0.24, blue: 0.24)]
        case .purple:
            return [Color(red: 0.70, green: 0.45, blue: 0.92), Color(red: 0.56, green: 0.30, blue: 0.80)]
        case .pink:
            return [Color(red: 0.98, green: 0.52, blue: 0.74), Color(red: 0.90, green: 0.33, blue: 0.58)]
        case .orange:
            return [Color(red: 1.0, green: 0.64, blue: 0.28), Color(red: 0.94, green: 0.48, blue: 0.12)]
        case .teal:
            return [Color(red: 0.20, green: 0.79, blue: 0.80), Color(red: 0.07, green: 0.66, blue: 0.68)]
        case .graphite:
            return [Color(red: 0.55, green: 0.58, blue: 0.64), Color(red: 0.40, green: 0.43, blue: 0.48)]
        }
    }
}

public struct FolderCustomizationRecord: Codable {
    public var colorRaw: String?
    public var imageFileName: String?

    public init(color: FolderCustomColor? = nil, imageFileName: String? = nil) {
        self.colorRaw = color?.rawValue
        self.imageFileName = imageFileName
    }

    public var color: FolderCustomColor? {
        get { colorRaw.flatMap(FolderCustomColor.init(rawValue:)) }
        set { colorRaw = newValue?.rawValue }
    }
}

public final class FolderCustomizationStore: ObservableObject {
    public static let shared = FolderCustomizationStore()

    private let defaultsKey = "WinExplorer_FolderCustomizations_v1"
    private var records: [String: FolderCustomizationRecord] = [:]
    private var imageMemoryCache = NSCache<NSString, NSImage>()

    @Published public private(set) var changeVersion: Int = 0

    private init() {
        loadRecords()
    }

    private var storageDirectoryURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("WinExplorerMac/FolderIcons", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    private func cleanKey(for url: URL) -> String {
        url.cleanFileURL.path
    }

    private func loadRecords() {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let decoded = try? JSONDecoder().decode([String: FolderCustomizationRecord].self, from: data) else {
            return
        }
        self.records = decoded
    }

    private func saveRecords() {
        if let encoded = try? JSONEncoder().encode(records) {
            UserDefaults.standard.set(encoded, forKey: defaultsKey)
        }
        DispatchQueue.main.async {
            self.changeVersion += 1
            NotificationCenter.default.post(name: .folderCustomizationChanged, object: nil)
        }
    }

    public func customColor(for url: URL) -> FolderCustomColor? {
        let key = cleanKey(for: url)
        return records[key]?.color
    }

    public func customImage(for url: URL) -> NSImage? {
        let key = cleanKey(for: url)
        guard let fileName = records[key]?.imageFileName else { return nil }

        if let cached = imageMemoryCache.object(forKey: fileName as NSString) {
            return cached
        }

        let fileURL = storageDirectoryURL.appendingPathComponent(fileName)
        if let image = NSImage(contentsOf: fileURL) {
            imageMemoryCache.setObject(image, forKey: fileName as NSString)
            return image
        }
        return nil
    }

    public func hasCustomization(for url: URL) -> Bool {
        let key = cleanKey(for: url)
        guard let record = records[key] else { return false }
        return (record.color != nil && record.color != .yellow) || record.imageFileName != nil
    }

    public func setColor(_ color: FolderCustomColor?, for url: URL) {
        let key = cleanKey(for: url)
        var record = records[key] ?? FolderCustomizationRecord()
        if color == .yellow || color == nil {
            record.color = nil
        } else {
            record.color = color
        }
        // If empty, remove key
        if record.color == nil && record.imageFileName == nil {
            records.removeValue(forKey: key)
        } else {
            records[key] = record
        }
        saveRecords()
    }

    public func setCustomImage(at sourceURL: URL, for folderURL: URL) {
        let key = cleanKey(for: folderURL)
        guard let sourceImage = NSImage(contentsOf: sourceURL) else { return }

        // Generate consistent file name based on folder path hash
        let hash = String(format: "%08x", abs(key.hashValue))
        let fileName = "\(hash).png"
        let destURL = storageDirectoryURL.appendingPathComponent(fileName)

        // Save image as PNG
        if let tiffData = sourceImage.tiffRepresentation,
           let bitmap = NSBitmapImageRep(data: tiffData),
           let pngData = bitmap.representation(using: .png, properties: [:]) {
            try? pngData.write(to: destURL, options: .atomic)
        }

        imageMemoryCache.removeObject(forKey: fileName as NSString)
        if let newImage = NSImage(contentsOf: destURL) {
            imageMemoryCache.setObject(newImage, forKey: fileName as NSString)
            // Also update macOS system icon so Finder matches
            NSWorkspace.shared.setIcon(newImage, forFile: key, options: [])
        }

        var record = records[key] ?? FolderCustomizationRecord()
        record.imageFileName = fileName
        records[key] = record
        saveRecords()
    }

    public func resetCustomization(for folderURL: URL) {
        let key = cleanKey(for: folderURL)
        if let fileName = records[key]?.imageFileName {
            imageMemoryCache.removeObject(forKey: fileName as NSString)
            let destURL = storageDirectoryURL.appendingPathComponent(fileName)
            try? FileManager.default.removeItem(at: destURL)
        }
        records.removeValue(forKey: key)
        // Reset macOS system icon
        NSWorkspace.shared.setIcon(nil, forFile: key, options: [])
        saveRecords()
    }

    @MainActor
    public func promptChooseImage(for folderURL: URL, completion: (() -> Void)? = nil) {
        let panel = NSOpenPanel()
        panel.title = "Seleccionar imagen para la carpeta"
        panel.prompt = "Elegir icono"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [
            .png,
            .jpeg,
            .tiff,
            .image,
            .init(filenameExtension: "icns")!
        ]

        if panel.runModal() == .OK, let selectedURL = panel.url {
            self.setCustomImage(at: selectedURL, for: folderURL)
            completion?()
        }
    }
}
