import Foundation
import AppKit
import GRDB

private let screenshotExtensions: Set<String> = ["png", "jpg", "jpeg", "tiff", "heic"]

actor ScreenshotIndexer {
    private let db: DatabasePool
    private let ocr = OCRProcessor()
    private let spotlight: SpotlightIndexer
    private let thumbnails: ThumbnailCache
    // Nil until convert_model.py has been run and model files are bundled
    private let embedder: EmbeddingProcessor?
    private let classifier: ScreenshotClassifier
    private var watchers: [FolderWatcher] = []
    private var activeURLs: [URL] = []
    let activationTracker = AppActivationTracker()

    private let operationQueue: OperationQueue = {
        let q = OperationQueue()
        q.maxConcurrentOperationCount = 2
        q.qualityOfService = .utility
        return q
    }()

    init(db: DatabasePool, spotlight: SpotlightIndexer, thumbnails: ThumbnailCache) {
        self.db = db
        self.spotlight = spotlight
        self.thumbnails = thumbnails
        self.embedder = EmbeddingProcessor.makeIfAvailable()
        self.classifier = ScreenshotClassifier(db: db)
    }

    func resolveBookmarksAndStartWatching() async {
        let bookmarkManager = BookmarkManager(db: db)
        guard let resolved = try? await bookmarkManager.resolveAll() else { return }

        for url in resolved {
            activeURLs.append(url)
            startWatching(url: url)
            await scanForNewFiles(in: url)
        }

        // Re-queue any items that were interrupted last session
        await requeueInterrupted()
    }

    func addWatchedFolder() async throws -> URL {
        let bookmarkManager = BookmarkManager(db: db)
        let url = try await bookmarkManager.addWatchedFolder()
        activeURLs.append(url)
        startWatching(url: url)
        await scanForNewFiles(in: url)
        return url
    }

    private func startWatching(url: URL) {
        let watcher = try? FolderWatcher(url: url) { [weak self] changedURL in
            Task { await self?.scanForNewFiles(in: changedURL) }
        }
        if let watcher { watchers.append(watcher) }
    }

    private func scanForNewFiles(in directory: URL) async {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.creationDateKey, .contentModificationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        let imageURLs = contents.filter {
            screenshotExtensions.contains($0.pathExtension.lowercased())
        }

        for url in imageURLs {
            await enqueue(url)
        }
    }

    private func enqueue(_ fileURL: URL) async {
        do {
            // Check for an existing record
            let existing = try await db.read { db in
                try ScreenshotRecord
                    .filter(Column("file_path") == fileURL.path)
                    .fetchOne(db)
            }

            // Already fully indexed — nothing to do
            if let existing, existing.ocrStatus == OCRStatus.done.rawValue { return }

            // Already in DB (pending/failed) — re-queue without re-inserting
            if let existing, let id = existing.id {
                operationQueue.addOperation { [weak self] in
                    Task { await self?.process(fileURL: fileURL, recordID: id) }
                }
                return
            }

            // Determine the actual capture moment for source-app attribution.
            //
            // Problem: Cmd+Shift+4 screenshots are written to disk only AFTER the
            // floating preview thumbnail auto-dismisses (~5 s). The filesystem
            // createdAt therefore points to AFTER the user may have switched apps,
            // causing the wrong app to be recorded.
            //
            // Fix: macOS always embeds the real capture time in the filename
            // ("Screenshot 2024-01-15 at 10.30.45.png"). Parsing that gives us the
            // moment the shutter fired, before any app switch. We fall back to
            // createdAt only for non-screenshot files that don't carry this pattern.
            let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path)
            let createdAt = (attrs?[.creationDate] as? Date) ?? .distantPast
            let captureDate = Self.parseCaptureDate(from: fileURL) ?? createdAt
            let isRecent = Date().timeIntervalSince(captureDate) < 90
            let sourceApp: String? = isRecent
                ? await activationTracker.appName(
                    at: captureDate,
                    currentFrontmost: await MainActor.run { NSWorkspace.shared.frontmostApplication?.localizedName }
                  )
                : nil

            // New file — insert and queue
            let recordID = try await db.write { db -> Int64 in
                var r = ScreenshotRecord(fileURL: fileURL, status: OCRStatus.pending.rawValue)
                r.sourceApp = sourceApp
                try r.insert(db)
                return r.id!
            }

            operationQueue.addOperation { [weak self] in
                Task { await self?.process(fileURL: fileURL, recordID: recordID) }
            }
        } catch {
            print("[Indexer] enqueue failed for \(fileURL.lastPathComponent): \(error)")
        }
    }

    private func process(fileURL: URL, recordID: Int64) async {
        do {
            let (text, confidence) = try await ocr.extractText(from: fileURL)

            let thumbPath = await thumbnails.generate(for: fileURL, id: recordID)

            try await db.write { db in
                try db.execute(sql: """
                    UPDATE screenshots
                    SET ocr_text = ?, ocr_confidence = ?, ocr_status = ?, thumbnail_path = ?
                    WHERE id = ?
                """, arguments: [text, confidence, OCRStatus.done.rawValue, thumbPath, recordID])
            }

            await spotlight.indexScreenshot(id: recordID, path: fileURL.path, text: text, thumbnailPath: thumbPath)

            // Compute and store embedding if the model is available
            if let embedder, !text.isEmpty {
                do {
                    let vector = try await embedder.embed(text)
                    let record = EmbeddingRecord(
                        screenshotId: recordID,
                        modelId: EmbeddingProcessor.modelID,
                        vector: vector
                    )
                    try? await db.write { db in
                        try record.save(db)   // insert or replace
                    }
                } catch {
                    // Embedding failure is non-fatal; literal search still works
                    print("[Embedder] Failed for id=\(recordID): \(error)")
                }
            }

            // Classify into a category (AI on macOS 26+, rules fallback otherwise)
            await classifier.classifyAndStore(
                id: recordID,
                thumbnailURL: thumbPath.map {
                    FileManager.default
                        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                        .appendingPathComponent("Scout/Thumbnails/\($0)")
                },
                ocrText: text,
                sourceApp: (try? await db.read { db in
                    try String.fetchOne(db, sql: "SELECT source_app FROM screenshots WHERE id = ?", arguments: [recordID])
                }) ?? nil
            )
        } catch {
            try? await db.write { db in
                try db.execute(
                    sql: "UPDATE screenshots SET ocr_status = ? WHERE id = ?",
                    arguments: [OCRStatus.failed.rawValue, recordID]
                )
            }
        }
    }

    private func requeueInterrupted() async {
        let interrupted = (try? await db.read { db in
            try ScreenshotRecord
                .filter(Column("ocr_status") == OCRStatus.pending.rawValue ||
                        Column("ocr_status") == OCRStatus.failed.rawValue)
                .fetchAll(db)
        }) ?? []

        for record in interrupted {
            guard let id = record.id else { continue }
            let path = record.filePath
            operationQueue.addOperation { [weak self] in
                Task { await self?.process(fileURL: URL(fileURLWithPath: path), recordID: id) }
            }
        }
    }

    // Parse the actual shutter timestamp from macOS screenshot filenames.
    // Format (all locales): "… YYYY-MM-DD … HH.MM.SS [AM|PM] …"
    // The word for "Screenshot" and the separator ("at", "a las", …) vary by locale,
    // but the numeric date/time pattern is always the same.
    private static func parseCaptureDate(from url: URL) -> Date? {
        let name = url.deletingPathExtension().lastPathComponent
        let pattern = #"(\d{4})-(\d{2})-(\d{2})\D+(\d{1,2})\.(\d{2})\.(\d{2})\s*(AM|PM)?"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let m = regex.firstMatch(in: name, range: NSRange(name.startIndex..., in: name)),
              m.numberOfRanges >= 7 else { return nil }

        func str(_ i: Int) -> String? {
            let r = m.range(at: i)
            guard r.location != NSNotFound, let range = Range(r, in: name) else { return nil }
            return String(name[range])
        }

        guard let year  = Int(str(1) ?? ""),
              let month = Int(str(2) ?? ""),
              let day   = Int(str(3) ?? ""),
              var hour  = Int(str(4) ?? ""),
              let min   = Int(str(5) ?? ""),
              let sec   = Int(str(6) ?? "") else { return nil }

        if let ampm = str(7) {
            if ampm.caseInsensitiveCompare("PM") == .orderedSame && hour < 12 { hour += 12 }
            else if ampm.caseInsensitiveCompare("AM") == .orderedSame && hour == 12 { hour = 0 }
        }

        var c = DateComponents()
        c.year = year; c.month = month; c.day = day
        c.hour = hour; c.minute = min; c.second = sec
        c.timeZone = TimeZone.current
        return Calendar.current.date(from: c)
    }

    // Classify any existing screenshots that were indexed before the classifier existed.
    func classifyUntagged() async {
        await classifier.classifyUntagged()
    }

    var semanticSearchAvailable: Bool { embedder != nil }

    func screenshotCount() async -> Int {
        (try? await db.read { db in
            try ScreenshotRecord.fetchCount(db)
        }) ?? 0
    }

    func pendingCount() async -> Int {
        (try? await db.read { db in
            try ScreenshotRecord
                .filter(Column("ocr_status") == OCRStatus.pending.rawValue)
                .fetchCount(db)
        }) ?? 0
    }

    // Remove DB records (and their thumbnails) for files no longer on disk.
    // CASCADE DELETE handles embeddings, clusters, and tags automatically.
    func cleanupDeletedFiles() async {
        do {
            // Collect paths + thumbnail names for files that no longer exist
            let stale: [(path: String, thumb: String?)] = try await db.read { db in
                try Row.fetchAll(db, sql: "SELECT file_path, thumbnail_path FROM screenshots")
                    .compactMap { row -> (String, String?)? in
                        let path: String = row["file_path"]
                        guard !FileManager.default.fileExists(atPath: path) else { return nil }
                        return (path, row["thumbnail_path"])
                    }
            }
            guard !stale.isEmpty else { return }

            let stalePaths = stale.map(\.path)
            let placeholders = stalePaths.map { _ in "?" }.joined(separator: ",")
            try await db.write { db in
                try db.execute(
                    sql: "DELETE FROM screenshots WHERE file_path IN (\(placeholders))",
                    arguments: StatementArguments(stalePaths)
                )
            }

            // Remove orphaned thumbnail files
            let thumbsDir = FileManager.default
                .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Scout/Thumbnails")
            for thumb in stale.compactMap(\.thumb) {
                try? FileManager.default.removeItem(at: thumbsDir.appendingPathComponent(thumb))
            }

            print("[Cleanup] Removed \(stale.count) stale record(s)")
        } catch {
            print("[Cleanup] \(error)")
        }
    }
}
