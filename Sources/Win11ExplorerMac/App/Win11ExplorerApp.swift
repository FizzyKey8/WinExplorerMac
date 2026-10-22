import SwiftUI
import AppKit

@main
public struct Win11ExplorerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    public init() {}

    public var body: some Scene {
        WindowGroup("Explorador de archivos") {
            MainExplorerWindowView()
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1180, height: 740)
        .commands {
            CommandGroup(replacing: .newItem) {
                // Handled directly inside MainExplorerWindowView shortcuts
            }
        }
    }
}

public final class AppDelegate: NSObject, NSApplicationDelegate {
    private var keyMonitor: Any?

    public func applicationDidFinishLaunching(_ notification: Notification) {
        NSWindow.allowsAutomaticWindowTabbing = false

        // Configure initial window appearance for integrated Windows 11 tab bar
        for window in NSApplication.shared.windows {
            configureWindow(window)
        }

        // Listen for F2 key (keyCode 120) to trigger inline rename just like Windows 11
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 120 { // F2 key on macOS
                NotificationCenter.default.post(name: .win11TriggerRenameShortcut, object: nil)
            }
            return event
        }
    }

    private func configureWindow(_ window: NSWindow) {
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.styleMask.insert(.fullSizeContentView)
        window.isMovableByWindowBackground = false
    }
}

public extension Notification.Name {
    static let win11TriggerRenameShortcut = Notification.Name("win11TriggerRenameShortcut")
}
