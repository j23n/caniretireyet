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
        var result = try folder.load()
        if result.report.needsMigration, let migration = try folder.migrate() {
            // As the app does: an older library is upgraded, after a backup, before anything is written.
            context.console.error("Upgraded the library from format version \(migration.fromVersion) to "
                + "\(migration.toVersion); the files as they were are in \(migration.backup.path)/.")
            result = try folder.load()
        }
        let errors = result.report.errors.count
        if errors > 0 {
            context.console.error("Warning: \(Format.count(errors, "file problem")) while loading the library; "
                + "run `retire validate` for details.")
        }
        return LoadedLibrary(folder: folder, library: result.library, report: result.report)
    }
}

/// A library loaded from its folder.
struct LoadedLibrary {
    var folder: LibraryFolder
    var library: Library
    var report: LoadReport

    /// Throws unless this version may write to the library.
    func checkWritable() throws {
        if report.isNewerSchema, let version = report.schemaVersion {
            throw StorageError.libraryIsNewer(version: version, supported: LibrarySettings.currentSchemaVersion)
        }
        // Its settings are only defaults: never write them over the file.
        if report.settingsUnreadable { throw StorageError.unreadableSettings }
        try folder.checkWritable(schemaVersion: library.settings.schemaVersion)
    }
}

/// A date option, parsed as `YYYY-MM-DD`.
func parseDate(_ text: String?, option: String) throws -> CalendarDate? {
    guard let text else { return nil }
    guard let date = CalendarDate(text) else {
        throw ValidationError("\(option) must be a date written YYYY-MM-DD, not “\(text)”.")
    }
    return date
}
