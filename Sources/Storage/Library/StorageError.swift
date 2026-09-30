/// Why Storage refused or failed to do something with the library folder.
/// Problems in individual files found while loading are ``LoadIssue``s instead.
public enum StorageError: Error, Hashable, Sendable, CustomStringConvertible {
    /// The library was written by a newer version of the app, so this one
    /// opens it read-only and won't write to it.
    case libraryIsNewer(version: Int, supported: Int)
    /// The library uses an older schema; it must be migrated before saving.
    case libraryNeedsMigration(version: Int, current: Int)
    /// There is no migration step from this schema version.
    case missingMigration(from: Int)
    /// A new library can't be created where one already exists.
    case libraryAlreadyExists(path: String)
    /// The library folder doesn't exist.
    case folderNotFound(path: String)
    /// A path that doesn't point inside the library folder, or is reserved.
    case invalidPath(String)
    /// The backup doesn't exist, or its `backup.json` can't be read.
    case backupNotFound(String)
    /// A file Storage needs can't be read.
    case unreadableFile(path: String, message: String)
    /// A file kept changing on disk while it was being saved, so it wasn't
    /// written.
    case fileKeptChanging(path: String)
    /// The backup was taken from a library in another format version, so
    /// restoring it would mix formats.
    case backupFromOtherVersion(name: String, version: Int, current: Int)

    public var description: String {
        switch self {
        case .libraryIsNewer(let version, let supported):
            "This library was written by a newer version of the app (format version \(version); this version "
                + "understands up to \(supported)). It's open read-only: update the app to make changes."
        case .libraryNeedsMigration(let version, let current):
            "This library uses format version \(version) and must be upgraded to version \(current) before saving."
        case .missingMigration(let version):
            "There is no upgrade from format version \(version)."
        case .libraryAlreadyExists(let path):
            "There is already a library at \(path)."
        case .folderNotFound(let path):
            "The library folder \(path) doesn't exist."
        case .invalidPath(let path):
            "\"\(path)\" isn't a file inside the library folder."
        case .backupNotFound(let name):
            "The backup \"\(name)\" doesn't exist or can't be read."
        case .unreadableFile(let path, let message):
            "\(path): \(message)"
        case .fileKeptChanging(let path):
            "\(path) kept changing on disk while it was being saved, so it wasn't written. Try again."
        case .backupFromOtherVersion(let name, let version, let current):
            "The backup \"\(name)\" was taken from a library in format version \(version), and this library uses "
                + "version \(current), so it can't be restored automatically. Its files are in backups/\(name)/."
        }
    }
}
