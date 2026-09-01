import SwiftUI

@main
struct ScoutApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate

    var body: some Scene {
        Window("Scout", id: "main") {
            ContentView()
                .environmentObject(delegate.appState)
                .frame(minWidth: 880, minHeight: 540)
        }
        .defaultSize(width: 1120, height: 720)
        .windowResizability(.contentMinSize)

        Settings {
            SettingsView()
                .environmentObject(delegate.appState)
        }

        Window("Scout Help", id: "help") {
            HelpWindow()
        }
        .defaultSize(width: 1100, height: 800)
        .windowResizability(.contentMinSize)
    }
}
