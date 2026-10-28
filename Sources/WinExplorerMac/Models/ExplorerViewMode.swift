import Foundation

public enum ExplorerViewMode: String, CaseIterable, Identifiable {
    case extraLargeIcons = "Iconos muy grandes"
    case largeIcons = "Iconos grandes"
    case mediumIcons = "Iconos medianos"
    case list = "Lista"
    case details = "Detalles"

    public var id: String { rawValue }

    public var sfSymbol: String {
        switch self {
        case .extraLargeIcons: return "square.grid.2x2.fill"
        case .largeIcons: return "square.grid.2x2"
        case .mediumIcons: return "square.grid.3x3"
        case .list: return "list.bullet"
        case .details: return "tablecells"
        }
    }

    public var iconSize: CGFloat {
        switch self {
        case .extraLargeIcons: return 96
        case .largeIcons: return 64
        case .mediumIcons: return 44
        case .list: return 20
        case .details: return 18
        }
    }

    public var gridCellWidth: CGFloat {
        switch self {
        case .extraLargeIcons: return 148
        case .largeIcons: return 112
        case .mediumIcons: return 94
        case .list: return 220
        case .details: return 0
        }
    }
}

public enum ExplorerSortField: String, CaseIterable, Identifiable {
    case name = "Nombre"
    case dateModified = "Fecha de modificación"
    case type = "Tipo"
    case size = "Tamaño"

    public var id: String { rawValue }
}

public enum ExplorerSidePaneMode: String, CaseIterable, Identifiable {
    case none = "Ninguno"
    case details = "Panel de detalles"
    case preview = "Panel de vista previa"

    public var id: String { rawValue }
}

public enum NavigationDestination: Equatable, Hashable {
    case home
    case thisPC
    case directory(URL)

    public var displayTitle: String {
        switch self {
        case .home:
            return "Inicio"
        case .thisPC:
            return "Este equipo"
        case .directory(let url):
            let name = url.lastPathComponent
            if name.isEmpty || url.path == "/" {
                return "Macintosh HD (C:)"
            }
            return Self.localizedFolderName(for: url)
        }
    }

    public var addressBarString: String {
        switch self {
        case .home:
            return "Inicio"
        case .thisPC:
            return "Este equipo"
        case .directory(let url):
            return url.path
        }
    }

    public static func localizedFolderName(for url: URL) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.cleanFileURL
        let std = url.cleanFileURL
        if std.path == home.path { return std.lastPathComponent }
        if std.path == home.appendingPathComponent("Desktop", isDirectory: true).path { return "Escritorio" }
        if std.path == home.appendingPathComponent("Downloads", isDirectory: true).path { return "Descargas" }
        if std.path == home.appendingPathComponent("Documents", isDirectory: true).path { return "Documentos" }
        if std.path == home.appendingPathComponent("Pictures", isDirectory: true).path { return "Imágenes" }
        if std.path == home.appendingPathComponent("Music", isDirectory: true).path { return "Música" }
        if std.path == home.appendingPathComponent("Movies", isDirectory: true).path { return "Videos" }
        if std.path == home.appendingPathComponent(".Trash", isDirectory: true).path { return "Papelera" }
        if std.path == FileSystemService.iCloudDriveURL.path { return "iCloud Drive" }
        if std.deletingLastPathComponent().cleanFileURL.path == FileSystemService.cloudStorageRootURL.path {
            return FileSystemService.parseCloudProviderFolderName(std.lastPathComponent).name
        }
        if std.lastPathComponent == "Documents",
           std.deletingLastPathComponent().deletingLastPathComponent().cleanFileURL.path == FileSystemService.mobileDocumentsRootURL.path {
            let container = std.deletingLastPathComponent().lastPathComponent
            if let match = FileSystemService.iCloudAppContainers.first(where: { $0.container == container }) {
                return match.title
            }
        }
        return std.lastPathComponent.isEmpty ? "Macintosh HD" : std.lastPathComponent
    }
}

public enum NewItemTemplate: String, CaseIterable, Identifiable {
    case folder = "Carpeta"
    case textDocument = "Documento de texto (.txt)"
    case markdownDocument = "Documento Markdown (.md)"
    case jsonFile = "Archivo JSON (.json)"

    public var id: String { rawValue }

    public var defaultBaseName: String {
        switch self {
        case .folder: return "Nueva carpeta"
        case .textDocument: return "Nuevo documento de texto.txt"
        case .markdownDocument: return "Notas.md"
        case .jsonFile: return "datos.json"
        }
    }

    public var defaultContents: String {
        switch self {
        case .folder: return ""
        case .textDocument: return ""
        case .markdownDocument: return "# Nuevo Documento\n\n"
        case .jsonFile: return "{\n  \n}\n"
        }
    }
}

public enum ArrowKeyDirection: Sendable {
    case up
    case down
    case left
    case right
}

public struct ArrowNavigationPayload: Sendable {
    public let direction: ArrowKeyDirection
    public let extendSelection: Bool

    public init(direction: ArrowKeyDirection, extendSelection: Bool) {
        self.direction = direction
        self.extendSelection = extendSelection
    }
}


