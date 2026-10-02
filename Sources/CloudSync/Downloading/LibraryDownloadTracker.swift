import Foundation
import Storage

/// What iCloud Drive says about one file of the library (an
/// `NSMetadataItem` of the downloader's query).
public struct UbiquitousFileStatus: Hashable, Sendable {
    /// The path relative to the library folder.
    public var path: String
    /// Whether the file's current version is on this device.
    public var isCurrent: Bool
    /// Whether iCloud is downloading it now.
    public var isDownloading: Bool
    /// Its size in bytes, if known.
    public var size: Int64?
    /// How much of it is downloaded, 0 to 1, if known.
    public var downloadedFraction: Double?
    /// Why its download failed, if it did.
    public var error: String?

    public init(path: String, isCurrent: Bool, isDownloading: Bool = false, size: Int64? = nil,
                downloadedFraction: Double? = nil, error: String? = nil) {
        self.path = path
        self.isCurrent = isCurrent
        self.isDownloading = isDownloading
        self.size = size
        self.downloadedFraction = downloadedFraction
        self.error = error
    }
}

/// A file iCloud Drive couldn't download, and why.
public struct LibraryDownloadFailure: Hashable, Sendable {
    /// The path relative to the library folder.
    public var path: String
    /// What iCloud said, e.g. "The Internet connection appears to be offline."
    public var message: String

    public init(path: String, message: String) {
        self.path = path
        self.message = message
    }
}

/// How far downloading the library from iCloud Drive has come.
public struct LibraryDownloadProgress: Hashable, Sendable {
    /// Whether iCloud Drive has listed the library's files yet. Before, the
    /// counts are what's on this device.
    public var isListed: Bool
    /// The files the app reads (see ``LibraryDownloadTracker/includes(_:)``).
    public var totalFiles: Int
    /// The files among them that weren't on this device (or not their
    /// current version) when first seen: the "N" of "n of N".
    public var filesToDownload: Int
    /// How many of those are on this device now.
    public var downloadedFiles: Int
    /// The size of the files to download, if iCloud gave every one's.
    public var bytesToDownload: Int64?
    /// How much of that is downloaded, if known.
    public var downloadedBytes: Int64?
    /// Files whose download failed, by path. They're reported, not waited
    /// for silently; asking again (`LibraryDownloading.requestAgain()`) clears them.
    public var failures: [LibraryDownloadFailure]
    /// Whether every file, `library.json` included, is on this device: the
    /// library can be read without waiting for the network.
    public var isComplete: Bool

    public init(isListed: Bool = false, totalFiles: Int = 0, filesToDownload: Int = 0, downloadedFiles: Int = 0,
                bytesToDownload: Int64? = nil, downloadedBytes: Int64? = nil,
                failures: [LibraryDownloadFailure] = [], isComplete: Bool = false) {
        self.isListed = isListed
        self.totalFiles = totalFiles
        self.filesToDownload = filesToDownload
        self.downloadedFiles = downloadedFiles
        self.bytesToDownload = bytesToDownload
        self.downloadedBytes = downloadedBytes
        self.failures = failures
        self.isComplete = isComplete
    }

    /// How much is done, 0 to 1: by bytes when every size is known, else by
    /// files. `nil` while there's nothing to download.
    public var fractionCompleted: Double? {
        if let bytesToDownload, let downloadedBytes, bytesToDownload > 0 {
            return min(1, max(0, Double(downloadedBytes) / Double(bytesToDownload)))
        }
        guard filesToDownload > 0 else { return nil }
        return Double(downloadedFiles) / Double(filesToDownload)
    }

    /// Whether this progress moved on from `previous`: iCloud listed the
    /// files or more of them, more files or bytes arrived, or it's complete.
    /// A failure isn't progress. Anything counts against no previous one.
    public func hasAdvanced(since previous: LibraryDownloadProgress?) -> Bool {
        guard let previous else { return true }
        return (isListed && !previous.isListed)
            || totalFiles > previous.totalFiles
            || downloadedFiles > previous.downloadedFiles
            || (downloadedBytes ?? 0) > (previous.downloadedBytes ?? 0)
            || (isComplete && !previous.isComplete)
    }
}

/// Plans and follows downloading a library from iCloud Drive before it's
/// read, without the query: which files to ask iCloud for, and the
/// progress. The downloader (`UbiquitousLibraryDownloader`, Apple
/// platforms only) feeds it the folder on disk, then iCloud's list.
///
/// A file is current if iCloud's list says so, or, for a file the list
/// doesn't (yet) hold, if it is on disk. Each file that isn't current is
/// asked for once (unless iCloud is already downloading it or reported an
/// error), and again after ``requestAgain()``. A file that changes again
/// after it arrived is asked for again.
public struct LibraryDownloadTracker: Hashable, Sendable {
    /// Which files are downloaded before the library is read: the ones it
    /// reads (JSON files outside `backups/`, see `LibraryChange.isWatched`)
    /// and the README, which is read once the library is open. Backups are
    /// left to iCloud.
    public static func includes(_ path: String) -> Bool {
        LibraryChange.isWatched(path) || path == LibraryFolder.readmePath
    }

