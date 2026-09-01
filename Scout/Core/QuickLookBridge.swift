import AppKit
import QuickLookUI

// NSResponder subclass placed in NSApp's responder chain at launch.
// QLPreviewPanel traverses the chain looking for acceptsPreviewPanelControl (informal ObjC
// protocol on NSResponder) and finds this object.
// Swift 6: NSResponder is @MainActor but QLPreviewPanelDataSource is not, so data-source
// methods are `nonisolated` and the backing array is nonisolated(unsafe) — all writes
// happen on the main thread from @MainActor callers anyway.
final class QuickLookBridge: NSResponder, QLPreviewPanelDataSource {
    static let shared = QuickLookBridge()

    nonisolated(unsafe) private var previewURLs: [URL] = []

    // MARK: – Public API (always called on main thread via @MainActor)

    func toggle(urls: [URL], at index: Int) {
        guard let panel = QLPreviewPanel.shared() else { return }
        if panel.isVisible {
            panel.orderOut(nil)
        } else {
            previewURLs = urls
            panel.reloadData()
            panel.currentPreviewItemIndex = max(0, min(index, urls.count - 1))
            panel.makeKeyAndOrderFront(nil)
        }
    }

    func dismiss() {
        QLPreviewPanel.shared()?.orderOut(nil)
    }

    var isVisible: Bool {
        QLPreviewPanel.sharedPreviewPanelExists() && (QLPreviewPanel.shared()?.isVisible ?? false)
    }

    // MARK: – QLPreviewPanelController (informal ObjC protocol — NSResponder overrides)

    override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool { true }

    override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
        panel.dataSource = self
    }

    override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
        panel.dataSource = nil
    }

    // MARK: – QLPreviewPanelDataSource (nonisolated — QL calls these on main thread)

    nonisolated func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        previewURLs.count
    }

    nonisolated func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)! {
        guard index < previewURLs.count else { return nil }
        return previewURLs[index] as NSURL
    }
}
