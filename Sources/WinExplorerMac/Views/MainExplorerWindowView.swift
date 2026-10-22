import SwiftUI
import AppKit

public struct MainExplorerWindowView: View {
    @StateObject private var windowVM = ExplorerWindowViewModel()
    @Environment(\.colorScheme) private var colorScheme

    public init() {}

    public var body: some View {
        let currentTab = windowVM.activeTab

        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                VStack(spacing: 0) {
                    // 1. Windows 11 Titlebar with Integrated Tabs
                    Win11TabBarView(windowVM: windowVM)

                    // 2. Windows 11 Address Bar + Breadcrumbs + Search Box
                    Win11AddressBarView(windowVM: windowVM, tab: currentTab)

                    // 3. Windows 11 Fluent Command Bar (+ Nuevo, Cut, Copy, Paste, Rename, Share, Delete, Sort, View)
                    Win11CommandBarView(
                        windowVM: windowVM,
                        tab: currentTab,
                        clipboard: windowVM.clipboard
                    )

                    // 4. Main Split Area: Left Navigation Sidebar | Center Content | Right Details/Preview Pane
                    HStack(spacing: 0) {
                        if windowVM.isSidebarVisible {
                            Win11SidebarView(
                                windowVM: windowVM,
                                tab: currentTab,
                                quickAccess: windowVM.quickAccess
                            )
                        }

                        // Active Tab Content
                        ActiveTabContentHostView(
                            windowVM: windowVM,
                            tab: currentTab
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                        if windowVM.sidePaneMode != .none {
                            Win11SidePaneView(
                                windowVM: windowVM,
                                tab: currentTab,
                                mode: windowVM.sidePaneMode
                            )
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    // 5. Windows 11 Bottom Status Bar
                    Win11StatusBarView(tab: currentTab)
                }

                // 6. Floating Windows 11 Right-Click Context Menu Overlay
                if let contextRequest = windowVM.activeContextMenu {
                    Win11ContextMenuOverlay(
                        windowVM: windowVM,
                        tab: currentTab,
                        request: contextRequest,
                        windowSize: geo.size
                    )
                    .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .topLeading)))
                }

                // Hidden Keyboard Shortcut Handlers (Cmd+T, Cmd+W, Cmd+X, Cmd+C, Cmd+V, F2, Delete, etc.)
                keyboardShortcutsResponder(for: currentTab)
            }
        }
        .frame(minWidth: 960, minHeight: 600)
        .background(Win11Theme.windowMicaBackground(colorScheme))
        .ignoresSafeArea(.container, edges: .top)
        .onReceive(NotificationCenter.default.publisher(for: .win11TriggerRenameShortcut)) { _ in
            if currentTab.renamingURL == nil {
                currentTab.beginRename()
            }
        }
        .sheet(item: $windowVM.propertiesTargetItem) { targetItem in
            Win11PropertiesModalView(item: targetItem) {
                windowVM.propertiesTargetItem = nil
            }
        }
        .sheet(isPresented: Binding(
            get: { windowVM.extractZipSourceURL != nil },
            set: { if !$0 { windowVM.extractZipSourceURL = nil } }
        )) {
            if let zipURL = windowVM.extractZipSourceURL {
                Win11ExtractZipModalView(
                    zipURL: zipURL,
                    onExtracted: { extractedFolder, shouldOpen in
                        windowVM.extractZipSourceURL = nil
                        currentTab.reload()
                        if shouldOpen {
                            currentTab.navigate(to: .directory(extractedFolder))
                        }
                    },
                    onCancel: {
                        windowVM.extractZipSourceURL = nil
                    }
                )
            }
        }
        .alert(
            "Explorador de archivos",
            isPresented: Binding(
                get: { currentTab.errorMessage != nil },
                set: { if !$0 { currentTab.errorMessage = nil } }
            ),
            actions: {
                Button("Aceptar", role: .cancel) {
                    currentTab.errorMessage = nil
                }
            },
            message: {
                Text(currentTab.errorMessage ?? "")
            }
        )
    }

    @ViewBuilder
    private func keyboardShortcutsResponder(for tab: ExplorerTabViewModel) -> some View {
        Group {
            // New Tab: Cmd + T
            Button("") {
                windowVM.createNewTab(at: .home, activate: true)
            }
            .keyboardShortcut("t", modifiers: [.command])

            // Close Tab: Cmd + W
            Button("") {
                windowVM.closeTab(id: tab.id)
            }
            .keyboardShortcut("w", modifiers: [.command])

            // Cut: Cmd + X
            Button("") {
                windowVM.cutSelection()
            }
            .keyboardShortcut("x", modifiers: [.command])

            // Copy: Cmd + C
            Button("") {
                windowVM.copySelection()
            }
            .keyboardShortcut("c", modifiers: [.command])

            // Paste: Cmd + V
            Button("") {
                windowVM.pasteIntoCurrentDirectory()
            }
            .keyboardShortcut("v", modifiers: [.command])

            // Copy as Path: Cmd + Shift + C
            Button("") {
                if !tab.selectedURLs.isEmpty {
                    FileSystemService.shared.copyPathToPasteboard(Array(tab.selectedURLs), quoted: true)
                    tab.statusMessage = "Ruta copiada al portapapeles"
                }
            }
            .keyboardShortcut("c", modifiers: [.command, .shift])

            // New Folder: Cmd + Shift + N
            Button("") {
                windowVM.createNewItem(.folder)
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])

            // Move to Trash: Cmd + Delete (Backspace)
            Button("") {
                windowVM.moveSelectedToTrash()
            }
            .keyboardShortcut(.delete, modifiers: [.command])

            // Refresh: Cmd + R
            Button("") {
                tab.reload()
                windowVM.refreshVolumes()
            }
            .keyboardShortcut("r", modifiers: [.command])

            // Focus Address Bar: Cmd + L
            Button("") {
                windowVM.isEditingAddressBar = true
            }
            .keyboardShortcut("l", modifiers: [.command])

            // Go Up: Cmd + Up Arrow
            Button("") {
                tab.goUp()
            }
            .keyboardShortcut(.upArrow, modifiers: [.command])

            // Go Back: Cmd + [
            Button("") {
                tab.goBack()
            }
            .keyboardShortcut("[", modifiers: [.command])

            // Go Forward: Cmd + ]
            Button("") {
                tab.goForward()
            }
            .keyboardShortcut("]", modifiers: [.command])

            // Select All: Cmd + A
            Button("") {
                tab.selectAll()
            }
            .keyboardShortcut("a", modifiers: [.command])

            // Properties: Cmd + I
            Button("") {
                windowVM.showProperties(for: nil)
            }
            .keyboardShortcut("i", modifiers: [.command])
        }
        .opacity(0)
        .frame(width: 0, height: 0)
        .allowsHitTesting(false)
    }
}

private struct ActiveTabContentHostView: View {
    @ObservedObject var windowVM: ExplorerWindowViewModel
    @ObservedObject var tab: ExplorerTabViewModel

    var body: some View {
        Group {
            switch tab.destination {
            case .home:
                Win11HomeView(
                    windowVM: windowVM,
                    tab: tab,
                    quickAccess: windowVM.quickAccess
                )
            case .thisPC:
                Win11ThisPCView(
                    windowVM: windowVM,
                    tab: tab
                )
            case .directory:
                Win11FolderContentView(
                    windowVM: windowVM,
                    tab: tab,
                    clipboard: windowVM.clipboard
                )
            }
        }
    }
}
