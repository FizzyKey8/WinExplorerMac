import SwiftUI

public struct Win11ExtractZipModalView: View {
    let zipURL: URL
    let onExtracted: (URL, Bool) -> Void
    let onCancel: () -> Void

    @State private var destinationPath: String
    @State private var showExtractedFilesWhenComplete: Bool = true
    @State private var errorMessage: String? = nil
    @State private var isExtracting: Bool = false

    public init(
        zipURL: URL,
        onExtracted: @escaping (URL, Bool) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.zipURL = zipURL
        self.onExtracted = onExtracted
        self.onCancel = onCancel
        let defaultFolder = zipURL.deletingPathExtension()
        _destinationPath = State(initialValue: defaultFolder.path)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Win11FolderIconView(size: 38, badgeSymbol: "doc.zipper", badgeColor: .orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Extraer carpetas comprimidas (en zip)")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Selecciona un destino y extrae los archivos")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text("Los archivos se extraerán en esta carpeta:")
                    .font(.system(size: 12))

                HStack(spacing: 8) {
                    TextField("", text: $destinationPath)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12))

                    Button("Examinar...") {
                        let panel = NSOpenPanel()
                        panel.canChooseFiles = false
                        panel.canChooseDirectories = true
                        panel.canCreateDirectories = true
                        panel.directoryURL = zipURL.deletingLastPathComponent()
                        if panel.runModal() == .OK, let url = panel.url {
                            destinationPath = url.path
                        }
                    }
                }
            }

            Toggle("Mostrar los archivos extraídos al completar", isOn: $showExtractedFilesWhenComplete)
                .font(.system(size: 12))

            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.red)
            }

            Spacer()

            Divider()

            HStack {
                Spacer()
                Button("Extraer") {
                    performExtraction()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(isExtracting)

                Button("Cancelar") {
                    onCancel()
                }
                .keyboardShortcut(.cancelAction)
            }
        }
        .padding(20)
        .frame(width: 480, height: 270)
    }

    private func performExtraction() {
        isExtracting = true
        errorMessage = nil
        let targetURL = URL(fileURLWithPath: (destinationPath as NSString).expandingTildeInPath)
        do {
            try ArchiveService.shared.extractZip(at: zipURL, to: targetURL)
            isExtracting = false
            onExtracted(targetURL, showExtractedFilesWhenComplete)
        } catch {
            isExtracting = false
            errorMessage = error.localizedDescription
        }
    }
}
