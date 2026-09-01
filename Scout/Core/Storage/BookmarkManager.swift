import AppKit
import GRDB

enum BookmarkError: Error {
    case cancelled
}

// Without App Sandbox, we don't need security-scoped bookmarks.
// We still use NSOpenPanel so the user explicitly chooses folders,
// and we store paths in the DB for persistence across relaunches.
actor BookmarkManager {
    private let db: DatabasePool

    init(db: DatabasePool) {
        self.db = db
    }

    @MainActor
    func addWatchedFolder() async throws -> URL {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = false
        panel.prompt = "Watch This Folder"
        panel.message = "Choose a folder where your screenshots are saved."

        let response = await panel.begin()
        guard response == .OK, let url = panel.url else {
            throw BookmarkError.cancelled
        }

        try await db.write { db in
            var r = WatchedFolderRecord(displayPath: url.path, bookmarkData: Data())
            try r.insert(db)
        }

        return url
    }

    func resolveAll() async throws -> [URL] {
        let folders = try await db.read { db in
            try WatchedFolderRecord
                .filter(Column("is_active") == true)
                .fetchAll(db)
        }
        return folders.map { URL(fileURLWithPath: $0.displayPath) }
    }

    func deactivate(folder: WatchedFolderRecord) async throws {
        guard let id = folder.id else { return }
        try await db.write { db in
            try db.execute(
                sql: "UPDATE watched_folders SET is_active = 0 WHERE id = ?",
                arguments: [id]
            )
        }
    }
}

extension Notification.Name {
    static let bookmarkBecameStale = Notification.Name("bookmarkBecameStale")
}
