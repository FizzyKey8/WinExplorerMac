import SwiftUI
import AppKit

/// AppKit bridge that captures left click (with modifier flags), double click, right click (with window coordinates),
/// and left mouse dragging (with window coordinates) so we can render the authentic Windows 11 floating acrylic
/// right-click menu and marquee drag selection.
public struct Win11MouseHandlerView: NSViewRepresentable {
    public var toolTip: String? = nil
    public var onHoverChanged: ((Bool) -> Void)? = nil
    public var onSingleClick: ((NSEvent.ModifierFlags) -> Void)?
    public var onDoubleClick: (() -> Void)?
    public var onRightClick: ((CGPoint) -> Void)?
    public var onDragChanged: ((CGPoint, CGPoint) -> Void)?
    public var onDragEnded: (() -> Void)?

    public init(
        toolTip: String? = nil,
        onHoverChanged: ((Bool) -> Void)? = nil,
        onSingleClick: ((NSEvent.ModifierFlags) -> Void)? = nil,
        onDoubleClick: (() -> Void)? = nil,
        onRightClick: ((CGPoint) -> Void)? = nil,
        onDragChanged: ((CGPoint, CGPoint) -> Void)? = nil,
        onDragEnded: (() -> Void)? = nil
    ) {
        self.toolTip = toolTip
        self.onHoverChanged = onHoverChanged
        self.onSingleClick = onSingleClick
        self.onDoubleClick = onDoubleClick
        self.onRightClick = onRightClick
        self.onDragChanged = onDragChanged
        self.onDragEnded = onDragEnded
    }

    public func makeNSView(context: Context) -> InteractiveNSView {
        let view = InteractiveNSView()
        view.pendingToolTip = toolTip
        view.onHoverChanged = onHoverChanged
        view.onSingleClick = onSingleClick
        view.onDoubleClick = onDoubleClick
        view.onRightClick = onRightClick
        view.onDragChanged = onDragChanged
        view.onDragEnded = onDragEnded
        return view
    }

    public func updateNSView(_ nsView: InteractiveNSView, context: Context) {
        nsView.pendingToolTip = toolTip
        nsView.onHoverChanged = onHoverChanged
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
        var onHoverChanged: ((Bool) -> Void)?
        var pendingToolTip: String? = nil

        private var trackingArea: NSTrackingArea?
        private var hoverTimer: Timer?
        private var dragStartWindowPoint: CGPoint? = nil
        private var isDragging: Bool = false

        public override var acceptsFirstResponder: Bool { true }

        public override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let trackingArea {
                removeTrackingArea(trackingArea)
            }
            let area = NSTrackingArea(
                rect: bounds,
                options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                owner: self,
                userInfo: nil
            )
            addTrackingArea(area)
            self.trackingArea = area
        }

        public override func mouseEntered(with event: NSEvent) {
            onHoverChanged?(true)
            hoverTimer?.invalidate()
            self.toolTip = nil
            if let text = pendingToolTip, !text.isEmpty {
                hoverTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { [weak self] _ in
                    guard let self = self else { return }
                    self.toolTip = text
                }
            }
        }

        public override func mouseExited(with event: NSEvent) {
            onHoverChanged?(false)
            hoverTimer?.invalidate()
            hoverTimer = nil
            self.toolTip = nil
        }

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
