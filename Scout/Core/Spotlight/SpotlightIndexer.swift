import CoreSpotlight
import AppKit

actor SpotlightIndexer {
    private let index = CSSearchableIndex.default()
    private var batch: [CSSearchableItem] = []
    private let batchFlushSize = 25
    private let thumbnails: ThumbnailCache

    init(thumbnails: ThumbnailCache) {
        self.thumbnails = thumbnails
    }

    func indexScreenshot(id: Int64, path: String, text: String, thumbnailPath: String?) async {
        let fileURL = URL(fileURLWithPath: path)
        let attributeSet = CSSearchableItemAttributeSet(contentType: .image)
        attributeSet.displayName = fileURL.lastPathComponent
        attributeSet.contentDescription = String(text.prefix(500))
        attributeSet.textContent = text
        attributeSet.contentURL = fileURL

        if let thumbRelPath = thumbnailPath {
            let thumbURL = await thumbnails.url(for: thumbRelPath)
            attributeSet.thumbnailData = try? Data(contentsOf: thumbURL)
        }

        let deepLinkURL = URL(string: "scout://open?path=\(path.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")")
        let item = CSSearchableItem(
            uniqueIdentifier: path,
            domainIdentifier: "com.samirthapa.scout",
            attributeSet: attributeSet
        )
        item.expirationDate = .distantFuture
        _ = deepLinkURL  // associated via contentURL; direct scheme handled in AppDelegate

        batch.append(item)
        if batch.count >= batchFlushSize {
            await flush()
        }
    }

    func flush() async {
        guard !batch.isEmpty else { return }
        let toFlush = batch
        batch = []
        try? await index.indexSearchableItems(toFlush)
    }

    func delete(path: String) async {
        try? await index.deleteSearchableItems(withIdentifiers: [path])
    }

    func deleteAll() async {
        try? await index.deleteAllSearchableItems()
    }
}
