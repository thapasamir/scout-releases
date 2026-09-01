import Foundation
import GRDB

struct TagRecord: Codable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "tags"

    var id: Int64?
    var name: String
    var kind: String

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }

    init(name: String, kind: TagKind = .auto) {
        self.name = name
        self.kind = kind.rawValue
    }
}

enum TagKind: String {
    case auto, manual, cluster
}
