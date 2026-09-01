import Accelerate
import GRDB

struct ClusterInfo: Identifiable, Sendable {
    let id: Int64
    let label: String
    let count: Int
}

actor ClusteringEngine {
    private let db: DatabasePool
    private static let k = 8
    private static let maxIterations = 30
    private static let dim = 384

    init(db: DatabasePool) {
        self.db = db
    }

    func cluster() async throws -> [ClusterInfo] {
        let rows: [(id: Int64, vector: [Float])] = try await db.read { db in
            try Row.fetchAll(db, sql: "SELECT screenshot_id, vector FROM embeddings")
                .map { row -> (Int64, [Float]) in
                    let id: Int64 = row["screenshot_id"]
                    let data: Data = row["vector"]
                    let floats = data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
                    return (id, floats)
                }
        }

        guard rows.count >= Self.k else { return [] }

        let ids     = rows.map(\.id)
        let vectors = rows.map(\.vector)
        let n       = rows.count

        var centroids  = pickInitialCentroids(vectors: vectors)
        var assignments = [Int](repeating: 0, count: n)

        for _ in 0..<Self.maxIterations {
            let next = assign(vectors: vectors, centroids: centroids)
            if next == assignments { break }
            assignments = next
            centroids = updateCentroids(vectors: vectors, assignments: assignments)
        }

        // Load OCR text for cluster naming
        let texts: [Int64: String] = try await db.read { db in
            var map: [Int64: String] = [:]
            let rows = try Row.fetchAll(db,
                sql: "SELECT id, ocr_text FROM screenshots WHERE ocr_status = 'done' AND ocr_text IS NOT NULL")
            for row in rows { map[row["id"]] = row["ocr_text"] ?? "" }
            return map
        }

        // Write clusters to DB
        // Snapshot mutable vars into lets before crossing into db.write closure
        let finalAssignments = assignments
        let finalCentroids = centroids

        let infos: [ClusterInfo] = try await db.write { db -> [ClusterInfo] in
            try db.execute(sql: "DELETE FROM screenshot_clusters")
            try db.execute(sql: "DELETE FROM clusters")

            var result: [ClusterInfo] = []
            for c in 0..<Self.k {
                let memberIndices = (0..<n).filter { finalAssignments[$0] == c }
                guard !memberIndices.isEmpty else { continue }

                let memberIDs = memberIndices.map { ids[$0] }
                let combinedText = memberIDs.compactMap { texts[$0] }.joined(separator: " ")
                let label = ClusteringEngine.topKeywords(from: combinedText)

                var record = ClusterRecord(label: label, centroid: finalCentroids[c])
                try record.insert(db)
                guard let clusterID = record.id else { continue }

                for idx in memberIndices {
                    let dot = vDSP.dot(vectors[idx], finalCentroids[c])
                    try ScreenshotClusterRecord(
                        screenshotId: ids[idx],
                        clusterId: clusterID,
                        distance: Double(1.0 - dot)
                    ).insert(db)
                }

                result.append(ClusterInfo(id: clusterID, label: label, count: memberIDs.count))
            }
            return result.sorted { $0.count > $1.count }
        }

        return infos
    }

    func loadExisting() async throws -> [ClusterInfo] {
        try await db.read { db in
            let clusters = try ClusterRecord.fetchAll(db)
            return try clusters.compactMap { cluster -> ClusterInfo? in
                guard let id = cluster.id else { return nil }
                let count = try ScreenshotClusterRecord
                    .filter(Column("cluster_id") == id)
                    .fetchCount(db)
                return ClusterInfo(id: id, label: cluster.label, count: count)
            }
            .sorted { $0.count > $1.count }
        }
    }

    func screenshots(inCluster clusterID: Int64, limit: Int = 200) async throws -> [SearchResult] {
        try await db.read { db in
            let sql = """
                SELECT s.id, s.file_path, s.file_name, s.file_created_at,
                       s.ocr_text, s.thumbnail_path, s.source_app,
                       sc.distance
                FROM screenshots s
                JOIN screenshot_clusters sc ON sc.screenshot_id = s.id
                WHERE sc.cluster_id = ?
                  AND s.ocr_status = 'done'
                ORDER BY sc.distance ASC
                LIMIT ?
            """
            return try Row.fetchAll(db, sql: sql, arguments: [clusterID, limit])
                .map { row -> SearchResult in
                    SearchResult(
                        id: row["id"],
                        filePath: row["file_path"],
                        fileName: row["file_name"],
                        fileCreatedAt: row["file_created_at"],
                        ocrText: row["ocr_text"],
                        thumbnailPath: row["thumbnail_path"],
                        sourceApp: row["source_app"],
                        relevanceScore: 1.0 - (row["distance"] as Double? ?? 0)
                    )
                }
        }
    }

    // MARK: – K-means internals

    private func pickInitialCentroids(vectors: [[Float]]) -> [[Float]] {
        var centroids: [[Float]] = []
        var used = Set<Int>()

        let first = Int.random(in: 0..<vectors.count)
        centroids.append(vectors[first])
        used.insert(first)

        while centroids.count < Self.k {
            var best = 0
            var bestDist: Float = -1
            for i in 0..<vectors.count where !used.contains(i) {
                let maxSim = centroids.map { vDSP.dot(vectors[i], $0) }.max() ?? 0
                let dist = 1.0 - maxSim
                if dist > bestDist { bestDist = dist; best = i }
            }
            centroids.append(vectors[best])
            used.insert(best)
        }
        return centroids
    }

    private func assign(vectors: [[Float]], centroids: [[Float]]) -> [Int] {
        vectors.map { v in
            var best = 0
            var bestDot: Float = -2
            for (c, centroid) in centroids.enumerated() {
                let dot = vDSP.dot(v, centroid)
                if dot > bestDot { bestDot = dot; best = c }
            }
            return best
        }
    }

    private func updateCentroids(vectors: [[Float]], assignments: [Int]) -> [[Float]] {
        (0..<Self.k).map { c in
            let members = (0..<vectors.count).filter { assignments[$0] == c }
            guard !members.isEmpty else { return [Float](repeating: 0, count: Self.dim) }

            var sum = [Float](repeating: 0, count: Self.dim)
            for idx in members {
                for d in 0..<Self.dim { sum[d] += vectors[idx][d] }
            }
            let invN = 1.0 / Float(members.count)
            sum = sum.map { $0 * invN }

            // L2 normalise
            let norm = sqrt(vDSP.dot(sum, sum))
            return norm > 0 ? sum.map { $0 / norm } : sum
        }
    }

    private static func topKeywords(from text: String, count: Int = 3) -> String {
        let stop: Set<String> = [
            "the","a","an","and","or","but","in","on","at","to","for","of","with",
            "is","are","was","were","be","it","this","that","from","by","not","you",
            "we","i","my","as","have","has","can","will","do","if","all","any","so",
            "no","up","he","she","they","his","her","our","your","its","been","had",
            "would","could","should","may","might","just","than","then","when","also"
        ]
        var freq: [String: Int] = [:]
        for word in text.lowercased().components(separatedBy: .whitespacesAndNewlines) {
            let w = word.trimmingCharacters(in: .punctuationCharacters)
            guard w.count >= 4, !stop.contains(w), w.allSatisfy(\.isLetter) else { continue }
            freq[w, default: 0] += 1
        }
        let top = freq.sorted { $0.value > $1.value }.prefix(count).map { $0.key.capitalized }
        return top.isEmpty ? "Miscellaneous" : top.joined(separator: " · ")
    }
}
