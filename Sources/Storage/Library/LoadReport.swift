import Model

/// A loaded library and what was found wrong with its files.
public struct LoadResult: Sendable {
    public var library: Library
    public var report: LoadReport

    public init(library: Library, report: LoadReport) {
        self.library = library
        self.report = report
    }
}

/// What loading a library folder found.
public struct LoadReport: Hashable, Sendable {
    /// Problems in individual files, sorted by path.
    public var issues: [LoadIssue]
    /// The `schemaVersion` in `library.json`, if it could be read.
    public var schemaVersion: Int?
    /// The number of data files read.
    public var filesRead: Int
    /// Whether `library.json` exists but couldn't be used: it can't be read,
    /// isn't valid JSON, or doesn't hold the settings. The library then has
    /// default settings in memory and is open read-only, so a save can't
    /// replace your settings with those defaults (see ``readOnlyReason``).
    /// `false` when there's no `library.json` at all.
    public var settingsUnreadable: Bool

    public init(issues: [LoadIssue] = [], schemaVersion: Int? = nil, filesRead: Int = 0,
                settingsUnreadable: Bool = false) {
        self.issues = issues
        self.schemaVersion = schemaVersion
        self.filesRead = filesRead
        self.settingsUnreadable = settingsUnreadable
    }

    /// Whether the library was written by a newer app version. It is then
    /// open read-only: every save throws ``StorageError/libraryIsNewer(version:supported:)``.
    public var isNewerSchema: Bool {
        schemaVersion.map { $0 > LibrarySettings.currentSchemaVersion } ?? false
    }

    /// Whether the library is open read-only: it was written by a newer app
    /// version (``isNewerSchema``), or its `library.json` can't be used
    /// (``settingsUnreadable``). Every save then throws.
    public var isReadOnly: Bool {
        isNewerSchema || settingsUnreadable
    }

    /// Why the library is open read-only, or `nil` when it isn't.
    public var readOnlyReason: ReadOnlyReason? {
        if isNewerSchema { return .newerSchema }
        return settingsUnreadable ? .unreadableSettings : nil
    }

    /// Why a library is open read-only, for the words that tell you what to do.
    public enum ReadOnlyReason: Hashable, Sendable {
        /// A newer app version wrote it (``LoadReport/isNewerSchema``): update the app.
        case newerSchema
        /// Its `library.json` exists but can't be used
        /// (``LoadReport/settingsUnreadable``): fix the file or restore it
        /// from a backup, then open the library again.
        case unreadableSettings
    }

    /// What a library whose `library.json` can't be used means, and what to do.
    static let unreadableSettingsAdvice = "The library is open read-only: saving would replace your settings with "
        + "defaults. Fix the file, or restore it from a backup in backups/, then open the library again."

    /// Whether the library uses an older schema and must be migrated (see
    /// ``LibraryFolder/migrate(to:steps:date:)``) before it can be saved.
    public var needsMigration: Bool {
        schemaVersion.map { $0 < LibrarySettings.currentSchemaVersion } ?? false
    }

    /// Issues where a file or record couldn't be loaded.
    public var errors: [LoadIssue] { issues.filter { $0.severity == .error } }

    /// Issues where everything was loaded but something looks wrong.
    public var warnings: [LoadIssue] { issues.filter { $0.severity == .warning } }

    /// The issues for one file.
    public func issues(for path: String) -> [LoadIssue] {
        issues.filter { $0.path == path }
    }
}

/// A problem in one file, found while loading.
public struct LoadIssue: Hashable, Sendable, CustomStringConvertible {
    /// How much of the file was affected.
    public enum Severity: String, Hashable, Sendable {
        /// The file, or some records in it, couldn't be loaded.
        case error
        /// Everything was loaded, but something should be fixed.
        case warning
    }

    /// The file's path relative to the library folder.
    public var path: String
    /// What is wrong, and where in the file, in plain words.
    public var message: String
    public var severity: Severity

    public init(path: String, message: String, severity: Severity) {
        self.path = path
        self.message = message
        self.severity = severity
    }

    /// `path: message`
    public var description: String { "\(path): \(message)" }
}
