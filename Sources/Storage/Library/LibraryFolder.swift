import Foundation
import Model

/// A library folder on disk (docs/schema): loads it into a `Library`,
/// writes back only what changed, and keeps backups.
///
/// It holds no state besides where the folder is and how to reach it, so it
/// can be used from any thread. The in-memory `Library` belongs to the
/// caller, who passes the previous and the new version to
/// ``save(_:previous:)``.
public struct LibraryFolder: Sendable {
    /// The library folder.
    public let root: URL
    /// How files are read and written.
    public let files: any FileAccessing

    public init(root: URL, files: any FileAccessing = LocalFileAccess()) {
        self.root = root
        self.files = files
    }

    /// The URL of a path relative to the library folder.
    public func url(for path: String) -> URL {
        root.appendingPathComponent(path)
    }

    /// The URL of a library file.
    public func url(for file: LibraryFile) -> URL {
        url(for: file.path)
    }

    /// The path of `url` relative to the library folder
    /// (`history/2026/2026-09.json`), or `nil` if it isn't inside it. Use
    /// ``LibraryFile/init(path:)`` to tell which file changed.
    public func relativePath(of url: URL) -> String? {
        func components(_ url: URL) -> [String] { url.standardizedFileURL.pathComponents }
        for (base, target) in [
            (components(root), components(url)),
            (components(root.resolvingSymlinksInPath()), components(url.resolvingSymlinksInPath())),
        ] where target.count > base.count && Array(target.prefix(base.count)) == base {
            return target.dropFirst(base.count).joined(separator: "/")
        }
        return nil
    }

    /// Whether the folder holds a library (it has a `library.json`).
    public var containsLibrary: Bool {
        files.fileExists(at: url(for: LibraryFile.settings))
    }

    /// The `schemaVersion` written in `library.json`, if it can be read.
    public func schemaVersionOnDisk() -> Int? {
        guard let data = try? files.readData(at: url(for: LibraryFile.settings)),
              let json = try? CanonicalJSON.parse(data)
        else { return nil }
        return json["schemaVersion"]?.intValue
    }

    /// Throws unless this app version may write to the library: the schema
    /// version in memory (if given) and on disk must be the current one, and
    /// a `library.json` on disk must be readable: one that can't be read,
    /// isn't valid JSON or doesn't hold the settings throws
    /// ``StorageError/unreadableFile(path:message:)``, since the settings in
    /// memory are then only defaults. A folder without `library.json` (a new
    /// library) can be written.
    public func checkWritable(schemaVersion: Int? = nil) throws {
        try checkSchemaVersions(schemaVersion)
        try checkSettingsReadable()
    }

    /// Throws unless the schema version in memory (if given) and on disk
    /// are the current one.
    func checkSchemaVersions(_ schemaVersion: Int?) throws {
        let current = LibrarySettings.currentSchemaVersion
        for version in [schemaVersion, schemaVersionOnDisk()].compactMap({ $0 }) {
            if version > current { throw StorageError.libraryIsNewer(version: version, supported: current) }
            if version < current { throw StorageError.libraryNeedsMigration(version: version, current: current) }
        }
    }

    /// Throws when `library.json` exists but can't be loaded as it is
    /// (``LoadReport/settingsUnreadable``).
    func checkSettingsReadable() throws {
        let settings = url(for: LibraryFile.settings)
        guard files.fileExists(at: settings) else { return }
        guard let data = try? files.readData(at: settings),
              !LibraryLoader.decode(.settings, from: data, in: self).hasErrors
        else {
            throw StorageError.unreadableSettings
        }
    }

    /// Checks that `path` is a plain relative path inside the folder.
    func validateRelativePath(_ path: String) throws {
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        guard !path.isEmpty, !path.hasPrefix("/"),
              parts.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." })
        else { throw StorageError.invalidPath(path) }
    }
}
