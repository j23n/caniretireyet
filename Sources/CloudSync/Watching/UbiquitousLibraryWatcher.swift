#if canImport(Darwin)
import Foundation
import Storage

/// Watches a library in iCloud Drive with an `NSMetadataQuery` on the
/// ubiquitous documents scope.
///
/// - Reports files that were added, changed or removed, once they're
///   downloaded, debounced into one ``LibraryChange`` per burst.
/// - Starts downloading every file that isn't downloaded yet, so the whole
///   library stays on the device ("Optimize Storage" never leaves gaps).
/// - Reports files with unresolved sync conflicts, including at the first
///   look, and there, given a baseline, every file changed since the
///   library was loaded (dates within a second of the baseline's count as
///   unchanged: the query's dates and the file system's can differ that much).
///
/// The query runs on the main thread, where its notifications arrive.
@MainActor
public final class UbiquitousLibraryWatcher: LibraryWatching {
    public let root: URL
    /// How long to wait for more events before reporting a change.
    public let debounce: Duration

    private let folder: LibraryFolder
    private var query: NSMetadataQuery?
    private var observers: [any NSObjectProtocol] = []
    private var snapshot: FolderSnapshot?
    /// The folder when the library was loaded, until the first look.
    private var baseline: FolderSnapshot?
    private var batcher = ChangeBatcher()
    private var flushTask: Task<Void, Never>?
    private var continuation: AsyncStream<LibraryChange>.Continuation?
    private var requestedDownloads: Set<String> = []

    public init(root: URL, debounce: Duration = .milliseconds(500)) {
        self.root = root
        self.debounce = debounce
        folder = LibraryFolder(root: root)
    }

    /// How far apart the query's and the file system's modification dates
    /// of the same version can be.
    static let baselineTolerance: TimeInterval = 1

    public func start(since baseline: FolderSnapshot?) -> AsyncStream<LibraryChange> {
        stop()
        let (stream, continuation) = AsyncStream<LibraryChange>.makeStream()
        self.continuation = continuation
        self.baseline = baseline

        let query = NSMetadataQuery()
        query.searchScopes = [NSMetadataQueryUbiquitousDocumentsScope]
        query.predicate = NSPredicate(format: "%K LIKE '*'", NSMetadataItemFSNameKey)
        query.notificationBatchingInterval = 0.25
        let center = NotificationCenter.default
        let names: [Notification.Name] = [.NSMetadataQueryDidFinishGathering, .NSMetadataQueryDidUpdate]
        for name in names {
            let observer = center.addObserver(forName: name, object: query, queue: .main) { [weak self] notification in
                let items = Self.items(of: notification)
                MainActor.assumeIsolated {
                    self?.receive(items)
                }
            }
            observers.append(observer)
        }
        self.query = query
        _ = query.start()
        return stream
    }

    public func stop() {
        query?.stop()
        query = nil
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
        observers = []
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

    /// What the query says about one item.
    struct Item: Sendable {
        var url: URL
        var modified: Date?
        var isDownloaded: Bool
        var isDownloading: Bool
        var hasConflicts: Bool
    }

    /// Every item of the query that posted `notification`. Called on the
    /// main queue, where the query delivers its notifications.
    nonisolated static func items(of notification: Notification) -> [Item] {
        guard let query = notification.object as? NSMetadataQuery else { return [] }
        query.disableUpdates()
        defer { query.enableUpdates() }
        var items: [Item] = []
        for result in query.results {
            guard let item = result as? NSMetadataItem,
                  let url = item.value(forAttribute: NSMetadataItemURLKey) as? URL
            else { continue }
            let status = item.value(forAttribute: NSMetadataUbiquitousItemDownloadingStatusKey) as? String
            items.append(Item(
                url: url,
                modified: item.value(forAttribute: NSMetadataItemFSContentChangeDateKey) as? Date,
                isDownloaded: status == nil || status == NSMetadataUbiquitousItemDownloadingStatusCurrent,
                isDownloading: item.value(forAttribute: NSMetadataUbiquitousItemIsDownloadingKey) as? Bool ?? false,
                hasConflicts: item.value(forAttribute: NSMetadataUbiquitousItemHasUnresolvedConflictsKey) as? Bool
                    ?? false))
        }
        return items
    }

    private func receive(_ items: [Item]) {
        var files: [String: WatchedFileState] = [:]
        for item in items {
            guard let path = folder.relativePath(of: item.url), LibraryChange.isWatched(path) else { continue }
            files[path] = WatchedFileState(
                modified: item.modified, isDownloaded: item.isDownloaded, hasConflicts: item.hasConflicts)
            if item.isDownloaded {
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
        let debounce = debounce
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
