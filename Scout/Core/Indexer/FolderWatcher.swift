import Foundation

final class FolderWatcher {
    private var source: DispatchSourceFileSystemObject?
    private let fileDescriptor: Int32
    private var debounceTask: Task<Void, Never>?

    init(url: URL, queue: DispatchQueue = .global(qos: .utility), onChange: @escaping @Sendable (URL) -> Void) throws {
        fileDescriptor = open(url.path, O_EVTONLY)
        guard fileDescriptor >= 0 else {
            throw FolderWatcherError.couldNotOpenDirectory(url)
        }

        let capturedURL = url
        source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: [.write, .rename],
            queue: queue
        )

        source?.setEventHandler { [weak self] in
            self?.debounceTask?.cancel()
            self?.debounceTask = Task {
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled else { return }
                onChange(capturedURL)
            }
        }

        source?.setCancelHandler { [fileDescriptor] in
            close(fileDescriptor)
        }

        source?.resume()
    }

    deinit {
        source?.cancel()
    }
}

enum FolderWatcherError: Error {
    case couldNotOpenDirectory(URL)
}
