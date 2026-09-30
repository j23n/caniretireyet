import Foundation
import Model

/// A copy of some library files in `backups/<name>/`, taken before a
/// migration, an import, or a save that replaced a file changed elsewhere.
///
/// The folder mirrors the library's layout and holds a `backup.json` that
/// lists what was copied, and which files didn't exist yet (restoring
/// deletes those, so an import that created a month file is fully undone).
/// After an import, the files as the import wrote them are recorded too
/// (``result``), so undoing it leaves later edits alone.
public struct Backup: Hashable, Sendable {
    /// The folder name in `backups/`, e.g. `2026-09-30-142501-import`.
    public var name: String
    /// What the backup was taken for, e.g. `import`.
    public var label: String
    /// When the backup was taken, to the second.
    public var created: Date
    /// The files copied, as paths relative to the library folder.
    public var files: [String]
    /// Paths that were asked for but didn't exist when the backup was taken.
    public var absentFiles: [String]
    /// The library's format version (`schemaVersion`) when the backup was
    /// taken; `nil` for backups that don't record it.
    public var schemaVersion: Int?
    /// The same files as the change wrote them, recorded after it with
    /// ``LibraryFolder/recordResult(of:)``; `nil` if none was recorded.
    public var result: BackupResult?

    public init(name: String, label: String, created: Date, files: [String], absentFiles: [String] = [],
                schemaVersion: Int? = nil, result: BackupResult? = nil) {
        self.name = name
        self.label = label
        self.created = created
        self.files = files
        self.absentFiles = absentFiles
        self.schemaVersion = schemaVersion
        self.result = result
    }

    /// The backup's folder, relative to the library folder.
    public var path: String { "\(LibraryFolder.backupsFolder)/\(name)" }

    /// Every path the backup covers: the files copied and the absent ones.
    public var paths: [String] { (files + absentFiles).sorted() }
}

/// The files of a backup as the change wrote them, in
/// `backups/<name>/result/`.
public struct BackupResult: Hashable, Sendable {
    /// The files copied, as paths relative to the library folder.
    public var files: [String]
    /// The backup's paths that didn't exist after the change.
    public var absentFiles: [String]

    public init(files: [String], absentFiles: [String] = []) {
        self.files = files
        self.absentFiles = absentFiles
    }
}

/// What undoing a backed-up change did (``LibraryFolder/undo(_:)``).
public struct UndoReport: Hashable, Sendable {
    /// Paths of the files written.
    public var written: [String]
    /// Paths of the files deleted.
    public var deleted: [String]
    /// Changes made after the backed-up change, which undoing left in place.
    public var keptChanges: [KeptChange]
    /// Whether the backup didn't record what the change wrote, so its files
    /// were put back as they were, over any later edits.
    public var restoredWholesale: Bool

    public init(written: [String] = [], deleted: [String] = [], keptChanges: [KeptChange] = [],
                restoredWholesale: Bool = false) {
        self.written = written
        self.deleted = deleted
        self.keptChanges = keptChanges
        self.restoredWholesale = restoredWholesale
    }

    /// Whether everything was undone.
    public var isComplete: Bool { keptChanges.isEmpty }

    /// The paths whose files changed: reload them.
    public var changedPaths: [String] { written + deleted }
}

/// A change made after a backed-up change, which undoing it left in place.
public struct KeptChange: Hashable, Sendable {
    /// The file's path relative to the library folder.
    public var path: String
    /// The records changed since, as `valuations: 2026-09-30 conto-fineco`;
    /// empty when the whole file was left as it is.
    public var records: [String]

    public init(path: String, records: [String] = []) {
        self.path = path
        self.records = records
    }

    /// What was left in place, in plain words.
    public var summary: String {
        if records.isEmpty { return "\(path) was changed after the import, so it was left as it is." }
        let count = records.count == 1 ? "1 record" : "\(records.count) records"
        return "In \(path), \(count) changed after the import kept their new values: "
            + "\(records.joined(separator: "; "))."
    }
}

extension LibraryFolder {
    /// The folder that holds backups.
    public static let backupsFolder = "backups"

    /// The file in each backup folder that describes it.
    static let backupManifestName = "backup.json"

