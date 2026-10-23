import SwiftUI

public struct Win11SidebarView: View {
    @ObservedObject var windowVM: ExplorerWindowViewModel
    @ObservedObject var tab: ExplorerTabViewModel
    @ObservedObject var quickAccess: QuickAccessStore
    @Environment(\.colorScheme) private var colorScheme

    @State private var isCloudExpanded: Bool = true
    @State private var isQuickAccessExpanded: Bool = true
    @State private var isThisPCExpanded: Bool = true

    public init(windowVM: ExplorerWindowViewModel, tab: ExplorerTabViewModel, quickAccess: QuickAccessStore) {
        self.windowVM = windowVM
        self.tab = tab
        self.quickAccess = quickAccess
    }

    public var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 2) {
                // 1. "Inicio" (Home)
                sidebarRow(
                    title: "Inicio",
                    isSelected: tab.destination == .home,
                    leadingIcon: {
                        Image(systemName: "house.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(Win11Theme.accentBlue(colorScheme))
                    },
                    trailingIcon: nil
                ) {
                    tab.navigate(to: .home)
                }

                Divider()
                    .padding(.vertical, 6)

                // 2. "Nube" (iCloud Drive, Claro drive, OneDrive, Google Drive, etc.)
                if !windowVM.cloudDrives.isEmpty {
                    DisclosureGroup(isExpanded: $isCloudExpanded) {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(windowVM.cloudDrives) { cloud in
                                WinCloudDriveTreeItemView(
                                    cloud: cloud,
                                    windowVM: windowVM,
                                    tab: tab
                                )
                            }
                        }
                        .padding(.top, 2)
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "icloud.fill")
                                .font(.system(size: 12.5))
                                .foregroundStyle(Color(red: 0.05, green: 0.52, blue: 0.95))
                            Text("Nube")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.primary)
                        }
                        .padding(.vertical, 4)
                    }
                    .padding(.horizontal, 6)

                    Divider()
                        .padding(.vertical, 6)
                }

                // 3. "Acceso rápido" (Quick Access / Pinned Folders)
                DisclosureGroup(isExpanded: $isQuickAccessExpanded) {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(quickAccess.pinnedFolders) { pinned in
                            let dest = NavigationDestination.directory(pinned.url)
                            sidebarRow(
                                title: pinned.title,
                                isSelected: tab.destination == dest,
                                indentation: 10,
                                leadingIcon: {
                                    sidebarFolderIcon(for: pinned.url)
                                },
                                trailingIcon: {
                                    Image(systemName: "pin.fill")
                                        .font(.system(size: 9))
                                        .foregroundStyle(.secondary.opacity(0.75))
                                        .rotationEffect(.degrees(45))
                                }
                            ) {
                                tab.navigate(to: dest)
                            }
                            .contextMenu {
                                Button("Abrir") {
                                    tab.navigate(to: dest)
                                }
                                Button("Abrir en una pestaña nueva") {
                                    windowVM.createNewTab(at: dest, activate: true)
                                }
                                Divider()
                                Button("Desanclar del Acceso rápido") {
                                    quickAccess.unpin(pinned.url)
                                }
                            }
                        }
                    }
                    .padding(.top, 2)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "star.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.yellow)
                        Text("Acceso rápido")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.primary)
                    }
                    .padding(.vertical, 4)
                }
                .padding(.horizontal, 6)

                Divider()
                    .padding(.vertical, 6)

                // 3. "Este equipo" (This PC & Volumes)
                DisclosureGroup(isExpanded: $isThisPCExpanded) {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(windowVM.volumes) { vol in
                            let dest = NavigationDestination.directory(vol.url)
                            sidebarRow(
                                title: vol.displayTitleWithDriveLetter,
                                isSelected: tab.destination == dest,
                                indentation: 10,
                                leadingIcon: {
                                    Image(systemName: vol.isRemovable ? "externaldrive.fill" : "internaldrive.fill")
                                        .font(.system(size: 13))
                                        .foregroundStyle(vol.isRemovable ? Color.orange : Color.secondary)
                                },
                                trailingIcon: nil
                            ) {
                                tab.navigate(to: dest)
                            }
                            .contextMenu {
                                Button("Abrir") {
                                    tab.navigate(to: dest)
                                }
                                Button("Abrir en una pestaña nueva") {
                                    windowVM.createNewTab(at: dest, activate: true)
                                }
                                Divider()
                                Button("Propiedades") {
                                    if let item = FileSystemService.shared.makeFileItem(from: vol.url) {
                                        windowVM.showProperties(for: item)
                                    }
                                }
                            }
                        }

                        // Applications shortcut
                        let appsURL = URL(fileURLWithPath: "/Applications")
                        sidebarRow(
                            title: "Aplicaciones",
                            isSelected: tab.destination == .directory(appsURL),
                            indentation: 10,
                            leadingIcon: {
                                Win11FolderIconView(size: 16, badgeSymbol: "app.badge", badgeColor: .blue)
                            },
                            trailingIcon: nil
                        ) {
                            tab.navigate(to: .directory(appsURL))
                        }

                        // Trash / Recycle Bin shortcut
                        let trashURL = FileSystemService.trashDirectoryURL
                        sidebarRow(
                            title: "Basurero",
                            isSelected: tab.destination == .directory(trashURL),
                            indentation: 10,
                            leadingIcon: {
                                Win11FolderIconView(size: 16, badgeSymbol: "trash.fill", badgeColor: Color(red: 0.45, green: 0.50, blue: 0.58))
                            },
                            trailingIcon: nil
                        ) {
                            tab.navigate(to: .directory(trashURL))
                        }
                        .contextMenu {
                            Button("Abrir Basurero") {
                                tab.navigate(to: .directory(trashURL))
                            }
                            Button("Abrir en una pestaña nueva") {
                                windowVM.createNewTab(at: .directory(trashURL), activate: true)
                            }
                            Divider()
                            Button("Vaciar Basurero...") {
                                FileSystemService.shared.emptyTrash()
                                tab.reload()
                            }
                        }
                    }
                    .padding(.top, 2)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "desktopcomputer")
                            .font(.system(size: 12.5))
                            .foregroundStyle(Win11Theme.accentBlue(colorScheme))
                        Text("Este equipo")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.primary)
                        Spacer()
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        tab.navigate(to: .thisPC)
                    }
                    .padding(.vertical, 4)
                }
                .padding(.horizontal, 6)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 10)
        }
        .frame(width: 225)
        .background(Win11Theme.sidebarBackground(colorScheme))
        .overlay(alignment: .trailing) {
            Divider().opacity(0.5)
        }
    }

    @ViewBuilder
    private func sidebarFolderIcon(for url: URL) -> some View {
        if let item = FileSystemService.shared.makeFileItem(from: url) {
            Win11ItemIconView(item: item, size: 17)
        } else {
            Win11FolderIconView(size: 17)
        }
    }

    private func sidebarRow<Leading: View, Trailing: View>(
        title: String,
        isSelected: Bool,
        indentation: CGFloat = 0,
        @ViewBuilder leadingIcon: () -> Leading,
        @ViewBuilder trailingIcon: () -> Trailing,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 9) {
                if isSelected {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Win11Theme.accentBlue(colorScheme))
                        .frame(width: 3, height: 16)
                } else {
                    Spacer().frame(width: 3)
                }

                leadingIcon()
                    .frame(width: 18, height: 18)

                Text(title)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                    .lineLimit(1)
                    .foregroundStyle(.primary)

                Spacer(minLength: 4)

                trailingIcon()
            }
            .padding(.leading, indentation)
            .padding(.trailing, 8)
            .frame(height: 30)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isSelected ? Win11Theme.selectionFill(colorScheme) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func sidebarRow<Leading: View>(
        title: String,
        isSelected: Bool,
        indentation: CGFloat = 0,
        @ViewBuilder leadingIcon: () -> Leading,
        trailingIcon: EmptyView?,
        action: @escaping () -> Void
    ) -> some View {
        sidebarRow(
            title: title,
            isSelected: isSelected,
            indentation: indentation,
            leadingIcon: leadingIcon,
            trailingIcon: { EmptyView() },
            action: action
        )
    }
}

