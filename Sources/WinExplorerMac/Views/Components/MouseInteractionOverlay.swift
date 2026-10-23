import SwiftUI
import AppKit

/// AppKit bridge that captures left click (with modifier flags), double click, right click (with window coordinates),
/// and left mouse dragging (with window coordinates) so we can render the authentic Windows 11 floating acrylic
/// right-click menu and marquee drag selection.
public struct Win11MouseHandlerView: NSViewRepresentable {
    public var onSingleClick: ((NSEvent.ModifierFlags) -> Void)?
    public var onDoubleClick: (() -> Void)?
    public var onRightClick: ((CGPoint) -> Void)?
    public var onDragChanged: ((CGPoint, CGPoint) -> Void)?
    public var onDragEnded: (() -> Void)?

    public init(
        onSingleClick: ((NSEvent.ModifierFlags) -> Void)? = nil,
        onDoubleClick: (() -> Void)? = nil,
        onRightClick: ((CGPoint) -> Void)? = nil,
        onDragChanged: ((CGPoint, CGPoint) -> Void)? = nil,
        onDragEnded: (() -> Void)? = nil
    ) {
        self.onSingleClick = onSingleClick
        self.onDoubleClick = onDoubleClick
        self.onRightClick = onRightClick
        self.onDragChanged = onDragChanged
        self.onDragEnded = onDragEnded
    }

    public func makeNSView(context: Context) -> InteractiveNSView {
        let view = InteractiveNSView()
        view.onSingleClick = onSingleClick
        view.onDoubleClick = onDoubleClick
        view.onRightClick = onRightClick
        view.onDragChanged = onDragChanged
        view.onDragEnded = onDragEnded
        return view
    }

    public func updateNSView(_ nsView: InteractiveNSView, context: Context) {
        nsView.onSingleClick = onSingleClick
        nsView.onDoubleClick = onDoubleClick
        nsView.onRightClick = onRightClick
        nsView.onDragChanged = onDragChanged
        nsView.onDragEnded = onDragEnded
    }

    public final class InteractiveNSView: NSView {
        var onSingleClick: ((NSEvent.ModifierFlags) -> Void)?
        var onDoubleClick: (() -> Void)?
        var onRightClick: ((CGPoint) -> Void)?
        var onDragChanged: ((CGPoint, CGPoint) -> Void)?
        var onDragEnded: (() -> Void)?

        private var dragStartWindowPoint: CGPoint? = nil
        private var isDragging: Bool = false

        public override var acceptsFirstResponder: Bool { true }

        private func toSwiftUIPoint(_ windowPoint: CGPoint) -> CGPoint {
            guard let window = self.window, let contentView = window.contentView else { return windowPoint }
            // Convert from AppKit bottom-left origin to SwiftUI top-left origin
            return CGPoint(
                x: windowPoint.x,
                y: contentView.bounds.height - windowPoint.y
            )
        }

        public override func mouseDown(with event: NSEvent) {
            if event.modifierFlags.contains(.control) {
                triggerRightClick(with: event)
                return
            }
            dragStartWindowPoint = event.locationInWindow
            isDragging = false
        }

        public override func mouseDragged(with event: NSEvent) {
            guard let startWindowPoint = dragStartWindowPoint else { return }
            let currentWindowPoint = event.locationInWindow
            let dx = currentWindowPoint.x - startWindowPoint.x
            let dy = currentWindowPoint.y - startWindowPoint.y

            if !isDragging && (dx * dx + dy * dy) > 16 { // moved more than 4 pixels
                isDragging = true
            }

            if isDragging {
                let start = toSwiftUIPoint(startWindowPoint)
                let current = toSwiftUIPoint(currentWindowPoint)
                onDragChanged?(start, current)
            }
        }

        public override func mouseUp(with event: NSEvent) {
            if isDragging {
                isDragging = false
                dragStartWindowPoint = nil
                onDragEnded?()
                return
            }
            dragStartWindowPoint = nil

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
            let topLeftPoint = CGPoint(
                x: locInWindow.x,
                y: contentView.bounds.height - locInWindow.y
            )
            onRightClick?(topLeftPoint)
        }
    }
}
