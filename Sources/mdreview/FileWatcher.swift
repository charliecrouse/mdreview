import Foundation

/// Calls `onChange` whenever the file at `url` is written, replaced, deleted or recreated.
@MainActor
final class FileWatcher {
    private let url: URL
    private let onChange: @MainActor () -> Void
    private var source: DispatchSourceFileSystemObject?

    init(url: URL, onChange: @escaping @MainActor () -> Void) {
        self.url = url
        self.onChange = onChange
        watch()
    }

    isolated deinit { source?.cancel() }

    /// A descriptor follows the inode, not the path: an atomic save swaps in a new file, so every event
    /// re-opens the path. While the file is missing, its folder is watched until the file comes back.
    private func watch() {
        source?.cancel()
        source = nil
        var descriptor = open(url.path, O_EVTONLY)
        if descriptor < 0 { descriptor = open(url.deletingLastPathComponent().path, O_EVTONLY) }
        guard descriptor >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor, eventMask: [.write, .extend, .delete, .rename, .revoke], queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated {
                self?.watch()
                self?.onChange()
            }
        }
        source.setCancelHandler { close(descriptor) }
        source.resume()
        self.source = source
    }
}
