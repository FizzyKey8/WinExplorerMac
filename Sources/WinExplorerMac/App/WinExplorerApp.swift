import SwiftUI
import AppKit

@main
public struct WinExplorerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    public init() {
        // Guarantee macOS treats this as a regular desktop GUI application with a Dock icon
        NSApplication.shared.setActivationPolicy(.regular)
    }

    public var body: some Scene {
        WindowGroup("Explorador de archivos") {
            MainExplorerWindowView()
                .background(WindowAccessor { window in
                    configureWindow(window)
                })
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1180, height: 740)
        .commands {
            CommandGroup(replacing: .newItem) {
                // Handled directly inside MainExplorerWindowView shortcuts
            }
        }
    }

    private func configureWindow(_ window: NSWindow) {
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.styleMask.insert(.fullSizeContentView)
        window.isMovableByWindowBackground = false
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}

public final class AppDelegate: NSObject, NSApplicationDelegate {
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
            for window in NSApplication.shared.windows {
                window.titleVisibility = .hidden
                window.titlebarAppearsTransparent = true
                window.styleMask.insert(.fullSizeContentView)
                window.isMovableByWindowBackground = false
                window.makeKeyAndOrderFront(nil)
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

    public func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            for window in sender.windows {
                window.makeKeyAndOrderFront(nil)
            }
        }
        return true
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
}
