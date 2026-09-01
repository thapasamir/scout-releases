import AppKit
import Foundation

actor ThumbnailCache {
    let cacheDirectory: URL

    init() {
        let support = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Scout/Thumbnails", isDirectory: true)
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        cacheDirectory = support
    }

    func generate(for screenshotURL: URL, id: Int64) async -> String? {
        let fileName = "\(id).jpg"
        let dest = cacheDirectory.appendingPathComponent(fileName)

        if FileManager.default.fileExists(atPath: dest.path) {
            return fileName
        }

        guard let image = NSImage(contentsOf: screenshotURL),
              let data = image.thumbnailJPEGData(maxDimension: 200) else {
            return nil
        }

        try? data.write(to: dest)
        return fileName
    }

    func url(for relativePath: String) -> URL {
        cacheDirectory.appendingPathComponent(relativePath)
    }
}

private extension NSImage {
    func thumbnailJPEGData(maxDimension: CGFloat) -> Data? {
        let scale = min(maxDimension / size.width, maxDimension / size.height, 1.0)
        let newSize = NSSize(width: size.width * scale, height: size.height * scale)
        let thumb = NSImage(size: newSize)
        thumb.lockFocus()
        draw(in: NSRect(origin: .zero, size: newSize),
             from: NSRect(origin: .zero, size: size),
             operation: .copy, fraction: 1.0)
        thumb.unlockFocus()
        return thumb.tiffRepresentation.flatMap {
            NSBitmapImageRep(data: $0)?.representation(using: .jpeg, properties: [.compressionFactor: 0.75])
        }
    }
}
