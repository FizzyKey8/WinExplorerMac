import SwiftUI
import AppKit

public struct Win11SidePaneView: View {
    @ObservedObject var windowVM: ExplorerWindowViewModel
    @ObservedObject var tab: ExplorerTabViewModel
    let mode: ExplorerSidePaneMode
    @Environment(\.colorScheme) private var colorScheme

    public init(windowVM: ExplorerWindowViewModel, tab: ExplorerTabViewModel, mode: ExplorerSidePaneMode) {
        self.windowVM = windowVM
        self.tab = tab
        self.mode = mode
    }

    private var selectedItem: FileItem? {
        tab.selectedFileItems.first
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text(mode.rawValue)
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Button {
                    windowVM.sidePaneMode = .none
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .frame(height: 36)

            Divider()

            if let item = selectedItem {
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: 16) {
                        if mode == .preview {
                            previewContent(for: item)
                        } else {
                            detailsContent(for: item)
                        }
                    }
                    .padding(16)
                }
            } else {
                VStack(spacing: 10) {
                    Image(systemName: mode == .preview ? "eye" : "info.circle")
                        .font(.system(size: 28))
                        .foregroundStyle(.secondary.opacity(0.6))
                    Text(mode == .preview
                         ? "Selecciona un archivo para obtener una vista previa."
                         : "Selecciona un elemento para ver sus detalles.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(width: 270)
        .background(Win11Theme.sidebarBackground(colorScheme))
        .overlay(alignment: .leading) {
            Divider().opacity(0.5)
        }
    }

    // MARK: - Preview Mode
    @ViewBuilder
    private func previewContent(for item: FileItem) -> some View {
        VStack(alignment: .center, spacing: 12) {
            if item.isImage, let nsImage = NSImage(contentsOf: item.url) {
                Image(nsImage: nsImage)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Win11Theme.subtleBorder(colorScheme), lineWidth: 1)
                    )
            } else if item.isTextPreviewable,
                      let text = try? String(contentsOf: item.url, encoding: .utf8) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(String(text.prefix(2000)))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Win11Theme.contentBackground(colorScheme))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Win11Theme.subtleBorder(colorScheme), lineWidth: 1)
                        )
                )
            } else {
                VStack(spacing: 12) {
                    Win11ItemIconView(item: item, size: 76)
                    Text("No hay vista previa interactiva para este tipo de elemento.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
            }

            Text(item.name)
                .font(.system(size: 13, weight: .semibold))
                .multilineTextAlignment(.center)
            Text(item.fileTypeDescription)
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Details Mode (Windows 11 Details Pane)
    @ViewBuilder
    private func detailsContent(for item: FileItem) -> some View {
        VStack(alignment: .center, spacing: 8) {
            if item.isImage, let nsImage = NSImage(contentsOf: item.url) {
                Image(nsImage: nsImage)
                    .resizable()
                    .scaledToFit()
                    .frame(height: 120)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                Win11ItemIconView(item: item, size: 68)
            }

            Text(item.name)
                .font(.system(size: 13.5, weight: .semibold))
                .multilineTextAlignment(.center)

            Text(item.fileTypeDescription)
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 6)

        Divider()

        VStack(alignment: .leading, spacing: 10) {
            Text("Propiedades")
                .font(.system(size: 12, weight: .semibold))

            detailKeyValue("Ruta de acceso", value: item.url.path)
            if !item.isDirectory {
                detailKeyValue("Tamaño", value: item.detailedByteSize)
            }
            detailKeyValue("Fecha de modificación", value: item.formattedModificationDate)
            detailKeyValue("Fecha de creación", value: item.formattedCreationDate)
            detailKeyValue("Oculto", value: item.isHidden ? "Sí" : "No")
            detailKeyValue("Permisos POSIX", value: String(format: "%o", item.posixPermissions))
        }

        Divider()

        Button {
            windowVM.showProperties(for: item)
        } label: {
            Label("Abrir ventana de Propiedades", systemImage: "slider.horizontal.3")
                .font(.system(size: 12))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
        }
        .buttonStyle(.bordered)
    }

    private func detailKeyValue(_ key: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(key)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 11.5, weight: .medium))
                .textSelection(.enabled)
        }
    }
}
