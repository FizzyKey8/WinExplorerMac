import SwiftUI

public struct Win11TabBarView: View {
    @ObservedObject var windowVM: ExplorerWindowViewModel
    @Environment(\.colorScheme) private var colorScheme
    @State private var hoveredTabId: UUID? = nil
    @State private var draggedTabId: UUID? = nil

    public init(windowVM: ExplorerWindowViewModel) {
        self.windowVM = windowVM
    }

    public var body: some View {
        HStack(spacing: 0) {
            // Reserve space for macOS traffic light buttons
            Spacer()
                .frame(width: 76)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .bottom, spacing: 4) {
                    ForEach(windowVM.tabs) { tab in
                        Win11SingleTabButton(
                            tab: tab,
                            isActive: windowVM.activeTabId == tab.id,
                            isHovered: hoveredTabId == tab.id,
                            onSelect: {
                                windowVM.selectTab(id: tab.id)
                            },
                            onClose: {
                                windowVM.closeTab(id: tab.id)
                            },
                            onDuplicate: {
                                windowVM.duplicateTab(tab)
                            },
                            onCloseOthers: {
                                windowVM.closeOtherTabs(keepingId: tab.id)
                            }
                        )
                        .onHover { hovering in
                            hoveredTabId = hovering ? tab.id : nil
                        }
                        .onDrag {
                            draggedTabId = tab.id
                            return NSItemProvider(object: tab.id.uuidString as NSString)
                        }
                        .onDrop(of: [.text], delegate: TabReorderDropDelegate(
                            targetTab: tab,
                            tabs: $windowVM.tabs,
                            draggedTabId: $draggedTabId
                        ))
                    }

                    // Windows 11 "+" New Tab Button
                    Button {
                        windowVM.createNewTab(at: .home, activate: true)
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.primary.opacity(0.85))
                            .frame(width: 28, height: 26)
                            .background(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(Color.primary.opacity(0.06))
                            )
                    }
                    .buttonStyle(.plain)
                    .padding(.bottom, 4)
                    .help("Crear nueva pestaña (Cmd+T)")
                }
                .padding(.top, 6)
                .padding(.horizontal, 4)
            }

            Spacer(minLength: 24)
        }
        .frame(height: 38)
        .background(Win11Theme.tabBarBackground(colorScheme))
    }
}

private struct Win11SingleTabButton: View {
    @ObservedObject var tab: ExplorerTabViewModel
    @ObservedObject private var themeManager = ThemeManager.shared
    let isActive: Bool
    let isHovered: Bool
    let onSelect: () -> Void
    let onClose: () -> Void
    let onDuplicate: () -> Void
    let onCloseOthers: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 8) {
            tabIcon
                .frame(width: 16, height: 16)

            Text(tab.title)
                .font(.system(size: 12, weight: isActive ? .semibold : .regular))
                .lineLimit(1)
                .frame(maxWidth: 155, alignment: .leading)

            Spacer(minLength: 2)

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 9.5, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 18, height: 18)
                    .background(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(Color.primary.opacity(isHovered ? 0.08 : 0.0))
                    )
            }
            .buttonStyle(.plain)
            .help("Cerrar pestaña (Cmd+W)")
        }
        .padding(.horizontal, 12)
        .frame(width: 205, height: 32)
        .background(
            UnevenRoundedRectangle(
                topLeadingRadius: 8,
                bottomLeadingRadius: isActive ? 0 : 6,
                bottomTrailingRadius: isActive ? 0 : 6,
                topTrailingRadius: 8
            )
            .fill(tabBackgroundColor)
        )
        .overlay(
            UnevenRoundedRectangle(
                topLeadingRadius: 8,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 0,
                topTrailingRadius: 8
            )
            .stroke(Win11Theme.subtleBorder(colorScheme), lineWidth: isActive ? 1 : 0)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            onSelect()
        }
        .contextMenu {
            Button("Nueva pestaña") {
                onDuplicate()
            }
            Button("Duplicar pestaña") {
                onDuplicate()
            }
            Divider()
            Button("Cerrar pestaña") {
                onClose()
            }
            Button("Cerrar otras pestañas") {
                onCloseOthers()
            }
        }
    }

    private var tabBackgroundColor: Color {
        if isActive {
            return Win11Theme.activeTabBackground(colorScheme)
        } else if isHovered {
            return Win11Theme.hoverFill(colorScheme)
        } else {
            return Color.clear
        }
    }

    @ViewBuilder
    private var tabIcon: some View {
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
            Win11FolderIconView(size: 16)
        }
    }
}

private struct TabReorderDropDelegate: DropDelegate {
    let targetTab: ExplorerTabViewModel
    @Binding var tabs: [ExplorerTabViewModel]
    @Binding var draggedTabId: UUID?

    func dropEntered(info: DropInfo) {
        guard let draggedId = draggedTabId,
              draggedId != targetTab.id,
              let fromIndex = tabs.firstIndex(where: { $0.id == draggedId }),
              let toIndex = tabs.firstIndex(where: { $0.id == targetTab.id }) else {
            return
        }
        withAnimation(.easeInOut(duration: 0.14)) {
            tabs.move(fromOffsets: IndexSet(integer: fromIndex), toOffset: toIndex > fromIndex ? toIndex + 1 : toIndex)
        }
    }

    func performDrop(info: DropInfo) -> Bool {
        draggedTabId = nil
        return true
    }
}
