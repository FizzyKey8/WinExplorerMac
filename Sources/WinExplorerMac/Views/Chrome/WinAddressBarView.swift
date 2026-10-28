import SwiftUI

public struct Win11AddressBarView: View {
    @ObservedObject var windowVM: ExplorerWindowViewModel
    @ObservedObject var tab: ExplorerTabViewModel
    @Environment(\.colorScheme) private var colorScheme

    @State private var addressText: String = ""
    @FocusState private var addressFieldFocused: Bool

    public init(windowVM: ExplorerWindowViewModel, tab: ExplorerTabViewModel) {
        self.windowVM = windowVM
        self.tab = tab
    }

    public var body: some View {
        HStack(spacing: 8) {
            // Navigation Buttons: Back, Forward, History dropdown, Up, Refresh
            HStack(spacing: 2) {
                navIconButton(
                    symbol: "arrow.left",
                    enabled: tab.canGoBack,
                    tooltip: "Atrás (Alt+Flecha izquierda)"
                ) {
                    tab.goBack()
                }

                navIconButton(
                    symbol: "arrow.right",
                    enabled: tab.canGoForward,
                    tooltip: "Adelante (Alt+Flecha derecha)"
                ) {
                    tab.goForward()
                }

                // Recent locations dropdown
                Menu {
                    if tab.backStack.isEmpty && tab.forwardStack.isEmpty {
                        Text("Sin historial reciente")
                    } else {
                        ForEach(Array(tab.backStack.suffix(8).reversed().enumerated()), id: \.offset) { _, dest in
                            Button(dest.displayTitle) {
                                tab.navigate(to: dest)
                            }
                        }
                    }
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8.5, weight: .semibold))
                        .foregroundStyle((tab.backStack.isEmpty && tab.forwardStack.isEmpty) ? Color.secondary.opacity(0.4) : Color.primary)
                        .frame(width: 16, height: 28)
                        .contentShape(Rectangle())
                }
                .menuIndicator(.hidden)
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("Ubicaciones recientes")

                navIconButton(
                    symbol: "arrow.up",
                    enabled: tab.canGoUp,
                    tooltip: "Subir un nivel (Cmd+Flecha arriba)"
                ) {
                    tab.goUp()
                }

                navIconButton(
                    symbol: "arrow.clockwise",
                    enabled: true,
                    tooltip: "Actualizar (F5 / Cmd+R)"
                ) {
                    tab.reload()
                    windowVM.refreshVolumes()
                }
            }

