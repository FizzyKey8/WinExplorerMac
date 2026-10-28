import SwiftUI

public struct Win11PropertiesModalView: View {
    let item: FileItem
    let onClose: () -> Void

    @State private var selectedTab: Int = 0
    @State private var calculatedBytes: Int64 = 0
    @State private var fileCount: Int = 0
    @State private var folderCount: Int = 0
    @State private var isCalculatingFolder: Bool = false
    @State private var isHiddenAttribute: Bool
    @ObservedObject private var folderCustomStore = FolderCustomizationStore.shared

    public init(item: FileItem, onClose: @escaping () -> Void) {
        self.item = item
        self.onClose = onClose
        _isHiddenAttribute = State(initialValue: item.isHidden)
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Windows 11 Properties Title Header
            HStack(spacing: 10) {
                Win11ItemIconView(item: item, size: 20)
                Text("Propiedades: \(item.name)")
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .frame(height: 38)

            // Tabs: General | Detalles | Personalizar (para carpetas)
            Picker("", selection: $selectedTab) {
                Text("General").tag(0)
                Text("Detalles").tag(1)
                if item.isDirectory {
                    Text("Personalizar").tag(2)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.bottom, 10)

            Divider()

            if selectedTab == 0 {
                generalTabContent
            } else if selectedTab == 1 {
                detailsTabContent
            } else {
                customizeTabContent
            }

            Divider()

            // Bottom Dialog Buttons: Aceptar / Cancelar
            HStack {
                Spacer()
                Button("Aceptar") {
                    onClose()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)

                Button("Cancelar") {
                    onClose()
                }
                .keyboardShortcut(.cancelAction)
            }
            .padding(14)
        }
        .frame(width: 420, height: 490)
        .onAppear {
            if item.isDirectory {
                isCalculatingFolder = true
                let targetURL = item.url
                DispatchQueue.global(qos: .userInitiated).async {
                    let metrics = FileSystemService.shared.calculateFolderMetrics(at: targetURL)
                    DispatchQueue.main.async {
                        self.calculatedBytes = metrics.totalBytes
                        self.fileCount = metrics.fileCount
                        self.folderCount = metrics.folderCount
                        self.isCalculatingFolder = false
                    }
                }
            }
        }
    }

    private var generalTabContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                Win11ItemIconView(item: item, size: 48)
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.name)
                        .font(.system(size: 14, weight: .semibold))
                        .textSelection(.enabled)
                    Text(item.fileTypeDescription)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            propertyRow(label: "Tipo:", value: item.fileTypeDescription)
            propertyRow(label: "Ubicación:", value: item.parentPath)

            if item.isDirectory {
                propertyRow(
                    label: "Tamaño:",
                    value: isCalculatingFolder ? "Calculando..." : formatDetailedBytes(calculatedBytes)
                )
                propertyRow(
                    label: "Contiene:",
                    value: isCalculatingFolder ? "Calculando..." : "\(fileCount) archivos, \(folderCount) carpetas"
                )
            } else {
                propertyRow(label: "Tamaño:", value: item.detailedByteSize)
            }

            Divider()

            propertyRow(label: "Creado:", value: item.formattedCreationDate)
            propertyRow(label: "Modificado:", value: item.formattedModificationDate)

            Divider()

            HStack(alignment: .center) {
                Text("Atributos:")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(width: 95, alignment: .leading)

                HStack(spacing: 18) {
                    Toggle(isOn: $isHiddenAttribute) {
                        Text("Oculto")
                            .font(.system(size: 12))
                    }
                    .toggleStyle(.checkbox)
                    .onChange(of: isHiddenAttribute) {
                        FileSystemService.shared.setHidden(isHiddenAttribute, for: [item.url])
                        NotificationCenter.default.post(name: .folderCustomizationChanged, object: nil)
                    }

                    Label("Permisos \(String(format: "%o", item.posixPermissions))", systemImage: "lock.shield")
                        .font(.system(size: 12))
                }
            }

            Spacer()
        }
        .padding(18)
    }

    private var detailsTabContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            propertyRow(label: "Nombre:", value: item.name)
            propertyRow(label: "Extensión:", value: item.fileExtension.isEmpty ? "(Ninguna)" : ".\(item.fileExtension)")
            propertyRow(label: "Ruta completa:", value: item.url.path)
            propertyRow(label: "Enlace simbólico:", value: item.isSymlink ? "Sí" : "No")
            propertyRow(label: "Permisos POSIX:", value: String(format: "0%o", item.posixPermissions))
            Spacer()
        }
        .padding(18)
    }

    private var customizeTabContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Iconos de carpeta")
                .font(.system(size: 13, weight: .semibold))

            Text("Puede cambiar el color de la carpeta o seleccionar una imagen personalizada para el icono:")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            HStack(spacing: 16) {
                Win11ItemIconView(item: item, size: 56)
                    .frame(width: 64, height: 64)
                    .background(Color.primary.opacity(0.04))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 6) {
                    let activeColor = folderCustomStore.customColor(for: item.url) ?? .yellow
                    Text("Color activo: \(activeColor.displayName)")
                        .font(.system(size: 12, weight: .medium))

                    if folderCustomStore.customImage(for: item.url) != nil {
                        Text("Icono de imagen personalizado activo")
                            .font(.system(size: 11))
                            .foregroundStyle(.blue)
                    }
                }
            }
            .padding(10)
            .background(Color.primary.opacity(0.03))
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

            VStack(alignment: .leading, spacing: 8) {
                Text("Elegir color:")
                    .font(.system(size: 12, weight: .medium))

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 5), spacing: 10) {
                    ForEach(FolderCustomColor.allCases) { color in
                        let isSelected = (folderCustomStore.customColor(for: item.url) == color) ||
                                         (folderCustomStore.customColor(for: item.url) == nil && color == .yellow)

                        Button {
                            folderCustomStore.setColor(color, for: item.url)
                        } label: {
                            VStack(spacing: 3) {
                                ZStack {
                                    Circle()
                                        .fill(color.swatchColor)
                                        .frame(width: 26, height: 26)
                                        .shadow(color: Color.black.opacity(0.18), radius: 2, x: 0, y: 1)

                                    if isSelected {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 11, weight: .bold))
                                            .foregroundStyle(.white)
                                    }
                                }
                                Text(color.displayName.components(separatedBy: " ").first ?? "")
                                    .font(.system(size: 10))
                                    .lineLimit(1)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 4)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Divider()

            HStack(spacing: 12) {
                Button {
                    folderCustomStore.promptChooseImage(for: item.url)
                } label: {
                    Label("Cambiar icono por imagen...", systemImage: "photo")
                        .font(.system(size: 12))
                }
                .buttonStyle(.bordered)

                if folderCustomStore.hasCustomization(for: item.url) {
                    Button {
                        folderCustomStore.resetCustomization(for: item.url)
                    } label: {
                        Label("Restaurar predeterminado", systemImage: "arrow.counterclockwise")
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
            }

            Spacer()
        }
        .padding(18)
    }

    private func propertyRow(label: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(width: 95, alignment: .leading)
            Text(value)
                .font(.system(size: 12))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func formatDetailedBytes(_ bytes: Int64) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        let raw = formatter.string(from: NSNumber(value: bytes)) ?? "\(bytes)"
        let mb = Double(bytes) / (1024.0 * 1024.0)
        return String(format: "%.2f MB (%@ bytes)", mb, raw)
    }
}
