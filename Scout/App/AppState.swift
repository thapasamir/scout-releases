import Foundation
import Combine
import GRDB
import AppKit

@MainActor
final class AppState: ObservableObject {
    @Published var searchResults: [SearchResult] = []
    @Published var isSearching = false
    @Published var searchMode: SearchMode = .literal
    @Published var watchedFolders: [WatchedFolderRecord] = []
    @Published var screenshotCount: Int = 0
    @Published var pendingCount: Int = 0
    @Published var selectedScreenshotPath: String?
    @Published var semanticSearchAvailable = false

    // Source apps (for sidebar listing)
    @Published var availableSourceApps: [String] = []

    // Tags
    @Published var availableTags: [String] = []

    // Auto-categories
    @Published var availableCategories: [String] = []

    // v1.2 — clusters
    @Published var clusters: [ClusterInfo] = []
    @Published var activeCluster: ClusterInfo?
    @Published var isClustering = false

    // Palette keyboard navigation
    @Published var paletteSelectedIndex: Int = 0

    // Gallery + detail view
    @Published var allScreenshots: [SearchResult] = []
    @Published var selectedResult: SearchResult?

    // Gallery keyboard navigation (-1 = nothing selected)
    @Published var galleryFocusedIndex: Int = -1
    private var galleryKeyMonitor: Any?

    // Bulk selection + delete
    @Published var isSelectMode: Bool = false
    @Published var selectedIDs: Set<Int64> = []
    @Published var showDeleteConfirm: Bool = false

    // Sidebar navigation
    @Published var sidebarSelection: SidebarItem = .all

    // Avoid reloading library on every 2-second poll tick
    private var lastLoadedScreenshotCount: Int = -1
    private var lastLoadedSidebarSelection: SidebarItem = .all

    var displayedResults: [SearchResult] {
        searchResults.isEmpty ? allScreenshots : searchResults
    }

    private var pollTask: Task<Void, Never>?
    private var hasTriggeredClustering = false
    let clustering: ClusteringEngine

    let db: DatabasePool
    let indexer: ScreenshotIndexer
    private let spotlight: SpotlightIndexer
    private let thumbnails: ThumbnailCache
    private let literalSearch: LiteralSearchEngine
    private let embedder: EmbeddingProcessor?

    init() {
        db = AppDatabase.shared.pool
        thumbnails = ThumbnailCache()
        spotlight = SpotlightIndexer(thumbnails: thumbnails)
        indexer = ScreenshotIndexer(db: db, spotlight: spotlight, thumbnails: thumbnails)
        literalSearch = LiteralSearchEngine(db: db)
        embedder = EmbeddingProcessor.makeIfAvailable()
        clustering = ClusteringEngine(db: db)
        semanticSearchAvailable = embedder != nil
    }

    // MARK: – Search

    func search(query: String, mode: SearchMode? = nil) async {
        activeCluster = nil  // clear cluster view when searching
        let effectiveMode = mode ?? searchMode
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        galleryFocusedIndex = -1
        guard !trimmed.isEmpty else { searchResults = []; return }

        isSearching = true
        defer { isSearching = false }

        paletteSelectedIndex = 0

        do {
            switch effectiveMode {
            case .literal:
                searchResults = try await literalSearch.search(query: trimmed)

            case .semantic:
                guard let embedder else {
                    // Model not available — fall back silently
                    searchResults = try await literalSearch.search(query: trimmed)
                    return
                }
                let engine = SemanticSearchEngine(db: db, embedder: embedder)
                searchResults = try await engine.search(query: trimmed)

            case .hybrid:
                // Run both in parallel, merge by de-duplicating on id, boosting shared hits
                async let literal  = literalSearch.search(query: trimmed)
                async let semantic: [SearchResult] = {
                    guard let embedder else { return [] }
                    let engine = SemanticSearchEngine(db: db, embedder: embedder)
                    return (try? await engine.search(query: trimmed)) ?? []
                }()

                let (lit, sem) = try await (literal, semantic)
                searchResults = merge(literal: lit, semantic: sem)
            }
        } catch {
            print("[Search] Error: \(error)")
            searchResults = []
        }
    }

