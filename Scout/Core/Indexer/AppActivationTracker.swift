import AppKit

/// Tracks which app was frontmost at any given moment.
/// Used to correctly attribute newly-detected screenshots to the app that was
/// in the foreground when macOS saved the file — not the app in focus when
/// Scout happens to index it (which can be different if the user switched).
actor AppActivationTracker {
    private struct Activation {
        let appName: String
        let at: Date
    }

    private var history: [Activation] = []

    // MARK: – Recording

    func record(appName: String) {
        history.append(Activation(appName: appName, at: Date()))
        // Keep only the last 10 minutes — older entries are never useful
        let cutoff = Date().addingTimeInterval(-600)
        history.removeAll { $0.at < cutoff }
    }

    // MARK: – Lookup

    /// Returns the app that was frontmost at (or just before) `timestamp`.
    /// Falls back to `currentFrontmost` when no history entry predates the file.
    func appName(at timestamp: Date, currentFrontmost: String?) -> String? {
        // Find the last activation that was recorded BEFORE the file was created.
        // This is the app that held focus when macOS saved the screenshot.
        let before = history.filter { $0.at <= timestamp }
        return before.last?.appName ?? currentFrontmost
    }
}
