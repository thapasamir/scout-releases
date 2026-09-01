import AppKit
import SwiftUI

@MainActor
final class MenuBarController {
    private var statusItem: NSStatusItem
    private let appState: AppState

    init(appState: AppState) {
        self.appState = appState
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        configure()
    }

    private func configure() {
        if let button = statusItem.button {
            if let img = NSImage(named: "MenuBarIcon") {
                img.isTemplate = true
                button.image = img
            } else {
                button.image = NSImage(systemSymbolName: "binoculars", accessibilityDescription: "Scout")
            }
            button.toolTip = "Scout"
        }

        let menu = NSMenu()
        menu.addItem(withTitle: "Search Screenshots…", action: #selector(openMainWindow), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",").target = self
        menu.addItem(withTitle: "Help…", action: #selector(openHelp), keyEquivalent: "?").target = self
        menu.addItem(.separator())
        let uninstallItem = NSMenuItem(title: "Uninstall Scout…", action: #selector(openUninstall), keyEquivalent: "")
        uninstallItem.target = self
        uninstallItem.attributedTitle = NSAttributedString(
            string: "Uninstall Scout…",
            attributes: [.foregroundColor: NSColor.systemRed]
        )
        menu.addItem(uninstallItem)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Scout", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        statusItem.menu = menu
    }

    @objc private func openMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first(where: { $0.identifier?.rawValue == "main" }) {
            window.makeKeyAndOrderFront(nil)
        } else {
            // Window hasn't been created yet — open via environment
            for scene in NSApp.windows {
                scene.makeKeyAndOrderFront(nil)
            }
        }
    }

    @objc private func openSettings() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }

    @objc private func openHelp() {
        NSApp.activate(ignoringOtherApps: true)
        ContentView.openHelpWindow()
    }

    @objc private func openUninstall() {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSWindow(
            contentRect: .zero,
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        panel.title = "Uninstall Scout"
        panel.isReleasedWhenClosed = false
        panel.contentView = NSHostingView(rootView: UninstallView())
        panel.center()
        panel.makeKeyAndOrderFront(nil)
    }
}
