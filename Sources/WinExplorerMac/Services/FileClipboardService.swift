import Foundation
import AppKit

public final class FileClipboardService: ObservableObject {
    public enum OperationMode {
        case copy
        case cut
    }

    @Published public private(set) var urls: [URL] = []
    @Published public private(set) var mode: OperationMode = .copy
    private var lastWrittenChangeCount: Int = -1

    public init() {}

    private func syncWithSystemPasteboardIfNeeded() {
        let currentChangeCount = NSPasteboard.general.changeCount
        if currentChangeCount != lastWrittenChangeCount {
            lastWrittenChangeCount = currentChangeCount
            if let pasted = NSPasteboard.general.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] {
                let fileURLs = pasted.filter { $0.isFileURL }.map { $0.cleanFileURL }
                if !fileURLs.isEmpty {
                    self.urls = fileURLs
                    self.mode = .copy
                } else {
                    self.urls = []
                }
            } else {
                self.urls = []
            }
        }
    }

    public var hasItems: Bool {
        syncWithSystemPasteboardIfNeeded()
        return !urls.isEmpty
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
        syncWithSystemPasteboardIfNeeded()
        guard mode == .cut else { return false }
        return urls.contains(url.cleanFileURL)
    }

    public func currentItemsForPaste() -> (urls: [URL], isCut: Bool) {
        syncWithSystemPasteboardIfNeeded()
        return (urls, mode == .cut)
    }

    public func completeCutOperationIfNeeded() {
        if mode == .cut {
            urls.removeAll()
            mode = .copy
            NSPasteboard.general.clearContents()
            lastWrittenChangeCount = NSPasteboard.general.changeCount
        }
    }

    private func writeToSystemPasteboard(_ items: [URL]) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects(items.map { $0 as NSURL })
        lastWrittenChangeCount = pasteboard.changeCount
    }
}