    // Merge literal + semantic results: shared hits float to the top,
    // then remaining literal, then remaining semantic.
    private func merge(literal: [SearchResult], semantic: [SearchResult]) -> [SearchResult] {
        let semIDs = Set(semantic.map(\.id))
        let litIDs = Set(literal.map(\.id))

        var shared   = literal.filter { semIDs.contains($0.id) }
        var litOnly  = literal.filter { !semIDs.contains($0.id) }
        var semOnly  = semantic.filter { !litIDs.contains($0.id) }

        // Boost shared results' score
        for i in shared.indices { shared[i].relevanceScore += 1.0 }

        return (shared + litOnly + semOnly).prefix(200).map { $0 }
    }

    // MARK: – Folder management

    func addWatchedFolder() async {
        do {
            _ = try await indexer.addWatchedFolder()
            await refreshWatchedFolders()
        } catch BookmarkError.cancelled { }
        catch { print("[AddFolder] \(error)") }
    }

    func removeWatchedFolder(_ folder: WatchedFolderRecord, deleteData: Bool = false) async {
        let manager = BookmarkManager(db: db)
        try? await manager.deactivate(folder: folder)

        if deleteData {
            let prefix = folder.displayPath.hasSuffix("/")
                ? folder.displayPath : folder.displayPath + "/"

            let rows = (try? await db.read { db in
                try Row.fetchAll(db,
                    sql: "SELECT id, thumbnail_path FROM screenshots WHERE file_path LIKE ?",
                    arguments: ["\(prefix)%"])
            }) ?? []

            if !rows.isEmpty {
                let thumbsDir = FileManager.default
                    .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                    .appendingPathComponent("Scout/Thumbnails")

                for row in rows {
                    if let thumb: String = row["thumbnail_path"] {
                        try? FileManager.default.removeItem(
                            at: thumbsDir.appendingPathComponent(thumb))
                    }
                }

                let ids: [Int64] = rows.compactMap { $0["id"] }
                let placeholders = ids.map { _ in "?" }.joined(separator: ",")
                try? await db.write { db in
                    try db.execute(
                        sql: "DELETE FROM screenshots WHERE id IN (\(placeholders))",
                        arguments: StatementArguments(ids))
                }

                let removed = Set(ids)
                allScreenshots.removeAll { removed.contains($0.id) }
                searchResults.removeAll  { removed.contains($0.id) }
                screenshotCount = max(0, screenshotCount - rows.count)
            }
        }

        if sidebarSelection == .folder(folder.displayPath) {
            setSidebarItem(.all)
        }

        await refreshWatchedFolders()
    }

    func refreshWatchedFolders() async {
        watchedFolders = (try? await db.read { db in
            try WatchedFolderRecord.filter(Column("is_active") == true).fetchAll(db)
        }) ?? []
        screenshotCount = await indexer.screenshotCount()
        pendingCount   = await indexer.pendingCount()
        semanticSearchAvailable = await indexer.semanticSearchAvailable

        await loadSourceApps()
        await loadAllScreenshots()

        // Always keep polling — FolderWatcher enqueues new screenshots into the
        // indexer actor, but AppState only learns about them through this poll.
        startPollingIfNeeded()

        if pendingCount == 0 {
            // Auto-cluster once after first full index
            if !hasTriggeredClustering && screenshotCount > 0 && semanticSearchAvailable {
                hasTriggeredClustering = true
                Task { await recluster() }
            } else if clusters.isEmpty && screenshotCount > 0 {
                clusters = (try? await clustering.loadExisting()) ?? []
            }

            // Backfill categories for any screenshots indexed before classifier existed
            if screenshotCount > 0 && availableCategories.isEmpty {
                Task {
                    await indexer.classifyUntagged()
                    await loadAvailableCategories()
                }
            }
        }
    }

