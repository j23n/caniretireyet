import Foundation

/// One version of a file that is in conflict with the current one.
public struct StoredFileVersion: Hashable, Sendable {
    /// Identifies the version to ``FileVersionProviding/markResolved(_:of:)``.
    public var id: String
    public var data: Data
    public var modified: Date
    /// The name of the device that saved it, if known.
    public var source: String?

    public init(id: String, data: Data, modified: Date, source: String? = nil) {
        self.id = id
        self.data = data
        self.modified = modified
        self.source = source
    }
}

/// Where the other versions of a file in a sync conflict are kept.
///
/// On Apple platforms that's iCloud's version store (``UbiquitousFileVersions``,
/// through `NSFileVersion`); a local library never has conflicts
/// (``NoFileVersions``). Tests supply their own.
public protocol FileVersionProviding: Sendable {
    /// The versions of the file at `url` that conflict with the current one
    /// and haven't been resolved, with their contents. Empty when there's no
    /// conflict.
    func unresolvedVersions(of url: URL) throws -> [StoredFileVersion]

    /// The name of the device that saved the current version, if known.
    func currentVersionSource(of url: URL) -> String?

    /// Marks the versions with these IDs resolved and removes them. Versions
    /// that appeared since they were read are left alone.
    func markResolved(_ ids: [String], of url: URL) throws
}

/// No versions and no conflicts: for a library that isn't synced.
public struct NoFileVersions: FileVersionProviding {
    public init() {}

    public func unresolvedVersions(of url: URL) throws -> [StoredFileVersion] { [] }

    public func currentVersionSource(of url: URL) -> String? { nil }

    public func markResolved(_ ids: [String], of url: URL) throws {}
}

#if canImport(Darwin)
/// iCloud's version store, through `NSFileVersion`.
public struct UbiquitousFileVersions: FileVersionProviding {
    public init() {}

    public func unresolvedVersions(of url: URL) throws -> [StoredFileVersion] {
        guard let versions = NSFileVersion.unresolvedConflictVersionsOfItem(at: url), !versions.isEmpty else {
            return []
        }
        return try versions.map { version in
            StoredFileVersion(
                id: version.url.path, data: try Data(contentsOf: version.url),
                modified: version.modificationDate ?? .distantPast, source: version.localizedNameOfSavingComputer)
        }
    }

    public func currentVersionSource(of url: URL) -> String? {
        NSFileVersion.currentVersionOfItem(at: url)?.localizedNameOfSavingComputer
    }

    public func markResolved(_ ids: [String], of url: URL) throws {
        let resolved = Set(ids)
        for version in NSFileVersion.unresolvedConflictVersionsOfItem(at: url) ?? []
        where resolved.contains(version.url.path) {
            version.isResolved = true
        }
        // Clean up the version store only when nothing new arrived meanwhile.
        if (NSFileVersion.unresolvedConflictVersionsOfItem(at: url) ?? []).isEmpty {
            try NSFileVersion.removeOtherVersionsOfItem(at: url)
        }
    }
}
#endif

extension LibraryLocation {
    /// The version store for this location: iCloud's for a library in
    /// iCloud Drive (on Apple platforms), none otherwise.
    public func makeFileVersions() -> any FileVersionProviding {
        #if canImport(Darwin)
        if isUbiquitous { return UbiquitousFileVersions() }
        #endif
        return NoFileVersions()
    }
}
