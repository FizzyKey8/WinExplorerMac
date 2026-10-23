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
        let home = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL
        let std = url.standardizedFileURL
        if std == home { return std.lastPathComponent }
        if std == home.appendingPathComponent("Desktop") { return "Escritorio" }
        if std == home.appendingPathComponent("Downloads") { return "Descargas" }
        if std == home.appendingPathComponent("Documents") { return "Documentos" }
        if std == home.appendingPathComponent("Pictures") { return "Imágenes" }
        if std == home.appendingPathComponent("Music") { return "Música" }
        if std == home.appendingPathComponent("Movies") { return "Videos" }
        if std == home.appendingPathComponent(".Trash") { return "Basurero" }
        if std == FileSystemService.iCloudDriveURL { return "iCloud Drive" }
        if std.deletingLastPathComponent().standardizedFileURL == FileSystemService.cloudStorageRootURL {
            return FileSystemService.parseCloudProviderFolderName(std.lastPathComponent).name
        }
        if std.lastPathComponent == "Documents",
           std.deletingLastPathComponent().deletingLastPathComponent().standardizedFileURL == FileSystemService.mobileDocumentsRootURL {
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
