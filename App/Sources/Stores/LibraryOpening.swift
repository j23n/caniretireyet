import CloudSync
import Foundation

/// What opening the library is doing, for the screen shown while
/// `LibraryStore.phase` is `.starting` (UI.md, "Opening the library"): the
/// step, whether it has stalled, and the words for both.
struct LibraryOpening: Equatable, Sendable {
    /// A step of opening the library.
    enum Step: Equatable, Sendable {
        /// Finding the library: in iCloud Drive (which may mean asking iCloud
        /// whether there's one), on this device, or `nil` before either.
        case looking(LibraryLocationKind?)
        /// Downloading the library's files from iCloud Drive before reading them.
        case downloading(LibraryDownloadProgress)
        /// Reading the library's files.
        case reading
    }

    var step: Step = .looking(nil)
    /// Whether the library is in iCloud Drive (or being looked for there).
    var isICloud = false
    /// Whether nothing has moved for a while (`LibraryStore.openingStallTime`):
    /// the screen says what may be wrong and offers Try Again and Keep Waiting.
    var isStalled = false

    // MARK: Words

    /// What's happening, e.g. "Downloading 12 of 150 files from iCloud Drive…".
    var title: String {
        switch step {
        case .looking(.iCloud?):
            "Looking for your library in iCloud Drive…"
        case .looking:
            "Opening your library…"
        case .downloading(let progress) where !progress.isListed || progress.filesToDownload == 0:
            progress.isComplete ? "Reading your library…" : "Checking your library in iCloud Drive…"
        case .downloading(let progress):
            "Downloading \(progress.downloadedFiles.formatted()) of \(progress.filesToDownload.formatted()) files "
                + "from iCloud Drive…"
        case .reading:
            "Reading your library…"
        }
    }

    /// How much is downloaded, e.g. "1.2 MB of 3.4 MB", when iCloud gave
    /// the sizes.
    var detail: String? {
        guard case .downloading(let progress) = step, progress.filesToDownload > 0,
              let total = progress.bytesToDownload, total > 0, let done = progress.downloadedBytes
        else { return nil }
        return "\(done.formatted(.byteCount(style: .file))) of \(total.formatted(.byteCount(style: .file)))"
    }

    /// Files iCloud Drive couldn't download, e.g. "2 files couldn't be
    /// downloaded: The Internet connection appears to be offline."
    var failureNote: String? {
        guard case .downloading(let progress) = step, let first = progress.failures.first else { return nil }
        let count = progress.failures.count
        let files = count == 1 ? "1 file" : "\(count.formatted()) files"
        return "\(files) couldn't be downloaded: \(first.message)"
    }

    /// The progress bar's value while downloading; `nil` shows a spinner.
    var fractionCompleted: Double? {
        guard case .downloading(let progress) = step, progress.isListed, progress.filesToDownload > 0 else { return nil }
        return progress.fractionCompleted
    }

    /// The heading once it has stalled.
    var stalledTitle: String {
        isICloud ? "Still waiting for iCloud Drive" : "Still opening your library"
    }

    /// What it's waiting for, once it has stalled.
    var stalledMessage: String {
        guard isICloud else { return "Opening your library is taking longer than it should." }
        switch step {
        case .looking:
            return "iCloud Drive hasn't said yet whether your library is there."
        case .downloading(let progress) where progress.isListed && progress.filesToDownload > 0:
            return "Your library is in iCloud Drive, but \((progress.filesToDownload - progress.downloadedFiles).formatted()) "
                + "of its files aren't on this device yet."
        case .downloading:
            return "Your library is in iCloud Drive, but iCloud Drive hasn't listed its files on this device yet."
        case .reading:
            return "Your library's files are taking a long time to arrive from iCloud Drive."
        }
    }

    /// Why iCloud Drive may not be delivering, once it has stalled; none
    /// for a library on this device. The settings are named as on an iPhone
    /// or iPad, or on a Mac.
    func stalledReasons(onMac: Bool) -> [String] {
        guard isICloud else { return [] }
        if onMac {
            return [
                "You're offline, or the connection is poor.",
                "Low Power Mode is on, which can pause iCloud downloads (System Settings › Battery).",
                "iCloud Drive is turned off for this app (System Settings › [your name] › iCloud › iCloud Drive).",
            ]
        }
        return [
            "You're offline, or the connection is poor.",
            "Cellular data is turned off for iCloud Drive (Settings › Cellular).",
            "Low Power Mode is on, which can pause iCloud downloads (Settings › Battery).",
            "iCloud Drive is turned off for this app (Settings › [your name] › iCloud › iCloud Drive).",
        ]
    }
}
