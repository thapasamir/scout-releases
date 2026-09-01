import AppKit
import Carbon.HIToolbox
import ServiceManagement

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let appState = AppState()
    private var menuBarController: MenuBarController?
    private var paletteController: PaletteWindowController?
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)

        // Insert Quick Look bridge into responder chain so QLPreviewPanel can find it
        let qlBridge = QuickLookBridge.shared
        qlBridge.nextResponder = NSApp.nextResponder
        NSApp.nextResponder = qlBridge

        menuBarController = MenuBarController(appState: appState)
        paletteController = PaletteWindowController(appState: appState)

        Task {
            await appState.indexer.resolveBookmarksAndStartWatching()
            await appState.indexer.cleanupDeletedFiles()
            await appState.refreshWatchedFolders()
        }

        // Track which app is frontmost so we can attribute screenshots correctly
        // even when the user switches apps while macOS is still saving the file.
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil, queue: .main
        ) { [weak self] note in
            guard let appName = (note.userInfo?[NSWorkspace.applicationUserInfoKey]
                as? NSRunningApplication)?.localizedName else { return }
            Task { await self?.appState.indexer.activationTracker.record(appName: appName) }
        }
        // Record the current frontmost app immediately at launch
        if let current = NSWorkspace.shared.frontmostApplication?.localizedName {
            Task { await appState.indexer.activationTracker.record(appName: current) }
        }

        registerLoginItem()
        registerHotKey()

        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleGetURL(_:withReplyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let eventHandler { RemoveEventHandler(eventHandler) }
    }

    // MARK: – Global Hotkey (⌥⇧Space via Carbon — no Accessibility permission required)

    private func registerHotKey() {
        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        InstallEventHandler(
            GetApplicationEventTarget(),
            { (_, event, userData) -> OSStatus in
                guard let userData else { return OSStatus(eventNotHandledErr) }
                let delegate = Unmanaged<AppDelegate>.fromOpaque(userData).takeUnretainedValue()
                DispatchQueue.main.async { delegate.paletteController?.toggle() }
                return noErr
            },
            1, &spec,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )

        var hotKeyID = EventHotKeyID(signature: OSType(0x474C4D50), id: 1)  // 'GLMP'
        RegisterEventHotKey(
            UInt32(kVK_Space),
            UInt32(optionKey | shiftKey),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
    }

    // MARK: – URL scheme deep-link from Spotlight

    @objc private func handleGetURL(_ event: NSAppleEventDescriptor, withReplyEvent: NSAppleEventDescriptor) {
        guard let urlString = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
              let url = URL(string: urlString),
              url.scheme == "scout",
              let filePath = url.queryParameters["path"]
        else { return }

        appState.openScreenshot(atPath: filePath)
    }

    // MARK: – Login item

    private func registerLoginItem() {
        do {
            if SMAppService.mainApp.status == .notRegistered {
                try SMAppService.mainApp.register()
            }
        } catch {
            print("[SMAppService] Registration failed: \(error)")
        }
    }
}

extension URL {
    var queryParameters: [String: String] {
        URLComponents(url: self, resolvingAgainstBaseURL: false)?
            .queryItems?
            .reduce(into: [:]) { $0[$1.name] = $1.value } ?? [:]
    }
}
