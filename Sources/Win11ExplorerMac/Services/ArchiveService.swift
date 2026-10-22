import Foundation

public final class ArchiveService {
    public static let shared = ArchiveService()

    private init() {}

    /// Compresses one or multiple files/folders into a .zip archive in the same directory using `/usr/bin/ditto`.
    @discardableResult
    public func compressToZip(items: [URL], in directory: URL) throws -> URL {
        guard !items.isEmpty else {
            throw NSError(domain: "ArchiveService", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "No se seleccionaron elementos para comprimir."
            ])
        }

        let baseArchiveName: String
        if items.count == 1 {
            let single = items[0]
            let stem = single.deletingPathExtension().lastPathComponent
            baseArchiveName = "\(stem).zip"
        } else {
            baseArchiveName = "\(directory.lastPathComponent.isEmpty ? "Archivo comprimido" : directory.lastPathComponent).zip"
        }

        let destinationZipURL = FileSystemService.shared.uniqueDestinationURL(
            forBaseName: baseArchiveName,
            in: directory
        )

        if items.count == 1 {
            try runDitto(arguments: ["-c", "-k", "--sequesterRsrc", "--keepParent", items[0].path, destinationZipURL.path])
        } else {
            let tempStaging = FileManager.default.temporaryDirectory.appendingPathComponent("Win11Zip_\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: tempStaging, withIntermediateDirectories: true)
            defer {
                try? FileManager.default.removeItem(at: tempStaging)
            }

            for item in items {
                let stagedDest = tempStaging.appendingPathComponent(item.lastPathComponent)
                try FileManager.default.copyItem(at: item, to: stagedDest)
            }
            try runDitto(arguments: ["-c", "-k", "--sequesterRsrc", tempStaging.path, destinationZipURL.path])
        }

        return destinationZipURL
    }

    /// Extracts a .zip archive into the specified destination folder using `/usr/bin/ditto`.
    public func extractZip(at zipURL: URL, to destinationFolder: URL) throws {
        if !FileManager.default.fileExists(atPath: destinationFolder.path) {
            try FileManager.default.createDirectory(at: destinationFolder, withIntermediateDirectories: true)
        }
        try runDitto(arguments: ["-x", "-k", zipURL.path, destinationFolder.path])
    }

    private func runDitto(arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = arguments

        let errorPipe = Pipe()
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: errorData, encoding: .utf8) ?? "Error al ejecutar /usr/bin/ditto"
            throw NSError(domain: "ArchiveService", code: Int(process.terminationStatus), userInfo: [
                NSLocalizedDescriptionKey: message
            ])
        }
    }
}
