import CloudSync
import Foundation
import Testing

/// What a watcher reports: changes between two looks at the folder.
struct SnapshotTests {
    private let t0 = Date(timeIntervalSince1970: 1_790_000_000)
    private let t1 = Date(timeIntervalSince1970: 1_790_000_100)

    @Test func onlyLibraryDataIsWatched() {
        #expect(LibraryChange.isWatched("accounts/casa.json"))
        #expect(LibraryChange.isWatched("library.json"))
        #expect(!LibraryChange.isWatched("README.md"))
        #expect(!LibraryChange.isWatched("backups/2026-09-30-v1/library.json"))
        #expect(!LibraryChange.isWatched(".Trash/casa.json"))
    }

    @Test func reportsAddedChangedAndRemovedFiles() {
        let before = FolderSnapshot(files: [
            "accounts/casa.json": WatchedFileState(modified: t0),
            "accounts/tfr.json": WatchedFileState(modified: t0),
            "plans/base.json": WatchedFileState(modified: t0),
        ])
        let after = FolderSnapshot(files: [
            "accounts/casa.json": WatchedFileState(modified: t0),
            "accounts/tfr.json": WatchedFileState(modified: t1),
            "accounts/directa.json": WatchedFileState(modified: t1),
            "README.md": WatchedFileState(modified: t1),
        ])
        let change = after.changes(since: before)
        #expect(change.paths == ["accounts/directa.json", "accounts/tfr.json", "plans/base.json"])
        #expect(change.conflictedPaths.isEmpty)
        #expect(after.changes(since: after).isEmpty)
    }

    @Test func waitsForDownloads() {
        let before = FolderSnapshot(files: ["history/2026/2026-09.json": WatchedFileState(modified: t0)])
        let downloading = FolderSnapshot(files: [
            "history/2026/2026-09.json": WatchedFileState(modified: t1, isDownloaded: false),
        ])
        #expect(downloading.changes(since: before).isEmpty)
        #expect(downloading.notDownloaded == ["history/2026/2026-09.json"])

        let downloaded = FolderSnapshot(files: ["history/2026/2026-09.json": WatchedFileState(modified: t1)])
        #expect(downloaded.changes(since: downloading).paths == ["history/2026/2026-09.json"])
    }

    @Test func reportsNewConflictsOnce() {
        let clean = FolderSnapshot(files: ["history/2026/2026-09.json": WatchedFileState(modified: t0)])
        let conflicted = FolderSnapshot(files: [
            "history/2026/2026-09.json": WatchedFileState(modified: t0, hasConflicts: true),
        ])
        #expect(conflicted.changes(since: clean).conflictedPaths == ["history/2026/2026-09.json"])
        #expect(conflicted.changes(since: conflicted).isEmpty)
        #expect(conflicted.initialChange == LibraryChange(conflictedPaths: ["history/2026/2026-09.json"]))
        #expect(clean.initialChange.isEmpty)
    }

    @Test func scansAFolder() throws {
        let folder = try TemporaryFolder()
        try folder.write("accounts/casa.json", "{}")
        try folder.write("accounts/.directa.json.icloud", "placeholder")
        try folder.write("README.md", "hello")
        let snapshot = FolderSnapshot.scan(folder.url)
        #expect(Set(snapshot.files.keys) == ["accounts/casa.json", "accounts/directa.json"])
        #expect(snapshot.notDownloaded == ["accounts/directa.json"])
    }

    @Test func batchesChanges() {
        var batcher = ChangeBatcher()
        #expect(batcher.take() == nil)
        batcher.add(LibraryChange(paths: ["b.json", "a.json"]))
        batcher.add(LibraryChange(paths: ["a.json"], conflictedPaths: ["c.json"]))
        #expect(batcher.take() == LibraryChange(paths: ["a.json", "b.json"], conflictedPaths: ["c.json"]))
        #expect(batcher.isEmpty)
    }
}
