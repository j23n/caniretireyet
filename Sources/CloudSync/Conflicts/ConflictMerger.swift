import Foundation
import Storage

/// A sync conflict that was resolved, for the Sync screen and the Overview's
/// "Needs attention".
public struct ConflictResolution: Hashable, Sendable, Identifiable {
    /// The file's path relative to the library folder.
    public var path: String
    /// What was merged, in plain words (from `ConflictResolver`).
    public var summary: String
    /// How many versions were merged, the current one included.
    public var versionCount: Int
    /// Records taken from a version other than the newest.
    public var recordsAdded: Int
    /// Records that differed between versions; the newest version's was kept.
    public var conflictingRecords: [String]
    /// When it was resolved.
    public var resolvedAt: Date

    public init(path: String, summary: String, versionCount: Int, recordsAdded: Int = 0,
                conflictingRecords: [String] = [], resolvedAt: Date) {
        self.path = path
        self.summary = summary
        self.versionCount = versionCount
        self.recordsAdded = recordsAdded
        self.conflictingRecords = conflictingRecords
        self.resolvedAt = resolvedAt
    }

    public var id: String { "\(path)@\(resolvedAt.timeIntervalSinceReferenceDate)" }
}

/// A conflict that couldn't be resolved.
public struct ConflictFailure: Hashable, Sendable, Identifiable {
    public var path: String
    public var message: String

    public init(path: String, message: String) {
        self.path = path
        self.message = message
    }

    public var id: String { path }
}

/// What resolving conflicts did.
public struct ConflictReport: Hashable, Sendable {
    public var resolved: [ConflictResolution]
    public var failed: [ConflictFailure]

    public init(resolved: [ConflictResolution] = [], failed: [ConflictFailure] = []) {
        self.resolved = resolved
        self.failed = failed
    }

    /// The paths whose contents may have changed.
    public var changedPaths: [String] { resolved.map(\.path) }

    public var isEmpty: Bool { resolved.isEmpty && failed.isEmpty }
}

/// Resolves sync conflicts in a library folder (FILE_FORMAT.md, "Sync
/// conflicts"): reads the current file and every unresolved version, merges
/// them with `ConflictResolver.merge(path:_:)`, writes the result, and marks
/// the versions resolved.
public struct ConflictMerger: Sendable {
    public let folder: LibraryFolder
    public let versions: any FileVersionProviding

    public init(folder: LibraryFolder, versions: any FileVersionProviding) {
        self.folder = folder
        self.versions = versions
    }

    /// Resolves the conflict in the file at `path` (relative to the library
    /// folder), or returns `nil` if it has none.
    ///
    /// Throws, and leaves the versions alone, when the library may not be
    /// written (it's newer than this app, or needs migrating): a newer app
    /// will resolve them.
    public func resolve(path: String, date: Date = Date()) throws -> ConflictResolution? {
        let url = folder.url(for: path)
        let others = try versions.unresolvedVersions(of: url)
        guard !others.isEmpty else { return nil }
        try folder.checkWritable()

        var candidates = others.map { ConflictVersion($0.data, modified: $0.modified, source: $0.source) }
        var current: Data?
        if folder.files.fileExists(at: url) {
            let data = try folder.files.readData(at: url)
            current = data
            let modified = (try? folder.files.modificationDate(of: url)) ?? .distantPast
            candidates.append(ConflictVersion(data, modified: modified, source: versions.currentVersionSource(of: url)))
        }
        let merged = ConflictResolver.merge(path: path, candidates)
        if merged.value != current {
            try folder.files.writeData(merged.value, to: url)
        }
        try versions.markResolved(others.map(\.id), of: url)
        return ConflictResolution(
            path: path, summary: merged.summary, versionCount: candidates.count, recordsAdded: merged.recordsAdded,
            conflictingRecords: merged.conflictingRecords, resolvedAt: date)
    }

    /// Resolves the conflicts in each of `paths`, collecting what happened.
    public func resolve(paths: [String], date: Date = Date()) -> ConflictReport {
        var report = ConflictReport()
        for path in Set(paths).sorted() {
            do {
                if let resolution = try resolve(path: path, date: date) { report.resolved.append(resolution) }
            } catch {
                report.failed.append(ConflictFailure(path: path, message: String(describing: error)))
            }
        }
        return report
    }
}
