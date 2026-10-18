#if canImport(Darwin)
import Foundation
import Storage

/// Watches a library in iCloud Drive with the iCloud Drive query
/// (`UbiquitousItemQuery`).
///
/// - Reports files that were added, changed or removed, once they're
///   downloaded, debounced into one ``LibraryChange`` per burst.
/// - Starts downloading every file that isn't downloaded yet, so the whole
///   library stays on the device ("Optimize Storage" never leaves gaps).
/// - Reports files with unresolved sync conflicts, including at the first
///   look, and there, given a baseline, every file changed since the
///   library was loaded (dates within a second of the baseline's count as
///   unchanged: the query's dates and the file system's can differ that much).
@MainActor
public final class UbiquitousLibraryWatcher: LibraryWatching {
    public let root: URL
    /// How long to wait for more events before reporting a change.
    static let debounce: Duration = .milliseconds(500)

    private let query: UbiquitousItemQuery
    private var snapshot: FolderSnapshot?
    /// The folder when the library was loaded, until the first look.
    private var baseline: FolderSnapshot?
    private var batcher = ChangeBatcher()
    private var flushTask: Task<Void, Never>?
    private var continuation: AsyncStream<LibraryChange>.Continuation?
    private var requestedDownloads: Set<String> = []

    public init(root: URL) {
        self.root = root
        query = UbiquitousItemQuery(root: root)
    }

    /// How far apart the query's and the file system's modification dates
    /// of the same version can be.
    static let baselineTolerance: TimeInterval = 1

    public func start(since baseline: FolderSnapshot?) -> AsyncStream<LibraryChange> {
        stop()
        let (stream, continuation) = AsyncStream<LibraryChange>.makeStream()
        self.continuation = continuation
        self.baseline = baseline

        query.start({ [weak self] items in self?.receive(items) })
        return stream
    }

    public func stop() {
        query.stop()
        flushTask?.cancel()
        flushTask = nil
        snapshot = nil
        baseline = nil
        batcher = ChangeBatcher()
        requestedDownloads = []
        continuation?.finish()
        continuation = nil
    }

    // MARK: - Query results

    private func receive(_ items: [UbiquitousItemQuery.Item]) {
        var files: [String: WatchedFileState] = [:]
        for item in items {
            let path = item.path
            guard LibraryChange.isWatched(path) else { continue }
            files[path] = WatchedFileState(
                modified: item.modified, isDownloaded: item.isCurrent, hasConflicts: item.hasConflicts)
            if item.isCurrent {
                requestedDownloads.remove(path)
            } else if !item.isDownloading, !requestedDownloads.contains(path) {
                requestedDownloads.insert(path)
                try? FileManager.default.startDownloadingUbiquitousItem(at: item.url)
            }
        }
        let current = FolderSnapshot(files: files)
        let change: LibraryChange
        if let snapshot {
            change = current.changes(since: snapshot)
        } else if let baseline {
            // The first look: what changed since the library was loaded.
            change = current.changes(since: baseline, tolerance: Self.baselineTolerance)
            self.baseline = nil
        } else {
            change = current.initialChange
        }
        snapshot = current
        guard !change.isEmpty else { return }
        batcher.add(change)
        scheduleFlush()
    }

    private func scheduleFlush() {
        flushTask?.cancel()
        let debounce = Self.debounce
        flushTask = Task { [weak self] in
            try? await Task.sleep(for: debounce)
            guard !Task.isCancelled else { return }
            self?.flush()
        }
    }

    private func flush() {
        guard let change = batcher.take() else { return }
        continuation?.yield(change)
    }
}
#endif
