import Foundation
import Storage

/// A sync conflict that was resolved, for the Sync screen and the Overview's
/// "Needs attention".
public struct ConflictResolution: Hashable, Sendable, Identifiable {
    /// The file's path relative to the library folder.
    public var path: String
    /// What was merged, in plain words (from `ConflictResolver`), and where
    /// the copies of the versions that differ from the result are (one
    /// backup each, labelled `conflict`).
    public var summary: String
    /// When it was resolved.
    public var resolvedAt: Date

    public init(path: String, summary: String, resolvedAt: Date) {
        self.path = path
        self.summary = summary
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

/// Resolves sync conflicts in a library folder (PLAN.md, "Merging,
/// saving and undo"): reads the current file and every unresolved version, merges
/// them with `ConflictResolver.merge(path:_:)`, copies each version that
/// differs from the result to `backups/<timestamp>-conflict/`, writes the
/// result, and marks the versions resolved (which removes them).
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
        // Every version the merge doesn't keep as it is is copied to
        // backups/ first: the current file is about to be replaced, and the
        // other versions removed from the version store for good.
        var losing: [Data] = []
        for data in (current.map { [$0] } ?? []) + others.map(\.data)
        where !CanonicalJSON.sameContents(data, merged.value)
            && !losing.contains(where: { CanonicalJSON.sameContents($0, data) }) {
            losing.append(data)
        }
        let backups = try losing.map { try folder.backup(contents: [path: $0], label: Self.backupLabel, date: date) }
        if merged.value != current {
            try folder.files.writeData(merged.value, to: url)
        }
        try versions.markResolved(others.map(\.id), of: url)
        var summary = merged.summary
        if !backups.isEmpty {
            let folders = backups.map { "\($0.path)/" }.joined(separator: ", ")
            summary += backups.count == 1
                ? " A copy of the version that differs from the result is in \(folders)."
                : " Copies of the \(backups.count) versions that differ from the result are in \(folders)."
        }
        return ConflictResolution(path: path, summary: summary, resolvedAt: date)
    }

    /// The label of the backups of versions a resolution replaced.
    public static let backupLabel = "conflict"

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