    /// The folder inside a backup that holds the files as the change wrote them.
    static let backupResultFolder = "result"

    /// Copies files into a new folder `backups/<timestamp>-<label>/`, e.g.
    /// before an import, so ``undo(_:)`` can undo it. `paths` are relative to
    /// the library folder; paths that don't exist are recorded, and undoing
    /// deletes them. The timestamp is `date` in the device's time zone
    /// (`2026-09-30-142501`).
    @discardableResult
    public func backup(paths: [String], label: String, date: Date = Date()) throws -> Backup {
        let label = Slug.make(from: label)
        return try makeBackup(paths: paths, name: "\(Self.timestamp(date))-\(label)", label: label, date: date)
    }

    /// Records the backup's files as they are now, after the change it was
    /// taken for (e.g. an import), in `backups/<name>/result/`, so
    /// ``undo(_:)`` can tell later edits apart. Returns the updated backup.
    @discardableResult
    public func recordResult(of backup: Backup) throws -> Backup {
        let folder = try manifestFolder(of: backup)
        var copied: [String] = []
        var absent: [String] = []
        for path in backup.paths {
            try validateRelativePath(path)
            let source = url(for: path)
            if files.fileExists(at: source) {
                try files.writeData(files.readData(at: source), to: url(for: "\(folder)/\(Self.backupResultFolder)/\(path)"))
                copied.append(path)
            } else {
                absent.append(path)
            }
        }
        var recorded = backup
        recorded.result = BackupResult(files: copied, absentFiles: absent)
        try writeManifest(of: recorded)
        return recorded
    }

    /// Puts the files of a backup back in place as they were, and deletes
    /// the files that didn't exist when it was taken, over any later edits.
    /// The backup itself is kept. To undo an import, use ``undo(_:)``, which
    /// keeps later edits.
    ///
    /// Throws ``StorageError/backupFromOtherVersion(name:version:current:)``
    /// for a backup of a library in another format version, and what
    /// ``checkWritable(schemaVersion:)`` throws.
    @discardableResult
    public func restore(backup: Backup) throws -> SaveReport {
        let folder = try checkRestorable(backup)
        var report = SaveReport()
        for path in backup.files {
            try validateRelativePath(path)
            try files.writeData(files.readData(at: url(for: "\(folder)/\(path)")), to: url(for: path))
            report.written.append(path)
        }
        for path in backup.absentFiles {
            try validateRelativePath(path)
            guard files.fileExists(at: url(for: path)) else { continue }
            try files.removeItem(at: url(for: path))
            report.deleted.append(path)
        }
        return report
    }

    /// Undoes the change a backup was taken for (an import), leaving later
    /// edits in place. File by file, with the files before the change (the
    /// backup), after it (its ``Backup/result``) and now:
    ///
    /// - unchanged since the change: put back as it was before (a file the
    ///   change created is deleted);
    /// - history and headline files changed since: merged record by record.
    ///   Records unchanged since the change go back to how they were before
    ///   it (records it added are removed); records changed since keep their
    ///   new values and are listed in ``UndoReport/keptChanges``;
    /// - any other file changed since: left as it is, and listed.
    ///
    /// A backup without a recorded result is restored as it was, over later
    /// edits (``UndoReport/restoredWholesale``). Throws what
    /// ``restore(backup:)`` throws.
    @discardableResult
    public func undo(_ backup: Backup) throws -> UndoReport {
        guard let result = backup.result else {
            let restored = try restore(backup: backup)
            return UndoReport(written: restored.written, deleted: restored.deleted, restoredWholesale: true)
        }
        let folder = try checkRestorable(backup)
        var report = SaveReport()
        var kept: [KeptChange] = []
        for path in backup.paths {
            try validateRelativePath(path)
            let before = backup.files.contains(path) ? try files.readData(at: url(for: "\(folder)/\(path)")) : nil
            let after = result.files.contains(path)
                ? try files.readData(at: url(for: "\(folder)/\(Self.backupResultFolder)/\(path)")) : nil
            var change: KeptChange?
            try apply(path: path, report: &report) { current in
                change = nil
                if Self.sameContents(current, after) {
                    return FilePlan(output: before.map { FilePlan.Output.write($0) } ?? .delete)
                }
                if Self.sameContents(current, before) { return FilePlan(output: .keep) }
                guard let file = LibraryFile(path: path), file.mergesRecords,
                      let undone = try self.undoRecords(of: file, before: before, after: after, current: current)
                else {
                    change = KeptChange(path: path)
                    return FilePlan(output: .keep)
                }
                if !undone.conflicts.isEmpty { change = KeptChange(path: path, records: undone.conflicts) }
                return FilePlan(output: undone.output)
            }
            if let change { kept.append(change) }
        }
        return UndoReport(written: report.written, deleted: report.deleted, keptChanges: kept)
    }