// MARK: - Expandable Cloud Drive Tree View (iCloud Drive, Claro drive, etc.)
private struct WinCloudDriveTreeItemView: View {
    let cloud: CloudDriveInfo
    let windowVM: ExplorerWindowViewModel
    @ObservedObject var tab: ExplorerTabViewModel

    @Environment(\.colorScheme) private var colorScheme
    @State private var isExpanded: Bool = false
    @State private var subfolders: [FileItem]? = nil
    @State private var isLoading: Bool = false

    private var isCloudSelected: Bool {
        tab.destination == .directory(cloud.url)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            // Root Cloud Drive Row (e.g. iCloud Drive / Claro drive)
            HStack(spacing: 2) {
                // Expand / Collapse Chevron Button
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        isExpanded.toggle()
                    }
                    if isExpanded && subfolders == nil && !isLoading {
                        loadRootSubfolders()
                    }
                } label: {
                    ZStack {
                        if isLoading {
                            ProgressView()
                                .controlSize(.mini)
                                .frame(width: 14, height: 14)
                        } else {
                            Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                                .font(.system(size: 8, weight: .semibold))
                                .foregroundStyle(Color.secondary.opacity(0.85))
                                .frame(width: 14, height: 14)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                // Drive Button
                Button {
                    tab.navigate(to: .directory(cloud.url))
                } label: {
                    HStack(spacing: 8) {
                        if isCloudSelected {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Win11Theme.accentBlue(colorScheme))
                                .frame(width: 3, height: 16)
                        } else {
                            Spacer().frame(width: 3)
                        }

                        Win11FolderIconView(
                            size: 17,
                            badgeSymbol: cloud.sfSymbol,
                            badgeColor: cloud.isClaroDrive
                                ? Color(red: 0.88, green: 0.14, blue: 0.14)
                                : Color(red: 0.05, green: 0.52, blue: 0.95)
                        )
                        .frame(width: 18, height: 18)

                        Text(cloud.name)
                            .font(.system(size: 12, weight: isCloudSelected ? .semibold : .regular))
                            .lineLimit(1)
                            .foregroundStyle(.primary)

                        Spacer()
                    }
                    .frame(height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(isCloudSelected ? Win11Theme.selectionFill(colorScheme) : Color.clear)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.leading, 6)
            .contextMenu {
                Button("Abrir \(cloud.name)") {
                    tab.navigate(to: .directory(cloud.url))
                }
                Button("Abrir en una pestaña nueva") {
                    windowVM.createNewTab(at: .directory(cloud.url), activate: true)
                }
                Divider()
                Button("Mostrar en Finder") {
                    FileSystemService.shared.revealInFinder(cloud.url)
                }
            }

            // Expanded Subfolders List
            if isExpanded {
                VStack(alignment: .leading, spacing: 1) {
                    if let folders = subfolders {
                        if folders.isEmpty {
                            Text("Sin carpetas")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .padding(.leading, 32)
                                .padding(.vertical, 3)
                        } else {
                            ForEach(folders) { folder in
                                WinSidebarSubfolderNodeView(
                                    folder: folder,
                                    level: 1,
                                    windowVM: windowVM,
                                    tab: tab
                                )
                            }
                        }
                    } else if isLoading {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.mini)
                            Text("Cargando carpetas...")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.leading, 32)
                        .padding(.vertical, 3)
                    }
                }
                .transition(.opacity)
            }
        }
        .onAppear {
            if let current = tab.currentDirectoryURL, current.path.hasPrefix(cloud.url.path) {
                isExpanded = true
                if subfolders == nil && !isLoading {
                    loadRootSubfolders()
                }
            }
        }
    }

    private func loadRootSubfolders() {
        isLoading = true
        let targetURL = cloud.url
        Task {
            let folders = await FileSystemService.shared.firstLevelSubfolders(at: targetURL)
            await MainActor.run {
                self.subfolders = folders
                self.isLoading = false
            }
        }
    }
}

