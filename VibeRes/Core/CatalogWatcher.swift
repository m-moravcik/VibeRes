import Foundation

/// Calls `onChange` on the main actor shortly after the catalog file changes
/// on disk, whoever changed it.
///
/// Two kernel event sources, because a file can change in two ways:
/// - replaced: `Data.write(options: .atomic)`, which both the app and the
///   `viberes` CLI use, writes a new file and renames it over the old one. The
///   old file's descriptor never sees that, but the directory does.
/// - edited in place, as `echo … > profiles.json` or some editors do. Only the
///   file's own descriptor sees that.
/// The file source is re-armed on every directory event, so it always
/// follows the file currently at the path.
///
/// Events are coalesced: one save is several events (create, rename,
/// attribute change), and one reload covers them all.
@MainActor
final class CatalogWatcher {
    private let file: URL
    private let onChange: @MainActor () -> Void
    private var directorySource: DispatchSourceFileSystemObject?
    private var fileSource: DispatchSourceFileSystemObject?
    private var pending: DispatchWorkItem?

    /// How long to wait for a burst of events to settle before reloading.
    nonisolated static let settleDelay: DispatchTimeInterval = .milliseconds(150)

    init(file: URL, onChange: @escaping @MainActor () -> Void) {
        self.file = file
        self.onChange = onChange
        directorySource = makeSource(
            path: file.deletingLastPathComponent().path,
            events: .write
        ) { [weak self] in
            self?.armFileSource()
            self?.scheduleChange()
        }
        armFileSource()
    }

    isolated deinit {
        pending?.cancel()
        directorySource?.cancel()
        fileSource?.cancel()
    }

    private func armFileSource() {
        fileSource?.cancel()
        // nil while there is no file yet; the directory event that creates
        // one arms it.
        fileSource = makeSource(path: file.path, events: [.write, .extend, .delete, .rename]) { [weak self] in
            self?.scheduleChange()
        }
    }

    private func scheduleChange() {
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.onChange() }
        }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.settleDelay, execute: work)
    }

    private func makeSource(
        path: String,
        events: DispatchSource.FileSystemEvent,
        handler: @escaping @MainActor () -> Void
    ) -> DispatchSourceFileSystemObject? {
        let descriptor = open(path, O_EVTONLY)
        guard descriptor >= 0 else { return nil }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor, eventMask: events, queue: .main
        )
        source.setEventHandler { MainActor.assumeIsolated { handler() } }
        source.setCancelHandler { close(descriptor) }
        source.resume()
        return source
    }
}
