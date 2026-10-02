#if canImport(Darwin)
import Foundation
import Storage

/// Downloads a library in iCloud Drive before it's read: every file that
/// isn't on this device is asked for at once
/// (`startDownloadingUbiquitousItem`), and progress is reported until all
/// are here.
///
/// 1. The folder on disk is listed off the main thread: placeholders and
///    iCloud's resource values say which files aren't current. If every
///    file is, `library.json` included, it's complete at once.
/// 2. Otherwise an `NSMetadataQuery` on the ubiquitous documents scope (the
///    container's `Documents/`, which is the library folder) lists the
///    files with their download status, size, progress and errors. It runs
///    on the main thread, where its notifications arrive; paths are matched
///    with `LibraryFolder.relativePath(of:)`, which copes with `/private`.
///    It's stopped once every file is current, or on ``stop()``.
///
/// ``LibraryDownloadTracker`` decides what to ask for and counts progress.
/// Its owner holds it while downloading and stops it when done.
@MainActor
public final class UbiquitousLibraryDownloader: LibraryDownloading {
    public let root: URL

    private let folder: LibraryFolder
    private var tracker = LibraryDownloadTracker()
    private var query: NSMetadataQuery?
    private var observers: [any NSObjectProtocol] = []
    /// The URLs iCloud gave for the files, by path.
    private var itemURLs: [String: URL] = [:]
    private var continuation: AsyncStream<LibraryDownloadProgress>.Continuation?
    private var scan: Task<Void, Never>?
    private var started = ContinuousClock.now
    private var lastLogged: LibraryDownloadProgress?

    public init(root: URL) {
        self.root = root
        folder = LibraryFolder(root: root)
    }

    public func start() -> AsyncStream<LibraryDownloadProgress> {
        stop()
        let (stream, continuation) = AsyncStream<LibraryDownloadProgress>.makeStream(
            bufferingPolicy: .bufferingNewest(1))
        self.continuation = continuation
        tracker = LibraryDownloadTracker()
        itemURLs = [:]
        lastLogged = nil
        started = .now
        let root = root
        scan = Task {
            let disk = await Task.detached(priority: .userInitiated) {
                UbiquitousLibraryDownloader.diskFiles(root)
            }.value
            guard !Task.isCancelled else { return }
            self.begin(disk: disk)
        }
        return stream
    }

    public func requestAgain() {
        let paths = tracker.requestAgain()
        LibraryLog.notice("Download: asking iCloud Drive again for \(paths.count) files")
        request(paths)
        publish()
    }

    public func stop() {
        scan?.cancel()
        scan = nil
        query?.stop()
        query = nil
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
        observers = []
        continuation?.finish()
        continuation = nil
    }

    // MARK: - Steps

    private func begin(disk: [String: Bool]) {
        let requests = tracker.seed(disk: disk)
        let missing = disk.values.filter { !$0 }.count
        LibraryLog.notice("Download: \(disk.count) library files on this device, \(missing) of them not downloaded")
        if tracker.progress.isComplete {
            LibraryLog.notice("Download: nothing to download")
            publish()
            stop()
            return
        }
        request(requests)
        publish()
        startQuery()
    }

    private func startQuery() {
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
        if query.start() {
            LibraryLog.notice("Download: asking iCloud Drive for the library's files")
        } else {
            // Without the list there's nothing to follow: reading the
            // library downloads what's missing, file by file.
            LibraryLog.error("Download: iCloud Drive's file list (NSMetadataQuery) didn't start")
            stop()
        }
    }

    /// What the query says about one item.
    struct Item: Sendable {
        var url: URL
        var isCurrent: Bool
        var isDownloading: Bool
        var size: Int64?
        var percentDownloaded: Double?
        var error: String?
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
            let error = item.value(forAttribute: NSMetadataUbiquitousItemDownloadingErrorKey) as? NSError
            items.append(Item(
                url: url,
                isCurrent: status == nil || status == NSMetadataUbiquitousItemDownloadingStatusCurrent,
                isDownloading: item.value(forAttribute: NSMetadataUbiquitousItemIsDownloadingKey) as? Bool ?? false,
                size: (item.value(forAttribute: NSMetadataItemFSSizeKey) as? NSNumber)?.int64Value,
                percentDownloaded: (item.value(forAttribute: NSMetadataUbiquitousItemPercentDownloadedKey)
                    as? NSNumber)?.doubleValue,
                error: error?.localizedDescription))
        }
        return items
    }

    /// The library's files on disk and whether each is current, from
    /// iCloud's resource values, or the placeholders where there are none.
    nonisolated static func diskFiles(_ root: URL) -> [String: Bool] {
        LibraryDownloadTracker.scanDisk(root) { url in
            let keys: Set<URLResourceKey> = [.isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey]
            guard let values = try? url.resourceValues(forKeys: keys), values.isUbiquitousItem == true,
                  let status = values.ubiquitousItemDownloadingStatus
            else { return nil }
            return status == .current
        }
    }

    private func receive(_ items: [Item]) {
        guard continuation != nil else { return }
        var files: [UbiquitousFileStatus] = []
        for item in items {
            guard let path = folder.relativePath(of: item.url) else { continue }
            itemURLs[path] = item.url
            files.append(UbiquitousFileStatus(
                path: path, isCurrent: item.isCurrent, isDownloading: item.isDownloading, size: item.size,
                downloadedFraction: item.percentDownloaded.map { $0 / 100 }, error: item.error))
        }
        let requests = tracker.update(files)
        request(requests)
        publish()
        if tracker.progress.isComplete {
            LibraryLog.notice("Download: every file is on this device after \(LibraryLog.seconds(.now - started))")
            stop()
        }
    }

    private func request(_ paths: [String]) {
        guard !paths.isEmpty else { return }
        for path in paths {
            do {
                try FileManager.default.startDownloadingUbiquitousItem(at: itemURLs[path] ?? folder.url(for: path))
            } catch {
                tracker.requestFailed(path, message: error.localizedDescription)
            }
        }
        LibraryLog.notice("Download: asked iCloud Drive for \(paths.count) files")
    }

    private func publish() {
        let progress = tracker.progress
        continuation?.yield(progress)
        log(progress)
    }

    private func log(_ progress: LibraryDownloadProgress) {
        let previous = lastLogged
        lastLogged = progress
        if progress.isListed, previous?.isListed != true {
            LibraryLog.notice(
                "Download: iCloud Drive lists \(progress.totalFiles) library files, \(progress.filesToDownload) to download")
        }
        if progress.downloadedFiles != previous?.downloadedFiles || progress.filesToDownload != previous?.filesToDownload {
            let bytes = progress.bytesToDownload.map { " (\(progress.downloadedBytes ?? 0) of \($0) bytes)" } ?? ""
            LibraryLog.info("Download: \(progress.downloadedFiles) of \(progress.filesToDownload) files\(bytes)")
        }
        let reported = Set(previous?.failures ?? [])
        for failure in progress.failures where !reported.contains(failure) {
            LibraryLog.error("Download: \(failure.path) couldn't be downloaded: \(failure.message)")
        }
    }
}
#endif
