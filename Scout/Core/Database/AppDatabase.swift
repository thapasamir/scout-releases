import Foundation
import GRDB

final class AppDatabase: @unchecked Sendable {
    static let shared: AppDatabase = {
        do {
            return try AppDatabase()
        } catch {
            fatalError("Failed to open database: \(error)")
        }
    }()

    let pool: DatabasePool

    private init() throws {
        let dbURL = Self.databaseURL()
        var config = Configuration()
        #if DEBUG
        config.prepareDatabase { db in
            db.trace { event in
                if case .statement(let statement) = event {
                    print("[SQL] \(statement)")
                }
            }
        }
        #endif
        pool = try DatabasePool(path: dbURL.path, configuration: config)
        try Migrations.migrate(pool)
    }

    static func databaseURL() -> URL {
        let support = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Scout", isDirectory: true)
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        return support.appendingPathComponent("screenshots.db")
    }
}
