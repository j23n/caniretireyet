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

    public init(issues: [LoadIssue] = [], schemaVersion: Int? = nil, filesRead: Int = 0) {
        self.issues = issues
        self.schemaVersion = schemaVersion
        self.filesRead = filesRead
    }

    /// Whether the library was written by a newer app version. It is then
    /// open read-only: every save throws ``StorageError/libraryIsNewer(version:supported:)``.
    public var isReadOnly: Bool {
        schemaVersion.map { $0 > LibrarySettings.currentSchemaVersion } ?? false
    }

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
