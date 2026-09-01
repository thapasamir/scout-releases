import Cocoa
import QuickLookUI
import SQLite3
import SwiftUI

@MainActor
final class PreviewViewController: NSViewController, @preconcurrency QLPreviewingController {

    func preparePreviewOfFile(at url: URL, completionHandler handler: @escaping (Error?) -> Void) {
        let ocrText = fetchOCRText(for: url)

        let preview = ScreenshotPreviewView(imageURL: url, ocrText: ocrText)
        let hosting = NSHostingController(rootView: preview)
        addChild(hosting)
        hosting.view.frame = view.bounds
        hosting.view.autoresizingMask = [.width, .height]
        view.addSubview(hosting.view)

        handler(nil)
    }

    private func fetchOCRText(for url: URL) -> String? {
        let support = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dbPath = support
            .appendingPathComponent("Scout/screenshots.db").path

        var db: OpaquePointer?
        guard sqlite3_open_v2(dbPath, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_close(db) }

        let sql = "SELECT ocr_text FROM screenshots WHERE file_path = ? AND ocr_status = 'done' LIMIT 1"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_text(statement, 1, url.path, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }

        return sqlite3_column_text(statement, 0).map { String(cString: $0) }
    }
}

private struct ScreenshotPreviewView: View {
    let imageURL: URL
    let ocrText: String?

    var body: some View {
        HSplitView {
            AsyncImage(url: imageURL) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                default:
                    Color.secondary.opacity(0.1)
                }
            }
            .frame(minWidth: 200)

            if let text = ocrText, !text.isEmpty {
                ScrollView {
                    Text(text)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(minWidth: 200)
            }
        }
    }
}
