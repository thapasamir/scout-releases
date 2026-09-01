import Foundation
import GRDB

struct ScreenshotRecord: Codable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "screenshots"
    nonisolated(unsafe) static let databaseColumnEncodingStrategy = DatabaseColumnEncodingStrategy.convertToSnakeCase
    nonisolated(unsafe) static let databaseColumnDecodingStrategy = DatabaseColumnDecodingStrategy.convertFromSnakeCase

    var id: Int64?
    var filePath: String
    var fileName: String
    var fileSize: Int?
    var width: Int?
    var height: Int?
    var fileCreatedAt: Double
    var fileModifiedAt: Double
    var indexedAt: Double
    var ocrText: String?
    var ocrConfidence: Double?
    var ocrStatus: String
    var spotlightIndexed: Bool
    var sourceApp: String?
    var sourceWindowTitle: String?
    var lastAccessedAt: Double?
    var hasSensitiveData: Bool
    var thumbnailPath: String?

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }

    init(fileURL: URL, status: String = "pending") {
        let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path)
        let now = Date().timeIntervalSince1970
        self.filePath = fileURL.path
        self.fileName = fileURL.lastPathComponent
        self.fileSize = attrs?[.size] as? Int
        self.fileCreatedAt = (attrs?[.creationDate] as? Date)?.timeIntervalSince1970 ?? now
        self.fileModifiedAt = (attrs?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? now
        self.indexedAt = now
        self.ocrStatus = status
        self.spotlightIndexed = false
        self.hasSensitiveData = false
    }
}

enum OCRStatus: String {
    case pending, done, failed, skipped
}
