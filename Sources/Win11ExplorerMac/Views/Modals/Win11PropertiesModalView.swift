import SwiftUI

public struct Win11PropertiesModalView: View {
    let item: FileItem
    let onClose: () -> Void

    @State private var selectedTab: Int = 0
    @State private var calculatedBytes: Int64 = 0
    @State private var fileCount: Int = 0
    @State private var folderCount: Int = 0
    @State private var isCalculatingFolder: Bool = false

    public init(item: FileItem, onClose: @escaping () -> Void) {
        self.item = item
        self.onClose = onClose
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

            // Tabs: General | Detalles
            Picker("", selection: $selectedTab) {
                Text("General").tag(0)
                Text("Detalles").tag(1)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.bottom, 10)

            Divider()

            if selectedTab == 0 {
                generalTabContent
            } else {
                detailsTabContent
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
        .frame(width: 410, height: 470)
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

            HStack(alignment: .top) {
                Text("Atributos:")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(width: 95, alignment: .leading)

                HStack(spacing: 18) {
                    Label(item.isHidden ? "Oculto (Sí)" : "Oculto (No)", systemImage: item.isHidden ? "checkmark.square.fill" : "square")
                        .font(.system(size: 12))
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
