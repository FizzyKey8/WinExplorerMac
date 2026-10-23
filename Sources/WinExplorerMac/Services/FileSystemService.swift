import Foundation
import AppKit
import UniformTypeIdentifiers
import Darwin
import ObjectiveC

public final class FileSystemService {
    public static let shared = FileSystemService()

    private let fileManager = FileManager.default
    private let typeDescriptionCache = NSCache<NSString, NSString>()
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

    private var cachedCloudDrives: [CloudDriveInfo]? = nil
    private var cachedCloudDrivesTimestamp: CFAbsoluteTime = 0

    public func cloudDrives() -> [CloudDriveInfo] {
        let now = CFAbsoluteTimeGetCurrent()
        if let cached = cachedCloudDrives, (now - cachedCloudDrivesTimestamp) < 10.0 {
            return cached
        }

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

        cachedCloudDrives = drives
        cachedCloudDrivesTimestamp = now
        return drives
    }

    private init() {}

    // MARK: - Fast Cached File Type Description
    public func fastTypeDescription(forName name: String, isDirectory: Bool) -> String {
        if isDirectory {
            if name.lowercased().hasSuffix(".app") {
                return "Aplicación"
            }
            return "Carpeta de archivos"
        }
        let ext = (name as NSString).pathExtension.lowercased()
        let key = (ext.isEmpty ? "__no_ext__" : ext) as NSString
        if let cached = typeDescriptionCache.object(forKey: key) {
            return cached as String
        }
        let desc: String
        if ext.isEmpty {
            desc = "Archivo"
        } else if let utType = UTType(filenameExtension: ext),
                  let localized = utType.localizedDescription, !localized.isEmpty {
            desc = localized
        } else {
            desc = "Archivo \(ext.uppercased())"
        }
        typeDescriptionCache.setObject(desc as NSString, forKey: key)
        return desc
    }

    public static func isCloudPath(_ path: String) -> Bool {
        path.hasPrefix(cloudStorageRootURL.path) || path.hasPrefix(mobileDocumentsRootURL.path)
    }

    // MARK: - Claro drive Direct Realm Metadata Reader (Bypasses FileProvider O(N^2) Bottleneck)
    private static var realmFrameworkLoaded: Bool = {
        let candidates = [
            "/Applications/Claro drive.app/Contents/PlugIns/FileProviderExt.appex/Contents/Frameworks/RealmSwift.framework/Versions/A/RealmSwift",
            "/Applications/Claro drive.app/Contents/PlugIns/FileProviderUIExt.appex/Contents/Frameworks/RealmSwift.framework/Versions/A/RealmSwift"
        ]
        for path in candidates {
            if dlopen(path, RTLD_NOW) != nil {
                return true
            }
        }
        return false
    }()

    private let realmSnapshotLock = NSLock()
    private var lastRealmSnapshotTime: CFAbsoluteTime = 0
    private var lastRealmSnapshotPath: String? = nil

    private func claroDriveServerUrl(for directoryURL: URL) -> String? {
        let stdPath = directoryURL.standardizedFileURL.path
        let cloudRootPath = Self.cloudStorageRootURL.path + "/"
        guard stdPath.hasPrefix(cloudRootPath) else { return nil }

        let remainder = String(stdPath.dropFirst(cloudRootPath.count))
        let components = remainder.split(separator: "/", omittingEmptySubsequences: false)
        guard let providerFolder = components.first.map(String.init),
              providerFolder.lowercased().hasPrefix("clarodrive-") else {
            return nil
        }

        let accountSpec = String(providerFolder.dropFirst("Clarodrive-".count))
        let acctParts = accountSpec.split(separator: "@", maxSplits: 1).map(String.init)
        guard acctParts.count == 2 else { return nil }
        let userId = acctParts[0]
        let host = acctParts[1]

        let providerRootPath = cloudRootPath + providerFolder
        let relativePath: String
        if stdPath.count > providerRootPath.count {
            relativePath = String(stdPath.dropFirst(providerRootPath.count))
        } else {
            relativePath = ""
        }
        return "https://\(host)/remote.php/dav/files/\(userId)\(relativePath)"
    }

