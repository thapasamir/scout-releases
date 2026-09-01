import Foundation
import AppKit
import GRDB

#if canImport(FoundationModels)
import FoundationModels
#endif

// MARK: – Category definitions

enum ScreenshotCategory: String, CaseIterable {
    case code     = "Code"
    case terminal = "Terminal"
    case error    = "Error"
    case design   = "Design"
    case chat     = "Chat"
    case web      = "Web"
    case docs     = "Docs"
    case meeting  = "Meeting"
    case media    = "Media"
    case other    = "Other"

    var icon: String {
        switch self {
        case .code:     return "chevron.left.forwardslash.chevron.right"
        case .terminal: return "terminal"
        case .error:    return "exclamationmark.triangle"
        case .design:   return "paintbrush"
        case .chat:     return "bubble.left.and.bubble.right"
        case .web:      return "globe"
        case .docs:     return "doc.text"
        case .meeting:  return "video"
        case .media:    return "play.rectangle"
        case .other:    return "square.stack"
        }
    }

    static func from(_ string: String) -> ScreenshotCategory? {
        allCases.first { $0.rawValue.caseInsensitiveCompare(string) == .orderedSame }
    }
}

// MARK: – Classifier

actor ScreenshotClassifier {
    private let db: DatabasePool

    init(db: DatabasePool) {
        self.db = db
    }

    // Classify and store as an auto tag. No-op if already classified.
    func classifyAndStore(
        id: Int64,
        thumbnailURL: URL?,
        ocrText: String,
        sourceApp: String?
    ) async {
        guard await needsClassification(id: id) else { return }
        let category = await classify(thumbnailURL: thumbnailURL, ocrText: ocrText, sourceApp: sourceApp)
        await storeAutoTag(category: category, for: id)
    }

    // Backfill existing screenshots that have no auto tag yet.
    func classifyUntagged() async {
        let thumbsBase = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Scout/Thumbnails")

        let rows = (try? await db.read { db in
            try Row.fetchAll(db, sql: """
                SELECT s.id, s.thumbnail_path, s.ocr_text, s.source_app
                FROM screenshots s
                WHERE s.ocr_status = 'done'
                  AND NOT EXISTS (
                      SELECT 1 FROM screenshot_tags st
                      JOIN tags t ON t.id = st.tag_id
                      WHERE st.screenshot_id = s.id AND t.kind = 'auto'
                  )
                ORDER BY s.file_created_at DESC
            """)
        }) ?? []

        for row in rows {
            let id: Int64      = row["id"]
            let thumb: String? = row["thumbnail_path"]
            let text: String   = row["ocr_text"] ?? ""
            let app: String?   = row["source_app"]
            let thumbURL       = thumb.map { thumbsBase.appendingPathComponent($0) }

            await classifyAndStore(id: id, thumbnailURL: thumbURL, ocrText: text, sourceApp: app)
            await Task.yield()  // yield between items so the actor stays responsive
        }
    }

    // MARK: – Private

    private func needsClassification(id: Int64) async -> Bool {
        let count = (try? await db.read { db in
            try Int.fetchOne(db, sql: """
                SELECT COUNT(*) FROM screenshot_tags st
                JOIN tags t ON t.id = st.tag_id
                WHERE st.screenshot_id = ? AND t.kind = 'auto'
            """, arguments: [id])
        }) ?? 0
        return count == 0
    }

    private func classify(thumbnailURL: URL?, ocrText: String, sourceApp: String?) async -> String {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            if let result = try? await aiClassify(thumbnailURL: thumbnailURL, ocrText: ocrText, sourceApp: sourceApp) {
                return result
            }
        }
        #endif
        return ruleClassify(ocrText: ocrText, sourceApp: sourceApp)
    }

    private func storeAutoTag(category: String, for id: Int64) async {
        try? await db.write { db in
            try db.execute(
                sql: "INSERT OR IGNORE INTO tags (name, kind) VALUES (?, 'auto')",
                arguments: [category])
            let tagId = try Int64.fetchOne(
                db, sql: "SELECT id FROM tags WHERE name = ?",
                arguments: [category])!
            try db.execute(
                sql: "INSERT OR IGNORE INTO screenshot_tags (screenshot_id, tag_id, confidence) VALUES (?, ?, 1.0)",
                arguments: [id, tagId])
        }
    }

    // MARK: – AI path (macOS 26+)

    #if canImport(FoundationModels)
    @available(macOS 26.0, *)
    private func aiClassify(thumbnailURL: URL?, ocrText: String, sourceApp: String?) async throws -> String {
        let model = SystemLanguageModel.default
        guard case .available = model.availability else {
            throw ClassifierError.modelUnavailable
        }

        let session = LanguageModelSession(
            model: model,
            instructions: "You classify macOS screenshots. Reply with exactly one category name — no explanation."
        )

        var userMessage = ""
        if let app = sourceApp, !app.isEmpty { userMessage += "Source app: \(app)\n" }
        if !ocrText.isEmpty { userMessage += "Text in screenshot: \(ocrText.prefix(600))\n" }
        userMessage += "Categories: Code, Terminal, Error, Design, Chat, Web, Docs, Meeting, Media, Other"

        let response = try await session.respond(to: userMessage)
        return validated(response.content)
    }

    private func validated(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return ScreenshotCategory.from(trimmed)?.rawValue ?? ScreenshotCategory.other.rawValue
    }
    #endif

    // MARK: – Rule-based fallback

    nonisolated private func ruleClassify(ocrText: String, sourceApp: String?) -> String {
        if let app = sourceApp {
            if codeApps.contains(app)     { return ScreenshotCategory.code.rawValue }
            if terminalApps.contains(app) { return ScreenshotCategory.terminal.rawValue }
            if designApps.contains(app)   { return ScreenshotCategory.design.rawValue }
            if chatApps.contains(app)     { return ScreenshotCategory.chat.rawValue }
            if browserApps.contains(app)  { return ScreenshotCategory.web.rawValue }
            if meetingApps.contains(app)  { return ScreenshotCategory.meeting.rawValue }
            if mediaApps.contains(app)    { return ScreenshotCategory.media.rawValue }
        }

        let text = ocrText.lowercased()

        if text.containsAny(["error:", "exception:", "traceback", "stack trace",
                              "typeerror", "cannot find", "undefined", "fatal:"]) {
            return ScreenshotCategory.error.rawValue
        }
        if text.containsAny(["func ", "class ", "struct ", "import ", "def ",
                              "public ", "private ", "return "]) {
            return ScreenshotCategory.code.rawValue
        }
        if text.containsAny(["$ ", "% ", ">>> ", "zsh:", "bash-", "#!/"]) {
            return ScreenshotCategory.terminal.rawValue
        }
        if text.containsAny(["to:", "from:", "subject:", "inbox", "page 1 of"]) {
            return ScreenshotCategory.docs.rawValue
        }

        return ScreenshotCategory.other.rawValue
    }

    // MARK: – App name lookup tables

    private let codeApps: Set<String> = [
        "Xcode", "Visual Studio Code", "Cursor", "Sublime Text", "Nova",
        "CLion", "IntelliJ IDEA", "PyCharm", "WebStorm", "RubyMine",
        "Android Studio", "Zed", "Neovim", "MacVim", "BBEdit", "Emacs"
    ]
    private let terminalApps: Set<String> = [
        "Terminal", "iTerm2", "Warp", "Hyper", "Ghostty", "Alacritty", "Kitty"
    ]
    private let designApps: Set<String> = [
        "Figma", "Sketch", "Adobe XD", "Framer", "Pixelmator Pro",
        "Affinity Designer", "Affinity Photo", "Adobe Photoshop",
        "Adobe Illustrator", "Canva", "Procreate", "Principle"
    ]
    private let chatApps: Set<String> = [
        "Slack", "Discord", "Microsoft Teams", "Messages", "WhatsApp",
        "Telegram", "Signal", "Viber", "Mattermost"
    ]
    private let browserApps: Set<String> = [
        "Safari", "Google Chrome", "Firefox", "Arc", "Brave Browser",
        "Opera", "Microsoft Edge", "Chromium", "Vivaldi", "Orion"
    ]
    private let meetingApps: Set<String> = [
        "Zoom", "FaceTime", "Webex", "Around", "Loom", "Riverside"
    ]
    private let mediaApps: Set<String> = [
        "Spotify", "Music", "VLC", "IINA", "Infuse",
        "QuickTime Player", "Final Cut Pro", "DaVinci Resolve"
    ]
}

private extension String {
    func containsAny(_ patterns: [String]) -> Bool {
        patterns.contains { self.contains($0) }
    }
}

private enum ClassifierError: Error {
    case modelUnavailable
}
