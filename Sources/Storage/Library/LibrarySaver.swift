import Foundation
import Model

/// What a save changed in the library folder.
public struct SaveReport: Hashable, Sendable {
    /// Paths of the files written, in order.
    public var written: [String]
    /// Paths of the files deleted.
    public var deleted: [String]
    /// Copies of files taken before they were overwritten or deleted, so
    /// nothing is lost: files that couldn't be read, and files changed on
    /// disk that the save replaced (see ``issues``).
    public var backups: [Backup]
    /// Paths of files that were changed on disk since `previous` was loaded
    /// (on the other device, or by hand). Their changes were merged in, or
    /// the file was kept, so the folder now holds something the saved
    /// library doesn't: reload them.
    public var reloadPaths: [String]
    /// What the save found on disk that it couldn't simply write over, for
    /// the Sync screen.
    public var issues: [SaveIssue]

    public init(written: [String] = [], deleted: [String] = [], backups: [Backup] = [], reloadPaths: [String] = [],
                issues: [SaveIssue] = []) {
        self.written = written
        self.deleted = deleted
        self.backups = backups
        self.reloadPaths = reloadPaths
        self.issues = issues
    }

    /// Whether nothing was written or deleted.
    public var isEmpty: Bool { written.isEmpty && deleted.isEmpty }
}

/// Something a save found on disk that it couldn't simply write over
/// (FILE_FORMAT.md, "Saving").
public struct SaveIssue: Hashable, Sendable {
    public enum Kind: String, Hashable, Sendable {
        /// The file was changed on disk and in the library since it was
        /// loaded: the library's version was written, after copying the one
        /// on disk to ``SaveIssue/backup``.
        case replaced
        /// Records were changed on disk and in the library, each in its own
        /// way: the library's versions were written (``SaveIssue/records``),
        /// after copying the file to ``SaveIssue/backup``. Every other change
        /// found on disk was kept.
        case recordsReplaced
        /// The library deleted the file, but it was changed on disk: it was
        /// kept.
        case kept
        /// The file on disk couldn't be read (it isn't valid JSON, or isn't
        /// what the file should hold): it was copied to ``SaveIssue/backup``
        /// before it was replaced or deleted.
        case unreadable
    }

    /// The file's path relative to the library folder.
    public var path: String
    public var kind: Kind
    /// The records whose version on disk was replaced, as
    /// `valuations: 2026-09-30 conto-fineco`.
    public var records: [String]
    /// The copy of the file as it was on disk.
    public var backup: Backup?

    public init(path: String, kind: Kind, records: [String] = [], backup: Backup? = nil) {
        self.path = path
        self.kind = kind
        self.records = records
        self.backup = backup
    }

    /// What happened, in plain words.
    public var summary: String {
        let copy = backup.map { " The version on disk was copied to \($0.path)." } ?? ""
        switch kind {
        case .replaced:
            return "\(path) was changed elsewhere after the app read it, and in the app too. The app's version was "
                + "saved.\(copy)"
        case .recordsReplaced:
            let count = records.count == 1 ? "1 record was" : "\(records.count) records were"
            return "In \(path), \(count) changed elsewhere and in the app: the app's version was saved "
                + "(\(records.joined(separator: "; "))). Every other change from elsewhere was kept.\(copy)"
        case .kept:
            return "\(path) was changed elsewhere after the app read it, so it wasn't deleted."
        case .unreadable:
            return "\(path) couldn't be read, so the app replaced it.\(copy)"
        }
    }
}

extension LibraryFolder {
    /// How many times a file is read and merged again when it changes
    /// between being read and being written.
    static let saveAttempts = 5

    // MARK: Whole library

