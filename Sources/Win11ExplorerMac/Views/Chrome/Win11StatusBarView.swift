import SwiftUI

public struct Win11StatusBarView: View {
    @ObservedObject var tab: ExplorerTabViewModel
    @Environment(\.colorScheme) private var colorScheme

    public init(tab: ExplorerTabViewModel) {
        self.tab = tab
    }

    public var body: some View {
        HStack(spacing: 14) {
            if case .directory = tab.destination {
                Text("\(tab.displayedItems.count) elementos")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)

                if !tab.selectedURLs.isEmpty {
                    Rectangle()
                        .fill(Win11Theme.subtleBorder(colorScheme))
                        .frame(width: 1, height: 12)

                    Text("\(tab.selectedURLs.count) elemento(s) seleccionado(s)")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)

                    if tab.selectedTotalBytes > 0 {
                        Text(formatBytes(tab.selectedTotalBytes))
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                Text(tab.destination.displayTitle)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
            }

            if let status = tab.statusMessage {
                Text("•  \(status)")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            // Quick View Switcher on bottom-right (Details vs Grid Icons, just like Windows 11)
            HStack(spacing: 2) {
                statusBarViewButton(mode: .details, symbol: "tablecells", tooltip: "Vista de detalles")
                statusBarViewButton(mode: .largeIcons, symbol: "square.grid.2x2", tooltip: "Vista de iconos grandes")
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 26)
        .background(Win11Theme.windowMicaBackground(colorScheme))
        .overlay(alignment: .top) {
            Divider().opacity(0.45)
        }
    }

    private func statusBarViewButton(mode: ExplorerViewMode, symbol: String, tooltip: String) -> some View {
        Button {
            tab.viewMode = mode
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 11))
                .foregroundStyle(tab.viewMode == mode ? Win11Theme.accentBlue(colorScheme) : .secondary)
                .frame(width: 24, height: 20)
                .background(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(tab.viewMode == mode ? Win11Theme.selectionFill(colorScheme) : Color.clear)
                )
        }
        .buttonStyle(.plain)
        .help(tooltip)
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let kb = Double(bytes) / 1024.0
        if kb < 1024 {
            return String(format: "%.1f KB", kb)
        }
        let mb = kb / 1024.0
        if mb < 1024 {
            return String(format: "%.2f MB", mb)
        }
        return String(format: "%.2f GB", mb / 1024.0)
    }
}
