import Foundation
import GRDB

struct ClusterRecord: Codable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "clusters"
    nonisolated(unsafe) static let databaseColumnEncodingStrategy = DatabaseColumnEncodingStrategy.convertToSnakeCase
    nonisolated(unsafe) static let databaseColumnDecodingStrategy = DatabaseColumnDecodingStrategy.convertFromSnakeCase

    var id: Int64?
    var label: String
    var centroid: Data?
    var createdAt: Double

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }

    init(label: String, centroid: [Float]? = nil, createdAt: Double = Date().timeIntervalSince1970) {
        self.label = label
        self.centroid = centroid.map { $0.withUnsafeBufferPointer { Data(buffer: $0) } }
        self.createdAt = createdAt
    }
}

struct ScreenshotClusterRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "screenshot_clusters"
    nonisolated(unsafe) static let databaseColumnEncodingStrategy = DatabaseColumnEncodingStrategy.convertToSnakeCase
    nonisolated(unsafe) static let databaseColumnDecodingStrategy = DatabaseColumnDecodingStrategy.convertFromSnakeCase

    var screenshotId: Int64
    var clusterId: Int64
    var distance: Double?
}