    private func startPollingIfNeeded() {
        guard pollTask == nil || pollTask!.isCancelled else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard let self, !Task.isCancelled else { return }
                await self.refreshWatchedFolders()
            }
        }
    }


    func loadAllScreenshots() async {
        // Skip if nothing changed (called every 2s during indexing)
        guard screenshotCount != lastLoadedScreenshotCount
                || sidebarSelection != lastLoadedSidebarSelection else { return }
        lastLoadedScreenshotCount = screenshotCount
        lastLoadedSidebarSelection = sidebarSelection

        let since: Date?
        let until: Date?
        let folderPath: String?
        let sourceApp: String?
        let tag: String?
        let category: String?

        switch sidebarSelection {
        case .all:
            since = nil; until = nil; folderPath = nil; sourceApp = nil; tag = nil; category = nil
        case .date(let df):
            since = df.since; until = nil; folderPath = nil; sourceApp = nil; tag = nil; category = nil
        case .dateRange(let from, let to):
            since = from; until = to; folderPath = nil; sourceApp = nil; tag = nil; category = nil
        case .folder(let path):
            since = nil; until = nil; folderPath = path; sourceApp = nil; tag = nil; category = nil
        case .app(let app):
            since = nil; until = nil; folderPath = nil; sourceApp = app; tag = nil; category = nil
        case .tag(let t):
            since = nil; until = nil; folderPath = nil; sourceApp = nil; tag = t; category = nil
        case .category(let c):
            since = nil; until = nil; folderPath = nil; sourceApp = nil; tag = nil; category = c
        }

        allScreenshots = (try? await literalSearch.loadAll(
            since: since, until: until, folderPath: folderPath,
            sourceApp: sourceApp, tag: tag, category: category
        )) ?? []
    }

    func setSidebarItem(_ item: SidebarItem) {
        sidebarSelection = item
        lastLoadedSidebarSelection = .all  // force reload on next call
        galleryFocusedIndex = -1
        searchResults = []
        Task { await loadAllScreenshots() }
    }

    // Keep for backward compat (dateFilter chips removed, but search() may use it)
    func setDateFilter(_ filter: DateFilter) {
        setSidebarItem(filter == .all ? .all : .date(filter))
    }

    func findSimilar(to result: SearchResult) async {
        guard let embedder else { return }
        selectedResult = nil
        isSearching = true
        defer { isSearching = false }
        galleryFocusedIndex = -1
        do {
            let engine = SemanticSearchEngine(db: db, embedder: embedder)
            searchResults = try await engine.findSimilar(to: result.id)
        } catch {
            print("[FindSimilar] \(error)")
            searchResults = []
        }
    }

    // MARK: – Selection + Delete

    func toggleSelectMode() {
        isSelectMode.toggle()
        if !isSelectMode { selectedIDs.removeAll() }
    }

    func toggleSelection(_ id: Int64) {
        if selectedIDs.contains(id) { selectedIDs.remove(id) }
        else { selectedIDs.insert(id) }
    }

    func deleteScreenshots(ids: Set<Int64>) async {
        guard !ids.isEmpty else { return }
        let idArray = Array(ids)
        let placeholders = idArray.map { _ in "?" }.joined(separator: ",")

        let rows = (try? await db.read { db in
            try Row.fetchAll(db,
                sql: "SELECT file_path, thumbnail_path FROM screenshots WHERE id IN (\(placeholders))",
                arguments: StatementArguments(idArray))
        }) ?? []

        let thumbsDir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Scout/Thumbnails")

        for row in rows {
            let path: String = row["file_path"]
            try? FileManager.default.removeItem(atPath: path)
            if let thumb: String = row["thumbnail_path"] {
                try? FileManager.default.removeItem(at: thumbsDir.appendingPathComponent(thumb))
            }
        }

        try? await db.write { db in
            try db.execute(
                sql: "DELETE FROM screenshots WHERE id IN (\(placeholders))",
                arguments: StatementArguments(idArray)
            )
        }

        allScreenshots.removeAll { ids.contains($0.id) }
        searchResults.removeAll { ids.contains($0.id) }
        screenshotCount = max(0, screenshotCount - rows.count)
        selectedIDs.removeAll()
        isSelectMode = false
        showDeleteConfirm = false
        lastLoadedScreenshotCount = -1
    }

    // MARK: – Gallery keyboard navigation

    func installGalleryKeyMonitor() {
        guard galleryKeyMonitor == nil else { return }
        galleryKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return self.handleGalleryKey(event)
        }
    }

    func removeGalleryKeyMonitor() {
        if let m = galleryKeyMonitor { NSEvent.removeMonitor(m); galleryKeyMonitor = nil }
    }

    private func handleGalleryKey(_ event: NSEvent) -> NSEvent? {
        guard let window = NSApp.keyWindow,
              window.identifier?.rawValue == "main" else { return event }

        // Let text fields keep all keystrokes
        let fr = window.firstResponder
        if fr is NSTextField || fr is NSText { return event }

        let results = displayedResults
        guard !results.isEmpty else { return event }

        // Estimate column count from window width (card min 210 + 16 spacing + 32 padding)
        let colCount = max(1, Int((window.frame.width - 16) / 226))
        let cur = galleryFocusedIndex

        switch event.keyCode {
        case 123: // ←
            galleryFocusedIndex = max(0, cur < 0 ? 0 : cur - 1)
            return nil
        case 124: // →
            galleryFocusedIndex = min(results.count - 1, cur < 0 ? 0 : cur + 1)
            return nil
        case 126: // ↑
            galleryFocusedIndex = max(0, cur < 0 ? 0 : cur - colCount)
            return nil
        case 125: // ↓ — only intercept if QL is not open (↓ in QL should advance its own list)
            guard !QuickLookBridge.shared.isVisible else { return event }
            galleryFocusedIndex = min(results.count - 1, cur < 0 ? 0 : cur + colCount)
            return nil
        case 49: // Space — toggle Quick Look for focused/first result
            let idx = cur < 0 ? 0 : cur
            if idx < results.count {
                if cur < 0 { galleryFocusedIndex = 0 }
                QuickLookBridge.shared.toggle(urls: results.map(\.fileURL), at: idx)
            }
            return nil
        case 36, 76: // Return / KP Return — open detail view
            let idx = cur < 0 ? 0 : cur
            if idx < results.count { selectedResult = results[idx] }
            return nil
        case 51: // Delete/Backspace — confirm delete in select mode
            if isSelectMode && !selectedIDs.isEmpty {
                showDeleteConfirm = true
                return nil
            }
            return event
        case 53: // Escape — exit select mode, close QL, or clear focus
            if isSelectMode {
                toggleSelectMode()
                return nil
            }
            if QuickLookBridge.shared.isVisible {
                QuickLookBridge.shared.dismiss()
                return nil
            }
            if galleryFocusedIndex >= 0 {
                galleryFocusedIndex = -1
                return nil
            }
            return event
        default:
            return event
        }
    }

    private func loadSourceApps() async {
        availableSourceApps = (try? await db.read { db in
            try String.fetchAll(db, sql: """
                SELECT DISTINCT source_app FROM screenshots
                WHERE source_app IS NOT NULL AND ocr_status = 'done'
                ORDER BY source_app
            """)
        }) ?? []
        await loadAvailableTags()
    }

    private func loadAvailableTags() async {
        availableTags = (try? await db.read { db in
            try String.fetchAll(db, sql: """
                SELECT DISTINCT t.name FROM tags t
                JOIN screenshot_tags st ON st.tag_id = t.id
                WHERE t.kind = 'manual'
                ORDER BY t.name
            """)
        }) ?? []
        await loadAvailableCategories()
    }

    private func loadAvailableCategories() async {
        let raw = (try? await db.read { db in
            try String.fetchAll(db, sql: """
                SELECT DISTINCT t.name FROM tags t
                JOIN screenshot_tags st ON st.tag_id = t.id
                WHERE t.kind = 'auto'
                ORDER BY t.name
            """)
        }) ?? []
        // Sort by the canonical category order rather than alphabetically
        let order = ScreenshotCategory.allCases.map(\.rawValue)
        availableCategories = raw.sorted { a, b in
            let ia = order.firstIndex(of: a) ?? Int.max
            let ib = order.firstIndex(of: b) ?? Int.max
            return ia < ib
        }
    }

    // MARK: – Tags

    func tagsForScreenshot(_ id: Int64) async -> [String] {
        (try? await db.read { db in
            try String.fetchAll(db, sql: """
                SELECT t.name FROM tags t
                JOIN screenshot_tags st ON st.tag_id = t.id
                WHERE st.screenshot_id = ?
                ORDER BY t.name
            """, arguments: [id])
        }) ?? []
    }

    func addTag(_ name: String, to screenshotId: Int64) async {
        let trimmed = name.trimmingCharacters(in: .whitespaces).lowercased()
        guard !trimmed.isEmpty else { return }
        try? await db.write { db in
            try db.execute(
                sql: "INSERT OR IGNORE INTO tags (name, kind) VALUES (?, 'manual')",
                arguments: [trimmed])
            let tagId = try Int64.fetchOne(db,
                sql: "SELECT id FROM tags WHERE name = ?",
                arguments: [trimmed])!
            try db.execute(
                sql: "INSERT OR IGNORE INTO screenshot_tags (screenshot_id, tag_id, confidence) VALUES (?, ?, 1.0)",
                arguments: [screenshotId, tagId])
        }
        await loadAvailableTags()
    }

    func removeTag(_ name: String, from screenshotId: Int64) async {
        try? await db.write { db in
            try db.execute(sql: """
                DELETE FROM screenshot_tags
                WHERE screenshot_id = ?
                  AND tag_id = (SELECT id FROM tags WHERE name = ?)
            """, arguments: [screenshotId, name])
            // Remove orphaned manual tags
            try db.execute(sql: """
                DELETE FROM tags
                WHERE kind = 'manual'
                  AND id NOT IN (SELECT DISTINCT tag_id FROM screenshot_tags)
            """)
        }
        // If we're viewing this tag in the sidebar and it's now empty, go back to All
        if case .tag(let t) = sidebarSelection, t == name, !availableTags.contains(name) {
            setSidebarItem(.all)
        }
        await loadAvailableTags()
    }

    // MARK: – Clusters

    func recluster() async {
        guard !isClustering else { return }
        isClustering = true
        defer { isClustering = false }
        clusters = (try? await clustering.cluster()) ?? []
    }

    func showCluster(_ cluster: ClusterInfo?) async {
        activeCluster = cluster
        guard let cluster else { searchResults = []; return }
        isSearching = true
        defer { isSearching = false }
        searchResults = (try? await clustering.screenshots(inCluster: cluster.id)) ?? []
    }

    func reindexAll() async {
        try? await db.write { db in
            try db.execute(sql: "UPDATE screenshots SET ocr_status = 'pending'")
        }
        await spotlight.deleteAll()
        await indexer.resolveBookmarksAndStartWatching()
    }

    // MARK: – Deep-link from Spotlight

    func openScreenshot(atPath path: String) {
        selectedScreenshotPath = path
        NSApp.activate(ignoringOtherApps: true)
    }
}

// MARK: – Date filter

enum DateFilter: String, CaseIterable, Equatable {
    case all = "All"
    case today = "Today"
    case week = "This Week"
    case month = "This Month"

    var since: Date? {
        let cal = Calendar.current
        let now = Date()
        switch self {
        case .all:   return nil
        case .today: return cal.startOfDay(for: now)
        case .week:  return cal.date(byAdding: .weekOfYear, value: -1, to: now)
        case .month: return cal.date(byAdding: .month, value: -1, to: now)
        }
    }
}

// MARK: – Sidebar navigation item

enum SidebarItem: Hashable {
    case all
    case date(DateFilter)
    case dateRange(from: Date, to: Date)
    case folder(String)      // displayPath
    case app(String)         // source app name
    case tag(String)
    case category(String)    // auto-category name
}
