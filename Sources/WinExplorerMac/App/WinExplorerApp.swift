import SwiftUI
import AppKit

@main
public struct WinExplorerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.openWindow) private var openWindow
    @ObservedObject private var themeManager = ThemeManager.shared

    public init() {
        // Guarantee macOS treats this as a regular desktop GUI application with a Dock icon
        NSApplication.shared.setActivationPolicy(.regular)
        // Prevent macOS from showing the "se forzó su salida mientras volvía a abrir las ventanas" prompt
        UserDefaults.standard.set(true, forKey: "ApplePersistenceIgnoreState")
        UserDefaults.standard.set(false, forKey: "NSQuitAlwaysKeepsWindows")
    }

    public var body: some Scene {
        WindowGroup("Explorador de archivos", id: "main-explorer") {
            MainExplorerWindowView()
                .background(WindowAccessor { window in
                    configureWindowIfNeeded(window)
                })
                .onReceive(NotificationCenter.default.publisher(for: .win11ReopenMainWindow)) { _ in
                    openWindow(id: "main-explorer")
                }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1180, height: 740)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Buscar actualizaciones...") {
                    Task { @MainActor in
                        UpdateService.shared.openUpdateModalAndCheck()
                    }
                }
                .keyboardShortcut("u", modifiers: [.command])
            }
            CommandGroup(replacing: .newItem) {
                Button("Nueva ventana del Explorador") {
                    AppDelegate.showOrCreateMainWindow(using: openWindow)
                }
                .keyboardShortcut("n", modifiers: [.command])
            }
            CommandMenu("Tema") {
                ForEach(ExplorerTheme.allCases) { theme in
                    Toggle(theme.displayName, isOn: Binding(
                        get: { themeManager.currentTheme == theme },
                        set: { _ in
                            withAnimation(.easeInOut(duration: 0.18)) {
                                themeManager.currentTheme = theme
                            }
                        }
                    ))
                }
            }
        }
    }

    private func configureWindowIfNeeded(_ window: NSWindow) {
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.styleMask.insert(.fullSizeContentView)
        window.isMovableByWindowBackground = false
        switch ThemeManager.shared.currentTheme {
        case .liquidGlass:
            window.isOpaque = false
            window.backgroundColor = .clear
        case .win, .minimalist:
            window.isOpaque = true
            window.backgroundColor = .windowBackgroundColor
        }
        // Keep the window instance alive when closed with the red 'X' button
        // so the app stays in the Dock and reopens the window on Dock click.
        window.isReleasedWhenClosed = false
        AppDelegate.mainExplorerWindow = window

        if !AppDelegate.configuredWindows.contains(ObjectIdentifier(window)) {
            AppDelegate.configuredWindows.insert(ObjectIdentifier(window))
            window.center()
            window.makeKeyAndOrderFront(nil)
            NSApplication.shared.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}

public final class AppDelegate: NSObject, NSApplicationDelegate {
    public static var configuredWindows = Set<ObjectIdentifier>()
    public static var mainExplorerWindow: NSWindow?
    private var keyMonitor: Any?

    public override init() {
        super.init()
        NSApplication.shared.setActivationPolicy(.regular)
    }

    public func applicationWillFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.regular)
    }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.regular)
        NSWindow.allowsAutomaticWindowTabbing = false

        DispatchQueue.main.async {
            NSApplication.shared.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
            var visibleCount = 0
            for window in NSApplication.shared.windows {
                if window.className != "NSStatusBarWindow" {
                    window.titleVisibility = .hidden
                    window.titlebarAppearsTransparent = true
                    window.styleMask.insert(.fullSizeContentView)
                    window.isMovableByWindowBackground = false
                    window.isReleasedWhenClosed = false
                    if Self.mainExplorerWindow == nil {
                        Self.mainExplorerWindow = window
                    }
                    window.makeKeyAndOrderFront(nil)
                    visibleCount += 1
                }
            }
            if visibleCount == 0 {
                NotificationCenter.default.post(name: .win11ReopenMainWindow, object: nil)
            }
        }

        // Listen for F2 key (keyCode 120) to trigger inline rename just like Windows 11
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 120 { // F2 key on macOS
                NotificationCenter.default.post(name: .win11TriggerRenameShortcut, object: nil)
            }
            return event
        }
    }

    // Keep the app running in the Dock when the window is closed with the red 'X' button
    public func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    // Reopen the window immediately when clicking the Dock icon
    public func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if let window = Self.mainExplorerWindow {
            if window.isMiniaturized {
                window.deminiaturize(nil)
            }
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return true
        }

        for window in sender.windows where Self.configuredWindows.contains(ObjectIdentifier(window)) {
            if window.isMiniaturized {
                window.deminiaturize(nil)
            }
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return true
        }

        NotificationCenter.default.post(name: .win11ReopenMainWindow, object: nil)
        return true
    }

    @MainActor
    public static func showOrCreateMainWindow(using openWindow: OpenWindowAction) {
        if let window = mainExplorerWindow {
            if window.isMiniaturized {
                window.deminiaturize(nil)
            }
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        } else {
            openWindow(id: "main-explorer")
        }
    }
}

public struct WindowAccessor: NSViewRepresentable {
    public let callback: (NSWindow) -> Void

    public init(callback: @escaping (NSWindow) -> Void) {
        self.callback = callback
    }

    public func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window {
                callback(window)
            }
        }
        return view
    }

    public func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            if let window = nsView.window {
                callback(window)
            }
        }
    }
}

public extension Notification.Name {
    static let win11TriggerRenameShortcut = Notification.Name("win11TriggerRenameShortcut")
    static let win11ReopenMainWindow = Notification.Name("win11ReopenMainWindow")
}
