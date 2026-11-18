import Foundation

/// Calls `onChange` on the main queue when the file or directory at `url` changes.
@MainActor final class FileWatcher {
    private let url: URL
    private let onChange: () -> Void
    nonisolated(unsafe) private var source: DispatchSourceFileSystemObject?

    init(url: URL, onChange: @escaping () -> Void) {
        self.url = url
        self.onChange = onChange
        start(retries: 0)
    }

    deinit { source?.cancel() }

    private func start(retries: Int) {
        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else {
            // A tool that deletes then recreates the file leaves a short gap.
            guard retries > 0 else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                self?.start(retries: retries - 1)
            }
            return
        }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.write, .extend, .delete, .rename], queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                // Atomic saves replace the inode, so the old descriptor goes stale.
                if !source.data.isDisjoint(with: [.delete, .rename]) {
                    source.cancel()
                    self.start(retries: 10)
                }
                self.onChange()
            }
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        self.source = source
    }
}
