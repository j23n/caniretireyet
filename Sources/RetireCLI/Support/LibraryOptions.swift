import ArgumentParser
import Foundation
import Model
import Storage

/// `--library <path>`, shared by every command.
struct LibraryOptions: ParsableArguments {
    @Option(
        name: .long,
        help: ArgumentHelp(
            "The library folder. Default: $\(CLIContext.libraryVariable), or the current folder if it holds a library.",
            valueName: "path"))
    var library: String?

    /// The path given with `--library` or `$RETIRE_LIBRARY`, if any.
    func givenPath(in context: CLIContext) -> String? {
        if let library, !library.isEmpty { return library }
        if let path = context.environment[CLIContext.libraryVariable], !path.isEmpty { return path }
        return nil
    }

    /// The library folder: `--library`, then `$RETIRE_LIBRARY`, then the
    /// current folder when it holds a `library.json`.
    func folder(in context: CLIContext) throws -> LibraryFolder {
        if let path = givenPath(in: context) { return LibraryFolder(root: context.url(forPath: path)) }
        let current = LibraryFolder(root: context.currentDirectory)
        if current.containsLibrary { return current }
        throw CLIError("No library folder: pass --library <path> or set \(CLIContext.libraryVariable).")
    }

    /// Loads the library, which must exist and have a `library.json`. Load
    /// errors are reported on standard error with a pointer to `retire validate`.
    func load(in context: CLIContext) throws -> LoadedLibrary {
        let folder = try folder(in: context)
        guard folder.files.fileExists(at: folder.root) else {
            throw CLIError("The library folder \(folder.root.path) doesn't exist.")
        }
        guard folder.containsLibrary else {
            throw CLIError("\(folder.root.path) isn't a library: it has no library.json. Create one with `retire init`.")
        }
        // An older library is upgraded, after a backup, before anything is written.
        let (result, migration) = try folder.loadMigrating()
        if let migration {
            context.console.error("Upgraded the library from format version \(migration.fromVersion) to "
                + "\(migration.toVersion); the files as they were are in \(migration.backup.path)/.")
        }
        let errors = result.report.errors.count
        if errors > 0 {
            context.console.error("Warning: \(Wording.count(errors, "file problem")) while loading the library; "
                + "run `retire validate` for details.")
        }
        return LoadedLibrary(folder: folder, library: result.library)
    }
}

/// A library loaded from its folder.
struct LoadedLibrary {
    var folder: LibraryFolder
    var library: Library

    /// Throws unless this version may write to the library: one written by
    /// a newer version, or whose `library.json` can't be read (its settings
    /// are only defaults), is read-only.
    func checkWritable() throws {
        try folder.checkWritable(schemaVersion: library.settings.schemaVersion)
    }

    /// Writes `library` over the loaded one, as the commands that change it
    /// do: backs up the files it changes, and `alsoBackingUp`, into
    /// `backups/<timestamp>-<label>/`, saves them, and records in the backup
    /// what was written, so undoing leaves later edits alone. With `dryRun`,
    /// or when no file changes, nothing is written.
    func save(_ library: Library, backupLabel label: String, alsoBackingUp extra: [String] = [],
              dryRun: Bool = false, in context: CLIContext) throws -> SavedChanges {
        var saved = SavedChanges(changed: library.files(changedFrom: self.library).map(\.path).sorted())
        guard !dryRun, !saved.changed.isEmpty else { return saved }
        try checkWritable()
        let backup = try folder.backup(paths: saved.changed + extra, label: label, date: context.now())
        let report = try folder.save(library, previous: self.library)
        try folder.recordResult(of: backup)
        saved.written = report.written
        saved.deleted = report.deleted
        saved.backup = backup.path
        return saved
    }
}

/// What ``LoadedLibrary/save(_:backupLabel:alsoBackingUp:dryRun:in:)`` did,
/// or with a dry run would do.
struct SavedChanges {
    /// The files that differ from the loaded library, sorted: the ones
    /// written or deleted, or with a dry run the ones that would be.
    var changed: [String]
    var written: [String] = []
    var deleted: [String] = []
    /// The backup taken first, relative to the library folder; `nil` when
    /// nothing was written.
    var backup: String?
}

/// A date option, parsed as `YYYY-MM-DD`.
func parseDate(_ text: String?, option: String) throws -> CalendarDate? {
    guard let text else { return nil }
    guard let date = CalendarDate(text) else {
        throw ValidationError("\(option) must be a date written YYYY-MM-DD, not “\(text)”.")
    }
    return date
}
