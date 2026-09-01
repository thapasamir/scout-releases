import Foundation
import GRDB

struct WatchedFolderRecord: Codable, FetchableRecord, MutablePersistableRecord, Identifiable {
    static let databaseTableName = "watched_folders"
    nonisolated(unsafe) static let databaseColumnEncodingStrategy = DatabaseColumnEncodingStrategy.convertToSnakeCase
    nonisolated(unsafe) static let databaseColumnDecodingStrategy = DatabaseColumnDecodingStrategy.convertFromSnakeCase

    var id: Int64?
    var displayPath: String
    var bookmarkData: Data
    var addedAt: Double
    var isActive: Bool

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }

    init(displayPath: String, bookmarkData: Data, addedAt: Double = Date().timeIntervalSince1970, isActive: Bool = true) {
        self.displayPath = displayPath
        self.bookmarkData = bookmarkData
        self.addedAt = addedAt
        self.isActive = isActive
    }
}
