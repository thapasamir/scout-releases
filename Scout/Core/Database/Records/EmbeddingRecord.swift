import Foundation
import GRDB

struct EmbeddingRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "embeddings"
    nonisolated(unsafe) static let databaseColumnEncodingStrategy = DatabaseColumnEncodingStrategy.convertToSnakeCase
    nonisolated(unsafe) static let databaseColumnDecodingStrategy = DatabaseColumnDecodingStrategy.convertFromSnakeCase

    var screenshotId: Int64
    var modelId: String
    var vector: Data
    var computedAt: Double

    init(screenshotId: Int64, modelId: String, vector: [Float], computedAt: Double = Date().timeIntervalSince1970) {
        self.screenshotId = screenshotId
        self.modelId = modelId
        self.vector = vector.withUnsafeBufferPointer { Data(buffer: $0) }
        self.computedAt = computedAt
    }

    var floatVector: [Float] {
        vector.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
    }
}
