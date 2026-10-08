import Foundation
import Model
import Storage

/// The result of reloading changed files.
public struct ReloadResult: Sendable {
    /// The library passed in, with the reloaded files' entities replaced
    /// (or removed, for files that are gone).
    public var library: Library
    /// The library files that were reloaded. Take them over with
    /// `Library.replaceEntities(of:from:)`.
    public var files: [LibraryFile]
    /// The issues found in the reloaded files, which replace any earlier
    /// issues for the same paths.
    public var issues: [LoadIssue]

    public init(library: Library, files: [LibraryFile], issues: [LoadIssue]) {
        self.library = library
        self.files = files
        self.issues = issues
    }

    /// The paths of the reloaded files.
    public var paths: [String] { files.map(\.path) }
}

/// The library folder as the app uses it: every read and write goes through
/// here, one at a time and off the main thread.
///
/// It wraps Storage's `LibraryFolder` with the file access and version store
/// that suit the location (coordinated access; iCloud's versions for a
/// library in iCloud Drive), and adds conflict resolution. It holds no
/// library in memory; the caller does, and passes the previous and new
/// versions to ``save(_:previous:)``.
public actor LibrarySync {
    public nonisolated let location: LibraryLocation
    public nonisolated let folder: LibraryFolder
    private let versions: any FileVersionProviding

    /// A library folder at `location` with the given file access and
    /// version store.
    public init(location: LibraryLocation, files: any FileAccessing, versions: any FileVersionProviding) {
        self.location = location
        self.folder = LibraryFolder(root: location.url, files: files)
        self.versions = versions
    }

    /// A library folder at `location`, read and written with
    /// `CoordinatedFileAccess`, with iCloud's version store when it's in
    /// iCloud Drive.
    public init(location: LibraryLocation) {
        self.init(location: location, files: CoordinatedFileAccess(), versions: location.makeFileVersions())
    }

    // MARK: Library

    /// Whether the folder holds a library (it has a `library.json`).
    public func containsLibrary() -> Bool {
        folder.containsLibrary
    }

    /// Creates a new library in the folder (see `LibraryFolder.createLibrary`).
    public func createLibrary(settings: LibrarySettings) throws {
        try folder.createLibrary(settings: settings)
    }

    /// Loads the whole library. A library with an older schema is migrated
    /// first (after a backup); one with a newer schema loads read-only.
    public func load() throws -> LoadResult {
        let result = try folder.load()
        if result.report.needsMigration, try folder.migrate() != nil {
            return try folder.load()
        }
        return result
    }

    /// Loads the whole library (see ``load()``), with the modification dates
    /// of its files taken just before. Pass the snapshot to the watcher
    /// (`LibraryWatching.start(since:)`) so a file that changes while the
    /// library loads is reloaded, and to ``changes(since:)`` later.
    public func loadWithSnapshot() throws -> (result: LoadResult, snapshot: FolderSnapshot) {
        let snapshot = self.snapshot()
        return (try load(), snapshot)
    }

    /// The watched files and their modification dates now.
    public func snapshot() -> FolderSnapshot {
        FolderSnapshot.scan(folder.root, using: folder.files)
    }

    /// The files whose modification date changed since `previous` (added,
    /// changed or removed), and the snapshot they were found with, for the
    /// next call. For catching up when the app comes back to the
    /// foreground, whatever the watcher missed.
    public func changes(since previous: FolderSnapshot) -> (change: LibraryChange, snapshot: FolderSnapshot) {
        let current = snapshot()
        return (current.changes(since: previous), current)
    }

    /// Writes what changed between `previous` and `library`, merged with
    /// changes made on disk meanwhile (see `LibraryFolder.save(_:previous:)`).
    /// Reload the report's `reloadPaths`.
    public func save(_ library: Library, previous: Library) throws -> SaveReport {
        try folder.save(library, previous: previous)
    }

    /// Copies the files at `paths` into `backups/<timestamp>-<label>/`.
    public func backup(paths: [String], label: String) throws -> Backup {
        try folder.backup(paths: paths, label: label)
    }

    /// Records a backup's files as they are now, after the change it was
    /// taken for (see `LibraryFolder.recordResult(of:)`).
    public func recordResult(of backup: Backup) throws -> Backup {
        try folder.recordResult(of: backup)
    }

    /// Undoes the change a backup was taken for, leaving later edits in
    /// place (see `LibraryFolder.undo(_:dryRun:)`).
    public func undo(_ backup: Backup) throws -> UndoReport {
        try folder.undo(backup)
    }

    /// Puts a backup's files back as they were (see
    /// `LibraryFolder.restore(backup:)`).
    public func restore(_ backup: Backup) throws -> SaveReport {
        try folder.restore(backup: backup)
    }

    /// Reloads the files at `paths` (relative to the library folder) into a
    /// copy of `library`. Paths that aren't library data files are skipped.
    public func reload(paths: [String], in library: Library) -> ReloadResult {
        var copy = library
        var files: [LibraryFile] = []
        var issues: [LoadIssue] = []
        for path in Set(paths).sorted() {
            guard let file = LibraryFile(path: path) else { continue }
            files.append(file)
            issues += folder.reload(file, into: &copy)
        }
        return ReloadResult(library: copy, files: files, issues: issues)
    }

    /// Updates the folder's README to this app version's text, if needed.
    @discardableResult
    public func updateReadme() throws -> Bool {
        try folder.checkWritable()
        return try folder.updateReadme()
    }

    /// The backups in `backups/`, oldest first.
    public func backups() throws -> [Backup] {
        try folder.backups()
    }

    // MARK: Conflicts

    /// Resolves the sync conflicts in the files at `paths`: each version is
    /// merged into the file (PLAN.md, "Merging, saving and undo"). Reload the
    /// ``ConflictReport/changedPaths`` afterwards.
    public func resolveConflicts(at paths: [String], date: Date = Date()) -> ConflictReport {
        ConflictMerger(folder: folder, versions: versions).resolve(paths: paths, date: date)
    }

    /// Looks through every watched file for unresolved conflicts and
    /// resolves them. For launch, before a watcher has reported anything.
    public func resolveAllConflicts(date: Date = Date()) -> ConflictReport {
        let paths = ((try? folder.files.listFiles(in: folder.root)) ?? []).filter(LibraryChange.isWatched)
        let conflicted = paths.filter { path in
            !((try? versions.unresolvedVersions(of: folder.url(for: path))) ?? []).isEmpty
        }
        return resolveConflicts(at: conflicted, date: date)
    }
}
