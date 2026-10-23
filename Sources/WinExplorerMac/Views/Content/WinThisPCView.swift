import SwiftUI

public struct Win11ThisPCView: View {
    @ObservedObject var windowVM: ExplorerWindowViewModel
    @ObservedObject var tab: ExplorerTabViewModel
    @Environment(\.colorScheme) private var colorScheme

    @State private var isFoldersExpanded: Bool = true
    @State private var isDrivesExpanded: Bool = true
    @State private var isCloudExpanded: Bool = true

    private let folderColumns = [
        GridItem(.adaptive(minimum: 200, maximum: 240), spacing: 12)
    ]

    private let driveColumns = [
        GridItem(.adaptive(minimum: 270, maximum: 320), spacing: 14)
    ]

    public init(windowVM: ExplorerWindowViewModel, tab: ExplorerTabViewModel) {
        self.windowVM = windowVM
        self.tab = tab
    }

    public var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 24) {
                // 1. Dispositivos y unidades (Drives with Windows 11 capacity bar)
                DisclosureGroup(isExpanded: $isDrivesExpanded) {
                    LazyVGrid(columns: driveColumns, alignment: .leading, spacing: 14) {
                        ForEach(windowVM.volumes) { volume in
                            driveCard(for: volume)
                        }
                    }
                    .padding(.top, 12)
                } label: {
                    Text("Dispositivos y unidades (\(windowVM.volumes.count))")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.primary)
                }

                Divider()

                // 2. Almacenamiento en la nube (iCloud Drive, Claro drive, etc.)
                if !windowVM.cloudDrives.isEmpty {
                    DisclosureGroup(isExpanded: $isCloudExpanded) {
                        LazyVGrid(columns: folderColumns, alignment: .leading, spacing: 12) {
                            ForEach(windowVM.cloudDrives) { cloud in
                                if let item = FileSystemService.shared.makeFileItem(from: cloud.url, customDisplayName: cloud.name) {
                                    systemFolderCard(item: item, title: cloud.name, subtitle: cloud.subtitle)
                                }
                            }
                        }
                        .padding(.top, 12)
                    } label: {
                        Text("Almacenamiento en la nube (\(windowVM.cloudDrives.count))")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.primary)
                    }

                    Divider()
                }

                // 3. Carpetas del usuario (Desktop, Downloads, Documents, Pictures, Music, Videos)
                DisclosureGroup(isExpanded: $isFoldersExpanded) {
                    LazyVGrid(columns: folderColumns, alignment: .leading, spacing: 12) {
                        ForEach(windowVM.quickAccess.pinnedFolders) { folder in
                            if let item = FileSystemService.shared.makeFileItem(from: folder.url) {
                                systemFolderCard(item: item, title: folder.title)
                            }
                        }
                    }
                    .padding(.top, 12)
                } label: {
                    Text("Carpetas (\(windowVM.quickAccess.pinnedFolders.count))")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.primary)
                }
            }
            .padding(20)
        }
        .background(Win11Theme.contentBackground(colorScheme))
        .onAppear {
            windowVM.refreshVolumes()
        }
    }

    private func driveCard(for volume: VolumeInfo) -> some View {
        let isSelected = tab.selectedURLs.contains(volume.url)

        return HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Win11Theme.accentBlue(colorScheme).opacity(0.12))
                    .frame(width: 48, height: 48)
                Image(systemName: volume.isRemovable ? "externaldrive.fill" : "internaldrive.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(volume.isRemovable ? Color.orange : Win11Theme.accentBlue(colorScheme))
            }

            VStack(alignment: .leading, spacing: 5) {
                Text(volume.displayTitleWithDriveLetter)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)

                // Windows 11 Storage Progress Bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.secondary.opacity(0.22))
                            .frame(height: 10)

                        RoundedRectangle(cornerRadius: 3)
                            .fill(
                                volume.isNearFull
                                    ? Color.red
                                    : Color(red: 0.0, green: 0.47, blue: 0.84)
                            )
                            .frame(width: max(4, geo.size.width * volume.usageFraction), height: 10)
                    }
                }
                .frame(height: 10)

                Text(volume.formattedCapacitySubtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(isSelected ? Win11Theme.selectionFill(colorScheme) : Win11Theme.cardBackground(colorScheme))
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(
                            isSelected ? Win11Theme.selectionBorder(colorScheme) : Win11Theme.subtleBorder(colorScheme),
                            lineWidth: 1
                        )
                )
        )
        .overlay(
            Win11MouseHandlerView(
                onSingleClick: { _ in
                    tab.selectedURLs = [volume.url]
                },
                onDoubleClick: {
                    tab.navigate(to: .directory(volume.url))
                },
                onRightClick: { point in
                    if let item = FileSystemService.shared.makeFileItem(from: volume.url) {
                        windowVM.presentContextMenu(for: item, at: point)
                    }
                }
            )
        )
    }

    private func systemFolderCard(item: FileItem, title: String, subtitle: String = "Carpeta del sistema") -> some View {
        let isSelected = tab.selectedURLs.contains(item.url)

        return HStack(spacing: 12) {
            Win11ItemIconView(item: item, size: 38)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(isSelected ? Win11Theme.selectionFill(colorScheme) : Win11Theme.cardBackground(colorScheme))
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(
                            isSelected ? Win11Theme.selectionBorder(colorScheme) : Win11Theme.subtleBorder(colorScheme),
                            lineWidth: 1
                        )
                )
        )
        .overlay(
            Win11MouseHandlerView(
                onSingleClick: { _ in
                    tab.selectedURLs = [item.url]
                },
                onDoubleClick: {
                    tab.navigate(to: .directory(item.url))
                },
                onRightClick: { point in
                    windowVM.presentContextMenu(for: item, at: point)
                }
            )
        )
    }
}
