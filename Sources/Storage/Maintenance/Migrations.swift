import Foundation
import Model

/// One step that upgrades a library from schema version ``version`` to
/// `version + 1`.
///
/// A step works on the library's JSON files as raw JSON, because files in an
/// old schema may not decode with today's model. It can change, add and
/// remove files; the migration then sets `schemaVersion` in `library.json`,
/// writes the changed files and deletes the removed ones.
public struct Migration: Sendable {
    /// The schema version this step upgrades from.
    public var version: Int
    /// What the step changes, in plain words.
    public var summary: String
    /// Changes the library's JSON files, keyed by path relative to the
    /// library folder (`accounts/directa.json`), and returns what it had to
    /// point out, in plain words (``MigrationReport/notes``). Files that
    /// aren't valid JSON aren't included.
    public var apply: @Sendable (inout [String: JSONValue]) throws -> [String]

    /// A step that changes the library's JSON files and has nothing to point out.
    public init(from version: Int, summary: String, apply: @escaping @Sendable (inout [String: JSONValue]) throws -> Void) {
        self.init(notedApply: { files in
            try apply(&files)
            return []
        }, from: version, summary: summary)
    }

    /// A step that changes the library's JSON files and returns notes. The
    /// closure comes first, so a trailing closure never picks this one.
    init(notedApply apply: @escaping @Sendable (inout [String: JSONValue]) throws -> [String], from version: Int,
         summary: String) {
        self.version = version
        self.summary = summary
        self.apply = apply
    }

    /// The steps this app knows, in order. Format version 4 is the oldest
    /// this app upgrades; earlier versions were test versions' and can't be
    /// upgraded (``StorageError/missingMigration(from:)``).
    public static let all: [Migration] = [format5]
}

/// What a migration did.
public struct MigrationReport: Hashable, Sendable {
    /// The schema version before migrating.
    public var fromVersion: Int
    /// The schema version now.
    public var toVersion: Int
    /// The copy of the whole library taken before migrating.
    public var backup: Backup
    /// The summaries of the steps applied, in order.
    public var steps: [String]
    /// What the steps had to point out, in plain words, in the order of the
    /// steps.
    public var notes: [String] = []
    /// Files the steps changed or added, rewritten in canonical form.
    public var written: [String]
    /// Files the steps removed.
    public var deleted: [String]
    /// JSON files that couldn't be parsed and were left as they were.
    public var skipped: [String]
}

extension LibraryFolder {
    /// Upgrades the library to schema version `target` by applying `steps`
    /// in order, after copying the whole library into
    /// `backups/<yyyy-MM-dd>-v<old>/`. Returns `nil` if the library is
    /// already at `target`.
    ///
    /// Throws ``StorageError/libraryIsNewer(version:supported:)`` for a
    /// library newer than `target`, and ``StorageError/missingMigration(from:)``
    /// if a step is missing. Nothing is written unless every step succeeds.
    @discardableResult
    public func migrate(
        to target: Int = LibrarySettings.currentSchemaVersion, steps: [Migration] = Migration.all, date: Date = Date()
    ) throws -> MigrationReport? {
        let settingsPath = LibraryFile.settings.path
        guard files.fileExists(at: url(for: settingsPath)) else {
            throw StorageError.unreadableFile(path: settingsPath, message: "The file is missing.")
        }
        guard let version = schemaVersionOnDisk() else {
            throw StorageError.unreadableFile(path: settingsPath, message: "\"schemaVersion\" can't be read.")
        }
        if version == target { return nil }
        if version > target { throw StorageError.libraryIsNewer(version: version, supported: target) }
        let chain = try (version..<target).flatMap { from in
            let found = steps.filter { $0.version == from }
            guard !found.isEmpty else { throw StorageError.missingMigration(from: from) }
            return found
        }

        let paths = try files.listFiles(in: root).filter { !$0.hasPrefix(Self.backupsFolder + "/") }
        var documents: [String: JSONValue] = [:]
        var skipped: [String] = []
        for path in paths where path.hasSuffix(".json") {
            if let json = try? CanonicalJSON.parse(files.readData(at: url(for: path))) {
                documents[path] = json
            } else {
                skipped.append(path)
            }
        }
        let original = documents
        var notes: [String] = []
        for step in chain {
            notes += try step.apply(&documents)
            let settings = documents[settingsPath] ?? .object([:])
            documents[settingsPath] = settings.withMember("schemaVersion", to: .number(Decimal(step.version + 1)))
        }

        let day = CalendarDate(date, in: .current)
        let backup = try makeBackup(paths: paths, name: "\(day)-v\(version)", label: "v\(version)", date: date)
        var written: [String] = []
        for (path, json) in documents.sorted(by: { $0.key < $1.key }) where original[path] != json {
            try validateRelativePath(path)
            try files.writeData(CanonicalJSON.data(for: json), to: url(for: path))
            written.append(path)
        }
        let deleted = original.keys.filter { documents[$0] == nil }.sorted()
        for path in deleted {
            try files.removeItem(at: url(for: path))
        }
        return MigrationReport(fromVersion: version, toVersion: target, backup: backup, steps: chain.map(\.summary),
                               notes: notes, written: written, deleted: deleted, skipped: skipped)
    }

    /// Loads the library (``load()``), upgrading it first with every step
    /// this app knows (``Migration/all``) when it uses an older schema
    /// version (``migrate(to:steps:date:)``, after a backup), so it can be
    /// saved; a library with a newer one loads read-only. Returns the
    /// migration, if one ran.
    public func loadMigrating() throws -> (result: LoadResult, migration: MigrationReport?) {
        let result = try load()
        guard result.report.needsMigration, let migration = try migrate() else { return (result, nil) }
        return (try load(), migration)
    }
}