    /// The backups in `backups/`, oldest first. Folders without a readable
    /// `backup.json` are left out.
    public func backups() throws -> [Backup] {
        let paths = try files.listFiles(in: url(for: Self.backupsFolder))
        var backups: [Backup] = []
        for path in paths {
            let parts = path.split(separator: "/")
            guard parts.count == 2, parts[1] == Self.backupManifestName else { continue }
            let name = String(parts[0])
            guard let data = try? files.readData(at: url(for: "\(Self.backupsFolder)/\(path)")),
                  let manifest = try? JSONDecoder().decode(BackupManifest.self, from: data),
                  let created = try? Date(manifest.created, strategy: .iso8601)
            else { continue }
            backups.append(Backup(
                name: name, label: manifest.label, created: created, files: manifest.files,
                absentFiles: manifest.absentFiles ?? [], schemaVersion: manifest.schemaVersion,
                result: manifest.result.map { BackupResult(files: $0.files, absentFiles: $0.absentFiles ?? []) }))
        }
        return backups.sorted { ($0.created, $0.name) < ($1.created, $1.name) }
    }

    // MARK: Internals

    /// Copies `paths` into `backups/<name>/` (or `<name>-2`, … if taken)
    /// and writes its `backup.json`. Paths in `contents` are written with
    /// those bytes instead of being read.
    func makeBackup(paths: [String], name: String, label: String, date: Date,
                    contents: [String: Data] = [:]) throws -> Backup {
        for path in paths {
            try validateRelativePath(path)
            guard path != Self.backupManifestName, !path.hasPrefix(Self.backupsFolder + "/") else {
                throw StorageError.invalidPath(path)
            }
        }
        let existing = Set(try files.listFiles(in: url(for: Self.backupsFolder)).map { String($0.prefix { $0 != "/" }) })
        let uniqueName = Slug.unique(name, among: existing)
        let folder = "\(Self.backupsFolder)/\(uniqueName)"
        var copied: [String] = []
        var absent: [String] = []
        for path in Set(paths).sorted() {
            let source = url(for: path)
            if let data = contents[path] {
                try files.writeData(data, to: url(for: "\(folder)/\(path)"))
                copied.append(path)
            } else if files.fileExists(at: source) {
                try files.writeData(files.readData(at: source), to: url(for: "\(folder)/\(path)"))
                copied.append(path)
            } else {
                absent.append(path)
            }
        }
        let created = date.formatted(.iso8601)
        // Whole seconds, as listed by `backups()`.
        let backup = Backup(name: uniqueName, label: label, created: (try? Date(created, strategy: .iso8601)) ?? date,
                            files: copied, absentFiles: absent, schemaVersion: schemaVersionOnDisk())
        try writeManifest(of: backup)
        return backup
    }

    /// Copies file contents read earlier into a new backup
    /// `backups/<timestamp>-<label>/`: the version on disk of a file a save
    /// is about to replace.
    func makeBackup(contents: [String: Data], label: String, date: Date = Date()) throws -> Backup {
        try makeBackup(paths: Array(contents.keys), name: "\(Self.timestamp(date))-\(label)", label: label, date: date,
                       contents: contents)
    }

    private func writeManifest(of backup: Backup) throws {
        let manifest = BackupManifest(
            label: backup.label, created: backup.created.formatted(.iso8601), files: backup.files,
            absentFiles: backup.absentFiles.isEmpty ? nil : backup.absentFiles, schemaVersion: backup.schemaVersion,
            result: backup.result.map {
                BackupManifest.Result(files: $0.files, absentFiles: $0.absentFiles.isEmpty ? nil : $0.absentFiles)
            })
        try files.writeData(CanonicalJSON.data(encoding: manifest),
                            to: url(for: "\(backup.path)/\(Self.backupManifestName)"))
    }

