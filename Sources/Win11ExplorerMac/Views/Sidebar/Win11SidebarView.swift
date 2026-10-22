import SwiftUI

public struct Win11SidebarView: View {
    @ObservedObject var windowVM: ExplorerWindowViewModel
    @ObservedObject var tab: ExplorerTabViewModel
    @ObservedObject var quickAccess: QuickAccessStore
    @Environment(\.colorScheme) private var colorScheme

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

                // 2. "Acceso rápido" (Quick Access / Pinned Folders)
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
