import Foundation
import AppKit

public final class FileSystemService {
    public static let shared = FileSystemService()

    private let fileManager = FileManager.default
    private let resourceKeys: Set<URLResourceKey> = [
        .nameKey,
        .isDirectoryKey,
        .isHiddenKey,
        .isSymbolicLinkKey,
        .fileSizeKey,
        .totalFileAllocatedSizeKey,
        .creationDateKey,
        .contentModificationDateKey,
        .contentAccessDateKey,
        .localizedTypeDescriptionKey
    ]

    public static var trashDirectoryURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".Trash").standardizedFileURL
    }

    public static var mobileDocumentsRootURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Mobile Documents")
            .standardizedFileURL
    }

    public static var iCloudDriveURL: URL {
        mobileDocumentsRootURL
            .appendingPathComponent("com~apple~CloudDocs")
            .standardizedFileURL
    }

    public static var cloudStorageRootURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/CloudStorage")
            .standardizedFileURL
    }

    public static let iCloudAppContainers: [(container: String, title: String)] = [
        ("com~apple~Pages", "Pages"),
        ("com~apple~Numbers", "Numbers"),
        ("com~apple~Keynote", "Keynote"),
        ("com~apple~Preview", "Vista Previa"),
        ("com~apple~TextEdit", "TextEdit"),
        ("com~apple~QuickTimePlayerX", "QuickTime Player"),
        ("com~apple~Automator", "Automator"),
        ("com~apple~ScriptEditor2", "Editor de Scripts"),
        ("iCloud~is~workflow~my~workflows", "Atajos"),
        ("F6266T9T75~com~apple~iMovie", "iMovie"),
        ("F3LWYJ7GM7~com~apple~garageband10", "GarageBand"),
        ("iCloud~com~clarodrive", "Claro drive (iCloud)")
    ]

    public static func parseCloudProviderFolderName(_ folderName: String) -> (name: String, subtitle: String, isClaro: Bool) {
        let lower = folderName.lowercased()
        if lower.hasPrefix("clarodrive") {
            let parts = folderName.split(separator: "-", maxSplits: 1)
            let acct = parts.count > 1 ? String(parts[1]) : "Almacenamiento en la nube"
            return ("Claro drive", acct, true)
        } else if lower.hasPrefix("onedrive") {
            let parts = folderName.split(separator: "-", maxSplits: 1)
            let acct = parts.count > 1 ? String(parts[1]) : "Microsoft OneDrive"
            return ("OneDrive", acct, false)
        } else if lower.hasPrefix("googledrive") || lower.hasPrefix("google drive") {
            let parts = folderName.split(separator: "-", maxSplits: 1)
            let acct = parts.count > 1 ? String(parts[1]) : "Google Drive"
            return ("Google Drive", acct, false)
        } else if lower.hasPrefix("dropbox") {
            return ("Dropbox", "Almacenamiento en la nube", false)
        } else if lower.hasPrefix("box") {
            return ("Box", "Almacenamiento en la nube", false)
        } else {
            return (folderName, "Almacenamiento en la nube", false)
        }
    }

    public func cloudDrives() -> [CloudDriveInfo] {
        var drives: [CloudDriveInfo] = []

        // 1. iCloud Drive
        let icloudURL = Self.iCloudDriveURL
        if fileManager.fileExists(atPath: icloudURL.path) || fileManager.fileExists(atPath: Self.mobileDocumentsRootURL.path) {
            drives.append(
                CloudDriveInfo(
                    url: icloudURL,
                    name: "iCloud Drive",
                    subtitle: "Apple iCloud",
                    sfSymbol: "icloud.fill",
                    isClaroDrive: false,
                    isICloud: true
                )
            )
        }

        // 2. Third-party CloudStorage providers (Claro drive, OneDrive, Google Drive, Dropbox, etc.)
        let cloudRoot = Self.cloudStorageRootURL
        if let entries = try? fileManager.contentsOfDirectory(
            at: cloudRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) {
            for entry in entries.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                var isDir: ObjCBool = false
                if fileManager.fileExists(atPath: entry.path, isDirectory: &isDir), isDir.boolValue {
                    let parsed = Self.parseCloudProviderFolderName(entry.lastPathComponent)
                    drives.append(
                        CloudDriveInfo(
                            url: entry,
                            name: parsed.name,
                            subtitle: parsed.subtitle,
                            sfSymbol: "cloud.fill",
                            isClaroDrive: parsed.isClaro,
                            isICloud: false
                        )
                    )
                }
            }
        }

        return drives
    }

    private init() {}

    // MARK: - List Directory Contents
    public func contentsOfDirectory(at url: URL, includeHidden: Bool) throws -> [FileItem] {
        var options: FileManager.DirectoryEnumerationOptions = [.skipsSubdirectoryDescendants, .skipsPackageDescendants]
        if !includeHidden {
            options.insert(.skipsHiddenFiles)
        }

        let stdURL = url.standardizedFileURL

        do {
            let urls = try fileManager.contentsOfDirectory(
                at: stdURL,
                includingPropertiesForKeys: Array(resourceKeys),
                options: options
            )

            var items = urls.compactMap { itemURL in
                makeFileItem(from: itemURL)
            }

            // When viewing iCloud Drive root, also surface iCloud app Documents folders just like macOS Finder
            if stdURL == Self.iCloudDriveURL {
                let existingNames = Set(items.map { $0.name.lowercased() })
                for (container, title) in Self.iCloudAppContainers {
                    guard !existingNames.contains(title.lowercased()) else { continue }
                    let docsURL = Self.mobileDocumentsRootURL
                        .appendingPathComponent(container)
                        .appendingPathComponent("Documents")
                        .standardizedFileURL
                    var isDir: ObjCBool = false
                    if fileManager.fileExists(atPath: docsURL.path, isDirectory: &isDir), isDir.boolValue {
                        if let appFolderItem = makeFileItem(from: docsURL, customDisplayName: title) {
                            items.append(appFolderItem)
                        }
                    }
                }
            }

            return items
        } catch {
            if stdURL == Self.trashDirectoryURL {
                if let fallbackItems = listTrashViaFinder(includeHidden: includeHidden) {
                    return fallbackItems
                }
            }
            throw error
        }
    }

    private func listTrashViaFinder(includeHidden: Bool) -> [FileItem]? {
        let script = """
        tell application "Finder"
            set itemNames to name of every item of trash
            if (count of itemNames) is 0 then return ""
            set itemKinds to kind of every item of trash
            set outList to {}
            repeat with i from 1 to count of itemNames
                set n to item i of itemNames
                set k to item i of itemKinds
                set end of outList to (n as string) & "\t" & (k as string)
            end repeat
            set AppleScript's text item delimiters to "\n"
            return outList as string
        end tell
        """
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        proc.arguments = ["-e", script]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = Pipe()
        do {
            try proc.run()
            proc.waitUntilExit()
            guard proc.terminationStatus == 0 else { return nil }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if output.isEmpty { return [] }
            let trashRoot = Self.trashDirectoryURL
            return output.components(separatedBy: "\n").compactMap { line -> FileItem? in
                let parts = line.components(separatedBy: "\t")
                guard parts.count >= 2 else { return nil }
                let name = parts[0]
                if !includeHidden && name.hasPrefix(".") { return nil }
                let kind = parts[1]
                let lowerKind = kind.lowercased()
                let isDir = lowerKind == "carpeta" || lowerKind == "folder"
                let itemURL = trashRoot.appendingPathComponent(name)
                return FileItem(
                    url: itemURL,
                    name: name,
                    isDirectory: isDir,
                    isHidden: name.hasPrefix("."),
                    isSymlink: false,
                    size: 0,
                    creationDate: nil,
                    modificationDate: Date(),
                    lastAccessDate: nil,
                    fileTypeDescription: kind
                )
            }
        } catch {
            return nil
        }
    }

    public func emptyTrash() {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        proc.arguments = ["-e", "tell application \"Finder\" to empty the trash"]
        try? proc.run()
        proc.waitUntilExit()
    }

    public func makeFileItem(from url: URL, customDisplayName: String? = nil) -> FileItem? {
        let stdURL = url.standardizedFileURL
        if stdURL == Self.trashDirectoryURL {
            return FileItem(
                url: stdURL,
                name: "Basurero",
                isDirectory: true,
                isHidden: false,
                isSymlink: false,
                size: 0,
                creationDate: nil,
                modificationDate: nil,
                lastAccessDate: nil,
                fileTypeDescription: "Papelera de reciclaje",
                posixPermissions: 0o700
            )
        }
        if stdURL == Self.iCloudDriveURL {
            return FileItem(
                url: stdURL,
                name: "iCloud Drive",
                isDirectory: true,
                isHidden: false,
                isSymlink: false,
                size: 0,
                creationDate: nil,
                modificationDate: nil,
                lastAccessDate: nil,
                fileTypeDescription: "Almacenamiento en la nube",
                posixPermissions: 0o700
            )
        }
        guard fileManager.fileExists(atPath: stdURL.path) else { return nil }

        let values = try? stdURL.resourceValues(forKeys: resourceKeys)
        let attrs = try? fileManager.attributesOfItem(atPath: stdURL.path)

        let isDir = values?.isDirectory ?? false
        let isHidden = (values?.isHidden ?? false) || stdURL.lastPathComponent.hasPrefix(".")
        let isSymlink = values?.isSymbolicLink ?? false
        let size = Int64(values?.fileSize ?? values?.totalFileAllocatedSize ?? 0)
        let creationDate = values?.creationDate ?? (attrs?[.creationDate] as? Date)
        let modDate = values?.contentModificationDate ?? (attrs?[.modificationDate] as? Date)
        let accessDate = values?.contentAccessDate
        let typeDesc = values?.localizedTypeDescription
        let posix = (attrs?[.posixPermissions] as? Int) ?? 0o755

        let resolvedName: String
        if let customDisplayName {
            resolvedName = customDisplayName
        } else if stdURL.deletingLastPathComponent().standardizedFileURL == Self.cloudStorageRootURL {
            resolvedName = Self.parseCloudProviderFolderName(stdURL.lastPathComponent).name
        } else {
            resolvedName = stdURL.lastPathComponent
        }

        return FileItem(
            url: stdURL,
            name: resolvedName,
            isDirectory: isDir,
            isHidden: isHidden,
            isSymlink: isSymlink,
            size: size,
            creationDate: creationDate,
            modificationDate: modDate,
            lastAccessDate: accessDate,
            fileTypeDescription: typeDesc,
            posixPermissions: posix
        )
    }

    // MARK: - Mounted Volumes (This PC / Este equipo)
    public func mountedVolumes() -> [VolumeInfo] {
        let keys: [URLResourceKey] = [
            .volumeNameKey,
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeIsRemovableKey,
            .volumeIsInternalKey,
            .volumeLocalizedFormatDescriptionKey
        ]

        let urls = fileManager.mountedVolumeURLs(includingResourceValuesForKeys: keys, options: [.skipHiddenVolumes]) ?? [URL(fileURLWithPath: "/")]
        let driveLetters = ["C:", "D:", "E:", "F:", "G:", "H:", "I:", "J:"]

        var volumes: [VolumeInfo] = []
        for (idx, volURL) in urls.enumerated() {
            let values = try? volURL.resourceValues(forKeys: Set(keys))
            let name = values?.volumeName ?? (volURL.path == "/" ? "Macintosh HD" : volURL.lastPathComponent)
            let total = Int64(values?.volumeTotalCapacity ?? 0)
            let availImportant = values?.volumeAvailableCapacityForImportantUsage ?? 0
            let availStandard = Int64(values?.volumeAvailableCapacity ?? 0)
            let available = availImportant > 0 ? availImportant : availStandard
            let removable = values?.volumeIsRemovable ?? false
            let isInternal = values?.volumeIsInternal ?? (volURL.path == "/")
            let format = values?.volumeLocalizedFormatDescription ?? "APFS"
            let badge = idx < driveLetters.count ? driveLetters[idx] : "Z:"

            volumes.append(
                VolumeInfo(
                    id: volURL,
                    url: volURL,
                    name: name,
                    driveLetterBadge: badge,
                    totalCapacity: total,
                    availableCapacity: available,
                    isRemovable: removable,
                    isInternal: isInternal,
                    fileSystemType: format
                )
            )
        }
        return volumes
    }

    // MARK: - Create New Folder / File
    @discardableResult
    public func createNewItem(in directory: URL, template: NewItemTemplate) throws -> URL {
        let targetURL = uniqueDestinationURL(forBaseName: template.defaultBaseName, in: directory)
        if template == .folder {
            try fileManager.createDirectory(at: targetURL, withIntermediateDirectories: false)
        } else {
            let data = template.defaultContents.data(using: .utf8) ?? Data()
            fileManager.createFile(atPath: targetURL.path, contents: data)
        }
        return targetURL
    }

    // MARK: - Rename Item
    @discardableResult
    public func renameItem(at url: URL, to newName: String) throws -> URL {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains("/") else {
            throw NSError(domain: "WinExplorerMac", code: 400, userInfo: [
                NSLocalizedDescriptionKey: "Los nombres de archivo no pueden estar vacíos ni contener el carácter '/'."
            ])
        }
        let destination = url.deletingLastPathComponent().appendingPathComponent(trimmed)
        if destination.standardizedFileURL == url.standardizedFileURL {
            return url
        }
        try fileManager.moveItem(at: url, to: destination)
        return destination
    }

    // MARK: - Copy / Move (Paste)
    @discardableResult
    public func copyOrMoveItems(_ sourceURLs: [URL], to destinationDirectory: URL, isCutOperation: Bool) throws -> [URL] {
        var resultingURLs: [URL] = []

        for srcURL in sourceURLs {
            let srcStd = srcURL.standardizedFileURL
            let dstDirStd = destinationDirectory.standardizedFileURL
            guard fileManager.fileExists(atPath: srcStd.path) else { continue }

            let proposedDest = dstDirStd.appendingPathComponent(srcStd.lastPathComponent)

            if isCutOperation {
                if proposedDest == srcStd {
                    resultingURLs.append(srcStd)
                    continue
                }
                let finalDest = fileManager.fileExists(atPath: proposedDest.path)
                    ? uniqueCopyDestinationURL(for: srcStd, in: dstDirStd, suffix: "")
                    : proposedDest
                try fileManager.moveItem(at: srcStd, to: finalDest)
                resultingURLs.append(finalDest)
            } else {
                let finalDest = fileManager.fileExists(atPath: proposedDest.path)
                    ? uniqueCopyDestinationURL(for: srcStd, in: dstDirStd, suffix: " - copia")
                    : proposedDest
                try fileManager.copyItem(at: srcStd, to: finalDest)
                resultingURLs.append(finalDest)
            }
        }
        return resultingURLs
    }

    // MARK: - Trash & Permanent Delete
    public func moveToTrash(_ urls: [URL]) throws {
        for url in urls {
            var resultingURL: NSURL?
            try fileManager.trashItem(at: url, resultingItemURL: &resultingURL)
        }
    }

    public func deletePermanently(_ urls: [URL]) throws {
        for url in urls {
            try fileManager.removeItem(at: url)
        }
    }

    // MARK: - Open / Reveal / Terminal / Share
    public func openItem(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

    public func availableApplications(for url: URL) -> [URL] {
        NSWorkspace.shared.urlsForApplications(toOpen: url)
    }

    public func openItem(_ url: URL, withApplication appURL: URL) {
        let config = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.open([url], withApplicationAt: appURL, configuration: config, completionHandler: nil)
    }

    public func openInTerminal(at directoryURL: URL) {
        let targetDir: URL = {
            var isDir: ObjCBool = false
            if fileManager.fileExists(atPath: directoryURL.path, isDirectory: &isDir), !isDir.boolValue {
                return directoryURL.deletingLastPathComponent()
            }
            return directoryURL
        }()

        if let terminalURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Terminal") {
            let config = NSWorkspace.OpenConfiguration()
            NSWorkspace.shared.open([targetDir], withApplicationAt: terminalURL, configuration: config, completionHandler: nil)
        }
    }

    public func revealInFinder(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    public func copyPathToPasteboard(_ urls: [URL], quoted: Bool = true) {
        let paths = urls.map { url in
            quoted ? "\"\(url.path)\"" : url.path
        }.joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(paths, forType: .string)
    }

    // MARK: - Recursive Folder Size Calculation (for Properties Modal)
    public func calculateFolderMetrics(at url: URL) -> (totalBytes: Int64, fileCount: Int, folderCount: Int) {
        var totalBytes: Int64 = 0
        var fileCount = 0
        var folderCount = 0

        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey],
            options: []
        ) else {
            return (0, 0, 0)
        }

        for case let itemURL as URL in enumerator {
            let values = try? itemURL.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey])
            if values?.isDirectory == true {
                folderCount += 1
            } else {
                fileCount += 1
                totalBytes += Int64(values?.fileSize ?? 0)
            }
        }
        return (totalBytes, fileCount, folderCount)
    }

    // MARK: - Unique Name Resolution (Windows 11 Style)
    public func uniqueDestinationURL(forBaseName baseName: String, in directory: URL) -> URL {
        let initial = directory.appendingPathComponent(baseName)
        if !fileManager.fileExists(atPath: initial.path) {
            return initial
        }

        let ext = (baseName as NSString).pathExtension
        let stem = (baseName as NSString).deletingPathExtension

        var counter = 2
        while true {
            let candidateName = ext.isEmpty
                ? "\(stem) (\(counter))"
                : "\(stem) (\(counter)).\(ext)"
            let candidateURL = directory.appendingPathComponent(candidateName)
            if !fileManager.fileExists(atPath: candidateURL.path) {
                return candidateURL
            }
            counter += 1
        }
    }

    private func uniqueCopyDestinationURL(for sourceURL: URL, in directory: URL, suffix: String) -> URL {
        let ext = sourceURL.pathExtension
        let stem = sourceURL.deletingPathExtension().lastPathComponent

        let firstCandidateName = ext.isEmpty
            ? "\(stem)\(suffix)"
            : "\(stem)\(suffix).\(ext)"
        let firstCandidate = directory.appendingPathComponent(firstCandidateName)
        if !fileManager.fileExists(atPath: firstCandidate.path) {
            return firstCandidate
        }

        var counter = 2
        while true {
            let candidateName = ext.isEmpty
                ? "\(stem)\(suffix) (\(counter))"
                : "\(stem)\(suffix) (\(counter)).\(ext)"
            let candidateURL = directory.appendingPathComponent(candidateName)
            if !fileManager.fileExists(atPath: candidateURL.path) {
                return candidateURL
            }
            counter += 1
        }
    }
}