    /// Writes the files of `library` that differ from `previous`, and
    /// deletes the files of entities that `previous` had and `library`
    /// doesn't. A month file with no records counts as absent.
    ///
    /// A file is only written when its data changed, and each is merged
    /// with what's on disk now (FILE_FORMAT.md, "Saving"), so a change made
    /// on disk since `previous` was loaded (by the other device, or by hand)
    /// is never lost:
    ///
    /// - History and headline files are merged record by record, with
    ///   `previous` as the common base: records changed only on disk keep
    ///   the disk's version, records changed only in `library` get
    ///   `library`'s. A record changed on both sides gets `library`'s version
    ///   (unless `library` deleted it: then it's kept), the file is copied to
    ///   `backups/` first, and the records are listed in the report's
    ///   ``SaveReport/issues``.
    /// - Any other file changed on disk is copied to `backups/` before it's
    ///   replaced, and is only deleted if it's unchanged.
    /// - A file that can't be read is copied to `backups/` before it's
    ///   replaced or deleted.
    ///
    /// Each file is read, merged and written as one coordinated operation
    /// when the file access supports it (``FileAccessing/replaceData(at:ifContentsAre:with:)``).
    /// When a rewrite happens, keys the model doesn't know are kept from the
    /// file on disk. Reload the report's ``SaveReport/reloadPaths``.
    ///
    /// Without `previous`, every file is written whose bytes differ from the
    /// file on disk, and nothing is deleted.
    ///
    /// Throws ``StorageError/libraryIsNewer(version:supported:)`` if the
    /// library (in memory or on disk) was written by a newer app version.
    @discardableResult
    public func save(_ library: Library, previous: Library? = nil) throws -> SaveReport {
        try checkWritable(schemaVersion: library.settings.schemaVersion)
        var report = SaveReport()
        guard let previous else {
            for file in library.libraryFiles.sorted() {
                guard let json = try Self.json(for: file, in: library) else { continue }
                try write(json, to: file, report: &report)
            }
            return report
        }
        for file in library.files(changedFrom: previous).sorted() {
            try apply(file, report: &report) { disk in
                try plan(file, disk: disk, library: library, previous: previous)
            }
        }
        return report
    }

    // MARK: One file

    /// Writes `library.json`.
    @discardableResult
    public func save(_ settings: LibrarySettings) throws -> SaveReport {
        try checkWritable(schemaVersion: settings.schemaVersion)
        return try saveFile(.settings, CanonicalJSON.json(encoding: settings))
    }

    /// Writes `accounts/<id>.json`.
    @discardableResult
    public func save(_ account: Account) throws -> SaveReport {
        try checkWritable()
        return try saveFile(.account(account.id), CanonicalJSON.json(encoding: account))
    }

    /// Writes `instruments/<id>.json`.
    @discardableResult
    public func save(_ instrument: Instrument) throws -> SaveReport {
        try checkWritable()
        return try saveFile(.instrument(instrument.id), CanonicalJSON.json(encoding: instrument))
    }

    /// Writes a month's history file, with its records sorted, or deletes it
    /// when the month has no records.
    @discardableResult
    public func save(_ month: MonthFile) throws -> SaveReport {
        try checkWritable()
        var report = SaveReport()
        if month.isEmpty {
            try remove(.month(month.month), report: &report)
        } else {
            try write(Self.json(for: month), to: .month(month.month), report: &report)
        }
        return report
    }

    /// Writes `plans/<id>.json`.
    @discardableResult
    public func save(_ plan: PlanDocument) throws -> SaveReport {
        try checkWritable()
        return try saveFile(.plan(plan.id), CanonicalJSON.json(encoding: plan))
    }

    /// Writes `imports/<id>.json`.
    @discardableResult
    public func save(_ profile: ImportProfile) throws -> SaveReport {
        try checkWritable()
        return try saveFile(.importProfile(profile.id), CanonicalJSON.json(encoding: profile))
    }

    /// Writes `projections/<plan>/baselines/<id>.json`.
    @discardableResult
    public func save(_ baseline: Baseline, id: BaselineID, plan: PlanID) throws -> SaveReport {
        try checkWritable()
        return try saveFile(.baseline(plan: plan, id: id), CanonicalJSON.json(encoding: baseline))
    }

    /// Writes `projections/<plan>/headlines/<year>.json`, sorted by date.
    @discardableResult
    public func save(_ headlines: HeadlineFile, year: Int, plan: PlanID) throws -> SaveReport {
        try checkWritable()
        return try saveFile(.headlines(plan: plan, year: year), Self.json(for: headlines))
    }

    /// Deletes a library file, if it exists.
    @discardableResult
    public func delete(_ file: LibraryFile) throws -> SaveReport {
        try checkWritable()
        var report = SaveReport()
        try remove(file, report: &report)
        return report
    }

    // MARK: Internals

    private func saveFile(_ file: LibraryFile, _ json: JSONValue) throws -> SaveReport {
        var report = SaveReport()
        try write(json, to: file, report: &report)
        return report
    }

