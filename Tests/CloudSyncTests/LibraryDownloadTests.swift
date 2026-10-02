import CloudSync
import Foundation
import Storage
import Testing

/// Downloading a library from iCloud Drive before it's read: what's asked
/// for, the progress, and noticing when nothing moves.
struct LibraryDownloadTests {
    /// iCloud's status of a file that isn't on the device yet.
    private func missing(_ path: String, size: Int64? = nil, downloading: Bool = false, fraction: Double? = nil,
                         error: String? = nil) -> UbiquitousFileStatus {
        UbiquitousFileStatus(path: path, isCurrent: false, isDownloading: downloading, size: size,
                             downloadedFraction: fraction, error: error)
    }

    private func current(_ path: String, size: Int64? = nil) -> UbiquitousFileStatus {
        UbiquitousFileStatus(path: path, isCurrent: true, size: size)
    }

    @Test func downloadsTheFilesTheLibraryReadsAndTheReadme() {
        #expect(LibraryDownloadTracker.includes("library.json"))
        #expect(LibraryDownloadTracker.includes("accounts/directa.json"))
        #expect(LibraryDownloadTracker.includes("history/2017/2017-01.json"))
        #expect(LibraryDownloadTracker.includes("README.md"))
        #expect(!LibraryDownloadTracker.includes("backups/2026-09-30-import/accounts/directa.json"))
        #expect(!LibraryDownloadTracker.includes("notes.txt"))
        #expect(!LibraryDownloadTracker.includes(".hidden/x.json"))
    }

    @Test func aLibraryAlreadyOnTheDeviceIsCompleteAtOnce() {
        var tracker = LibraryDownloadTracker()
        let requests = tracker.seed(disk: ["library.json": true, "accounts/casa.json": true, "README.md": true,
                                           "backups/x/accounts/casa.json": false])
        #expect(requests.isEmpty)
        let progress = tracker.progress
        #expect(progress.isComplete)
        #expect(!progress.isListed)
        #expect(progress.totalFiles == 3)
        #expect(progress.filesToDownload == 0)
        #expect(progress.fractionCompleted == nil)
    }

    @Test func aFolderWithoutLibraryJSONIsNeverComplete() {
        var tracker = LibraryDownloadTracker()
        _ = tracker.seed(disk: [:])
        #expect(!tracker.progress.isComplete)
        _ = tracker.seed(disk: ["accounts/casa.json": true])
        #expect(!tracker.progress.isComplete)
        // iCloud lists it, not downloaded yet.
        #expect(tracker.update([missing("library.json"), current("accounts/casa.json")]) == ["library.json"])
        #expect(!tracker.progress.isComplete)
        _ = tracker.update([current("library.json"), current("accounts/casa.json")])
        #expect(tracker.progress.isComplete)
    }

    @Test func asksForEveryMissingFileOnceAndCountsThemIn() {
        var tracker = LibraryDownloadTracker()
        // Placeholders on disk are asked for before iCloud lists anything.
        let first = tracker.seed(disk: ["library.json": false, "accounts/casa.json": true,
                                        "history/2017/2017-01.json": false])
        #expect(first == ["history/2017/2017-01.json", "library.json"])
        #expect(tracker.progress.filesToDownload == 2)
        #expect(tracker.progress.downloadedFiles == 0)

        // iCloud's list has more files; those already asked for aren't asked again,
        // nor one iCloud is downloading already.
        let second = tracker.update([
            missing("library.json", size: 200, downloading: true, fraction: 0.5),
            current("accounts/casa.json", size: 300),
            missing("history/2017/2017-01.json", size: 1_000),
            missing("history/2017/2017-02.json", size: 1_000),
            missing("history/2017/2017-03.json", size: 1_000, downloading: true),
            missing("backups/x/library.json", size: 200),
        ])
        #expect(second == ["history/2017/2017-02.json"])
        var progress = tracker.progress
        #expect(progress.isListed)
        #expect(progress.totalFiles == 5)
        #expect(progress.filesToDownload == 4)
        #expect(progress.downloadedFiles == 0)
        #expect(progress.bytesToDownload == 3_200)
        #expect(progress.downloadedBytes == 100)
        #expect(!progress.isComplete)

        // Files arrive.
        let third = tracker.update([
            current("library.json", size: 200),
            current("accounts/casa.json", size: 300),
            current("history/2017/2017-01.json", size: 1_000),
            missing("history/2017/2017-02.json", size: 1_000, downloading: true, fraction: 0.25),
            missing("history/2017/2017-03.json", size: 1_000, downloading: true, fraction: 1),
        ])
        #expect(third.isEmpty)
        progress = tracker.progress
        #expect(progress.downloadedFiles == 2)
        #expect(progress.filesToDownload == 4)
        // library.json and 2017-01 (200 + 1,000), a quarter of 2017-02, all of 2017-03.
        let downloadedBytes: Int64 = 2_450
        #expect(progress.downloadedBytes == downloadedBytes)
        #expect(progress.fractionCompleted == 2_450.0 / 3_200)

        _ = tracker.update([
            current("library.json"), current("accounts/casa.json"), current("history/2017/2017-01.json"),
            current("history/2017/2017-02.json"), current("history/2017/2017-03.json"),
        ])
        progress = tracker.progress
        #expect(progress.isComplete)
        #expect(progress.downloadedFiles == 4)
        // Sizes no longer known: counted by files.
        #expect(progress.bytesToDownload == nil)
        #expect(progress.fractionCompleted == 1)
    }