            // Address / Breadcrumb Bar
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Win11Theme.addressBarBackground(colorScheme))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(
                                windowVM.isEditingAddressBar
                                    ? Win11Theme.accentBlue(colorScheme)
                                    : Win11Theme.subtleBorder(colorScheme),
                                lineWidth: windowVM.isEditingAddressBar ? 1.5 : 1
                            )
                    )

                if windowVM.isEditingAddressBar {
                    HStack(spacing: 6) {
                        Image(systemName: "folder")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                        TextField("Escribe una ruta (ej. ~/Desktop o /Applications)", text: $addressText)
                            .textFieldStyle(.plain)
                            .font(.system(size: 12.5))
                            .focused($addressFieldFocused)
                            .onSubmit {
                                windowVM.isEditingAddressBar = false
                                tab.navigateToPathString(addressText)
                            }
                            .onExitCommand {
                                windowVM.isEditingAddressBar = false
                            }

                        Button {
                            windowVM.isEditingAddressBar = false
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 10)
                } else {
                    HStack(spacing: 2) {
                        destinationSmallIcon
                            .padding(.leading, 8)
                            .padding(.trailing, 4)

                        ScrollViewReader { scrollProxy in
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 2) {
                                    ForEach(Array(tab.breadcrumbSegments.enumerated()), id: \.offset) { idx, segment in
                                        BreadcrumbSegmentButton(title: segment.title) {
                                            tab.navigate(to: segment.destination)
                                        }
                                        .id("seg-\(idx)")

                                        BreadcrumbChevronMenu(destination: segment.destination, tab: tab)
                                            .id("chev-\(idx)")
                                    }
                                }
                                .padding(.trailing, 6)
                            }
                            .onAppear {
                                if let lastIdx = tab.breadcrumbSegments.indices.last {
                                    scrollProxy.scrollTo("chev-\(lastIdx)", anchor: .trailing)
                                }
                            }
                            .onChange(of: tab.destination) {
                                DispatchQueue.main.async {
                                    if let lastIdx = tab.breadcrumbSegments.indices.last {
                                        withAnimation(.easeInOut(duration: 0.15)) {
                                            scrollProxy.scrollTo("chev-\(lastIdx)", anchor: .trailing)
                                        }
                                    }
                                }
                            }
                        }
                        .layoutPriority(1)

                        // Clicking empty area in breadcrumb bar activates path editing like Windows 11
                        Color.clear
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                addressText = tab.destination.addressBarString
                                windowVM.isEditingAddressBar = true
                                addressFieldFocused = true
                            }

                        if let currentURL = tab.currentDirectoryURL {
                            Button {
                                FileSystemService.shared.copyPathToPasteboard([currentURL], quoted: false)
                                tab.statusMessage = "Ruta copiada al portapapeles"
                            } label: {
                                Image(systemName: "doc.on.doc")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 8)
                            }
                            .buttonStyle(.plain)
                            .help("Copiar ruta actual")
                        }
                    }
                }
            }
            .frame(height: 32)

            // Search Box (Right side of Address Bar)
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)

                TextField("Buscar en \(tab.title)", text: $tab.searchQuery)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))

                if !tab.searchQuery.isEmpty {
                    Button {
                        tab.searchQuery = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .frame(width: 230, height: 32)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Win11Theme.addressBarBackground(colorScheme))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(Win11Theme.subtleBorder(colorScheme), lineWidth: 1)
                    )
            )
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Win11Theme.activeTabBackground(colorScheme))
    }

    @ViewBuilder
    private var destinationSmallIcon: some View {
        switch tab.destination {
        case .home:
            Image(systemName: "house.fill")
                .font(.system(size: 12))
                .foregroundStyle(Win11Theme.accentBlue(colorScheme))
        case .thisPC:
            Image(systemName: "desktopcomputer")
                .font(.system(size: 12))
                .foregroundStyle(Win11Theme.accentBlue(colorScheme))
        case .directory:
            Win11FolderIconView(size: 15)
        }
    }

    private func navIconButton(symbol: String, enabled: Bool, tooltip: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(enabled ? Color.primary : Color.secondary.opacity(0.4))
                .frame(width: 28, height: 28)
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

private struct BreadcrumbSegmentButton: View {
    let title: String
    let action: () -> Void
    @State private var isHovered: Bool = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(isHovered ? Color.primary.opacity(0.06) : Color.primary.opacity(0.001))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

private struct BreadcrumbChevronMenu: View {
    let destination: NavigationDestination
    @ObservedObject var tab: ExplorerTabViewModel
    @State private var isHovered: Bool = false

    var body: some View {
        Menu {
            let items = fetchSubfolders(for: destination)
            if items.isEmpty {
                Text("Sin subcarpetas")
            } else {
                ForEach(items, id: \.destination) { sub in
                    Button {
                        tab.navigate(to: sub.destination)
                    } label: {
                        Label(sub.title, systemImage: "folder")
                    }
                }
            }
        } label: {
            Image(systemName: "chevron.right")
                .font(.system(size: 8.5, weight: .semibold))
                .foregroundStyle(isHovered ? Color.primary : Color.secondary.opacity(0.75))
                .frame(width: 14, height: 22)
                .background(
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(isHovered ? Color.primary.opacity(0.08) : Color.clear)
                )
                .contentShape(Rectangle())
        }
        .menuIndicator(.hidden)
        .menuStyle(.borderlessButton)
        .fixedSize()
        .onHover { isHovered = $0 }
        .help("Mostrar subcarpetas")
    }

    private func fetchSubfolders(for dest: NavigationDestination) -> [(title: String, destination: NavigationDestination)] {
        switch dest {
        case .home:
            return QuickAccessStore.shared.pinnedFolders.map {
                ($0.title, .directory($0.url))
            }

        case .thisPC:
            var result: [(title: String, destination: NavigationDestination)] = []
            let home = FileManager.default.homeDirectoryForCurrentUser.cleanFileURL
            let standardLibs: [(String, String)] = [
                ("Desktop", "Escritorio"),
                ("Downloads", "Descargas"),
                ("Documents", "Documentos"),
                ("Pictures", "Imágenes"),
                ("Music", "Música"),
                ("Movies", "Videos"),
                (".Trash", "Papelera")
            ]
            for (folder, localized) in standardLibs {
                let url = home.appendingPathComponent(folder, isDirectory: true).cleanFileURL
                if FileManager.default.fileExists(atPath: url.path) || folder == ".Trash" {
                    result.append((localized, .directory(url)))
                }
            }
            for vol in FileSystemService.shared.mountedVolumes() {
                result.append((vol.name, .directory(vol.url)))
            }
            for cloud in FileSystemService.shared.cloudDrives() {
                result.append((cloud.name, .directory(cloud.url)))
            }
            return result

        case .directory(let url):
            let stdURL = url.cleanFileURL
            guard let entries = try? FileManager.default.contentsOfDirectory(
                at: stdURL,
                includingPropertiesForKeys: [.isDirectoryKey, .isPackageKey, .isHiddenKey],
                options: [.skipsHiddenFiles]
            ) else { return [] }

            var folders: [(title: String, destination: NavigationDestination)] = []
            for itemURL in entries {
                let stdItem = itemURL.cleanFileURL
                guard let vals = try? stdItem.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey, .isHiddenKey]) else {
                    continue
                }
                if vals.isHidden == true { continue }
                if vals.isDirectory == true && vals.isPackage != true {
                    let name = NavigationDestination.localizedFolderName(for: stdItem)
                    folders.append((name, .directory(stdItem)))
                }
            }
            folders.sort { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
            return folders
        }
    }
}
