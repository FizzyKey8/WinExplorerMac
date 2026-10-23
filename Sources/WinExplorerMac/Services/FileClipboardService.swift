import Foundation
import AppKit

public final class FileClipboardService: ObservableObject {
    public enum OperationMode {
        case copy
        case cut
    }

    @Published public private(set) var urls: [URL] = []
    @Published public private(set) var mode: OperationMode = .copy

    public init() {}

    public var hasItems: Bool {
        if !urls.isEmpty { return true }
        if let pasted = NSPasteboard.general.readObjects(forClasses: [NSURL.self], options: nil) as? [URL], !pasted.isEmpty {
            return true
        }
        return false
    }

    public func copy(_ items: [URL]) {
        guard !items.isEmpty else { return }
        self.urls = items.map { $0.cleanFileURL }
        self.mode = .copy
        writeToSystemPasteboard(items)
    }

    public func cut(_ items: [URL]) {
        guard !items.isEmpty else { return }
        self.urls = items.map { $0.cleanFileURL }
        self.mode = .cut
        writeToSystemPasteboard(items)
    }

    public func isItemCut(_ url: URL) -> Bool {
        guard mode == .cut else { return false }
        return urls.contains(url.cleanFileURL)
    }

    public func currentItemsForPaste() -> (urls: [URL], isCut: Bool) {
        if !urls.isEmpty {
            return (urls, mode == .cut)
        }
        if let pasted = NSPasteboard.general.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] {
            return (pasted.filter { $0.isFileURL }, false)
        }
        return ([], false)
    }

    public func completeCutOperationIfNeeded() {
        if mode == .cut {
            urls.removeAll()
            mode = .copy
        }
    }

    private func writeToSystemPasteboard(_ items: [URL]) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects(items.map { $0 as NSURL })
    }
}