    @Test func aFileThatChangesAgainIsAskedForAgain() {
        var tracker = LibraryDownloadTracker()
        _ = tracker.seed(disk: ["library.json": true])
        #expect(tracker.update([current("library.json"), missing("plans/base.json")]) == ["plans/base.json"])
        #expect(tracker.update([current("library.json"), current("plans/base.json")]).isEmpty)
        #expect(tracker.update([current("library.json"), missing("plans/base.json")]) == ["plans/base.json"])
        #expect(tracker.progress.filesToDownload == 1)
    }

    @Test func failuresAreReportedAndAskedForAgainOnRequest() {
        var tracker = LibraryDownloadTracker()
        _ = tracker.seed(disk: ["library.json": true])
        let offline = "The Internet connection appears to be offline."
        let requests = tracker.update([
            current("library.json"),
            missing("accounts/casa.json", error: offline),
            missing("accounts/tfr.json"),
        ])
        // A file iCloud failed on isn't asked for by itself.
        #expect(requests == ["accounts/tfr.json"])
        tracker.requestFailed("accounts/tfr.json", message: "Not allowed")
        var progress = tracker.progress
        #expect(progress.failures == [
            LibraryDownloadFailure(path: "accounts/casa.json", message: offline),
            LibraryDownloadFailure(path: "accounts/tfr.json", message: "Not allowed"),
        ])
        #expect(!progress.isComplete)

        // Keep waiting: both are asked for again, and the failures are forgotten
        // until iCloud reports them again.
        #expect(tracker.requestAgain() == ["accounts/casa.json", "accounts/tfr.json"])
        progress = tracker.progress
        #expect(progress.failures.isEmpty)

        // A file that arrives is no longer a failure.
        _ = tracker.update([current("library.json"), current("accounts/casa.json"),
                            missing("accounts/tfr.json", error: offline)])
        #expect(tracker.progress.failures == [LibraryDownloadFailure(path: "accounts/tfr.json", message: offline)])
    }

    @Test func progressAdvancesWhenFilesAreListedOrArrive() {
        let start = LibraryDownloadProgress(filesToDownload: 2)
        #expect(start.hasAdvanced(since: nil))
        #expect(!start.hasAdvanced(since: start))
        var listed = start
        listed.isListed = true
        #expect(listed.hasAdvanced(since: start))
        var more = listed
        more.totalFiles = 150
        #expect(more.hasAdvanced(since: listed))
        var oneFile = more
        oneFile.downloadedFiles = 1
        #expect(oneFile.hasAdvanced(since: more))
        var someBytes = oneFile
        someBytes.downloadedBytes = 10
        #expect(someBytes.hasAdvanced(since: oneFile))
        var failed = someBytes
        failed.failures = [LibraryDownloadFailure(path: "library.json", message: "Offline")]
        #expect(!failed.hasAdvanced(since: someBytes))
        var complete = failed
        complete.isComplete = true
        #expect(complete.hasAdvanced(since: failed))
    }

    @Test func noticesWhenNothingMoves() {
        let start = ContinuousClock.now
        var detector = StallDetector(threshold: .seconds(20), now: start)
        #expect(!detector.isStalled(at: start + .seconds(19)))
        #expect(detector.isStalled(at: start + .seconds(20)))
        #expect(detector.deadline == start + .seconds(20))
        detector.noteProgress(at: start + .seconds(15))
        #expect(!detector.isStalled(at: start + .seconds(30)))
        #expect(detector.isStalled(at: start + .seconds(35)))
    }

    @Test func scansTheFolderForPlaceholders() throws {
        let folder = try TemporaryFolder()
        try folder.write("library.json", "{}")
        try folder.write("accounts/.casa.json.icloud", "placeholder")
        try folder.write("history/2017/2017-01.json", "{}")
        try folder.write("backups/x/library.json", "{}")
        try folder.write("README.md", "readme")
        #expect(LibraryDownloadTracker.scanDisk(folder.url) == [
            "library.json": true, "accounts/casa.json": false, "history/2017/2017-01.json": true, "README.md": true,
        ])
        // What iCloud's resource values say wins.
        let scanned = LibraryDownloadTracker.scanDisk(folder.url) { url in
            url.lastPathComponent == "2017-01.json" ? false : nil
        }
        #expect(scanned["history/2017/2017-01.json"] == false)
        #expect(scanned["library.json"] == true)
    }

    @MainActor
    @Test func thereIsNothingToDownloadOutsideICloud() throws {
        let folder = try TemporaryFolder()
        #expect(LibraryLocation(kind: .local, url: folder.url).makeDownloader() == nil)
        #if !canImport(Darwin)
        #expect(LibraryLocation(kind: .iCloud, url: folder.url).makeDownloader() == nil)
        #endif
    }

    @MainActor
    @Test func aPlaceholderOfLibraryJSONCountsAsALibrary() async throws {
        let folder = try TemporaryFolder()
        let location = LibraryLocation(kind: .iCloud, url: folder.url)
        #if !canImport(Darwin)
        #expect(await !location.containsLibrary(waitingUpTo: .milliseconds(10)))
        #endif
        try folder.write(".library.json.icloud", "placeholder")
        #expect(await location.containsLibrary(waitingUpTo: .milliseconds(10)))
    }
}
