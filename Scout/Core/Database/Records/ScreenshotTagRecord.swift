import Foundation
import GRDB

struct ScreenshotTagRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "screenshot_tags"

    var screenshotId: Int64
    var tagId: Int64
    var confidence: Double

    init(screenshotId: Int64, tagId: Int64, confidence: Double = 1.0) {
        self.screenshotId = screenshotId
        self.tagId = tagId
        self.confidence = confidence
    }
}
