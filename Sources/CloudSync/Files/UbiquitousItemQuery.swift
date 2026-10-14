#if canImport(Darwin)
import Foundation

/// The `NSMetadataQuery` that the downloader and the watcher run: every
/// item in the ubiquitous documents scope (the container's `Documents/`,
/// which is the library folder), with what iCloud says about each.
///
/// The query runs on the main thread, where its notifications arrive. Its
/// owner stops it when done.
@MainActor
final class UbiquitousItemQuery {
    /// What the query says about one item.
    struct Item: Sendable {
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

    private var query: NSMetadataQuery?
    private var observers: [any NSObjectProtocol] = []

    /// Starts the query (stopping a previous run first). `receive` gets
    /// every item when the first results are in and each time they change.
    /// Returns whether it started.
    func start(_ receive: @escaping @MainActor @Sendable ([Item]) -> Void) -> Bool {
        stop()
        let query = NSMetadataQuery()
        query.searchScopes = [NSMetadataQueryUbiquitousDocumentsScope]
        query.predicate = NSPredicate(format: "%K LIKE '*'", NSMetadataItemFSNameKey)
        query.notificationBatchingInterval = 0.25
        let center = NotificationCenter.default
        let names: [Notification.Name] = [.NSMetadataQueryDidFinishGathering, .NSMetadataQueryDidUpdate]
        for name in names {
            let observer = center.addObserver(forName: name, object: query, queue: .main) { notification in
                let items = Self.items(of: notification)
                MainActor.assumeIsolated {
                    receive(items)
                }
            }
            observers.append(observer)
        }
        self.query = query
        return query.start()
    }

    /// Stops the query; nothing more is received.
    func stop() {
        query?.stop()
        query = nil
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
        observers = []
    }

    /// Every item of the query that posted `notification`. Called on the
    /// main queue, where the query delivers its notifications.
    nonisolated private static func items(of notification: Notification) -> [Item] {
        guard let query = notification.object as? NSMetadataQuery else { return [] }
        query.disableUpdates()
        defer { query.enableUpdates() }
        var items: [Item] = []
        for result in query.results {
            guard let item = result as? NSMetadataItem,
                  let url = item.value(forAttribute: NSMetadataItemURLKey) as? URL
            else { continue }
            let status = item.value(forAttribute: NSMetadataUbiquitousItemDownloadingStatusKey) as? String
            let error = item.value(forAttribute: NSMetadataUbiquitousItemDownloadingErrorKey) as? NSError
            items.append(Item(
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
