import Foundation

/// Watches a library folder for files changed on disk and reports them as a
/// stream of ``LibraryChange``s.
///
/// Changes the app makes itself are reported too; reloading them is
/// harmless. Watchers live on the main actor; stop one before dropping it.
@MainActor
public protocol LibraryWatching: AnyObject {
    /// Starts watching (stopping a previous run first). Changes arrive on
    /// the stream until ``stop()``, which finishes it.
    func start() -> AsyncStream<LibraryChange>

    /// Stops watching and finishes the stream.
    func stop()
}

extension LibraryLocation {
    /// A watcher for this location: an `NSMetadataQuery` for iCloud Drive on
    /// Apple platforms, polling otherwise.
    @MainActor
    public func makeWatcher() -> any LibraryWatching {
        #if canImport(Darwin)
        if isUbiquitous { return UbiquitousLibraryWatcher(root: url) }
        #endif
        return PollingLibraryWatcher(root: url)
    }
}

/// Watches a folder by comparing modification dates every few seconds: for
/// a local library, which only a text editor on this device can change.
@MainActor
public final class PollingLibraryWatcher: LibraryWatching {
    public let root: URL
    /// Time between two looks at the folder.
    public let interval: Duration
    private var task: Task<Void, Never>?
    private var continuation: AsyncStream<LibraryChange>.Continuation?

    public init(root: URL, interval: Duration = .seconds(3)) {
        self.root = root
        self.interval = interval
    }

    public func start() -> AsyncStream<LibraryChange> {
        stop()
        let (stream, continuation) = AsyncStream<LibraryChange>.makeStream()
        self.continuation = continuation
        let root = root
        let interval = interval
        task = Task.detached(priority: .utility) {
            var previous = FolderSnapshot.scan(root)
            let initial = previous.initialChange
            if !initial.isEmpty { continuation.yield(initial) }
            while !Task.isCancelled {
                try? await Task.sleep(for: interval)
                if Task.isCancelled { break }
                let current = FolderSnapshot.scan(root)
                let change = current.changes(since: previous)
                previous = current
                if !change.isEmpty { continuation.yield(change) }
            }
        }
        return stream
    }

    public func stop() {
        task?.cancel()
        task = nil
        continuation?.finish()
        continuation = nil
    }
}