// MARK: - Recursive Subfolder Node View
private struct WinSidebarSubfolderNodeView: View {
    let folder: FileItem
    let level: Int
    let windowVM: ExplorerWindowViewModel
    @ObservedObject var tab: ExplorerTabViewModel

    @Environment(\.colorScheme) private var colorScheme
    @State private var isExpanded: Bool = false
    @State private var children: [FileItem]? = nil
    @State private var isLoading: Bool = false

    private var isSelected: Bool {
        tab.destination == .directory(folder.url)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 2) {
                // Chevron for subfolder
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        isExpanded.toggle()
                    }
                    if isExpanded && children == nil && !isLoading {
                        loadChildren()
                    }
                } label: {
                    ZStack {
                        if isLoading {
                            ProgressView().controlSize(.mini).frame(width: 12, height: 12)
                        } else {
                            Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                                .font(.system(size: 7.5, weight: .semibold))
                                .foregroundStyle(Color.secondary.opacity(0.75))
                                .frame(width: 12, height: 12)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                // Subfolder Button
                Button {
                    tab.navigate(to: .directory(folder.url))
                } label: {
                    HStack(spacing: 7) {
                        if isSelected {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Win11Theme.accentBlue(colorScheme))
                                .frame(width: 3, height: 14)
                        } else {
                            Spacer().frame(width: 3)
                        }

                        Win11FolderIconView(size: 15, badgeSymbol: nil, badgeColor: Win11Theme.accentBlue(colorScheme))
                            .frame(width: 16, height: 16)

                        Text(folder.displayName(showExtensions: false))
                            .font(.system(size: 11.5, weight: isSelected ? .semibold : .regular))
                            .lineLimit(1)
                            .foregroundStyle(.primary)

                        Spacer()
                    }
                    .frame(height: 26)
                    .background(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(isSelected ? Win11Theme.selectionFill(colorScheme) : Color.clear)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.leading, CGFloat(8 + level * 14))
            .contextMenu {
                Button("Abrir") {
                    tab.navigate(to: .directory(folder.url))
                }
                Button("Abrir en una pestaña nueva") {
                    windowVM.createNewTab(at: .directory(folder.url), activate: true)
                }
                let isPinned = windowVM.quickAccess.isPinned(folder.url)
                Button(isPinned ? "Desanclar del Acceso rápido" : "Anclar al Acceso rápido") {
                    windowVM.quickAccess.togglePin(for: folder.url)
                }
                Divider()
                Button("Mostrar en Finder") {
                    FileSystemService.shared.revealInFinder(folder.url)
                }
            }

            // Level 2+ Children
            if isExpanded, let childItems = children {
                ForEach(childItems) { child in
                    WinSidebarSubfolderNodeView(
                        folder: child,
                        level: level + 1,
                        windowVM: windowVM,
                        tab: tab
                    )
                }
            }
        }
        .onAppear {
            if let current = tab.currentDirectoryURL, current.path.hasPrefix(folder.url.path) && current.path != folder.url.path {
                isExpanded = true
                if children == nil && !isLoading {
                    loadChildren()
                }
            }
        }
    }

    private func loadChildren() {
        isLoading = true
        let url = folder.url
        Task {
            let items = await FileSystemService.shared.firstLevelSubfolders(at: url)
            await MainActor.run {
                self.children = items
                self.isLoading = false
            }
        }
    }
}
