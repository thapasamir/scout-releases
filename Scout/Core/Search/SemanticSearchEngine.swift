import Foundation
import Accelerate
import GRDB

// Implemented in v1.1 once the Core ML model is bundled.
struct SemanticSearchEngine {
    let db: DatabasePool
    let embedder: EmbeddingProcessor

    func search(query: String, topK: Int = 50) async throws -> [SearchResult] {
        let queryVector = try await embedder.embed(query)

        let stored: [(id: Int64, vector: [Float])] = try await db.read { db in
            try Row.fetchAll(db, sql: "SELECT screenshot_id, vector FROM embeddings")
                .map { row in
                    let id: Int64 = row["screenshot_id"]
                    let data: Data = row["vector"]
                    let floats = data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
                    return (id, floats)
                }
        }

        guard !stored.isEmpty else { return [] }

        // Brute-force cosine similarity — vectors are L2-normalized, so dot product = cosine
        let scores: [(id: Int64, score: Float)] = stored
            .map { entry -> (id: Int64, score: Float) in
                let len = min(queryVector.count, entry.vector.count)
                let dot = vDSP.dot(Array(queryVector.prefix(len)), Array(entry.vector.prefix(len)))
                return (id: entry.id, score: dot)
            }
            .sorted { $0.score > $1.score }
            .prefix(topK)
            .map { $0 }

        let ids = scores.map(\.id)
        let scoreMap = Dictionary(uniqueKeysWithValues: scores.map { ($0.id, Double($0.score)) })

        let screenshots = try await db.read { db in
            try ScreenshotRecord
                .filter(ids.contains(Column("id")))
                .fetchAll(db)
        }

        return screenshots.compactMap { record -> SearchResult? in
            guard let id = record.id else { return nil }
            return SearchResult(
                id: id,
                filePath: record.filePath,
                fileName: record.fileName,
                fileCreatedAt: record.fileCreatedAt,
                ocrText: record.ocrText,
                thumbnailPath: record.thumbnailPath,
                sourceApp: record.sourceApp,
                relevanceScore: scoreMap[id] ?? 0
            )
        }
        .sorted { $0.relevanceScore > $1.relevanceScore }
    }

    func findSimilar(to screenshotId: Int64, topK: Int = 50) async throws -> [SearchResult] {
        // Load the source embedding
        guard let sourceVector = try await db.read({ db -> [Float]? in
            guard let row = try Row.fetchOne(
                db, sql: "SELECT vector FROM embeddings WHERE screenshot_id = ?",
                arguments: [screenshotId]
            ) else { return nil }
            let data: Data = row["vector"]
            return data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
        }) else { return [] }

        // Load all other embeddings
        let stored: [(id: Int64, vector: [Float])] = try await db.read { db in
            try Row.fetchAll(
                db, sql: "SELECT screenshot_id, vector FROM embeddings WHERE screenshot_id != ?",
                arguments: [screenshotId]
            ).map { row in
                let id: Int64 = row["screenshot_id"]
                let data: Data = row["vector"]
                let floats = data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
                return (id, floats)
            }
        }
        guard !stored.isEmpty else { return [] }

        let scores: [(id: Int64, score: Float)] = stored
            .map { entry in
                let len = min(sourceVector.count, entry.vector.count)
                let dot = vDSP.dot(Array(sourceVector.prefix(len)), Array(entry.vector.prefix(len)))
                return (id: entry.id, score: dot)
            }
            .sorted { $0.score > $1.score }
            .prefix(topK)
            .map { $0 }

        let ids = scores.map(\.id)
        let scoreMap = Dictionary(uniqueKeysWithValues: scores.map { ($0.id, Double($0.score)) })

        let screenshots = try await db.read { db in
            try ScreenshotRecord.filter(ids.contains(Column("id"))).fetchAll(db)
        }

        return screenshots.compactMap { record -> SearchResult? in
            guard let id = record.id else { return nil }
            return SearchResult(
                id: id, filePath: record.filePath, fileName: record.fileName,
                fileCreatedAt: record.fileCreatedAt, ocrText: record.ocrText,
                thumbnailPath: record.thumbnailPath, sourceApp: record.sourceApp,
                relevanceScore: scoreMap[id] ?? 0
            )
        }
        .sorted { $0.relevanceScore > $1.relevanceScore }
    }
}
