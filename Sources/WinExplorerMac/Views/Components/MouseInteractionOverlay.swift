import SwiftUI
import AppKit

/// AppKit bridge that captures left click (with modifier flags), double click, and right click (with window coordinates)
/// so we can render the authentic Windows 11 floating acrylic right-click menu.
public struct Win11MouseHandlerView: NSViewRepresentable {
    public var onSingleClick: ((NSEvent.ModifierFlags) -> Void)?
    public var onDoubleClick: (() -> Void)?
    public var onRightClick: ((CGPoint) -> Void)?

    public init(
        onSingleClick: ((NSEvent.ModifierFlags) -> Void)? = nil,
        onDoubleClick: (() -> Void)? = nil,
        onRightClick: ((CGPoint) -> Void)? = nil
    ) {
        self.onSingleClick = onSingleClick
        self.onDoubleClick = onDoubleClick
        self.onRightClick = onRightClick
    }

    public func makeNSView(context: Context) -> InteractiveNSView {
        let view = InteractiveNSView()
        view.onSingleClick = onSingleClick
        view.onDoubleClick = onDoubleClick
        view.onRightClick = onRightClick
        return view
    }

    public func updateNSView(_ nsView: InteractiveNSView, context: Context) {
        nsView.onSingleClick = onSingleClick
        nsView.onDoubleClick = onDoubleClick
        nsView.onRightClick = onRightClick
    }

    public final class InteractiveNSView: NSView {
        var onSingleClick: ((NSEvent.ModifierFlags) -> Void)?
        var onDoubleClick: (() -> Void)?
        var onRightClick: ((CGPoint) -> Void)?

        public override var acceptsFirstResponder: Bool { true }

        public override func mouseDown(with event: NSEvent) {
            if event.modifierFlags.contains(.control) {
                triggerRightClick(with: event)
                return
            }
            if event.clickCount == 2 {
                onDoubleClick?()
            } else if event.clickCount == 1 {
                onSingleClick?(event.modifierFlags)
            }
        }

        public override func rightMouseDown(with event: NSEvent) {
            triggerRightClick(with: event)
        }

        private func triggerRightClick(with event: NSEvent) {
            guard let window = self.window, let contentView = window.contentView else { return }
            let locInWindow = event.locationInWindow
            // Convert from AppKit bottom-left origin to SwiftUI top-left origin
            let topLeftPoint = CGPoint(
                x: locInWindow.x,
                y: contentView.bounds.height - locInWindow.y
            )
            onRightClick?(topLeftPoint)
        }
    }
}