    /// Writes `json` to `file` in canonical form, keeping unknown keys from
    /// the file on disk. Skips the write when the bytes are already there.
    /// A file on disk that can't be read is backed up first.
    func write(_ json: JSONValue, to file: LibraryFile, report: inout SaveReport) throws {
        try apply(file, report: &report) { disk in
            let found = self.read(disk, as: file)
            let output = found.raw.map { KeyPreservation.preserving($0, known: found.known, in: json, for: file) } ?? json
            var plan = FilePlan(output: .write(CanonicalJSON.data(for: output)))
            if found.isUnreadable { plan.markUnreadable(file) }
            return plan
        }
    }

    /// Deletes `file`. A history or headline file that still holds data the
    /// model doesn't know (unknown keys, records it can't read) is rewritten
    /// without its records instead, so that data survives. A file that
    /// can't be read is backed up first.
    func remove(_ file: LibraryFile, report: inout SaveReport) throws {
        try apply(file, report: &report) { disk in
            let found = self.read(disk, as: file)
            var plan = FilePlan(output: try self.removal(of: file, raw: found.raw))
            if found.isUnreadable { plan.markUnreadable(file) }
            return plan
        }
    }

    /// Reads the file on disk, asks `decide` what to do with it, backs it up
    /// if the plan says so, and writes or deletes it only if it's still what
    /// was read. When it changed meanwhile, the whole thing starts over.
    private func apply(_ file: LibraryFile, report: inout SaveReport, decide: (Data?) throws -> FilePlan) throws {
        try apply(path: file.path, report: &report, decide: decide)
    }

    /// ``apply(_:report:decide:)`` for any path in the library folder.
    func apply(path: String, report: inout SaveReport, decide: (Data?) throws -> FilePlan) throws {
        let url = url(for: path)
        for _ in 0..<Self.saveAttempts {
            let disk = files.fileExists(at: url) ? try files.readData(at: url) : nil
            var plan = try decide(disk)
            if let label = plan.backupLabel, let disk {
                let backup = try makeBackup(contents: [path: disk], label: label)
                report.backups.append(backup)
                plan.issue?.backup = backup
            }
            let done: Bool
            switch plan.output {
            case .keep:
                done = true
            case .write(let data):
                done = try data == disk || files.replaceData(at: url, ifContentsAre: disk, with: data)
                if done, data != disk { report.written.append(path) }
            case .delete:
                done = try disk == nil || files.replaceData(at: url, ifContentsAre: disk, with: nil)
                if done, disk != nil { report.deleted.append(path) }
            }
            guard done else { continue }
            if plan.reload { report.reloadPaths.append(path) }
            if let issue = plan.issue { report.issues.append(issue) }
            return
        }
        throw StorageError.fileKeptChanging(path: path)
    }

    // MARK: Merging with the disk

    /// What to do with one file.
    struct FilePlan {
        enum Output {
            case keep
            case write(Data)
            case delete
        }

        var output: Output
        /// Copy the file on disk into `backups/<timestamp>-<label>/` first.
        var backupLabel: String?
        var issue: SaveIssue?
        /// The file on disk had changes the saved library doesn't have.
        var reload = false

        mutating func markUnreadable(_ file: LibraryFile) {
            backupLabel = "unreadable"
            issue = SaveIssue(path: file.path, kind: .unreadable)
            reload = true
        }
    }

    /// A file on disk as the save sees it.
    private struct DiskFile {
        /// Whether there's a file.
        var exists: Bool
        /// Its JSON, if it's a JSON object.
        var raw: JSONValue?
        /// What loading it gives: a library holding only its entity.
        var loaded: Library?
        /// The model's JSON of its entity (``LibraryFolder/json(for:in:)``),
        /// if it could be loaded without errors.
        var known: JSONValue?
        /// It exists, but can't be read, or holds something a rewrite would
        /// lose.
        var isUnreadable: Bool
    }

