import Foundation
import Storage

/// Files in the library folder that changed on disk: synced from another
/// device, or edited in a text editor.
public struct LibraryChange: Hashable, Sendable {
    /// Paths relative to the library folder of files that were added,
    /// changed or removed, sorted. Reload them with `LibrarySync.reload`.
    public var paths: [String]
    /// Paths of files with unresolved sync conflicts, sorted. Resolve them
    /// with `LibrarySync.resolveConflicts`.
    public var conflictedPaths: [String]

    public init(paths: [String] = [], conflictedPaths: [String] = []) {
        self.paths = paths
        self.conflictedPaths = conflictedPaths
    }

    public var isEmpty: Bool { paths.isEmpty && conflictedPaths.isEmpty }

    /// Which paths are watched: JSON files outside `backups/`. The README and
    /// anything the app doesn't read are ignored.
    public static func isWatched(_ path: String) -> Bool {
        path.hasSuffix(".json") && !path.hasPrefix(LibraryFolder.backupsFolder + "/")
            && !path.split(separator: "/").contains { $0.hasPrefix(".") }
    }
}

/// What a watcher knows about one file.
public struct WatchedFileState: Hashable, Sendable {
    /// When its contents last changed, if known.
    public var modified: Date?
    /// Whether the file's current contents are on this device. Files that
    /// aren't are reported once they are.
    public var isDownloaded: Bool
    /// Whether it has unresolved sync conflicts.
    public var hasConflicts: Bool

    public init(modified: Date?, isDownloaded: Bool = true, hasConflicts: Bool = false) {
        self.modified = modified
        self.isDownloaded = isDownloaded
        self.hasConflicts = hasConflicts
    }
}

/// The watched files of a library folder at one moment, by relative path.
/// Comparing two snapshots gives the ``LibraryChange`` between them.
public struct FolderSnapshot: Hashable, Sendable {
    public var files: [String: WatchedFileState]

    public init(files: [String: WatchedFileState] = [:]) {
        self.files = files.filter { LibraryChange.isWatched($0.key) }
    }

    /// The watched files under `root` with their modification dates, read
    /// with `access` (placeholders of files not downloaded count as not
    /// downloaded).
    public static func scan(_ root: URL, using access: any FileAccessing = CoordinatedFileAccess()) -> FolderSnapshot {
        let paths = (try? access.listFiles(in: root)) ?? []
        var files: [String: WatchedFileState] = [:]
        for path in paths where LibraryChange.isWatched(path) {
            let url = root.appendingPathComponent(path)
            let downloaded = FileManager.default.fileExists(atPath: url.path)
            files[path] = WatchedFileState(modified: try? access.modificationDate(of: url), isDownloaded: downloaded)
        }
        return FolderSnapshot(files: files)
    }

    /// What changed since `previous`:
    ///
    /// - a downloaded file that is new, or whose modification date changed,
    ///   or that has just finished downloading;
    /// - a file that is gone;
    /// - conflicts: files that have unresolved conflicts now and didn't
    ///   before, or changed since.
    ///
    /// Files still downloading are left out until they're downloaded.
    public func changes(since previous: FolderSnapshot) -> LibraryChange {
        var paths: Set<String> = []
        var conflicted: Set<String> = []
        for (path, state) in files {
            let old = previous.files[path]
            if state.isDownloaded, old == nil || old?.modified != state.modified || old?.isDownloaded == false {
                paths.insert(path)
            }
            if state.hasConflicts, old?.hasConflicts != true || old?.modified != state.modified {
                conflicted.insert(path)
            }
        }
        for path in previous.files.keys where files[path] == nil {
            paths.insert(path)
        }
        return LibraryChange(paths: paths.sorted(), conflictedPaths: conflicted.sorted())
    }

    /// What a watcher reports when it first looks: only the conflicts. The
    /// files themselves were just loaded.
    public var initialChange: LibraryChange {
        LibraryChange(conflictedPaths: files.filter(\.value.hasConflicts).keys.sorted())
    }

    /// The paths of files that aren't downloaded yet, sorted.
    public var notDownloaded: [String] {
        files.filter { !$0.value.isDownloaded }.keys.sorted()
    }
}

/// Collects changes between flushes, so a burst of file events becomes one
/// ``LibraryChange``.
public struct ChangeBatcher: Hashable, Sendable {
    private var paths: Set<String> = []
    private var conflicted: Set<String> = []

    public init() {}

    public var isEmpty: Bool { paths.isEmpty && conflicted.isEmpty }

    public mutating func add(_ change: LibraryChange) {
        paths.formUnion(change.paths)
        conflicted.formUnion(change.conflictedPaths)
    }

    /// Everything collected since the last call, or `nil` if nothing was.
    public mutating func take() -> LibraryChange? {
        guard !isEmpty else { return nil }
        defer {
            paths = []
            conflicted = []
        }
        return LibraryChange(paths: paths.sorted(), conflictedPaths: conflicted.sorted())
    }
}