    /// The backup's folder, after checking that it exists.
    private func manifestFolder(of backup: Backup) throws -> String {
        try validateRelativePath(backup.name)
        guard !backup.name.contains("/"),
              files.fileExists(at: url(for: "\(backup.path)/\(Self.backupManifestName)"))
        else { throw StorageError.backupNotFound(backup.name) }
        return backup.path
    }

    /// The backup's folder, after checking that it exists, that this app
    /// may write to the library, and that the backup is of the library's
    /// format version.
    private func checkRestorable(_ backup: Backup) throws -> String {
        let folder = try manifestFolder(of: backup)
        try checkWritable()
        let current = LibrarySettings.currentSchemaVersion
        if let version = backup.schemaVersion, version != current {
            throw StorageError.backupFromOtherVersion(name: backup.name, version: version, current: current)
        }
        return folder
    }

    /// Whether two versions of a file hold the same: the same bytes, or the
    /// same JSON.
    static func sameContents(_ a: Data?, _ b: Data?) -> Bool {
        guard let a, let b else { return a == nil && b == nil }
        if a == b { return true }
        guard let left = try? CanonicalJSON.parse(a), let right = try? CanonicalJSON.parse(b) else { return false }
        return left == right
    }

    /// Undoes a change to a history or headline file record by record: base
    /// = after the change, ours = now, theirs = before it. `nil` if the file
    /// can't be read now.
    private func undoRecords(of file: LibraryFile, before: Data?, after: Data?, current: Data?) throws
        -> (output: FilePlan.Output, conflicts: [String])? {
        func load(_ data: Data?) -> Library? {
            guard let data else { return Library() }
            let (library, hasErrors) = LibraryLoader.decode(file, from: data, in: self)
            return hasErrors && (try? CanonicalJSON.parse(data))?.objectValue == nil ? nil : library
        }
        guard let current, let raw = try? CanonicalJSON.parse(current), raw.objectValue != nil,
              let now = load(current), let base = load(after), let theirs = load(before)
        else { return nil }
        let merged: JSONValue?
        let conflicts: [String]
        switch file {
        case .month(let month):
            let merge = RecordMerger.merge(base: base.months[month], ours: now.months[month],
                                           theirs: theirs.months[month], month: month, rule: .ours)
            merged = try Self.json(forMonth: merge.value)
            conflicts = merge.conflicts
        case .headlines(let plan, let year):
            let merge = RecordMerger.merge(base: base.projections[plan]?.headlines[year],
                                           ours: now.projections[plan]?.headlines[year],
                                           theirs: theirs.projections[plan]?.headlines[year], rule: .ours)
            merged = merge.value.headlines.isEmpty ? Optional.none : try Self.json(for: merge.value)
            conflicts = merge.conflicts
        default:
            return nil
        }
        guard let merged else { return (try removal(of: file, raw: raw), conflicts) }
        let kept = KeyPreservation.preserving(raw, known: nil, in: merged, for: file)
        return (.write(CanonicalJSON.data(for: kept)), conflicts)
    }

    /// `2026-09-30-142501`, in the device's time zone.
    static func timestamp(_ date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        func pad(_ value: Int?, _ width: Int) -> String {
            let digits = String(value ?? 0)
            return String(repeating: "0", count: max(0, width - digits.count)) + digits
        }
        return "\(pad(parts.year, 4))-\(pad(parts.month, 2))-\(pad(parts.day, 2))-"
            + "\(pad(parts.hour, 2))\(pad(parts.minute, 2))\(pad(parts.second, 2))"
    }
}

/// `backups/<name>/backup.json`.
private struct BackupManifest: Codable {
    struct Result: Codable {
        var files: [String]
        var absentFiles: [String]?
    }

    var label: String
    /// ISO 8601, e.g. `2026-09-30T12:25:01Z`.
    var created: String
    var files: [String]
    var absentFiles: [String]?
    var schemaVersion: Int?
    var result: Result?
}