    private func read(_ disk: Data?, as file: LibraryFile) -> DiskFile {
        guard let disk else { return DiskFile(exists: false, isUnreadable: false) }
        let raw = (try? CanonicalJSON.parse(disk)).flatMap { $0.objectValue != nil ? $0 : nil }
        let (loaded, hasErrors) = LibraryLoader.decode(file, from: disk, in: self)
        guard let raw else { return DiskFile(exists: true, loaded: loaded, isUnreadable: true) }
        if file.mergesRecords {
            // Records that can't be read are kept in the file; only a list
            // that isn't a list would be lost.
            let lists = Self.recordLists(of: file).keys
            let broken = lists.contains { raw[$0].map { !$0.isNull && $0.arrayValue == nil } ?? false }
            return DiskFile(exists: true, raw: raw, loaded: loaded, isUnreadable: broken)
        }
        let known = hasErrors ? nil : try? Self.json(for: file, in: loaded)
        return DiskFile(exists: true, raw: raw, loaded: loaded, known: known, isUnreadable: known == nil)
    }

    /// Plans the save of a file that `library` changed from `previous`,
    /// given what's on disk now.
    private func plan(_ file: LibraryFile, disk data: Data?, library: Library, previous: Library) throws -> FilePlan {
        let disk = read(data, as: file)
        if file.mergesRecords {
            return try planRecords(file, disk: disk, library: library, previous: previous)
        }
        let base = try Self.json(for: file, in: previous)
        let ours = try Self.json(for: file, in: library)
        let matchesBase = disk.exists ? disk.known != nil && disk.known == base : base == nil
        guard let ours else {
            if !disk.exists { return FilePlan(output: .keep) }
            if matchesBase { return FilePlan(output: .delete) }
            if disk.isUnreadable {
                var plan = FilePlan(output: .delete)
                plan.markUnreadable(file)
                return plan
            }
            return FilePlan(output: .keep, issue: SaveIssue(path: file.path, kind: .kept), reload: true)
        }
        let output = disk.raw.map { KeyPreservation.preserving($0, known: disk.known, in: ours, for: file) } ?? ours
        var plan = FilePlan(output: .write(CanonicalJSON.data(for: output)))
        if !disk.exists || matchesBase || disk.known == ours { return plan }
        if disk.isUnreadable {
            plan.markUnreadable(file)
        } else {
            plan.backupLabel = "conflict"
            plan.issue = SaveIssue(path: file.path, kind: .replaced)
        }
        return plan
    }

    /// Plans the save of a history or headline file: a three-way merge of
    /// its records.
    private func planRecords(_ file: LibraryFile, disk: DiskFile, library: Library, previous: Library) throws
        -> FilePlan {
        let merged: JSONValue?
        let conflicts: [String]
        let changedOnDisk: Bool
        switch file {
        case .month(let month):
            let base = previous.months[month]
            // A file that can't be read can't tell what changed: take it as unchanged.
            let theirs = !disk.exists ? nil : disk.isUnreadable ? base : disk.loaded?.months[month]
            let merge = RecordMerger.merge(base: base, ours: library.months[month], theirs: theirs, month: month,
                                           rule: .oursUnlessDeleted)
            merged = try Self.json(forMonth: merge.value)
            conflicts = merge.conflicts
            changedOnDisk = try Self.json(forMonth: theirs) != Self.json(forMonth: base)
        case .headlines(let plan, let year):
            let base = previous.projections[plan]?.headlines[year]
            let ours = library.projections[plan]?.headlines[year]
            let theirs = !disk.exists ? nil : disk.isUnreadable ? base : disk.loaded?.projections[plan]?.headlines[year]
            let merge = RecordMerger.merge(base: base, ours: ours, theirs: theirs, rule: .oursUnlessDeleted)
            merged = ours == nil && merge.value.headlines.isEmpty ? Optional.none : try Self.json(for: merge.value)
            conflicts = merge.conflicts
            changedOnDisk = try theirs.map(Self.json(for:)) != base.map(Self.json(for:))
        default:
            preconditionFailure("\(file) isn't merged record by record")
        }
        let output: FilePlan.Output
        if let merged {
            let kept = disk.raw.map { KeyPreservation.preserving($0, known: nil, in: merged, for: file) } ?? merged
            output = .write(CanonicalJSON.data(for: kept))
        } else {
            output = try removal(of: file, raw: disk.raw)
        }
        var plan = FilePlan(output: output, reload: changedOnDisk)
        if disk.isUnreadable {
            plan.markUnreadable(file)
        } else if !conflicts.isEmpty {
            plan.backupLabel = "conflict"
            plan.issue = SaveIssue(path: file.path, kind: .recordsReplaced, records: conflicts)
            plan.reload = true
        }
        return plan
    }

