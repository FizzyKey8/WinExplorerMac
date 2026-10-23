import Foundation
import AppKit
import UniformTypeIdentifiers
import CoreServices

@MainActor
public final class DefaultFileManagerService: ObservableObject {
    public static let shared = DefaultFileManagerService()

    public static let bundleIdentifier = "com.winexplorermac.app"
    public static let finderBundleIdentifier = "com.apple.finder"

    @Published public private(set) var isDefaultFileManager: Bool = false

    private init() {
        refreshStatus()
    }

    public func refreshStatus() {
        let globalDomain = UserDefaults.standard.persistentDomain(forName: UserDefaults.globalDomain)
        let currentViewer = globalDomain?["NSFileViewer"] as? String

        if currentViewer == Self.bundleIdentifier {
            self.isDefaultFileManager = true
            return
        }

        if let handler = LSCopyDefaultRoleHandlerForContentType("public.folder" as CFString, .all)?.takeRetainedValue() as String? {
            self.isDefaultFileManager = (handler == Self.bundleIdentifier)
        } else {
            self.isDefaultFileManager = false
        }
    }

    @discardableResult
    public func setAsDefaultFileManager() -> (success: Bool, message: String) {
        let appBundleId = Self.bundleIdentifier

        // 1. Set global NSFileViewer so AppKit's activateFileViewerSelecting and reveal calls target WinExplorerMac
        runShellCommand("defaults write -g NSFileViewer -string \"\(appBundleId)\"")

        // 2. Register LaunchServices secure handler entry for folders
        let addHandlerCmd = "defaults write com.apple.LaunchServices/com.apple.launchservices.secure LSHandlers -array-add '{\"LSHandlerContentType\"=\"public.folder\";\"LSHandlerRoleAll\"=\"\(appBundleId)\";}'"
        runShellCommand(addHandlerCmd)

        // 4. NSWorkspace modern API (macOS 12+)
        let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: appBundleId) ?? Bundle.main.bundleURL
        if #available(macOS 12.0, *) {
            Task {
                try? await NSWorkspace.shared.setDefaultApplication(at: appURL, toOpen: UTType.folder)
                try? await NSWorkspace.shared.setDefaultApplication(at: appURL, toOpen: UTType.directory)
            }
        }

        // 5. Force update LaunchServices database via lsregister
        let lsregisterPath = "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
        if FileManager.default.fileExists(atPath: lsregisterPath) {
            runShellCommand("\"\(lsregisterPath)\" -f \"\(appURL.path)\"")
        }

        refreshStatus()
        return (true, "WinExplorerMac ha sido configurado como tu explorador de archivos predeterminado.")
    }

    @discardableResult
    public func restoreFinderAsDefault() -> (success: Bool, message: String) {
        let finderId = Self.finderBundleIdentifier

        // 1. Remove global NSFileViewer
        runShellCommand("defaults delete -g NSFileViewer 2>/dev/null || true")

        // 2. Add Finder to LSHandlers
        let addHandlerCmd = "defaults write com.apple.LaunchServices/com.apple.launchservices.secure LSHandlers -array-add '{\"LSHandlerContentType\"=\"public.folder\";\"LSHandlerRoleAll\"=\"\(finderId)\";}'"
        runShellCommand(addHandlerCmd)

        // 4. NSWorkspace modern API
        if let finderURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: finderId) {
            if #available(macOS 12.0, *) {
                Task {
                    try? await NSWorkspace.shared.setDefaultApplication(at: finderURL, toOpen: UTType.folder)
                    try? await NSWorkspace.shared.setDefaultApplication(at: finderURL, toOpen: UTType.directory)
                }
            }
        }

        refreshStatus()
        return (true, "Finder ha sido restablecido como el explorador predeterminado.")
    }

    @discardableResult
    private func runShellCommand(_ command: String) -> String {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/sh")
        proc.arguments = ["-c", command]

        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = pipe

        try? proc.run()
        proc.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}
