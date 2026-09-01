import AppKit
import SwiftUI

@MainActor
final class PaletteWindowController {
    private var panel: NSPanel?
    private let appState: AppState
    private var keyMonitor: Any?

    private let maxVisibleResults = 8

    init(appState: AppState) {
        self.appState = appState
    }

    func toggle() {
        if let panel, panel.isVisible {
            hide()
        } else {
            show()
        }
    }

    func show() {
        let panel = makePanelIfNeeded()
        panel.center()
        if let screen = NSScreen.main {
            let x = (screen.frame.width - panel.frame.width) / 2 + screen.frame.minX
            let y = screen.frame.maxY - 200
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        appState.paletteSelectedIndex = 0

        // Ensure the TextField inside the SwiftUI hosting view gets keyboard focus
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            guard let panel = self?.panel else { return }
            if let tf = Self.firstTextField(in: panel.contentView) {
                panel.makeFirstResponder(tf)
            }
        }

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return self.handleKeyDown(event)
        }
    }

    func hide() {
        panel?.orderOut(nil)
        if let m = keyMonitor { NSEvent.removeMonitor(m); keyMonitor = nil }
        appState.searchResults = []
        appState.paletteSelectedIndex = 0
    }

    // MARK: – Key handling

    private func handleKeyDown(_ event: NSEvent) -> NSEvent? {
        // Only intercept when our panel is actually the key window
        guard let panel, panel.isKeyWindow else { return event }

        switch event.keyCode {
        case 53: // Escape
            hide()
            return nil

        case 125: // ↓
            let count = min(appState.searchResults.count, maxVisibleResults)
            if appState.paletteSelectedIndex < count - 1 {
                appState.paletteSelectedIndex += 1
            }
            return nil

        case 126: // ↑
            if appState.paletteSelectedIndex > 0 {
                appState.paletteSelectedIndex -= 1
            }
            return nil

        case 36, 76: // Return / KP Return — open selected result
            let results = appState.searchResults.prefix(maxVisibleResults)
            let idx = appState.paletteSelectedIndex
            if idx < results.count {
                let result = Array(results)[idx]
                hide()
                NSWorkspace.shared.activateFileViewerSelecting([result.fileURL])
            }
            return nil

        default:
            return event
        }
    }

    // MARK: – Helpers

    private static func firstTextField(in view: NSView?) -> NSTextField? {
        guard let view else { return nil }
        for sub in view.subviews {
            if let tf = sub as? NSTextField, tf.isEditable { return tf }
            if let found = firstTextField(in: sub) { return found }
        }
        return nil
    }

    // MARK: – Panel setup

    private func makePanelIfNeeded() -> NSPanel {
        if let existing = panel { return existing }

        let p = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 680, height: 420),
            styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        p.titleVisibility = .hidden
        p.titlebarAppearsTransparent = true
        p.isMovableByWindowBackground = true
        p.isFloatingPanel = true
        p.hidesOnDeactivate = false
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.level = .floating
        p.hasShadow = true
        p.backgroundColor = .clear

        let view = PaletteView(onDismiss: { [weak self] in self?.hide() })
            .environmentObject(appState)

        let hosting = NSHostingController(rootView: view)
        hosting.view.wantsLayer = true
        p.contentViewController = hosting

        self.panel = p
        return p
    }
}
