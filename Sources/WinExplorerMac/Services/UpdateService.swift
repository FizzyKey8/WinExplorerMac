import Foundation
import AppKit

public struct ReleaseUpdateInfo: Equatable {
    public let tagName: String
    public let cleanVersion: String
    public let title: String
    public let releaseNotes: String
    public let publishedAt: String?
    public let htmlURL: URL
    public let assetDownloadURL: URL?
    public let assetName: String?
    public let sourceZipballURL: URL?
}

public enum UpdateCheckStatus: Equatable {
    case idle
    case checking
    case upToDate(currentVersion: String)
    case updateAvailable(ReleaseUpdateInfo)
    case downloading(progress: Double, description: String)
    case installing(description: String)
    case noReleasesInRepo(currentVersion: String)
    case error(String)
}

@MainActor
public final class UpdateService: ObservableObject {
    public static let shared = UpdateService()

    public let repoOwner = "FizzyKey8"
    public let repoName = "WinExplorerMac"

    @Published public var status: UpdateCheckStatus = .idle
    @Published public var isUpdateModalPresented: Bool = false
    @Published public var availableUpdate: ReleaseUpdateInfo? = nil
    @Published public var lastCheckedDate: Date? = nil

    private let autoCheckKey = "WinExplorerMac.AutoCheckUpdatesOnLaunch.v1"
    private var hasCheckedOnLaunch = false

