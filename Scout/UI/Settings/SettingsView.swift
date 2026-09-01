import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        Form {
            Section("Watched Folders") {
                if appState.watchedFolders.isEmpty {
                    Text("No folders watched yet.")
                        .foregroundStyle(.secondary)
                }
                ForEach(appState.watchedFolders, id: \.displayPath) { folder in
                    WatchedFolderRow(folder: folder) {
                        Task { await appState.removeWatchedFolder(folder) }
                    }
                }
                Button("Add Folder…") {
                    Task { await appState.addWatchedFolder() }
                }
            }

            Section("Library") {
                LabeledContent("Indexed screenshots", value: "\(appState.screenshotCount)")
                Button("Re-index All") {
                    Task { await appState.reindexAll() }
                }
                .foregroundStyle(.red)
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 450, minHeight: 300)
        .onAppear {
            Task { await appState.refreshWatchedFolders() }
        }
    }
}