    private var onDisk: [String: Bool] = [:]
    private var reported: [String: UbiquitousFileStatus] = [:]
    private var isListed = false
    private var planned: Set<String> = []
    private var requested: Set<String> = []
    private var requestErrors: [String: String] = [:]

    public init() {}

    /// Starts from the folder on disk: each file's path relative to the
    /// folder, and whether it's current (see ``scanDisk(_:isCurrent:)``).
    /// Returns the files to ask iCloud for.
    public mutating func seed(disk files: [String: Bool]) -> [String] {
        onDisk = files.filter { Self.includes($0.key) }
        return plan()
    }

    /// Takes iCloud's list of the folder's files (all of them, each time).
    /// Returns the files to ask iCloud for: not current, not downloading,
    /// no error, and not asked for yet.
    public mutating func update(_ files: [UbiquitousFileStatus]) -> [String] {
        isListed = true
        reported = [:]
        for file in files where Self.includes(file.path) {
            reported[file.path] = file
        }
        return plan()
    }

    /// Asking iCloud for a file failed (`startDownloadingUbiquitousItem`
    /// threw).
    public mutating func requestFailed(_ path: String, message: String) {
        requestErrors[path] = message
    }

    /// Forgets which files were asked for and the errors, and returns every
    /// file that isn't current and isn't downloading, to ask for again.
    public mutating func requestAgain() -> [String] {
        requested = []
        requestErrors = [:]
        for path in reported.keys {
            reported[path]?.error = nil
        }
        return plan()
    }

    /// Where the download stands.
    public var progress: LibraryDownloadProgress {
        let paths = allPaths
        let toDownload = planned.intersection(paths)
        let downloaded = toDownload.filter(isCurrent)
        var bytesToDownload: Int64? = toDownload.isEmpty ? nil : 0
        var downloadedBytes: Int64? = toDownload.isEmpty ? nil : 0
        for path in toDownload {
            guard let size = reported[path]?.size, let total = bytesToDownload, let done = downloadedBytes else {
                bytesToDownload = nil
                downloadedBytes = nil
                break
            }
            bytesToDownload = total + size
            if isCurrent(path) {
                downloadedBytes = done + size
            } else if let fraction = reported[path]?.downloadedFraction {
                downloadedBytes = done + Int64((Double(size) * min(1, max(0, fraction))).rounded())
            }
        }
        let failures = paths.sorted().compactMap { path -> LibraryDownloadFailure? in
            guard !isCurrent(path), let message = requestErrors[path] ?? reported[path]?.error else { return nil }
            return LibraryDownloadFailure(path: path, message: message)
        }
        return LibraryDownloadProgress(
            isListed: isListed, totalFiles: paths.count, filesToDownload: toDownload.count,
            downloadedFiles: downloaded.count, bytesToDownload: bytesToDownload, downloadedBytes: downloadedBytes,
            failures: failures,
            isComplete: isCurrent(LibraryFile.settings.path) && paths.allSatisfy(isCurrent))
    }

    // MARK: - Internals

    private var allPaths: Set<String> {
        Set(onDisk.keys).union(reported.keys)
    }

    private func isCurrent(_ path: String) -> Bool {
        reported[path]?.isCurrent ?? onDisk[path] ?? false
    }

    private mutating func plan() -> [String] {
        var requests: [String] = []
        for path in allPaths.sorted() {
            if isCurrent(path) {
                requested.remove(path)
                continue
            }
            planned.insert(path)
            let status = reported[path]
            guard status?.isDownloading != true, status?.error == nil, requestErrors[path] == nil,
                  !requested.contains(path)
            else { continue }
            requested.insert(path)
            requests.append(path)
        }
        return requests
    }
}

extension LibraryDownloadTracker {
    /// The files under `root` that ``includes(_:)`` keeps, by path relative
    /// to it, and whether each is current. A file that is only an iCloud
    /// placeholder (`.name.json.icloud`) isn't; `isCurrent` can say better
    /// (iCloud's resource values on Apple platforms), and returning `nil`
    /// falls back to the placeholder. Reads only the folder's listing.
    public static func scanDisk(_ root: URL, isCurrent: (URL) -> Bool? = { _ in nil }) -> [String: Bool] {
        let access = CoordinatedFileAccess()
        let paths = ((try? access.listFiles(in: root)) ?? []).filter(includes)
        var files: [String: Bool] = [:]
        for path in paths {
            let url = root.appendingPathComponent(path)
            files[path] = isCurrent(url) ?? FileManager.default.fileExists(atPath: url.path)
        }
        return files
    }
}
