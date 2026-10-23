#if canImport(Darwin)
import Foundation
import Storage

/// The `NSMetadataQuery` that the downloader and the watcher run: every
/// item in the ubiquitous documents scope (the container's `Documents/`,
/// which is the library folder), with what iCloud says about each.
///
/// The query runs on a queue of its own, not the main thread: it lists every
/// file in the folder, backups included, and goes through all of them again
/// at each update, which on a library with many backups takes seconds. Items
/// outside the folder and in `backups/` are left out there, so the owner
/// gets only the library's own files, on the main thread. Its owner stops it
/// when done.
@MainActor
final class UbiquitousItemQuery {
    /// What the query says about one item.
    struct Item: Sendable {
        /// The item's path relative to the library folder
        /// (`LibraryFolder.relativePath(of:)`, which copes with `/private`).
        var path: String
        var url: URL
        var modified: Date?
        /// Whether this device has the latest version.
        var isCurrent: Bool
        var isDownloading: Bool
        var size: Int64?
        var percentDownloaded: Double?
        /// Why downloading it failed, if it did.
        var error: String?
        var hasConflicts: Bool
    }

    private let folder: LibraryFolder
    private var run: Run?

    /// A query of the items in the library folder at `root`.
    init(root: URL) {
        folder = LibraryFolder(root: root)
    }

    /// Starts the query (stopping a previous run first). `receive` gets
    /// every item, on the main thread, when the first results are in and
    /// each time they change; `failed` is called instead if the query
    /// doesn't start.
    func start(_ receive: @escaping @MainActor @Sendable ([Item]) -> Void,
               failed: @escaping @MainActor @Sendable () -> Void = {}) {
        stop()
        let run = Run()
        let folder = folder
        let names: [Notification.Name] = [.NSMetadataQueryDidFinishGathering, .NSMetadataQueryDidUpdate]
        for name in names {
            // Without a queue of its own, the observer runs where the query
            // posts: on the query's queue, while its results hold still.
            let observer = NotificationCenter.default.addObserver(forName: name, object: run.query,
                                                                  queue: nil) { notification in
                let items = Self.items(of: notification, in: folder)
                run.onMain { receive(items) }
            }
            run.observers.append(observer)
        }
        self.run = run
        run.start { run.onMain(failed) }
    }

    /// Stops the query; nothing more is received.
    func stop() {
        run?.stop()
        run = nil
    }

    /// One run of the query, with the queue it runs on. The query is used
    /// only on that queue once it starts; ``isStopped`` and the observers
    /// only on the main thread.
    private final class Run: @unchecked Sendable {
        let query = NSMetadataQuery()
        let queue = OperationQueue()
        var observers: [any NSObjectProtocol] = []
        var isStopped = false

        init() {
            queue.name = "UbiquitousItemQuery"
            queue.maxConcurrentOperationCount = 1
            queue.qualityOfService = .utility
            query.searchScopes = [NSMetadataQueryUbiquitousDocumentsScope]
            query.predicate = NSPredicate(format: "%K LIKE '*'", NSMetadataItemFSNameKey)
            query.notificationBatchingInterval = 0.25
            query.operationQueue = queue
        }

        /// Starts the query on its queue; `failed` runs there if it doesn't start.
        func start(failed: @escaping @Sendable () -> Void) {
            queue.addOperation {
                if !self.query.start() { failed() }
            }
        }

        /// Runs `work` on the main thread, unless the query has stopped by then.
        func onMain(_ work: @escaping @MainActor @Sendable () -> Void) {
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard !self.isStopped else { return }
                    work()
                }
            }
        }

        func stop() {
            isStopped = true
            for observer in observers {
                NotificationCenter.default.removeObserver(observer)
            }
            observers = []
            queue.addOperation { self.query.stop() }
        }
    }

    /// The library's items of the query that posted `notification`, without
    /// those in `backups/`. Called on the query's queue, where it posts its
    /// notifications.
    nonisolated private static func items(of notification: Notification, in folder: LibraryFolder) -> [Item] {
        guard let query = notification.object as? NSMetadataQuery else { return [] }
        query.disableUpdates()
        defer { query.enableUpdates() }
        var items: [Item] = []
        for result in query.results {
            guard let item = result as? NSMetadataItem,
                  let url = item.value(forAttribute: NSMetadataItemURLKey) as? URL,
                  let path = folder.relativePath(of: url),
                  path != LibraryFolder.backupsFolder, !path.hasPrefix(LibraryFolder.backupsFolder + "/")
            else { continue }
            let status = item.value(forAttribute: NSMetadataUbiquitousItemDownloadingStatusKey) as? String
            let error = item.value(forAttribute: NSMetadataUbiquitousItemDownloadingErrorKey) as? NSError
            items.append(Item(
                path: path,
                url: url,
                modified: item.value(forAttribute: NSMetadataItemFSContentChangeDateKey) as? Date,
                isCurrent: status == nil || status == NSMetadataUbiquitousItemDownloadingStatusCurrent,
                isDownloading: item.value(forAttribute: NSMetadataUbiquitousItemIsDownloadingKey) as? Bool ?? false,
                size: (item.value(forAttribute: NSMetadataItemFSSizeKey) as? NSNumber)?.int64Value,
                percentDownloaded: (item.value(forAttribute: NSMetadataUbiquitousItemPercentDownloadedKey)
                    as? NSNumber)?.doubleValue,
                error: error?.localizedDescription,
                hasConflicts: item.value(forAttribute: NSMetadataUbiquitousItemHasUnresolvedConflictsKey) as? Bool
                    ?? false))
        }
        return items
    }
}
#endif
