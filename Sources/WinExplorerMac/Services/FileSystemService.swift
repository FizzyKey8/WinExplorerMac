import Foundation
import AppKit
import ImageIO
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

    // MARK: - Claro drive Direct Realm Metadata Reader & Preview Credentials
    public struct ClaroDriveCredentials: Codable {
        public let userAgent: String
        public let user: String
        public let userId: String
        public let serverUrl: String
        public let password: String
    }

    private let credentialsLock = NSLock()
    private var cachedClaroCredentials: ClaroDriveCredentials? = nil
    private let credentialsCacheFile = URL(fileURLWithPath: "/tmp/winexplorermac_clarodrive_creds.json", isDirectory: false)
    private let cloudOpenSession: URLSession = {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 20
        cfg.timeoutIntervalForResource = 45
        cfg.httpMaximumConnectionsPerHost = 4
        return URLSession(configuration: cfg)
    }()

    public func claroDriveCredentials() -> ClaroDriveCredentials? {
        credentialsLock.lock()
        defer { credentialsLock.unlock() }

        if let existing = cachedClaroCredentials {
            return existing
        }

        if let data = try? Data(contentsOf: credentialsCacheFile),
           let decoded = try? JSONDecoder().decode(ClaroDriveCredentials.self, from: data),
           !decoded.password.isEmpty {
            cachedClaroCredentials = decoded
            return decoded
        }

        let containerRoot = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Group Containers/com.clarodrive")
        let socketPath = containerRoot.appendingPathComponent(".fileprovidersocket").path
        let domainsDir = containerRoot.appendingPathComponent("File Provider Domains")

        guard let domainEntries = try? fileManager.contentsOfDirectory(
            at: domainsDir,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ), let domainId = domainEntries.first?.lastPathComponent else {
            return nil
        }

        let sock = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard sock >= 0 else { return nil }
        defer { Darwin.close(sock) }

        var tv = timeval(tv_sec: 2, tv_usec: 0)
        setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(sock, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = socketPath.utf8CString
        guard pathBytes.count <= MemoryLayout.size(ofValue: addr.sun_path) else { return nil }
        withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
            ptr.withMemoryRebound(to: CChar.self, capacity: pathBytes.count) { dst in
                for i in 0..<pathBytes.count {
                    dst[i] = pathBytes[i]
                }
            }
        }

        let connectRes = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockAddrPtr in
                Darwin.connect(sock, sockAddrPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connectRes == 0 else { return nil }

        var initialBuf = [UInt8](repeating: 0, count: 1024)
        _ = Darwin.recv(sock, &initialBuf, initialBuf.count, 0)

        let reply = "FILE_PROVIDER_DOMAIN_IDENTIFIER_REQUEST_REPLY:\(domainId)\n"
        _ = reply.withCString { cstr in
            Darwin.send(sock, cstr, strlen(cstr), 0)
        }

        var accumulated = Data()
        var chunk = [UInt8](repeating: 0, count: 16384)
        let start = CFAbsoluteTimeGetCurrent()
        while (CFAbsoluteTimeGetCurrent() - start) < 1.5 {
            let n = Darwin.recv(sock, &chunk, chunk.count, 0)
            if n <= 0 { break }
            accumulated.append(contentsOf: chunk[0..<n])
            if let str = String(data: accumulated, encoding: .utf8),
               str.contains("ACCOUNT_DETAILS:") {
                break
            }
        }

        guard let fullText = String(data: accumulated, encoding: .utf8) else { return nil }
        for line in fullText.components(separatedBy: "\n") {
            if line.hasPrefix("ACCOUNT_DETAILS:") {
                let payload = String(line.dropFirst("ACCOUNT_DETAILS:".count))
                let parts = payload.components(separatedBy: "~")
                if parts.count >= 5 {
                    let creds = ClaroDriveCredentials(
                        userAgent: parts[0],
                        user: parts[1],
                        userId: parts[2],
                        serverUrl: parts[3],
                        password: parts[4].trimmingCharacters(in: .whitespacesAndNewlines)
                    )
                    cachedClaroCredentials = creds
                    if let encoded = try? JSONEncoder().encode(creds) {
                        try? encoded.write(to: credentialsCacheFile, options: .atomic)
                    }
                    return creds
                }
            }
        }
        return nil
    }

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
        let stdPath = directoryURL.cleanFileURL.path
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

    public func claroDriveEncodedWebDavURL(for targetURL: URL) -> URL? {
        let stdPath = targetURL.cleanFileURL.path
        let cloudRootPath = Self.cloudStorageRootURL.path + "/"
        guard stdPath.hasPrefix(cloudRootPath) else { return nil }

        let remainder = String(stdPath.dropFirst(cloudRootPath.count))
        let components = remainder.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard let providerFolder = components.first,
              providerFolder.lowercased().hasPrefix("clarodrive-") else {
            return nil
        }

        let accountSpec = String(providerFolder.dropFirst("Clarodrive-".count))
        let acctParts = accountSpec.split(separator: "@", maxSplits: 1).map(String.init)
        guard acctParts.count == 2 else { return nil }
        let userId = acctParts[0]
        let host = acctParts[1]

        let allowed = CharacterSet.urlPathAllowed.subtracting(CharacterSet(charactersIn: "/?#%;+&"))
        let encodedSegments = components.dropFirst().compactMap { seg -> String? in
            if seg.isEmpty { return nil }
            let nfc = seg.precomposedStringWithCanonicalMapping
            return nfc.addingPercentEncoding(withAllowedCharacters: allowed) ?? nfc
        }
        let pathSuffix = encodedSegments.isEmpty ? "" : "/" + encodedSegments.joined(separator: "/")
        return URL(string: "https://\(host)/remote.php/dav/files/\(userId)\(pathSuffix)")
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
        directoriesOnly: Bool = false,
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
                let format = directoriesOnly
                    ? "serverUrl == %@ AND deleted == false AND directory == true"
                    : "serverUrl == %@ AND deleted == false"
                let predicate = NSPredicate(format: format, candidateUrl)
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
                        if directoriesOnly && !isDir { continue }
                        let downloaded = (obj.value(forKey: "downloaded") as? Bool) ?? false
                        let isCloudDataless = !isDir && !downloaded
                        let fileId = obj.value(forKey: "fileId") as? String
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
                            isCloudDataless: isCloudDataless,
                            cloudFileId: fileId
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

    private struct WebDAVParsedEntry {
        var href: String = ""
        var isDirectory: Bool = false
        var fileId: String? = nil
        var size: Int64 = 0
        var modDate: Date? = nil
        var isHidden: Bool = false
    }

    private final class ClaroDriveWebDAVPropfindParser: NSObject, XMLParserDelegate {
        var entries: [WebDAVParsedEntry] = []
        private var currentEntry: WebDAVParsedEntry? = nil
        private var currentText: String = ""
        private var insideResourceType: Bool = false

        private static let rfc1123Formatter: DateFormatter = {
            let df = DateFormatter()
            df.locale = Locale(identifier: "en_US_POSIX")
            df.timeZone = TimeZone(secondsFromGMT: 0)
            df.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
            return df
        }()

        private func localTagName(_ elementName: String) -> String {
            if let colonIdx = elementName.lastIndex(of: ":") {
                return String(elementName[elementName.index(after: colonIdx)...]).lowercased()
            }
            return elementName.lowercased()
        }

        func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
            let tag = localTagName(elementName)
            currentText = ""
            if tag == "response" {
                currentEntry = WebDAVParsedEntry()
                insideResourceType = false
            } else if tag == "resourcetype" {
                insideResourceType = true
            } else if tag == "collection" && insideResourceType {
                currentEntry?.isDirectory = true
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            currentText.append(string)
        }

        func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
            let tag = localTagName(elementName)
            let trimmed = currentText.trimmingCharacters(in: .whitespacesAndNewlines)

            if tag == "resourcetype" {
                insideResourceType = false
            } else if tag == "href" {
                if !trimmed.isEmpty, currentEntry?.href.isEmpty == true {
                    currentEntry?.href = trimmed
                }
            } else if tag == "fileid" {
                if !trimmed.isEmpty {
                    currentEntry?.fileId = trimmed
                }
            } else if tag == "size" || tag == "getcontentlength" {
                if let val = Int64(trimmed), val > 0 {
                    currentEntry?.size = val
                }
            } else if tag == "getlastmodified" {
                if !trimmed.isEmpty, let date = Self.rfc1123Formatter.date(from: trimmed) {
                    currentEntry?.modDate = date
                }
            } else if tag == "hidden" {
                if trimmed.lowercased() == "true" || trimmed == "1" {
                    currentEntry?.isHidden = true
                }
            } else if tag == "response" {
                if let entry = currentEntry, !entry.href.isEmpty {
                    entries.append(entry)
                }
                currentEntry = nil
            }
            currentText = ""
        }
    }

    private func streamClaroDriveViaWebDAV(
        at stdURL: URL,
        includeHidden: Bool,
        firstBatchSize: Int,
        subsequentBatchSize: Int,
        directoriesOnly: Bool = false,
        onBatch: @escaping ([FileItem], Bool) -> Bool
    ) -> Bool {
        guard let creds = claroDriveCredentials(),
              let baseWebDavURL = claroDriveEncodedWebDavURL(for: stdURL) else {
            return false
        }

        let propfindBody = """
        <?xml version="1.0" encoding="utf-8" ?>
        <d:propfind xmlns:d="DAV:" xmlns:oc="http://owncloud.org/ns" xmlns:nc="http://nextcloud.org/ns">
          <d:prop>
            <d:resourcetype/>
            <d:getlastmodified/>
            <d:getcontentlength/>
            <oc:size/>
            <oc:fileid/>
            <nc:hidden/>
          </d:prop>
        </d:propfind>
        """.data(using: .utf8)

        let authBase64 = Data("\(creds.user):\(creds.password)".utf8).base64EncodedString()

        // Try exact encoded URL and trailing-slash variant
        var candidateURLs: [URL] = [baseWebDavURL]
        if !baseWebDavURL.absoluteString.hasSuffix("/"),
           let slashURL = URL(string: baseWebDavURL.absoluteString + "/") {
            candidateURLs.insert(slashURL, at: 0)
        }

        var responseData: Data? = nil
        for targetURL in candidateURLs {
            var req = URLRequest(url: targetURL, timeoutInterval: 20)
            req.httpMethod = "PROPFIND"
            req.setValue("Basic \(authBase64)", forHTTPHeaderField: "Authorization")
            req.setValue(creds.userAgent, forHTTPHeaderField: "User-Agent")
            req.setValue("1", forHTTPHeaderField: "Depth")
            req.setValue("application/xml; charset=utf-8", forHTTPHeaderField: "Content-Type")
            req.httpBody = propfindBody

            let sem = DispatchSemaphore(value: 0)
            var fetched: Data? = nil
            var statusCode: Int = 0

            let task = cloudOpenSession.dataTask(with: req) { data, resp, _ in
                if let http = resp as? HTTPURLResponse {
                    statusCode = http.statusCode
                }
                fetched = data
                sem.signal()
            }
            task.resume()
            _ = sem.wait(timeout: .now() + 22)

            if (200...299).contains(statusCode), let data = fetched, !data.isEmpty {
                responseData = data
                break
            }
        }

        guard let xmlData = responseData else {
            return false
        }

        let delegate = ClaroDriveWebDAVPropfindParser()
        let xmlParser = XMLParser(data: xmlData)
        xmlParser.delegate = delegate
        _ = xmlParser.parse()

        guard !delegate.entries.isEmpty else {
            return false
        }

        // The first entry in a Depth:1 PROPFIND response is the directory itself
        let selfHrefTrimmed = delegate.entries[0].href.trimmingCharacters(in: CharacterSet(charactersIn: "/"))

        var batch: [FileItem] = []
        batch.reserveCapacity(firstBatchSize)
        var isFirstBatch = true

        for (index, entry) in delegate.entries.enumerated() {
            let trimmedHref = entry.href.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            if index == 0 || trimmedHref == selfHrefTrimmed {
                continue
            }
            guard let lastSegment = trimmedHref.split(separator: "/").last.map(String.init) else {
                continue
            }
            let fileName = lastSegment.removingPercentEncoding ?? lastSegment
            if fileName.isEmpty || fileName == "." || fileName == ".." || fileName == ".__NC_ROOT__" {
                continue
            }
            let isHidden = entry.isHidden || fileName.hasPrefix(".")
            if !includeHidden && isHidden {
                continue
            }

            let isDir = entry.isDirectory
            if directoriesOnly && !isDir { continue }
            let itemURL = stdURL.appendingPathComponent(fileName, isDirectory: isDir)
            let item = FileItem(
                url: itemURL,
                name: fileName,
                isDirectory: isDir,
                isHidden: isHidden,
                isSymlink: false,
                size: isDir ? 0 : entry.size,
                creationDate: entry.modDate,
                modificationDate: entry.modDate,
                lastAccessDate: entry.modDate,
                fileTypeDescription: fastTypeDescription(forName: fileName, isDirectory: isDir),
                posixPermissions: 0o755,
                isCloudDataless: !isDir,
                cloudFileId: entry.fileId
            )
            batch.append(item)

            let targetSize = isFirstBatch ? firstBatchSize : subsequentBatchSize
            if batch.count >= targetSize {
                let shouldContinue = onBatch(batch, false)
                batch.removeAll(keepingCapacity: true)
                isFirstBatch = false
                if !shouldContinue {
                    return true
                }
            }
        }

        _ = onBatch(batch, true)
        return true
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
        directoriesOnly: Bool = false,
        firstBatchSize: Int = 180,
        subsequentBatchSize: Int = 450,
        onBatch: @escaping ([FileItem], Bool) -> Bool
    ) throws {
        let stdURL = url.cleanFileURL
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
                directoriesOnly: directoriesOnly,
                forceRefreshSnapshot: false,
                onBatch: onBatch
            ) {
                return
            }
            // Subfolders inside non-materialized folders (e.g., Imagenes/Mis Twices/Sanita hermosa diosa)
            // are not in the local Realm DB yet because FileProviderExt never finished enumerating Mis Twices.
            // Query Claro drive WebDAV PROPFIND (Depth: 1) directly so they open in ~200ms without touching the blocked VFS!
            if streamClaroDriveViaWebDAV(
                at: stdURL,
                includeHidden: includeHidden,
                firstBatchSize: firstBatchSize,
                subsequentBatchSize: subsequentBatchSize,
                directoriesOnly: directoriesOnly,
                onBatch: onBatch
            ) {
                return
            }
            _ = onBatch([], true)
            return
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
            if directoriesOnly && dType != UInt8(DT_DIR) && dType != UInt8(DT_UNKNOWN) && dType != UInt8(DT_LNK) {
                continue
            }

            if let item = makeFileItemFromStat(
                parentURL: stdURL,
                parentPath: dirPath,
                entryName: name,
                dType: dType,
                isCloudDirectory: isCloudDir
            ) {
                if !includeHidden && item.isHidden { continue }
                if directoriesOnly && !item.isDirectory { continue }
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
    public func firstLevelSubfolders(at url: URL) async -> [FileItem] {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                var folders: [FileItem] = []
                _ = try? Self.shared.streamContentsOfDirectory(
                    at: url,
                    includeHidden: false,
                    directoriesOnly: true,
                    firstBatchSize: 300,
                    subsequentBatchSize: 600
                ) { batch, _ in
                    folders.append(contentsOf: batch.filter(\.isDirectory))
                    return true
                }
                folders.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
                continuation.resume(returning: folders)
            }
        }
    }

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
        let stdURL = url.cleanFileURL
        if stdURL == Self.trashDirectoryURL {
            return FileItem(
                url: stdURL,
                name: "Papelera",
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
        // Fast path for CloudStorage to avoid blocking kernel VFS calls on the main thread
        if Self.isCloudPath(stdURL.path) || claroDriveServerUrl(for: stdURL) != nil {
            let isDir = stdURL.hasDirectoryPath || stdURL.pathExtension.isEmpty
            let fileName = customDisplayName ?? stdURL.lastPathComponent
            let hashK = String(abs(stdURL.path.hashValue))
            let isDownloaded = CloudDownloadManager.shared.isDownloaded(key: hashK)

            var item = FileItem(
                url: stdURL,
                name: fileName,
                isDirectory: isDir,
                isHidden: fileName.hasPrefix("."),
                isSymlink: false,
                size: 0,
                creationDate: nil,
                modificationDate: nil,
                lastAccessDate: nil,
                fileTypeDescription: fastTypeDescription(forName: fileName, isDirectory: isDir),
                posixPermissions: 0o755,
                isCloudDataless: !isDir && !isDownloaded,
                cloudFileId: nil
            )
            if let cached = CloudDownloadManager.shared.localCachedURL(for: item) {
                item.isCloudDataless = false
                CloudDownloadManager.shared.finishDownload(for: item)
                if let attr = try? FileManager.default.attributesOfItem(atPath: cached.path),
                   let cachedSize = attr[.size] as? NSNumber {
                    item.size = cachedSize.int64Value
                }
            }
            return item
        }

        let parentURL = stdURL.deletingLastPathComponent().cleanFileURL
        let parentPath = parentURL.path
        let entryName = stdURL.lastPathComponent

        if let fastItem = makeFileItemFromStat(
            parentURL: parentURL,
            parentPath: parentPath,
            entryName: entryName,
            dType: UInt8(DT_UNKNOWN),
            isCloudDirectory: false,
            customDisplayName: customDisplayName
        ) {
            return fastItem
        }

        return nil
    }

    public func makeFileItem(from record: RecentFileRecord) -> FileItem {
        let stdURL = record.url.cleanFileURL
        let fileName = record.name ?? stdURL.lastPathComponent
        let isCloud = Self.isCloudPath(stdURL.path) || claroDriveServerUrl(for: stdURL) != nil

        let hashK = String(abs(stdURL.path.hashValue))
        let isDownloaded = CloudDownloadManager.shared.isDownloaded(key: record.cloudFileId ?? hashK)

        var item = FileItem(
            url: stdURL,
            name: fileName,
            isDirectory: false,
            isHidden: fileName.hasPrefix("."),
            isSymlink: false,
            size: record.size,
            creationDate: record.accessedAt,
            modificationDate: record.accessedAt,
            lastAccessDate: record.accessedAt,
            fileTypeDescription: fastTypeDescription(forName: fileName, isDirectory: false),
            posixPermissions: 0o755,
            isCloudDataless: isCloud && !isDownloaded && record.isCloudDataless,
            cloudFileId: record.cloudFileId
        )

        if let cached = CloudDownloadManager.shared.localCachedURL(for: item) {
            item.isCloudDataless = false
            CloudDownloadManager.shared.finishDownload(for: item)
            if let attr = try? FileManager.default.attributesOfItem(atPath: cached.path),
               let cachedSize = attr[.size] as? NSNumber {
                item.size = cachedSize.int64Value
            }
        }
        return item
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

    // MARK: - Free Up Space (Evict Ubiquitous Cloud Items)
    public func freeUpCloudSpace(at url: URL) throws {
        // macOS FileProvider handles single files and entire folder trees natively in one call
        try fileManager.evictUbiquitousItem(at: url)
    }

    // MARK: - Open / Reveal / Terminal / Share
    public func openFileItem(
        _ item: FileItem,
        withApplication appURL: URL? = nil,
        onStatus: ((String?) -> Void)? = nil,
        onError: ((String?) -> Void)? = nil
    ) {
        // 1. If already locally cached in /tmp/WinExplorerMac_CloudOpened: open immediately (< 1ms)!
        if let cachedURL = CloudDownloadManager.shared.localCachedURL(for: item) {
            CloudDownloadManager.shared.finishDownload(for: item)
            onStatus?(nil)
            openLocalURL(cachedURL, withApplication: appURL)
            return
        }

        // 2. If locally present on disk with allocated blocks: open directly!
        if isFileLocallyPresent(item.url) {
            CloudDownloadManager.shared.finishDownload(for: item)
            onStatus?(nil)
            openLocalURL(item.url, withApplication: appURL)
            return
        }

        // 3. Claro drive virtual dataless item:
        if claroDriveServerUrl(for: item.url) != nil || item.cloudFileId != nil {
            openClaroDriveItem(item, withApplication: appURL, onStatus: onStatus, onError: onError)
            return
        }

        openLocalURL(item.url, withApplication: appURL)
    }

    public func isFileLocallyPresent(_ url: URL) -> Bool {
        var st = Darwin.stat()
        guard lstat(url.path, &st) == 0 else { return false }
        let isDataless = (st.st_flags & 0x40000000) != 0 || (st.st_blocks == 0 && st.st_size > 0)
        return !isDataless
    }

    public func openItem(_ url: URL) {
        if claroDriveServerUrl(for: url) != nil {
            let syntheticItem = FileItem(
                url: url,
                name: url.lastPathComponent,
                isDirectory: false,
                isCloudDataless: true
            )
            openClaroDriveItem(syntheticItem, withApplication: nil, onStatus: nil, onError: nil)
            return
        }
        openLocalURL(url, withApplication: nil)
    }

    private func openLocalURL(_ url: URL, withApplication appURL: URL?) {
        let config = NSWorkspace.OpenConfiguration()
        config.promptsUserIfNeeded = false
        if let appURL {
            NSWorkspace.shared.open([url], withApplicationAt: appURL, configuration: config, completionHandler: nil)
        } else {
            NSWorkspace.shared.open(url, configuration: config, completionHandler: nil)
        }
    }

    private func openClaroDriveItem(
        _ item: FileItem,
        withApplication appURL: URL?,
        onStatus: ((String?) -> Void)?,
        onError: ((String?) -> Void)?
    ) {
        let baseCacheDir = URL(fileURLWithPath: "/tmp/WinExplorerMac_CloudOpened", isDirectory: true)
        let folderKey: String = {
            if let fid = item.cloudFileId, !fid.isEmpty {
                return fid
            }
            return String(abs(item.url.path.hashValue))
        }()
        let itemCacheDir = baseCacheDir.appendingPathComponent(folderKey, isDirectory: true)
        try? fileManager.createDirectory(at: itemCacheDir, withIntermediateDirectories: true)
        let destURL = itemCacheDir.appendingPathComponent(item.name, isDirectory: false)

        // 1. Instant open (< 1ms) if already in /tmp/WinExplorerMac_CloudOpened
        if let cached = CloudDownloadManager.shared.localCachedURL(for: item) {
            CloudDownloadManager.shared.finishDownload(for: item)
            onStatus?(nil)
            openLocalURL(cached, withApplication: appURL)
            return
        }
        if fileManager.fileExists(atPath: destURL.path) {
            CloudDownloadManager.shared.finishDownload(for: item)
            onStatus?(nil)
            openLocalURL(destURL, withApplication: appURL)
            return
        }

        // 2. Instant open (~20ms) if high-res preview /tmp/WinExplorerMac_CloudPreviews/<fileId>.img is already on disk
        let previewFid = (item.cloudFileId?.isEmpty == false) ? item.cloudFileId! : String(abs(item.url.path.hashValue))
        let previewDiskFile = URL(fileURLWithPath: "/tmp/WinExplorerMac_CloudPreviews/\(previewFid).img", isDirectory: false)
        if item.isImage,
           item.fileExtension != "gif",
           fileManager.fileExists(atPath: previewDiskFile.path),
           let previewData = try? Data(contentsOf: previewDiskFile),
           Self.writeConvertedImageData(previewData, to: destURL, fileExtension: item.fileExtension) {
            CloudDownloadManager.shared.finishDownload(for: item)
            onStatus?(nil)
            openLocalURL(destURL, withApplication: appURL)
            return
        }

        // 3. Download asynchronously via dedicated session (never touching FileProvider VFS)
        onStatus?("Abriendo '\(item.name)' desde la nube...")
        let fileId = item.cloudFileId
        let isImage = item.isImage
        let ext = item.fileExtension
        let itemURL = item.url
        let itemName = item.name

        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self = self,
                  let creds = self.claroDriveCredentials() else {
                CloudDownloadManager.shared.cancelDownload(for: item)
                await MainActor.run {
                    onStatus?(nil)
                    onError?("No se pudieron obtener las credenciales de Claro drive para abrir '\(itemName)'.")
                }
                return
            }

            let authData = Data("\(creds.user):\(creds.password)".utf8).base64EncodedString()

            // Try fast fileId preview endpoint first for non-GIF images (returns 1080p/2K in ~150ms)
            if isImage, ext != "gif", let fid = fileId, !fid.isEmpty,
               let previewURL = URL(string: "\(creds.serverUrl)/index.php/core/preview?fileId=\(fid)&x=2048&y=2048&a=1") {
                CloudDownloadManager.shared.updateProgress(for: item, fraction: 0.15)
                if let data = await self.fetchCloudDataWithRetry(url: previewURL, authBase64: authData, userAgent: creds.userAgent) {
                    let previewDiskFile = URL(fileURLWithPath: "/tmp/WinExplorerMac_CloudPreviews/\(fid).img", isDirectory: false)
                    try? data.write(to: previewDiskFile, options: .atomic)
                    if Self.writeConvertedImageData(data, to: destURL, fileExtension: ext) {
                        CloudDownloadManager.shared.finishDownload(for: item)
                        await MainActor.run {
                            onStatus?(nil)
                            self.openLocalURL(destURL, withApplication: appURL)
                        }
                        return
                    }
                }
            }

            // For cloud videos: 1. Stream instantly to QuickTime Player (plays in < 1s)
            //                    2. Automatically download in the background with live progress and final checkmark
            if item.isVideo, let remoteURL = self.claroDriveEncodedWebDavURL(for: itemURL) {
                let streamURL = CloudMediaStreamServer.shared.register(
                    item: item,
                    remoteURL: remoteURL,
                    authBase64: authData,
                    userAgent: creds.userAgent
                )
                let opened = CloudMediaStreamServer.shared.openInVideoPlayer(streamURL: streamURL, withApplication: appURL)
                if opened {
                    // Start background download with live progress bar and final checkmark (give QuickTime 2s head start)
                    Task.detached(priority: .utility) { [weak self] in
                        guard let self = self else { return }
                        try? await Task.sleep(nanoseconds: 2_000_000_000)
                        let success = await self.downloadCloudFileWithProgress(
                            from: remoteURL,
                            to: destURL,
                            authBase64: authData,
                            userAgent: creds.userAgent,
                            item: item,
                            onStatus: onStatus
                        )
                        if success && self.fileManager.fileExists(atPath: destURL.path) {
                            CloudDownloadManager.shared.finishDownload(for: item)
                            let thumbDir = URL(fileURLWithPath: "/tmp/WinExplorerMac_CloudPreviews", isDirectory: true)
                            let thumbFile = thumbDir.appendingPathComponent("\(folderKey).img")
                            if !self.fileManager.fileExists(atPath: thumbFile.path),
                               let thumb = ThumbnailService.generateVideoThumbnail(at: destURL, maxPixelSize: 320),
                               let data = ThumbnailService.jpegData(from: thumb) {
                                try? data.write(to: thumbFile, options: .atomic)
                            }
                        } else {
                            CloudDownloadManager.shared.cancelDownload(for: item)
                        }
                        await MainActor.run {
                            onStatus?(nil)
                        }
                    }
                    return
                }
            }

            // Try WebDAV download directly to disk with live progress (for videos fallback, documents, or full originals)
            if let remoteURL = self.claroDriveEncodedWebDavURL(for: itemURL) {
                let success = await self.downloadCloudFileWithProgress(
                    from: remoteURL,
                    to: destURL,
                    authBase64: authData,
                    userAgent: creds.userAgent,
                    item: item,
                    onStatus: onStatus
                )
                if success && self.fileManager.fileExists(atPath: destURL.path) {
                    CloudDownloadManager.shared.finishDownload(for: item)
                    if item.isVideo {
                        let thumbDir = URL(fileURLWithPath: "/tmp/WinExplorerMac_CloudPreviews", isDirectory: true)
                        let thumbFile = thumbDir.appendingPathComponent("\(folderKey).img")
                        if !self.fileManager.fileExists(atPath: thumbFile.path),
                           let thumb = ThumbnailService.generateVideoThumbnail(at: destURL, maxPixelSize: 320),
                           let data = ThumbnailService.jpegData(from: thumb) {
                            try? data.write(to: thumbFile, options: .atomic)
                        }
                    }
                    await MainActor.run {
                        onStatus?(nil)
                        self.openLocalURL(destURL, withApplication: appURL)
                    }
                    return
                }
            }

            CloudDownloadManager.shared.cancelDownload(for: item)
            await MainActor.run {
                onStatus?(nil)
                onError?("No se pudo abrir '\(itemName)' desde Claro drive. Inténtalo de nuevo en unos segundos.")
            }
        }
    }

    private func downloadCloudFileWithProgress(
        from remoteURL: URL,
        to destURL: URL,
        authBase64: String,
        userAgent: String,
        item: FileItem,
        onStatus: ((String?) -> Void)?
    ) async -> Bool {
        var req = URLRequest(url: remoteURL, timeoutInterval: 120)
        req.setValue("Basic \(authBase64)", forHTTPHeaderField: "Authorization")
        req.setValue(userAgent, forHTTPHeaderField: "User-Agent")

        CloudDownloadManager.shared.updateProgress(for: item, fraction: 0.02)

        return await withCheckedContinuation { continuation in
            let cfg = URLSessionConfiguration.default
            cfg.timeoutIntervalForRequest = 180
            cfg.timeoutIntervalForResource = 7200
            let session = URLSession(configuration: cfg)
            
            final class DownloadStateBox: @unchecked Sendable {
                var observation: NSKeyValueObservation?
                var lastUpdate: CFAbsoluteTime = 0
            }
            let box = DownloadStateBox()

            let task = session.downloadTask(with: req) { tempURL, resp, _ in
                box.observation?.invalidate()
                box.observation = nil
                session.finishTasksAndInvalidate()
                guard let tempURL = tempURL,
                      let http = resp as? HTTPURLResponse,
                      (200...299).contains(http.statusCode) else {
                    continuation.resume(returning: false)
                    return
                }
                do {
                    try? FileManager.default.removeItem(at: destURL)
                    try FileManager.default.moveItem(at: tempURL, to: destURL)
                    continuation.resume(returning: true)
                } catch {
                    continuation.resume(returning: false)
                }
            }

            box.observation = task.progress.observe(\.fractionCompleted) { progress, _ in
                let fraction = progress.fractionCompleted

                let now = CFAbsoluteTimeGetCurrent()
                if now - box.lastUpdate >= 0.25 || fraction >= 1.0 {
                    box.lastUpdate = now
                    CloudDownloadManager.shared.updateProgress(for: item, fraction: fraction)
                    let percent = Int(fraction * 100)
                    let totalBytes = progress.totalUnitCount
                    let completedBytes = progress.completedUnitCount
                    if totalBytes > 0 {
                        let mbDone = Double(completedBytes) / (1024 * 1024)
                        let mbTotal = Double(totalBytes) / (1024 * 1024)
                        DispatchQueue.main.async {
                            onStatus?(String(format: "Descargando '%@' (%.1f MB / %.1f MB - %d%%)...", item.name, mbDone, mbTotal, percent))
                        }
                    } else {
                        DispatchQueue.main.async {
                            onStatus?("Descargando '\(item.name)' (\(percent)%)...")
                        }
                    }
                }
            }

            task.resume()
        }
    }

    private func fetchCloudDataWithRetry(url: URL, authBase64: String, userAgent: String) async -> Data? {
        for attempt in 0..<3 {
            var req = URLRequest(url: url, timeoutInterval: 25)
            req.setValue("Basic \(authBase64)", forHTTPHeaderField: "Authorization")
            req.setValue(userAgent, forHTTPHeaderField: "User-Agent")

            if let (data, resp) = try? await cloudOpenSession.data(for: req),
               let http = resp as? HTTPURLResponse {
                if (200...299).contains(http.statusCode), !data.isEmpty {
                    return data
                }
                if http.statusCode == 503 || http.statusCode == 429 {
                    try? await Task.sleep(nanoseconds: UInt64(250_000_000 * (attempt + 1)))
                    continue
                }
            }
            if attempt < 2 {
                try? await Task.sleep(nanoseconds: 200_000_000)
            }
        }
        return nil
    }

    private static func writeConvertedImageData(_ data: Data, to destURL: URL, fileExtension: String) -> Bool {
        if data.count > 4 {
            if (try? data.write(to: destURL, options: .atomic)) != nil {
                return true
            }
        }
        let ext = fileExtension.lowercased()
        if let source = CGImageSourceCreateWithData(data as CFData, nil),
           let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) {
            let rep = NSBitmapImageRep(cgImage: cgImage)
            if ext == "png", let pngData = rep.representation(using: .png, properties: [:]) {
                if (try? pngData.write(to: destURL, options: .atomic)) != nil {
                    return true
                }
            } else if ext == "jpg" || ext == "jpeg" {
                if let jpgData = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.92]),
                   (try? jpgData.write(to: destURL, options: .atomic)) != nil {
                    return true
                }
            } else if ext == "tiff" || ext == "tif",
                      let tiffData = rep.representation(using: .tiff, properties: [:]) {
                if (try? tiffData.write(to: destURL, options: .atomic)) != nil {
                    return true
                }
            } else if ext == "bmp",
                      let bmpData = rep.representation(using: .bmp, properties: [:]) {
                if (try? bmpData.write(to: destURL, options: .atomic)) != nil {
                    return true
                }
            }
        }
        return false
    }

    public func availableApplications(for url: URL) -> [URL] {
        if Self.isCloudPath(url.path) {
            let ext = url.pathExtension
            if !ext.isEmpty, let contentType = UTType(filenameExtension: ext) {
                return NSWorkspace.shared.urlsForApplications(toOpen: contentType)
            }
            return []
        }
        return NSWorkspace.shared.urlsForApplications(toOpen: url)
    }

    public func openItem(_ url: URL, withApplication appURL: URL) {
        if claroDriveServerUrl(for: url) != nil {
            let syntheticItem = FileItem(
                url: url,
                name: url.lastPathComponent,
                isDirectory: false,
                isCloudDataless: true
            )
            openClaroDriveItem(syntheticItem, withApplication: appURL, onStatus: nil, onError: nil)
            return
        }
        openLocalURL(url, withApplication: appURL)
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
