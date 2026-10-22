import SwiftUI
import AppKit

public struct Win11ContextMenuOverlay: View {
    @ObservedObject var windowVM: ExplorerWindowViewModel
    @ObservedObject var tab: ExplorerTabViewModel
    let request: ContextMenuRequest
    let windowSize: CGSize

    @Environment(\.colorScheme) private var colorScheme

    public init(
        windowVM: ExplorerWindowViewModel,
        tab: ExplorerTabViewModel,
        request: ContextMenuRequest,
        windowSize: CGSize
    ) {
        self.windowVM = windowVM
        self.tab = tab
        self.request = request
        self.windowSize = windowSize
    }

    private let menuWidth: CGFloat = 278

    public var body: some View {
        ZStack(alignment: .topLeading) {
            // Transparent backdrop to dismiss menu on click outside
            Color.black.opacity(0.001)
                .ignoresSafeArea()
                .onTapGesture {
                    windowVM.dismissContextMenu()
                }

            VStack(alignment: .leading, spacing: 4) {
                if let item = request.targetItem {
                    itemContextMenuContent(for: item)
                } else {
                    backgroundContextMenuContent()
                }
            }
            .padding(6)
            .frame(width: menuWidth)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Win11Theme.contextMenuBackground(colorScheme))
                    .shadow(color: Color.black.opacity(0.28), radius: 14, x: 0, y: 6)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Win11Theme.subtleBorder(colorScheme), lineWidth: 1)
            )
            .offset(x: clampedPosition.x, y: clampedPosition.y)
        }
    }

    private var clampedPosition: CGPoint {
        let estimatedHeight: CGFloat = request.targetItem != nil ? 375 : 310
        let x = min(max(8, request.locationInWindow.x), max(8, windowSize.width - menuWidth - 12))
        let y = min(max(44, request.locationInWindow.y), max(44, windowSize.height - estimatedHeight - 12))
        return CGPoint(x: x, y: y)
    }

    // MARK: - 1. Windows 11 Context Menu for a File or Folder
    @ViewBuilder
    private func itemContextMenuContent(for item: FileItem) -> some View {
        // Top Action Icon Bar (Signature Windows 11 Right-Click Bar: Cut, Copy, Paste, Rename, Share, Delete)
        HStack(spacing: 4) {
            topActionIconButton(symbol: "scissors", tooltip: "Cortar (Cmd+X)") {
                windowVM.cutSelection()
            }
            topActionIconButton(symbol: "doc.on.doc", tooltip: "Copiar (Cmd+C)") {
                windowVM.copySelection()
            }
            if item.isDirectory && windowVM.clipboard.hasItems {
                topActionIconButton(symbol: "doc.on.clipboard", tooltip: "Pegar dentro de la carpeta") {
                    windowVM.pasteIntoCurrentDirectory(targetFolderOverride: item.url)
                }
            }
            topActionIconButton(symbol: "character.cursor.ibeam", tooltip: "Cambiar nombre (F2)") {
                windowVM.dismissContextMenu()
                tab.beginRename(for: item)
            }
            topActionIconButton(symbol: "square.and.arrow.up", tooltip: "Compartir") {
                windowVM.shareItems(Array(tab.selectedURLs))
            }
            topActionIconButton(symbol: "trash", tooltip: "Eliminar (Cmd+Delete)") {
                windowVM.moveSelectedToTrash()
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 3)

        Divider()
            .padding(.vertical, 2)

        // Primary Open Actions
        contextMenuRow(
            title: "Abrir",
            symbol: item.isDirectory ? "folder" : "arrow.up.forward.app",
            shortcut: "Intro",
            isBold: true
        ) {
            windowVM.openItem(item, inNewTab: false)
        }

        if item.isDirectory {
            contextMenuRow(
                title: "Abrir en una pestaña nueva",
                symbol: "plus.rectangle.on.rectangle"
            ) {
                windowVM.openItem(item, inNewTab: true)
            }

            let isPinned = windowVM.quickAccess.isPinned(item.url)
            contextMenuRow(
                title: isPinned ? "Desanclar del Acceso rápido" : "Anclar al Acceso rápido",
                symbol: isPinned ? "pin.slash" : "pin"
            ) {
                windowVM.quickAccess.togglePin(for: item.url)
                windowVM.dismissContextMenu()
            }
        } else {
            // "Abrir con..." submenu for files
            let apps = FileSystemService.shared.availableApplications(for: item.url).prefix(6)
            if !apps.isEmpty {
                Menu {
                    ForEach(Array(apps), id: \.self) { appURL in
                        Button(appURL.deletingPathExtension().lastPathComponent) {
                            FileSystemService.shared.openItem(item.url, withApplication: appURL)
                            windowVM.dismissContextMenu()
                        }
                    }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "app.badge")
                            .frame(width: 16)
                        Text("Abrir con")
                            .font(.system(size: 12.5))
                        Spacer()
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                }
                .menuStyle(.borderlessButton)
            }
        }

        if item.isArchiveZip {
            contextMenuRow(
                title: "Extraer todo...",
                symbol: "archivebox"
            ) {
                windowVM.promptExtractZip(for: item.url)
            }
        }

        Divider()
            .padding(.vertical, 2)

        contextMenuRow(
            title: "Comprimir en archivo ZIP",
            symbol: "doc.zipper"
        ) {
            windowVM.compressSelectedToZip()
        }

        contextMenuRow(
            title: "Copiar como ruta de acceso",
            symbol: "link",
            shortcut: "Cmd+Shift+C"
        ) {
            FileSystemService.shared.copyPathToPasteboard(Array(tab.selectedURLs), quoted: true)
            tab.statusMessage = "Ruta copiada al portapapeles"
            windowVM.dismissContextMenu()
        }

        if item.isDirectory {
            contextMenuRow(
                title: "Abrir en Terminal",
                symbol: "terminal"
            ) {
                FileSystemService.shared.openInTerminal(at: item.url)
                windowVM.dismissContextMenu()
            }
        }

        contextMenuRow(
            title: "Mostrar en Finder de macOS",
            symbol: "macwindow"
        ) {
            FileSystemService.shared.revealInFinder(item.url)
            windowVM.dismissContextMenu()
        }

        Divider()
            .padding(.vertical, 2)

        contextMenuRow(
            title: "Propiedades",
            symbol: "info.circle",
            shortcut: "Alt+Intro"
        ) {
            windowVM.showProperties(for: item)
        }
    }

    // MARK: - 2. Windows 11 Context Menu for Empty Folder Space
    @ViewBuilder
    private func backgroundContextMenuContent() -> some View {
        if windowVM.clipboard.hasItems {
            HStack(spacing: 4) {
                topActionIconButton(symbol: "doc.on.clipboard", tooltip: "Pegar (Cmd+V)") {
                    windowVM.pasteIntoCurrentDirectory()
                }
                Spacer()
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 3)

            Divider()
                .padding(.vertical, 2)
        }

        // View Mode Sub-options
        Menu {
            ForEach(ExplorerViewMode.allCases) { mode in
                Button {
                    tab.viewMode = mode
                    windowVM.dismissContextMenu()
                } label: {
                    Label(mode.rawValue, systemImage: mode.sfSymbol)
                }
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: tab.viewMode.sfSymbol)
                    .frame(width: 16)
                Text("Ver")
                    .font(.system(size: 12.5))
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
        }
        .menuStyle(.borderlessButton)

        // Sort By Sub-options
        Menu {
            ForEach(ExplorerSortField.allCases) { field in
                Button(field.rawValue) {
                    tab.toggleSort(by: field)
                    windowVM.dismissContextMenu()
                }
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "arrow.up.arrow.down")
                    .frame(width: 16)
                Text("Ordenar por")
                    .font(.system(size: 12.5))
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
        }
        .menuStyle(.borderlessButton)

        contextMenuRow(
            title: "Actualizar",
            symbol: "arrow.clockwise",
            shortcut: "Cmd+R"
        ) {
            tab.reload()
            windowVM.dismissContextMenu()
        }

        Divider()
            .padding(.vertical, 2)

        contextMenuRow(
            title: "Nueva carpeta",
            symbol: "folder.badge.plus",
            shortcut: "Cmd+Shift+N"
        ) {
            windowVM.createNewItem(.folder)
        }

        contextMenuRow(
            title: "Nuevo documento de texto",
            symbol: "doc.badge.plus"
        ) {
            windowVM.createNewItem(.textDocument)
        }

        if windowVM.clipboard.hasItems {
            contextMenuRow(
                title: "Pegar",
                symbol: "doc.on.clipboard",
                shortcut: "Cmd+V"
            ) {
                windowVM.pasteIntoCurrentDirectory()
            }
        }

        Divider()
            .padding(.vertical, 2)

        if let dirURL = tab.currentDirectoryURL {
            contextMenuRow(
                title: "Abrir en Terminal",
                symbol: "terminal"
            ) {
                FileSystemService.shared.openInTerminal(at: dirURL)
                windowVM.dismissContextMenu()
            }

            contextMenuRow(
                title: "Anclar carpeta actual al Acceso rápido",
                symbol: "pin"
            ) {
                windowVM.quickAccess.togglePin(for: dirURL)
                windowVM.dismissContextMenu()
            }
        }

        contextMenuRow(
            title: "Propiedades",
            symbol: "info.circle"
        ) {
            windowVM.showProperties(for: nil)
        }
    }

    // MARK: - Helper Subviews
    private func topActionIconButton(symbol: String, tooltip: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(.primary)
                .frame(width: 36, height: 32)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.primary.opacity(0.05))
                )
        }
        .buttonStyle(.plain)
        .help(tooltip)
    }

    private func contextMenuRow(
        title: String,
        symbol: String,
        shortcut: String? = nil,
        isBold: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 13))
                    .foregroundStyle(.primary.opacity(0.85))
                    .frame(width: 18)

                Text(title)
                    .font(.system(size: 12.5, weight: isBold ? .semibold : .regular))
                    .foregroundStyle(.primary)

                Spacer()

                if let shortcut {
                    Text(shortcut)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color.primary.opacity(0.001))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