    private func prepareClaroDriveRealmSnapshot(forceRefresh: Bool = false) -> String? {
        guard Self.realmFrameworkLoaded else { return nil }
        realmSnapshotLock.lock()
        defer { realmSnapshotLock.unlock() }

        let now = CFAbsoluteTimeGetCurrent()
        if !forceRefresh,
           let existing = lastRealmSnapshotPath,
           (now - lastRealmSnapshotTime) < 2.5,
           fileManager.fileExists(atPath: existing) {
            return existing
        }

        let domainsDir = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Group Containers/com.clarodrive/File Provider Domains")
        guard let domainEntries = try? fileManager.contentsOfDirectory(
            at: domainsDir,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        for domainURL in domainEntries {
            let domainId = domainURL.lastPathComponent
            let candidateRealm = domainURL.appendingPathComponent("\(domainId).realm")
            if fileManager.fileExists(atPath: candidateRealm.path) {
                let snapshotPath = "/tmp/winexplorermac_clarodrive_\(domainId).realm"
                try? fileManager.removeItem(atPath: snapshotPath)
                if (try? fileManager.copyItem(atPath: candidateRealm.path, toPath: snapshotPath)) != nil {
                    lastRealmSnapshotPath = snapshotPath
                    lastRealmSnapshotTime = now
                    return snapshotPath
                }
            }
        }
        return nil
    }

    private func streamClaroDriveFromRealm(
        at stdURL: URL,
        serverUrl: String,
        includeHidden: Bool,
        firstBatchSize: Int,
        subsequentBatchSize: Int,
        forceRefreshSnapshot: Bool = false,
        onBatch: @escaping ([FileItem], Bool) -> Bool
    ) -> Bool {
        guard let snapshotPath = prepareClaroDriveRealmSnapshot(forceRefresh: forceRefreshSnapshot),
              let configClass = NSClassFromString("RLMRealmConfiguration") as? NSObject.Type,
              let realmClass: AnyClass = NSClassFromString("RLMRealm") else {
            return false
        }

        return autoreleasepool {
            let config = configClass.init()
            config.setValue(URL(fileURLWithPath: snapshotPath), forKey: "fileURL")
            config.setValue(true, forKey: "dynamic")
            config.setValue(true, forKey: "readOnly")

            let selRealm = NSSelectorFromString("realmWithConfiguration:error:")
            typealias RealmWithConfigFn = @convention(c) (AnyClass, Selector, AnyObject, UnsafeMutablePointer<NSError?>?) -> AnyObject?
            guard let impRealm = class_getMethodImplementation(object_getClass(realmClass), selRealm) else {
                return false
            }
            let fnRealm = unsafeBitCast(impRealm, to: RealmWithConfigFn.self)
            var err: NSError? = nil
            guard let realm = fnRealm(realmClass, selRealm, config, &err) as? NSObject else {
                return false
            }

            let selObjects = NSSelectorFromString("objects:withPredicate:")
            typealias ObjectsWithPredFn = @convention(c) (AnyObject, Selector, NSString, NSPredicate) -> AnyObject?
            guard let impObjects = class_getMethodImplementation(type(of: realm), selObjects) else {
                return false
            }
            let fnObjects = unsafeBitCast(impObjects, to: ObjectsWithPredFn.self)

            let selCount = NSSelectorFromString("count")
            typealias CountFn = @convention(c) (AnyObject, Selector) -> UInt
            let selObjAt = NSSelectorFromString("objectAtIndex:")
            typealias ObjAtIndexFn = @convention(c) (AnyObject, Selector, UInt) -> AnyObject?

            var matchedResults: NSObject? = nil
            var totalCount: Int = 0

            for candidateUrl in [serverUrl, serverUrl + " "] {
                let predicate = NSPredicate(format: "serverUrl == %@ AND deleted == false", candidateUrl)
                if let res = fnObjects(realm, selObjects, "RealmItemMetadata" as NSString, predicate) as? NSObject,
                   let impCount = class_getMethodImplementation(type(of: res), selCount) {
                    let fnCount = unsafeBitCast(impCount, to: CountFn.self)
                    let c = Int(fnCount(res, selCount))
                    if c > 0 {
                        matchedResults = res
                        totalCount = c
                        break
                    }
                }
            }

            guard let results = matchedResults,
                  totalCount > 0,
                  let impObjAt = class_getMethodImplementation(type(of: results), selObjAt) else {
                return false
            }
            let fnObjAt = unsafeBitCast(impObjAt, to: ObjAtIndexFn.self)

            var batch: [FileItem] = []
            batch.reserveCapacity(firstBatchSize)
            var isFirstBatch = true

            var idx = 0
            while idx < totalCount {
                let chunkEnd = min(idx + 500, totalCount)
                var cancelled = false
                autoreleasepool {
                    while idx < chunkEnd {
                        defer { idx += 1 }
                        guard let obj = fnObjAt(results, selObjAt, UInt(idx)) as? NSObject else { continue }
                        let fileName = (obj.value(forKey: "fileNameView") as? String)
                            ?? (obj.value(forKey: "fileName") as? String)
                            ?? ""
                        if fileName.isEmpty || fileName == ".__NC_ROOT__" || fileName == "." || fileName == ".." {
                            continue
                        }
                        let isHidden = ((obj.value(forKey: "hidden") as? Bool) ?? false) || fileName.hasPrefix(".")
                        if !includeHidden && isHidden { continue }

                        let isDir = (obj.value(forKey: "directory") as? Bool) ?? false
                        let downloaded = (obj.value(forKey: "downloaded") as? Bool) ?? false
                        let isCloudDataless = !isDir && !downloaded
                        let size = isDir ? 0 : Int64((obj.value(forKey: "size") as? NSNumber)?.int64Value ?? 0)
                        let modDate = obj.value(forKey: "date") as? Date
                        let creationDate = obj.value(forKey: "creationDate") as? Date
                        let itemURL = stdURL.appendingPathComponent(fileName, isDirectory: isDir)

                        let item = FileItem(
                            url: itemURL,
                            name: fileName,
                            isDirectory: isDir,
                            isHidden: isHidden,
                            isSymlink: false,
                            size: size,
                            creationDate: creationDate,
                            modificationDate: modDate,
                            lastAccessDate: modDate,
                            fileTypeDescription: fastTypeDescription(forName: fileName, isDirectory: isDir),
                            posixPermissions: 0o755,
                            isCloudDataless: isCloudDataless
                        )
                        batch.append(item)

                        let targetSize = isFirstBatch ? firstBatchSize : subsequentBatchSize
                        if batch.count >= targetSize {
                            let shouldContinue = onBatch(batch, false)
                            batch.removeAll(keepingCapacity: true)
                            isFirstBatch = false
                            if !shouldContinue {
                                cancelled = true
                                break
                            }
                        }
                    }
                }
                if cancelled { return true }
            }

            _ = onBatch(batch, true)
            return true
        }
    }

    private func makeFileItemFromStat(
        parentURL: URL,
        parentPath: String,
        entryName: String,
        dType: UInt8,
        isCloudDirectory: Bool,
        customDisplayName: String? = nil
    ) -> FileItem? {
        let fullPath = parentPath == "/" ? "/\(entryName)" : "\(parentPath)/\(entryName)"
        var st = Darwin.stat()
        guard lstat(fullPath, &st) == 0 else { return nil }

        let mode = st.st_mode & S_IFMT
        let isSymlink = (mode == S_IFLNK)
        var isDir = (mode == S_IFDIR)
        if isSymlink {
            var targetSt = Darwin.stat()
            if stat(fullPath, &targetSt) == 0 {
                isDir = ((targetSt.st_mode & S_IFMT) == S_IFDIR)
            }
        } else if dType == UInt8(DT_DIR) {
            isDir = true
        }

        let isHidden = entryName.hasPrefix(".") || ((st.st_flags & UInt32(UF_HIDDEN)) != 0)
        // SF_DATALESS on macOS is 0x40000000; also check zero allocated blocks inside cloud storage
        let isDatalessFlag = (st.st_flags & 0x40000000) != 0
        let isCloudZeroBlocks = isCloudDirectory && !isDir && st.st_blocks == 0 && st.st_size > 0
        let isCloudDataless = isDatalessFlag || isCloudZeroBlocks

        let size = isDir ? 0 : Int64(st.st_size)
        let modDate = Date(timeIntervalSince1970: TimeInterval(st.st_mtimespec.tv_sec))
        let creationDate = Date(timeIntervalSince1970: TimeInterval(st.st_birthtimespec.tv_sec))
        let accessDate = Date(timeIntervalSince1970: TimeInterval(st.st_atimespec.tv_sec))
        let posix = Int(st.st_mode & 0o7777)

        let itemURL = parentURL.appendingPathComponent(entryName, isDirectory: isDir)
        let resolvedName: String
        if let customDisplayName {
            resolvedName = customDisplayName
        } else if parentPath == Self.cloudStorageRootURL.path {
            resolvedName = Self.parseCloudProviderFolderName(entryName).name
        } else {
            resolvedName = entryName
        }

        return FileItem(
            url: itemURL,
            name: resolvedName,
            isDirectory: isDir,
            isHidden: isHidden,
            isSymlink: isSymlink,
            size: size,
            creationDate: creationDate,
            modificationDate: modDate,
            lastAccessDate: accessDate,
            fileTypeDescription: fastTypeDescription(forName: entryName, isDirectory: isDir),
            posixPermissions: posix,
            isCloudDataless: isCloudDataless
        )
    }

    // MARK: - Progressive / Streaming Directory Reader (POSIX opendir/readdir + lstat)
    public func streamContentsOfDirectory(
        at url: URL,
        includeHidden: Bool,
        firstBatchSize: Int = 180,
        subsequentBatchSize: Int = 450,
        onBatch: @escaping ([FileItem], Bool) -> Bool
    ) throws {
        let stdURL = url.standardizedFileURL
        let dirPath = stdURL.path
        let isCloudDir = Self.isCloudPath(dirPath)

        // Fast-path for Claro drive: read directly from local Realm metadata DB in ~70ms
        // so folders with 39,000+ virtual files (like Mis Twices) never block on FileProviderExt's O(N^2) enumeration
        if let claroServerUrl = claroDriveServerUrl(for: stdURL) {
            if streamClaroDriveFromRealm(
                at: stdURL,
                serverUrl: claroServerUrl,
                includeHidden: includeHidden,
                firstBatchSize: firstBatchSize,
                subsequentBatchSize: subsequentBatchSize,
                forceRefreshSnapshot: false,
                onBatch: onBatch
            ) {
                return
            }
        }

        guard let dirPtr = Darwin.opendir(dirPath) else {
            let errCode = errno
            if stdURL == Self.trashDirectoryURL,
               let fallbackItems = listTrashViaFinder(includeHidden: includeHidden) {
                _ = onBatch(fallbackItems, true)
                return
            }
            throw NSError(
                domain: NSPOSIXErrorDomain,
                code: Int(errCode),
                userInfo: [NSLocalizedDescriptionKey: String(cString: strerror(errCode))]
            )
        }
        defer { Darwin.closedir(dirPtr) }

        var batch: [FileItem] = []
        batch.reserveCapacity(firstBatchSize)
        var isFirstBatch = true
        var existingNamesLower = Set<String>()

        while let entryPtr = Darwin.readdir(dirPtr) {
            let dType = entryPtr.pointee.d_type
            let nameLen = Int(entryPtr.pointee.d_namlen)
            let name: String = withUnsafePointer(to: &entryPtr.pointee.d_name) { ptr in
                ptr.withMemoryRebound(to: UInt8.self, capacity: nameLen) { utf8Ptr in
                    String(decoding: UnsafeBufferPointer(start: utf8Ptr, count: nameLen), as: UTF8.self)
                }
            }

            if name == "." || name == ".." { continue }
            if !includeHidden && (name.hasPrefix(".") || name == "Icon\r") { continue }

            if let item = makeFileItemFromStat(
                parentURL: stdURL,
                parentPath: dirPath,
                entryName: name,
                dType: dType,
                isCloudDirectory: isCloudDir
            ) {
                if !includeHidden && item.isHidden { continue }
                batch.append(item)
                if stdURL == Self.iCloudDriveURL {
                    existingNamesLower.insert(item.name.lowercased())
                }

                let targetSize = isFirstBatch ? firstBatchSize : subsequentBatchSize
                if batch.count >= targetSize {
                    let shouldContinue = onBatch(batch, false)
                    batch.removeAll(keepingCapacity: true)
                    isFirstBatch = false
                    if !shouldContinue { return }
                }
            }
        }

        // When viewing iCloud Drive root, also surface iCloud app Documents folders just like macOS Finder
        if stdURL == Self.iCloudDriveURL {
            for (container, title) in Self.iCloudAppContainers {
                guard !existingNamesLower.contains(title.lowercased()) else { continue }
                let docsURL = Self.mobileDocumentsRootURL
                    .appendingPathComponent(container)
                    .appendingPathComponent("Documents")
                    .standardizedFileURL
                var isDir: ObjCBool = false
                if fileManager.fileExists(atPath: docsURL.path, isDirectory: &isDir), isDir.boolValue {
                    if let appFolderItem = makeFileItem(from: docsURL, customDisplayName: title) {
                        batch.append(appFolderItem)
                    }
                }
            }
        }

        _ = onBatch(batch, true)
    }

    // MARK: - List Directory Contents
    public func contentsOfDirectory(at url: URL, includeHidden: Bool) throws -> [FileItem] {
        var allItems: [FileItem] = []
        try streamContentsOfDirectory(
            at: url,
            includeHidden: includeHidden,
            firstBatchSize: 2000,
            subsequentBatchSize: 4000
        ) { batch, _ in
            allItems.append(contentsOf: batch)
            return true
        }
        return allItems
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
        let parentURL = stdURL.deletingLastPathComponent().standardizedFileURL
        let parentPath = parentURL.path
        let entryName = stdURL.lastPathComponent
        if let fastItem = makeFileItemFromStat(
            parentURL: parentURL,
            parentPath: parentPath,
            entryName: entryName,
            dType: UInt8(DT_UNKNOWN),
            isCloudDirectory: Self.isCloudPath(stdURL.path),
            customDisplayName: customDisplayName
        ) {
            return fastItem
        }
        return nil
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