    public var autoCheckOnLaunch: Bool {
        get {
            if UserDefaults.standard.object(forKey: autoCheckKey) == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: autoCheckKey)
        }
        set {
            objectWillChange.send()
            UserDefaults.standard.set(newValue, forKey: autoCheckKey)
        }
    }

    public var currentVersion: String {
        if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
           !version.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return Self.normalizeVersion(version)
        }
        return "1.0.0"
    }

    private init() {}

    public func checkOnLaunchIfNeeded() {
        guard !hasCheckedOnLaunch else { return }
        hasCheckedOnLaunch = true
        guard autoCheckOnLaunch else { return }

        Task {
            // Brief delay so main window finishes presenting smoothly first
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            await checkForUpdates(userInitiated: false)
        }
    }

    public func openUpdateModalAndCheck() {
        isUpdateModalPresented = true
        Task {
            await checkForUpdates(userInitiated: true)
        }
    }

    public func checkForUpdates(userInitiated: Bool) async {
        if case .downloading = status { return }
        if case .installing = status { return }

        status = .checking

        do {
            if let releaseInfo = try await fetchLatestReleaseOrTag() {
                lastCheckedDate = Date()
                if Self.isVersion(releaseInfo.cleanVersion, newerThan: currentVersion) {
                    availableUpdate = releaseInfo
                    status = .updateAvailable(releaseInfo)
                    // Automatically show modal if found on launch or manual check
                    isUpdateModalPresented = true
                } else {
                    availableUpdate = nil
                    status = .upToDate(currentVersion: currentVersion)
                    if userInitiated {
                        isUpdateModalPresented = true
                    }
                }
            } else {
                lastCheckedDate = Date()
                availableUpdate = nil
                status = .noReleasesInRepo(currentVersion: currentVersion)
                if userInitiated {
                    isUpdateModalPresented = true
                }
            }
        } catch {
            status = .error("No se pudo conectar con GitHub (\(repoOwner)/\(repoName)): \(error.localizedDescription)")
            if userInitiated {
                isUpdateModalPresented = true
            }
        }
    }

    // MARK: - GitHub API Lookup (Releases + Tags Fallback)
    private func fetchLatestReleaseOrTag() async throws -> ReleaseUpdateInfo? {
        let sessionConfig = URLSessionConfiguration.ephemeral
        sessionConfig.timeoutIntervalForRequest = 15
        let session = URLSession(configuration: sessionConfig)

        // 1. Check /releases/latest first
        let latestReleaseURL = URL(string: "https://api.github.com/repos/\(repoOwner)/\(repoName)/releases/latest")!
        var releaseReq = URLRequest(url: latestReleaseURL)
        releaseReq.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        releaseReq.setValue("WinExplorerMac/\(currentVersion)", forHTTPHeaderField: "User-Agent")

        let (relData, relResp) = try await session.data(for: releaseReq)
        if let httpResp = relResp as? HTTPURLResponse, httpResp.statusCode == 200 {
            if let json = try JSONSerialization.jsonObject(with: relData) as? [String: Any],
               let tagName = json["tag_name"] as? String {
                let name = (json["name"] as? String)?.isEmpty == false ? (json["name"] as! String) : tagName
                let body = (json["body"] as? String) ?? "Sin notas de versión."
                let publishedAt = json["published_at"] as? String
                let htmlURLStr = (json["html_url"] as? String) ?? "https://github.com/\(repoOwner)/\(repoName)/releases"
                let zipballStr = json["zipball_url"] as? String

                var foundAssetURL: URL? = nil
                var foundAssetName: String? = nil
                if let assets = json["assets"] as? [[String: Any]] {
                    for asset in assets {
                        if let assetName = asset["name"] as? String,
                           let downloadStr = asset["browser_download_url"] as? String,
                           assetName.lowercased().hasSuffix(".zip"),
                           let url = URL(string: downloadStr) {
                            foundAssetURL = url
                            foundAssetName = assetName
                            break
                        }
                    }
                }

                return ReleaseUpdateInfo(
                    tagName: tagName,
                    cleanVersion: Self.normalizeVersion(tagName),
                    title: name,
                    releaseNotes: body,
                    publishedAt: publishedAt,
                    htmlURL: URL(string: htmlURLStr)!,
                    assetDownloadURL: foundAssetURL,
                    assetName: foundAssetName,
                    sourceZipballURL: zipballStr != nil ? URL(string: zipballStr!) : nil
                )
            }
        }

        // 2. Fallback: Check /tags if no formal Release exists yet
        let tagsURL = URL(string: "https://api.github.com/repos/\(repoOwner)/\(repoName)/tags")!
        var tagsReq = URLRequest(url: tagsURL)
        tagsReq.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        tagsReq.setValue("WinExplorerMac/\(currentVersion)", forHTTPHeaderField: "User-Agent")

        let (tagsData, tagsResp) = try await session.data(for: tagsReq)
        if let httpResp = tagsResp as? HTTPURLResponse, httpResp.statusCode == 200 {
            if let tagsArray = try JSONSerialization.jsonObject(with: tagsData) as? [[String: Any]],
               let firstTag = tagsArray.first,
               let tagName = firstTag["name"] as? String {
                let zipballStr = firstTag["zipball_url"] as? String
                let htmlURL = URL(string: "https://github.com/\(repoOwner)/\(repoName)/releases/tag/\(tagName)")!
                return ReleaseUpdateInfo(
                    tagName: tagName,
                    cleanVersion: Self.normalizeVersion(tagName),
                    title: "Versión \(tagName)",
                    releaseNotes: "Etiqueta de versión \(tagName) publicada en GitHub (\(repoOwner)/\(repoName)).",
                    publishedAt: nil,
                    htmlURL: htmlURL,
                    assetDownloadURL: nil,
                    assetName: nil,
                    sourceZipballURL: zipballStr != nil ? URL(string: zipballStr!) : nil
                )
            }
        }

        return nil
    }

    // MARK: - Download, Build/Extract & Auto-Replace Running App
    public func installUpdate(_ update: ReleaseUpdateInfo) {
        Task {
            await performInstallUpdate(update)
        }
    }

    private func performInstallUpdate(_ update: ReleaseUpdateInfo) async {
        let fm = FileManager.default
        let stagingDir = fm.temporaryDirectory.appendingPathComponent("WinExplorerMac_Update_\(UUID().uuidString)")

        do {
            try fm.createDirectory(at: stagingDir, withIntermediateDirectories: true)

            var newAppBundleURL: URL? = nil

            // Strategy A: Prebuilt .zip asset attached to GitHub Release
            if let assetURL = update.assetDownloadURL {
                status = .downloading(progress: 0.15, description: "Descargando paquete \(update.assetName ?? "de actualización")...")
                let zipFile = stagingDir.appendingPathComponent("release_app.zip")
                try await downloadFile(from: assetURL, to: zipFile)

                status = .installing(description: "Extrayendo aplicación actualizada...")
                let extractDir = stagingDir.appendingPathComponent("extracted")
                try fm.createDirectory(at: extractDir, withIntermediateDirectories: true)
                try runProcess("/usr/bin/ditto", arguments: ["-x", "-k", zipFile.path, extractDir.path])

                newAppBundleURL = findAppBundle(in: extractDir)
            }

            // Strategy B: Fallback to source zipball compilation if no binary .zip asset was attached
            if newAppBundleURL == nil, let sourceZipURL = update.sourceZipballURL {
                status = .downloading(progress: 0.25, description: "Descargando código fuente de \(update.tagName)...")
                let srcZipFile = stagingDir.appendingPathComponent("source.zip")
                try await downloadFile(from: sourceZipURL, to: srcZipFile)

                status = .installing(description: "Extrayendo y compilando versión \(update.cleanVersion)...")
                let srcExtractDir = stagingDir.appendingPathComponent("src")
                try fm.createDirectory(at: srcExtractDir, withIntermediateDirectories: true)
                try runProcess("/usr/bin/ditto", arguments: ["-x", "-k", srcZipFile.path, srcExtractDir.path])

                if let repoRoot = findDirectoryContainingPackageSwift(in: srcExtractDir) {
                    let buildScript = repoRoot.appendingPathComponent("build_mac_app.sh")
                    if fm.fileExists(atPath: buildScript.path) {
                        try runProcess("/bin/chmod", arguments: ["+x", buildScript.path])
                        try runProcess("/bin/bash", arguments: [buildScript.path], currentDirectory: repoRoot)
                        newAppBundleURL = findAppBundle(in: repoRoot.appendingPathComponent("build"))
                    }
                }
            }

            guard let validNewApp = newAppBundleURL else {
                status = .error("No se encontró un paquete WinExplorerMac.app válido en el release. Se abrirá la página de GitHub.")
                NSWorkspace.shared.open(update.htmlURL)
                return
            }

            status = .installing(description: "Instalando versión \(update.cleanVersion) y reiniciando...")
            // Clear quarantine attributes if any
            _ = try? runProcess("/usr/bin/xattr", arguments: ["-cr", validNewApp.path])

            let targetAppURL = resolveTargetAppBundleURL()
            try launchDetachedReplacerScript(newAppURL: validNewApp, targetAppURL: targetAppURL)

            try? await Task.sleep(nanoseconds: 300_000_000)
            NSApplication.shared.terminate(nil)
        } catch {
            status = .error("Error durante la actualización automática: \(error.localizedDescription)")
        }
    }

    private func downloadFile(from url: URL, to destination: URL) async throws {
        let session = URLSession(configuration: .ephemeral)
        var request = URLRequest(url: url)
        request.setValue("WinExplorerMac/\(currentVersion)", forHTTPHeaderField: "User-Agent")

        let (tempURL, response) = try await session.download(for: request)
        if let httpResp = response as? HTTPURLResponse, !(200...299).contains(httpResp.statusCode) {
            throw NSError(domain: "WinExplorerMac.Update", code: httpResp.statusCode, userInfo: [
                NSLocalizedDescriptionKey: "Descarga fallida (HTTP \(httpResp.statusCode))."
            ])
        }
        status = .downloading(progress: 0.90, description: "Descarga completada, verificando archivos...")
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.moveItem(at: tempURL, to: destination)
    }

    private func resolveTargetAppBundleURL() -> URL {
        let bundleURL = Bundle.main.bundleURL
        if bundleURL.pathExtension.lowercased() == "app" {
            return bundleURL
        }
        // Fallback if run from swift run / Xcode during development
        let localBuildApp = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("build/WinExplorerMac.app")
        return localBuildApp
    }

    private func launchDetachedReplacerScript(newAppURL: URL, targetAppURL: URL) throws {
        let currentPID = ProcessInfo.processInfo.processIdentifier
        let scriptURL = FileManager.default.temporaryDirectory.appendingPathComponent("winexplorer_updater_\(currentPID).sh")

        let scriptContent = """
        #!/usr/bin/env bash
        # Wait for the running instance to close
        for i in {1..30}; do
            if ! kill -0 \(currentPID) 2>/dev/null; then
                break
            fi
            sleep 0.2
        done

        mkdir -p "$(dirname "\(targetAppURL.path)")"
        rm -rf "\(targetAppURL.path)"
        mv -f "\(newAppURL.path)" "\(targetAppURL.path)"
        touch "\(targetAppURL.path)"
        open "\(targetAppURL.path)"
        rm -f "\(scriptURL.path)"
        """

        try scriptContent.write(to: scriptURL, atomically: true, encoding: .utf8)
        try runProcess("/bin/chmod", arguments: ["+x", scriptURL.path])

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/bash")
        proc.arguments = [scriptURL.path]
        try proc.run()
    }

    @discardableResult
    private func runProcess(_ launchPath: String, arguments: [String], currentDirectory: URL? = nil) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments
        if let currentDirectory {
            process.currentDirectoryURL = currentDirectory
        }
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        if process.terminationStatus != 0 {
            throw NSError(domain: "WinExplorerMac.Update", code: Int(process.terminationStatus), userInfo: [
                NSLocalizedDescriptionKey: output.isEmpty ? "El comando falló con código \(process.terminationStatus)" : output
            ])
        }
        return output
    }

    private func findAppBundle(in root: URL) -> URL? {
        let fm = FileManager.default
        if let enumerator = fm.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) {
            for case let url as URL in enumerator {
                if url.pathExtension.lowercased() == "app" {
                    return url
                }
            }
        }
        return nil
    }

    private func findDirectoryContainingPackageSwift(in root: URL) -> URL? {
        let fm = FileManager.default
        if fm.fileExists(atPath: root.appendingPathComponent("Package.swift").path) {
            return root
        }
        if let enumerator = fm.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) {
            for case let url as URL in enumerator {
                if url.lastPathComponent == "Package.swift" {
                    return url.deletingLastPathComponent()
                }
            }
        }
        return nil
    }

    // MARK: - Semantic Version Comparison
    public static func normalizeVersion(_ raw: String) -> String {
        var cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while cleaned.first == "v" || cleaned.first == "V" {
            cleaned.removeFirst()
        }
        return cleaned
    }

    public static func isVersion(_ remote: String, newerThan current: String) -> Bool {
        let rParts = normalizeVersion(remote)
            .split(separator: "-")
            .first?
            .split(separator: ".")
            .map { Int($0) ?? 0 } ?? []
        let cParts = normalizeVersion(current)
            .split(separator: "-")
            .first?
            .split(separator: ".")
            .map { Int($0) ?? 0 } ?? []

        let count = max(rParts.count, cParts.count)
        for i in 0..<count {
            let r = i < rParts.count ? rParts[i] : 0
            let c = i < cParts.count ? cParts[i] : 0
            if r != c {
                return r > c
            }
        }
        return false
    }
}
