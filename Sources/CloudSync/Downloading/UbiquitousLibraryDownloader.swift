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
/// 2. Otherwise the iCloud Drive query (`UbiquitousItemQuery`) lists the
///    files with their download status, size, progress and errors. It's
///    stopped once every file is current, or on ``stop()``.
///
/// Reading a file iCloud Drive hasn't downloaded yet (a coordinated read)
/// waits until it's downloaded, so reading a library that's only partly on
/// the device would download it one file at a time, with nothing to show
/// and no end if iCloud can't download. This asks for every missing file at
/// once, and the library is read once they're all here.
///
/// ``LibraryDownloadTracker`` decides what to ask for and counts progress.
/// It lives on the main actor; its owner holds it while downloading and
/// stops it before dropping it.
@MainActor
public final class UbiquitousLibraryDownloader {
    public let root: URL

    private let folder: LibraryFolder
    private var tracker = LibraryDownloadTracker()
    private let query: UbiquitousItemQuery
    /// The URLs iCloud gave for the files, by path.
    private var itemURLs: [String: URL] = [:]
    private var continuation: AsyncStream<LibraryDownloadProgress>.Continuation?
    private var scan: Task<Void, Never>?
    private var started = ContinuousClock.now
    private var lastLogged: LibraryDownloadProgress?

    public init(root: URL) {
        self.root = root
        folder = LibraryFolder(root: root)
        query = UbiquitousItemQuery(root: root)
    }

    /// Starts (stopping a previous run first). Progress arrives on the
    /// stream, the latest first if it can't keep up. The stream finishes
    /// after a progress that ``LibraryDownloadProgress/isComplete``, or on
    /// ``stop()``. It can also finish without one if the download can't be
    /// followed; reading the library then downloads what's missing itself.
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

    /// Asks iCloud again for every file that hasn't arrived, forgetting
    /// failures, e.g. when the user chooses to keep waiting.
    public func requestAgain() {
        let paths = tracker.requestAgain()
        LibraryLog.notice("Download: asking iCloud Drive again for \(paths.count) files")
        request(paths)
        publish()
    }

    /// Stops following the download and finishes the stream. Downloads
    /// already asked for go on.
    public func stop() {
        scan?.cancel()
        scan = nil
        query.stop()
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
        LibraryLog.notice("Download: asking iCloud Drive for the library's files")
        query.start({ [weak self] items in self?.receive(items) }, failed: { [weak self] in
            // Without the list there's nothing to follow: reading the
            // library downloads what's missing, file by file.
            LibraryLog.error("Download: iCloud Drive's file list (NSMetadataQuery) didn't start")
            self?.stop()
        })
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

    private func receive(_ items: [UbiquitousItemQuery.Item]) {
        guard continuation != nil else { return }
        var files: [UbiquitousFileStatus] = []
        for item in items {
            itemURLs[item.path] = item.url
            files.append(UbiquitousFileStatus(
                path: item.path, isCurrent: item.isCurrent, isDownloading: item.isDownloading, size: item.size,
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

extension LibraryLocation {
    /// A downloader for this location: for a library in iCloud Drive; `nil`
    /// for one on this device, where there's nothing to download.
    @MainActor
    public func makeDownloader() -> UbiquitousLibraryDownloader? {
        isUbiquitous ? UbiquitousLibraryDownloader(root: url) : nil
    }
}
#endif
