import SwiftUI
import AppKit

/// Native AppKit text field for inline renaming that automatically gains focus,
/// selects the base filename (excluding extension like Windows 11), and handles Enter/Escape/Blur.
public struct Win11RenameTextField: NSViewRepresentable {
    @Binding var text: String
    var alignment: NSTextAlignment = .left
    var onCommit: () -> Void
    var onCancel: () -> Void

    public init(
        text: Binding<String>,
        alignment: NSTextAlignment = .left,
        onCommit: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        self._text = text
        self.alignment = alignment
        self.onCommit = onCommit
        self.onCancel = onCancel
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    public func makeNSView(context: Context) -> NSTextField {
        let textField = FocusableTextField()
        textField.isBordered = false
        textField.drawsBackground = true
        textField.backgroundColor = NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(red: 0.11, green: 0.11, blue: 0.13, alpha: 1.0)
                : NSColor.white
        }
        textField.textColor = NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor.white
                : NSColor.labelColor
        }
        textField.font = NSFont.systemFont(ofSize: 12)
        textField.alignment = alignment
        textField.delegate = context.coordinator
        textField.stringValue = text
        textField.lineBreakMode = .byWordWrapping
        textField.focusRingType = .none
        textField.cell?.wraps = true
        textField.cell?.isScrollable = false
        textField.maximumNumberOfLines = 6

        return textField
    }

    public func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSTextField, context: Context) -> CGSize? {
        let targetWidth = proposal.width ?? nsView.fittingSize.width
        guard targetWidth > 0 else { return nsView.fittingSize }

        let cell = nsView.cell?.copy() as? NSTextFieldCell ?? nsView.cell!
        cell.stringValue = text.isEmpty ? "A" : text
        let rect = NSRect(x: 0, y: 0, width: targetWidth, height: 2000)
        let calcSize = cell.cellSize(forBounds: rect)
        let finalHeight = max(22, min(120, calcSize.height + 4))
        return CGSize(width: targetWidth, height: finalHeight)
    }

    public func updateNSView(_ nsView: NSTextField, context: Context) {
        if nsView.stringValue != text && nsView.currentEditor() == nil {
            nsView.stringValue = text
        }
    }

    public final class FocusableTextField: NSTextField {
        public override var acceptsFirstResponder: Bool { true }

        public override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            DispatchQueue.main.async { [weak self] in
                guard let self = self, let window = self.window else { return }
                window.makeFirstResponder(self)
                if let editor = self.currentEditor() {
                    let isDark = self.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                    let bg = isDark ? NSColor(red: 0.11, green: 0.11, blue: 0.13, alpha: 1.0) : NSColor.white
                    let fg = isDark ? NSColor.white : NSColor.labelColor

                    if let textView = editor as? NSTextView {
                        textView.drawsBackground = true
                        textView.backgroundColor = bg
                        textView.textColor = fg
                        textView.insertionPointColor = fg
                    }

                    let baseName = (self.stringValue as NSString).deletingPathExtension
                    let selectLength = baseName.isEmpty ? self.stringValue.count : baseName.count
                    editor.selectedRange = NSRange(location: 0, length: selectLength)
                }
            }
        }

        public override func performKeyEquivalent(with event: NSEvent) -> Bool {
            if event.modifierFlags.contains(.command) {
                let chars = event.charactersIgnoringModifiers?.lowercased()
                if chars == "c" {
                    if let editor = currentEditor() as? NSTextView, editor.selectedRange.length > 0 {
                        editor.copy(nil)
                    } else if !stringValue.isEmpty {
                        let pb = NSPasteboard.general
                        pb.clearContents()
                        pb.setString(stringValue, forType: .string)
                    } else {
                        NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: self)
                    }
                    return true
                }
                if chars == "x" {
                    if let editor = currentEditor() as? NSTextView, editor.selectedRange.length > 0 {
                        editor.cut(nil)
                    } else {
                        NSApp.sendAction(#selector(NSText.cut(_:)), to: nil, from: self)
                    }
                    return true
                }
                if chars == "v" {
                    if let editor = currentEditor() as? NSTextView {
                        editor.paste(nil)
                    } else {
                        NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: self)
                    }
                    return true
                }
                if chars == "a" {
                    if let editor = currentEditor() {
                        editor.selectAll(nil)
                    } else {
                        selectText(nil)
                    }
                    return true
                }
            }
            return super.performKeyEquivalent(with: event)
        }
    }

    public final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: Win11RenameTextField
        var isFinishing = false

        init(_ parent: Win11RenameTextField) {
            self.parent = parent
        }

        public func controlTextDidChange(_ obj: Notification) {
            if let textField = obj.object as? NSTextField {
                parent.text = textField.stringValue
            }
        }

        public func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                guard !isFinishing else { return true }
                isFinishing = true
                parent.onCommit()
                return true
            } else if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
                guard !isFinishing else { return true }
                isFinishing = true
                parent.onCancel()
                return true
            }
            return false
        }

        public func controlTextDidEndEditing(_ obj: Notification) {
            guard !isFinishing else { return }
            isFinishing = true
            parent.onCommit()
        }
    }
}
