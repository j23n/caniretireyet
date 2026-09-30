import Foundation
import Model

/// What a save changed in the library folder.
public struct SaveReport: Hashable, Sendable {
    /// Paths of the files written, in order.
    public var written: [String]
    /// Paths of the files deleted.
    public var deleted: [String]
    /// Copies of files that weren't valid JSON, taken before they were
    /// overwritten, so nothing is lost.
    public var backups: [Backup]

    public init(written: [String] = [], deleted: [String] = [], backups: [Backup] = []) {
        self.written = written
        self.deleted = deleted
        self.backups = backups
    }

    /// Whether nothing was written or deleted.
    public var isEmpty: Bool { written.isEmpty && deleted.isEmpty }
}

extension LibraryFolder {
    // MARK: Whole library

    /// Writes the files of `library` that differ from `previous`, and
    /// deletes the files of entities that `previous` had and `library`
    /// doesn't. A month file with no records counts as absent.
    ///
    /// Files are compared by their canonical bytes, so a file is only
    /// written when its data changed. When a file is rewritten, keys the
    /// model doesn't know are kept from the file on disk. Without
    /// `previous`, every file is written whose bytes differ from the file on
    /// disk, and nothing is deleted.
    ///
    /// Throws ``StorageError/libraryIsNewer(version:supported:)`` if the
    /// library (in memory or on disk) was written by a newer app version.
    @discardableResult
    public func save(_ library: Library, previous: Library? = nil) throws -> SaveReport {
        try checkWritable(schemaVersion: library.settings.schemaVersion)
        var report = SaveReport()
        let newFiles = library.libraryFiles
        let oldFiles = previous?.libraryFiles ?? []
        for file in newFiles.sorted() {
            let existed = previous != nil && oldFiles.contains(file)
            if existed, let previous, Self.entitiesEqual(file, previous, library) { continue }
            guard let json = try Self.json(for: file, in: library) else { continue }
            if existed, let previous, let oldJSON = try Self.json(for: file, in: previous),
               CanonicalJSON.data(for: oldJSON) == CanonicalJSON.data(for: json) {
                continue
            }
            try write(json, to: file, report: &report)
        }
        for file in oldFiles.subtracting(newFiles).sorted() {
            try remove(file, report: &report)
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
    /// A file on disk that isn't a JSON object is backed up first.
    func write(_ json: JSONValue, to file: LibraryFile, report: inout SaveReport) throws {
        let url = url(for: file)
        var output = json
        var existing: Data?
        if files.fileExists(at: url) {
            let data = try files.readData(at: url)
            existing = data
            if let old = try? CanonicalJSON.parse(data), old.objectValue != nil {
                output = KeyPreservation.rule(for: file).preserving(old, in: json)
            } else {
                report.backups.append(try backup(paths: [file.path], label: "unreadable"))
            }
        }
        let bytes = CanonicalJSON.data(for: output)
        guard bytes != existing else { return }
        try files.writeData(bytes, to: url)
        report.written.append(file.path)
    }

    /// Deletes `file`. A month file that still holds data the model doesn't
    /// know (unknown keys, records it can't read) is rewritten without its
    /// records instead, so that data survives.
    func remove(_ file: LibraryFile, report: inout SaveReport) throws {
        let url = url(for: file)
        guard files.fileExists(at: url) else { return }
        if case .month(let month) = file,
           let old = try? CanonicalJSON.parse(files.readData(at: url)), old.objectValue != nil {
            let empty = try Self.json(for: MonthFile(month: month))
            if KeyPreservation.month.preserving(old, in: empty) != empty {
                try write(empty, to: file, report: &report)
                return
            }
        }
        try files.removeItem(at: url)
        report.deleted.append(file.path)
    }

    /// The JSON of the entity a file holds, or `nil` if the library doesn't
    /// have it (or it's an empty month).
    static func json(for file: LibraryFile, in library: Library) throws -> JSONValue? {
        switch file {
        case .settings: try CanonicalJSON.json(encoding: library.settings)
        case .account(let id): try library.accounts[id].map { try CanonicalJSON.json(encoding: $0) }
        case .instrument(let id): try library.instruments[id].map { try CanonicalJSON.json(encoding: $0) }
        case .month(let month): try library.months[month].flatMap { $0.isEmpty ? nil : try json(for: $0) }
        case .plan(let id): try library.plans[id].map { try CanonicalJSON.json(encoding: $0) }
        case .importProfile(let id): try library.importProfiles[id].map { try CanonicalJSON.json(encoding: $0) }
        case .baseline(let plan, let id):
            try library.projections[plan]?.baselines[id].map { try CanonicalJSON.json(encoding: $0) }
        case .headlines(let plan, let year):
            try library.projections[plan]?.headlines[year].map { try json(for: $0) }
        }
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
    private static func entitiesEqual(_ file: LibraryFile, _ a: Library, _ b: Library) -> Bool {
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
