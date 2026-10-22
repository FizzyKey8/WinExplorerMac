import SwiftUI

public struct Win11CommandBarView: View {
    @ObservedObject var windowVM: ExplorerWindowViewModel
    @ObservedObject var tab: ExplorerTabViewModel
    @ObservedObject var clipboard: FileClipboardService
    @ObservedObject private var updateService = UpdateService.shared
    @Environment(\.colorScheme) private var colorScheme

    public init(windowVM: ExplorerWindowViewModel, tab: ExplorerTabViewModel, clipboard: FileClipboardService) {
        self.windowVM = windowVM
        self.tab = tab
        self.clipboard = clipboard
    }

    private var isInRealDirectory: Bool {
        tab.currentDirectoryURL != nil
    }

    private var hasSelection: Bool {
        !tab.selectedURLs.isEmpty
    }

    private var hasSingleSelection: Bool {
        tab.selectedURLs.count == 1
    }

    public var body: some View {
        HStack(spacing: 4) {
            // "+ Nuevo" Dropdown Button (Windows 11 primary command)
            Menu {
                ForEach(NewItemTemplate.allCases) { template in
                    Button {
                        windowVM.createNewItem(template)
                    } label: {
                        Label(
                            template.rawValue,
                            systemImage: template == .folder ? "folder.badge.plus" : "doc.badge.plus"
                        )
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus.circle.fill")
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(Win11Theme.accentBlue(colorScheme))
                        .font(.system(size: 15))
                    Text("Nuevo")
                        .font(.system(size: 12, weight: .medium))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .disabled(!isInRealDirectory)
            .opacity(isInRealDirectory ? 1.0 : 0.45)
            .help("Crear un nuevo elemento en la ubicación actual")

            commandDivider

            // Quick Action Icon Buttons: Cut, Copy, Paste, Rename, Share, Delete, ZIP
            HStack(spacing: 2) {
                commandIconButton(
                    symbol: "scissors",
                    tooltip: "Cortar (Cmd+X)",
                    enabled: isInRealDirectory && hasSelection
                ) {
                    windowVM.cutSelection()
                }

                commandIconButton(
                    symbol: "doc.on.doc",
                    tooltip: "Copiar (Cmd+C)",
                    enabled: isInRealDirectory && hasSelection
                ) {
                    windowVM.copySelection()
                }

                commandIconButton(
                    symbol: "doc.on.clipboard",
                    tooltip: "Pegar (Cmd+V)",
                    enabled: isInRealDirectory && clipboard.hasItems
                ) {
                    windowVM.pasteIntoCurrentDirectory()
                }

                commandIconButton(
                    symbol: "character.cursor.ibeam",
                    tooltip: "Cambiar nombre (F2)",
                    enabled: isInRealDirectory && hasSingleSelection
                ) {
                    tab.beginRename()
                }

                commandIconButton(
                    symbol: "square.and.arrow.up",
                    tooltip: "Compartir",
                    enabled: isInRealDirectory && hasSelection
                ) {
                    windowVM.shareItems(Array(tab.selectedURLs))
                }

                commandIconButton(
                    symbol: "trash",
                    tooltip: "Eliminar a la Papelera (Cmd+Delete)",
                    enabled: isInRealDirectory && hasSelection
                ) {
                    windowVM.moveSelectedToTrash()
                }

                commandIconButton(
                    symbol: "doc.zipper",
                    tooltip: "Comprimir en archivo ZIP",
                    enabled: isInRealDirectory && hasSelection
                ) {
                    windowVM.compressSelectedToZip()
                }
            }

            commandDivider

            // "Ordenar" Menu
            Menu {
                Section("Ordenar por") {
                    ForEach(ExplorerSortField.allCases) { field in
                        Button {
                            tab.sortField = field
                        } label: {
                            HStack {
                                Text(field.rawValue)
                                if tab.sortField == field {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                }
                Divider()
                Section("Dirección") {
                    Button {
                        tab.sortAscending = true
                    } label: {
                        HStack {
                            Text("Ascendente")
                            if tab.sortAscending {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                    Button {
                        tab.sortAscending = false
                    } label: {
                        HStack {
                            Text("Descendente")
                            if !tab.sortAscending {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "arrow.up.arrow.down")
                        .font(.system(size: 12))
                    Text("Ordenar")
                        .font(.system(size: 12))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Ordenar y agrupar opciones")

            // "Ver" Menu
            Menu {
                Section("Diseño") {
                    ForEach(ExplorerViewMode.allCases) { mode in
                        Button {
                            tab.viewMode = mode
                        } label: {
                            Label(mode.rawValue, systemImage: mode.sfSymbol)
                        }
                    }
                }
                Divider()
                Section("Mostrar u ocultar") {
                    Toggle("Extensiones de nombre de archivo", isOn: $tab.showFileExtensions)
                    Toggle("Elementos ocultos (.dotfiles)", isOn: Binding(
                        get: { tab.showHiddenFiles },
                        set: { newValue in
                            tab.showHiddenFiles = newValue
                            tab.reload()
                        }
                    ))
                    Toggle("Panel de navegación izquierdo", isOn: $windowVM.isSidebarVisible)
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: tab.viewMode.sfSymbol)
                        .font(.system(size: 12))
                    Text("Ver")
                        .font(.system(size: 12))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Opciones de vista y visualización")

            Spacer()

            // Right Side: Update Check + Details Pane / Preview Pane toggles
            HStack(spacing: 4) {
                Button {
                    updateService.openUpdateModalAndCheck()
                } label: {
                    HStack(spacing: 5) {
                        ZStack(alignment: .topTrailing) {
                            Image(systemName: updateService.availableUpdate != nil ? "arrow.down.circle.fill" : "arrow.triangle.2.circlepath")
                                .font(.system(size: 12))
                                .foregroundStyle(updateService.availableUpdate != nil ? Win11Theme.accentBlue(colorScheme) : .primary)
                            if updateService.availableUpdate != nil {
                                Circle()
                                    .fill(Color.green)
                                    .frame(width: 6, height: 6)
                                    .offset(x: 2, y: -2)
                            }
                        }
                        if let rel = updateService.availableUpdate {
                            Text("Actualizar (v\(rel.cleanVersion))")
                                .font(.system(size: 11.5, weight: .semibold))
                                .foregroundStyle(Win11Theme.accentBlue(colorScheme))
                        } else {
                            Text("Actualizar")
                                .font(.system(size: 12))
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(updateService.availableUpdate != nil ? Win11Theme.selectionFill(colorScheme) : Color.clear)
                    )
                }
                .buttonStyle(.plain)
                .help("Buscar actualizaciones en GitHub (Cmd+U)")

                commandDivider

                Button {
                    windowVM.sidePaneMode = (windowVM.sidePaneMode == .preview) ? .none : .preview
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "eye")
                            .font(.system(size: 12))
                        Text("Vista previa")
                            .font(.system(size: 12))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(windowVM.sidePaneMode == .preview ? Win11Theme.selectionFill(colorScheme) : Color.clear)
                    )
                }
                .buttonStyle(.plain)
                .help("Mostrar u ocultar el panel de vista previa")

                Button {
                    windowVM.sidePaneMode = (windowVM.sidePaneMode == .details) ? .none : .details
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "sidebar.right")
                            .font(.system(size: 12))
                        Text("Detalles")
                            .font(.system(size: 12))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(windowVM.sidePaneMode == .details ? Win11Theme.selectionFill(colorScheme) : Color.clear)
                    )
                }
                .buttonStyle(.plain)
                .help("Mostrar u ocultar el panel de detalles")
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 40)
        .background(Win11Theme.commandBarBackground(colorScheme))
        .overlay(alignment: .top) {
            Divider().opacity(0.5)
        }
        .overlay(alignment: .bottom) {
            Divider().opacity(0.5)
        }
    }

    private var commandDivider: some View {
        Rectangle()
            .fill(Win11Theme.subtleBorder(colorScheme))
            .frame(width: 1, height: 22)
            .padding(.horizontal, 4)
    }

    private func commandIconButton(symbol: String, tooltip: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13.5, weight: .regular))
                .foregroundStyle(enabled ? Color.primary : Color.secondary.opacity(0.35))
                .frame(width: 32, height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(Color.primary.opacity(0.001))
                )
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .help(tooltip)
    }
}
