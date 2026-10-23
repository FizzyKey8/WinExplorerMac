import SwiftUI
import AppKit

public struct Win11UpdateModalView: View {
    @ObservedObject var updater: UpdateService
    let onClose: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    public init(updater: UpdateService, onClose: @escaping () -> Void) {
        self.updater = updater
        self.onClose = onClose
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 10) {
                Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(Win11Theme.accentBlue(colorScheme))

                Text("Actualizaciones de WinExplorerMac")
                    .font(.system(size: 13.5, weight: .semibold))

                Spacer()

                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 18)
            .frame(height: 42)

            Divider()

            // Main Content
            VStack(alignment: .leading, spacing: 16) {
                // App & Version Summary Card
                HStack(spacing: 14) {
                    Win11FolderIconView(size: 46, badgeSymbol: "arrow.down.circle.fill")

                    VStack(alignment: .leading, spacing: 3) {
                        Text("WinExplorerMac")
                            .font(.system(size: 15, weight: .bold))
                        Text("Versión instalada: v\(updater.currentVersion)")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                        Text("Repositorio: github.com/\(updater.repoOwner)/\(updater.repoName)")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary.opacity(0.85))
                    }

                    Spacer()
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Win11Theme.cardBackground(colorScheme))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(Win11Theme.subtleBorder(colorScheme), lineWidth: 1)
                        )
                )

                // Status Area
                statusContentView

                Spacer(minLength: 4)

                // Auto-check toggle
                Toggle(isOn: Binding(
                    get: { updater.autoCheckOnLaunch },
                    set: { updater.autoCheckOnLaunch = $0 }
                )) {
                    Text("Buscar actualizaciones automáticamente al abrir el explorador")
                        .font(.system(size: 12))
                }
                .toggleStyle(.checkbox)
            }
            .padding(18)

            Divider()

            // Footer Actions
            HStack(spacing: 10) {
                Button {
                    if let url = URL(string: "https://github.com/\(updater.repoOwner)/\(updater.repoName)/releases") {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    Label("Abrir Releases en GitHub", systemImage: "safari")
                        .font(.system(size: 12))
                }
                .buttonStyle(.link)

                Spacer()

                if !isBusy {
                    Button("Comprobar ahora") {
                        Task {
                            await updater.checkForUpdates(userInitiated: true)
                        }
                    }
                }

                if case .updateAvailable(let info) = updater.status {
                    Button("Actualizar e instalar v\(info.cleanVersion)") {
                        updater.installUpdate(info)
                    }
                    .buttonStyle(.borderedProminent)
                }

                Button("Cerrar") {
                    onClose()
                }
                .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
        }
        .frame(width: 500, height: 420)
        .background(Win11Theme.windowMicaBackground(colorScheme))
    }

    private var isBusy: Bool {
        switch updater.status {
        case .checking, .downloading, .installing:
            return true
        default:
            return false
        }
    }

    @ViewBuilder
    private var statusContentView: some View {
        switch updater.status {
        case .idle, .checking:
            HStack(spacing: 12) {
                ProgressView()
                    .controlSize(.small)
                Text("Consultando el repositorio en GitHub para verificar si existe una versión más reciente...")
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 130, alignment: .center)

        case .upToDate(let current):
            HStack(spacing: 12) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(.green)
                VStack(alignment: .leading, spacing: 4) {
                    Text("¡WinExplorerMac está actualizado!")
                        .font(.system(size: 13.5, weight: .semibold))
                    Text("Tienes instalada la versión más reciente disponible (v\(current)).")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.green.opacity(0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color.green.opacity(0.25), lineWidth: 1)
                    )
            )

        case .noReleasesInRepo(let current):
            HStack(spacing: 12) {
                Image(systemName: "tag.circle.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(Win11Theme.accentBlue(colorScheme))
                VStack(alignment: .leading, spacing: 4) {
                    Text("Versión actual v\(current) (Sin tags/releases remotos aún)")
                        .font(.system(size: 13, weight: .semibold))
                    Text("En cuanto publiques un tag o release superior (ej. v1.0.1) en GitHub, aparecerá aquí para actualizar automáticamente.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Win11Theme.cardBackground(colorScheme))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Win11Theme.subtleBorder(colorScheme), lineWidth: 1)
                    )
            )

        case .updateAvailable(let info):
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("Nueva versión disponible: v\(info.cleanVersion)", systemImage: "sparkles")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Win11Theme.accentBlue(colorScheme))
                    Spacer()
                    Text(info.title)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                }

                ScrollView(.vertical) {
                    Text(info.releaseNotes)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.primary.opacity(0.9))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                }
                .frame(maxHeight: 120)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Win11Theme.contentBackground(colorScheme))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(Win11Theme.subtleBorder(colorScheme), lineWidth: 1)
                        )
                )
            }

        case .downloading(let progress, let description):
            VStack(alignment: .leading, spacing: 10) {
                Text(description)
                    .font(.system(size: 12.5, weight: .medium))
                ProgressView(value: progress, total: 1.0)
                    .progressViewStyle(.linear)
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 110)

        case .installing(let description):
            HStack(spacing: 12) {
                ProgressView()
                    .controlSize(.small)
                VStack(alignment: .leading, spacing: 4) {
                    Text(description)
                        .font(.system(size: 12.5, weight: .semibold))
                    Text("La aplicación se cerrará y volverá a abrirse automáticamente al finalizar.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 110, alignment: .leading)

        case .error(let message):
            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(.orange)
                Text(message)
                    .font(.system(size: 12))
                    .foregroundStyle(.primary)
                Spacer()
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.orange.opacity(0.10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color.orange.opacity(0.30), lineWidth: 1)
                    )
            )
        }
    }
}
