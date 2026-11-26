import Foundation
import GRDB

struct LiteralSearchEngine {
    let db: DatabasePool

    func search(query: String, limit: Int = 200) async throws -> [SearchResult] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return [] }

        return try await db.read { db in
            if trimmed.count < 2 {
                return try likeFallback(db: db, query: trimmed, limit: limit)
            }
            return try fts5Search(db: db, query: trimmed, limit: limit)
        }
    }

    // MARK: – Query building

    // Common English words that add noise when required as AND terms.
    private static let stopWords: Set<String> = [
        "a", "an", "the", "is", "it", "in", "on", "at", "to", "for",
        "of", "and", "or", "but", "with", "from", "by", "as", "be",
        "was", "are", "were", "been", "has", "have", "had", "do", "did",
        "does", "will", "would", "could", "should", "may", "might", "can",
        "this", "that", "these", "those", "i", "my", "we", "you", "am",
        "so", "if", "no", "not", "up", "out", "its"
    ]

    // Returns meaningful search terms: lowercased, punctuation-stripped, stop-words removed.
    // Falls back to the original token list if everything gets filtered (rare for short queries).
    private func searchTerms(from query: String) -> [String] {
        let all = query
            .lowercased()
            .components(separatedBy: .whitespaces)
            .map { $0.trimmingCharacters(in: .punctuationCharacters) }
            .filter { $0.count >= 2 }

        let filtered = all.filter { !Self.stopWords.contains($0) }
        return filtered.isEmpty ? all : filtered
    }

    private func escapeFTS(_ word: String) -> String {
        word.replacingOccurrences(of: "\"", with: "\"\"")
    }

    // MARK: – FTS5 search

    private func fts5Search(db: Database, query: String, limit: Int) throws -> [SearchResult] {
        let terms = searchTerms(from: query)
        guard !terms.isEmpty else { return [] }

        // AND of all meaningful terms — words can appear in any order.
        let andQuery = terms.map { "\"\(escapeFTS($0))\"*" }.joined(separator: " ")
        var results = try runFTS(db: db, ftsQuery: andQuery, limit: limit)

        // Phrase boost: if results also contain the words as an exact adjacent
        // phrase, promote them to the top (more negative BM25 = better rank).
        if terms.count > 1 {
            let phraseQuery = "\"" + terms.map(escapeFTS).joined(separator: " ") + "\""
            let phraseIDs = Set(try runFTS(db: db, ftsQuery: phraseQuery, limit: limit).map(\.id))
            if !phraseIDs.isEmpty {
                results = results.map { r in
                    guard phraseIDs.contains(r.id) else { return r }
                    var copy = r
                    copy.relevanceScore -= abs(copy.relevanceScore) * 0.5
                    return copy
                }
                .sorted { $0.relevanceScore < $1.relevanceScore }
            }
        }

        // OR fallback: if AND found nothing, widen to any-term match so the
        // user always gets something rather than a blank result.
        if results.isEmpty && terms.count > 1 {
            let orQuery = terms.map { "\"\(escapeFTS($0))\"*" }.joined(separator: " OR ")
            results = try runFTS(db: db, ftsQuery: orQuery, limit: limit)
        }

        return results
    }

    private func runFTS(db: Database, ftsQuery: String, limit: Int) throws -> [SearchResult] {
        let sql = """
            SELECT s.id, s.file_path, s.file_name, s.file_created_at,
                   s.ocr_text, s.thumbnail_path, s.source_app,
                   fts.rank AS rank
            FROM screenshots s
            JOIN screenshots_fts fts ON fts.rowid = s.id
            WHERE screenshots_fts MATCH ?
              AND s.ocr_status = 'done'
            ORDER BY rank
            LIMIT ?
        """
        let rows = try Row.fetchAll(db, sql: sql, arguments: [ftsQuery, limit])
        return rows.map(makeResult)
    }

    private func likeFallback(db: Database, query: String, limit: Int) throws -> [SearchResult] {
        let sql = """
            SELECT id, file_path, file_name, file_created_at,
                   ocr_text, thumbnail_path, source_app
            FROM screenshots
            WHERE ocr_text LIKE ? AND ocr_status = 'done'
            ORDER BY file_created_at DESC
            LIMIT ?
        """
        let rows = try Row.fetchAll(db, sql: sql, arguments: ["%\(query)%", limit])
        return rows.map(makeResult)
    }

    // MARK: – loadAll (sidebar / browse, no query)

    func loadAll(
        limit: Int = 200,
        since: Date? = nil,
        until: Date? = nil,
        folderPath: String? = nil,
        sourceApp: String? = nil,
        tag: String? = nil,
        category: String? = nil
    ) async throws -> [SearchResult] {
        try await db.read { db in
            var conditions = ["ocr_status = 'done'"]
            var args: [DatabaseValueConvertible] = []

            if let since {
                conditions.append("file_created_at >= ?")
                args.append(since.timeIntervalSince1970)
            }
            if let until {
                conditions.append("file_created_at <= ?")
                args.append(until.timeIntervalSince1970)
            }
            if let folderPath {
                conditions.append("file_path LIKE ?")
                args.append(folderPath + "%")
            }
            if let sourceApp {
                conditions.append("source_app = ?")
                args.append(sourceApp)
            }
            if let tagName = tag {
                conditions.append("EXISTS (SELECT 1 FROM screenshot_tags st JOIN tags t ON t.id = st.tag_id WHERE st.screenshot_id = s.id AND t.name = ? AND t.kind = 'manual')")
                args.append(tagName)
            }
            if let categoryName = category {
                conditions.append("EXISTS (SELECT 1 FROM screenshot_tags st JOIN tags t ON t.id = st.tag_id WHERE st.screenshot_id = s.id AND t.name = ? AND t.kind = 'auto')")
                args.append(categoryName)
            }

            let where_ = conditions.joined(separator: " AND ")
            let sql = """
                SELECT s.id, s.file_path, s.file_name, s.file_created_at,
                       s.ocr_text, s.thumbnail_path, s.source_app
                FROM screenshots s
                WHERE \(where_)
                ORDER BY s.file_created_at DESC
                LIMIT ?
            """
            args.append(limit)
            let rows = try Row.fetchAll(db, sql: sql, arguments: StatementArguments(args))
            return rows.map(makeResult)
        }
    }

    // MARK: – Helpers

    private func makeResult(from row: Row) -> SearchResult {
        SearchResult(
            id: row["id"],
            filePath: row["file_path"],
            fileName: row["file_name"],
            fileCreatedAt: row["file_created_at"],
            ocrText: row["ocr_text"],
            thumbnailPath: row["thumbnail_path"],
            sourceApp: row["source_app"],
            relevanceScore: (row["rank"] as Double?) ?? 0.0
        )
    }
}