    /// Deleting `file`, whose JSON on disk is `raw`: a history or headline
    /// file that holds data the model doesn't know is written without its
    /// records instead.
    func removal(of file: LibraryFile, raw: JSONValue?) throws -> FilePlan.Output {
        guard let raw, file.mergesRecords else { return .delete }
        let empty: JSONValue = switch file {
        case .month(let month): try Self.json(for: MonthFile(month: month))
        default: try Self.json(for: HeadlineFile())
        }
        let kept = KeyPreservation.rule(for: file).preserving(raw, in: empty)
        return kept == empty ? .delete : .write(CanonicalJSON.data(for: kept))
    }

    /// The record lists of a history or headline file.
    static func recordLists(of file: LibraryFile) -> [String: KeyPreservation.RecordList] {
        if case .month = file { KeyPreservation.RecordList.monthLists } else { KeyPreservation.RecordList.headlineLists }
    }

    // MARK: JSON of entities

    /// The JSON of the entity a file holds, or `nil` if the library doesn't
    /// have it (or it's an empty month).
    static func json(for file: LibraryFile, in library: Library) throws -> JSONValue? {
        switch file {
        case .settings: try CanonicalJSON.json(encoding: library.settings)
        case .account(let id): try library.accounts[id].map { try CanonicalJSON.json(encoding: $0) }
        case .instrument(let id): try library.instruments[id].map { try CanonicalJSON.json(encoding: $0) }
        case .month(let month): try json(forMonth: library.months[month])
        case .plan(let id): try library.plans[id].map { try CanonicalJSON.json(encoding: $0) }
        case .importProfile(let id): try library.importProfiles[id].map { try CanonicalJSON.json(encoding: $0) }
        case .baseline(let plan, let id):
            try library.projections[plan]?.baselines[id].map { try CanonicalJSON.json(encoding: $0) }
        case .headlines(let plan, let year):
            try library.projections[plan]?.headlines[year].map { try json(for: $0) }
        }
    }

    /// A month file's JSON, or `nil` for no month or an empty one.
    static func json(forMonth month: MonthFile?) throws -> JSONValue? {
        guard let month, !month.isEmpty else { return nil }
        return try json(for: month)
    }

    /// A month file's JSON, with its records sorted by date, then ID.
    static func json(for month: MonthFile) throws -> JSONValue {
        var sorted = month
        sorted.sortRecords()
        return try CanonicalJSON.json(encoding: sorted)
    }

    /// A headline file's JSON, with its headlines sorted by date.
    static func json(for headlines: HeadlineFile) throws -> JSONValue {
        try CanonicalJSON.json(encoding: HeadlineFile(headlines: headlines.headlines.sortedByKey()))
    }

    /// A quick check that skips encoding when the model values are equal
    /// (equal values have equal canonical bytes).
    static func entitiesEqual(_ file: LibraryFile, _ a: Library, _ b: Library) -> Bool {
        switch file {
        case .settings: a.settings == b.settings
        case .account(let id): a.accounts[id] == b.accounts[id]
        case .instrument(let id): a.instruments[id] == b.instruments[id]
        case .month(let month): a.months[month] == b.months[month]
        case .plan(let id): a.plans[id] == b.plans[id]
        case .importProfile(let id): a.importProfiles[id] == b.importProfiles[id]
        case .baseline(let plan, let id): a.projections[plan]?.baselines[id] == b.projections[plan]?.baselines[id]
        case .headlines(let plan, let year): a.projections[plan]?.headlines[year] == b.projections[plan]?.headlines[year]
        }
    }
}

extension Library {
    /// The data files whose contents differ between `previous` and this
    /// library: the ones ``LibraryFolder/save(_:previous:)`` writes or
    /// deletes. Files are compared by their canonical JSON, so equal data
    /// written differently (records in another order, `1500` and `1500.00`)
    /// doesn't count.
    public func files(changedFrom previous: Library) -> Set<LibraryFile> {
        libraryFiles.union(previous.libraryFiles).filter { file in
            guard !LibraryFolder.entitiesEqual(file, previous, self) else { return false }
            do {
                return try LibraryFolder.json(for: file, in: previous) != LibraryFolder.json(for: file, in: self)
            } catch {
                return true
            }
        }
    }
}
