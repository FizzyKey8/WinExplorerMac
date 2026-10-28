import AppKit
import SwiftUI

/// Authentic Windows 11 persistent, clickable vertical scrollbar that stays visible,
/// provides a dedicated clickable track on the right edge of the folder view,
/// and allows smooth dragging and clicking without interfering with file items or marquee selection.
public final class Win11Scroller: NSScroller {
    private var isHovered: Bool = false
    private var isKnobHovered: Bool = false
    private var trackingArea: NSTrackingArea?

    /// Forces macOS to treat this scroller as a permanent, legacy-style scroller with its own reserved column,
    /// preventing it from fading away or becoming unclickable.
    public override class var isCompatibleWithOverlayScrollers: Bool {
        return false
    }

    public override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeInKeyWindow],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        self.trackingArea = area
    }

    public override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        isHovered = true
        needsDisplay = true
    }

    public override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        isHovered = false
        isKnobHovered = false
        needsDisplay = true
    }

    public override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        let loc = convert(event.locationInWindow, from: nil)
        let knobRect = rect(for: .knob)
        let overKnob = knobRect.contains(loc)
        if overKnob != isKnobHovered {
            isKnobHovered = overKnob
            needsDisplay = true
        }
    }

    public override func drawKnobSlot(in slotRect: NSRect, highlight flag: Bool) {
        // Subtle Windows 11 style track background when hovered or clicked
        if isHovered || flag {
            NSColor.textColor.withAlphaComponent(0.04).setFill()
            slotRect.fill()
        }
    }

    public override func drawKnob() {
        let knobRect = rect(for: .knob)
        guard knobRect.width > 0 && knobRect.height > 0 else { return }

        // Windows 11 rounded pill thumb
        let insetX: CGFloat = isHovered ? 2.5 : 3.5
        let pillRect = knobRect.insetBy(dx: insetX, dy: 2)
        guard pillRect.width > 0 && pillRect.height > 0 else { return }
        let radius = min(pillRect.width / 2, 4)
        let path = NSBezierPath(roundedRect: pillRect, xRadius: radius, yRadius: radius)

        let alpha: CGFloat = isKnobHovered ? 0.55 : (isHovered ? 0.40 : 0.28)
        let knobColor = NSColor.textColor.withAlphaComponent(alpha)
        knobColor.setFill()
        path.fill()
    }
}

public struct Win11ScrollModifier: NSViewRepresentable {
    public init() {}

    public func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            apply(to: view)
        }
        return view
    }

    public func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            apply(to: nsView)
        }
    }

    private func apply(to view: NSView) {
        guard let sv = view.enclosingScrollView else { return }
        if !(sv.verticalScroller is Win11Scroller) {
            let scroller = Win11Scroller()
            sv.verticalScroller = scroller
            sv.hasVerticalScroller = true
            sv.scrollerStyle = .legacy
            sv.verticalScroller?.controlSize = .regular
            sv.tile()
        } else {
            sv.hasVerticalScroller = true
            sv.scrollerStyle = .legacy
        }
    }
}

public extension View {
    func win11ScrollBar() -> some View {
        self.background(Win11ScrollModifier())
    }
}
