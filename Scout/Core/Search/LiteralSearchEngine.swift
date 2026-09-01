import Foundation
import GRDB

struct LiteralSearchEngine {
    let db: DatabasePool

    func search(query: String, limit: Int = 200) async throws -> [SearchResult] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return [] }

        return try await db.read { db in
            if trimmed.count < 2 {
                // FTS5 requires ≥2 chars; fall back to LIKE
                return try likeFallback(db: db, query: trimmed, limit: limit)
            }
            return try fts5Search(db: db, query: trimmed, limit: limit)
        }
    }

    private func fts5Search(db: Database, query: String, limit: Int) throws -> [SearchResult] {
        let escaped = query.replacingOccurrences(of: "\"", with: "\"\"")
        let ftsQuery = "\"\(escaped)\"*"
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
