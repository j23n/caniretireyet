import Foundation
import Model

/// One version of a file in a sync conflict: its contents and when it was
/// last modified.
public struct ConflictVersion: Sendable {
    public var value: Data
    public var modified: Date
    /// Where the version comes from, for the description, e.g. the name of
    /// the device that saved it.
    public var source: String?

    public init(_ value: Data, modified: Date, source: String? = nil) {
        self.value = value
        self.modified = modified
        self.source = source
    }
}

/// The result of resolving a sync conflict.
public struct MergeResult: Sendable {
    /// The merged file's contents.
    public var value: Data
    /// A short description of what was merged, for the Sync screen.
    public var summary: String
    /// Records taken from a version other than the newest.
    public var recordsAdded: Int
    /// Records that differed between versions; the newest version's was kept.
    public var conflictingRecords: [String]

    public init(value: Data, summary: String, recordsAdded: Int = 0, conflictingRecords: [String] = []) {
        self.value = value
        self.summary = summary
        self.recordsAdded = recordsAdded
        self.conflictingRecords = conflictingRecords
    }
}

/// Resolves sync conflicts: two or more versions of the same file saved on
/// different devices before they synced (PLAN.md, "Merging, saving and undo").
///
/// - History and headline files merge record by record with the save's
///   merge (``RecordMerger``), without a common base: every record from
///   every version is kept, matched by its key, and when versions disagree
///   about a record, the most recently modified version wins. What the
///   model doesn't know (unknown keys, records it can't read) is kept from
///   each version, the newest first.
/// - Every other file: the most recently modified version wins.
///
/// Versions modified at the same moment are ordered by their contents, so
/// every device resolves the same conflict the same way. The functions are
/// pure; CloudSync reads the versions and writes the result.
public enum ConflictResolver {
    /// Resolves the versions of the file at `path` (relative to the library
    /// folder). History and headline files are merged record by record and
    /// written in canonical form; other files keep the newest version's
    /// bytes. Versions that aren't valid JSON can't be merged: they're left
    /// out, unless none is valid, in which case the newest one wins.
    public static func merge(path: String, _ versions: [ConflictVersion]) -> MergeResult {
        precondition(!versions.isEmpty, "A conflict needs at least one version")
        guard let file = LibraryFile(path: path), file.mergesRecords else { return newest(versions, name: path) }
        let parsed = versions.compactMap { version -> ParsedVersion? in
            guard let json = try? CanonicalJSON.parse(version.value), json.objectValue != nil else { return nil }
            return ParsedVersion(json: json, modified: version.modified, data: version.value)
        }
        guard !parsed.isEmpty else { return newest(versions, name: path) }
        let ranked = rank(parsed)
        let merged: RecordsMerge
        switch file {
        case .month(let month):
            merged = mergeRecords(ranked, of: file, empty: MonthFile(month: month)) { $0.months[month] }
        case .headlines(let plan, let year):
            merged = mergeRecords(ranked, of: file, empty: HeadlineFile()) { $0.projections[plan]?.headlines[year] }
        default:
            return newest(versions, name: path)
        }
        var text = summary(name: path, versions: parsed.count, added: merged.recordsAdded,
                           conflicts: merged.conflicts.count)
        let unreadable = versions.count - parsed.count
        if unreadable > 0 {
            text += " \(unreadable == 1 ? "1 version wasn't" : "\(unreadable) versions weren't") valid JSON "
                + "and \(unreadable == 1 ? "was" : "were") left out."
        }
        // When the newest version already holds every record, keep its bytes.
        let value = merged.json.map { CanonicalJSON.data(for: $0) } ?? ranked[0].data
        return MergeResult(value: value, summary: text, recordsAdded: merged.recordsAdded,
                           conflictingRecords: merged.conflicts)
    }

    // MARK: Internals

    /// A version that is a JSON object, with its bytes.
    private struct ParsedVersion {
        var json: JSONValue
        var modified: Date
        var data: Data
    }

    /// The versions, newest first; ties broken by canonical bytes, descending.
    private static func rank(_ versions: [ParsedVersion]) -> [ParsedVersion] {
        let keyed = versions.map { ($0, Array(CanonicalJSON.data(for: $0.json))) }
        return keyed.sorted { lhs, rhs in
            if lhs.0.modified != rhs.0.modified { return lhs.0.modified > rhs.0.modified }
            return rhs.1.lexicographicallyPrecedes(lhs.1)
        }.map(\.0)
    }

    /// Keeps the most recently modified version; ties broken by its bytes.
    private static func newest(_ versions: [ConflictVersion], name: String) -> MergeResult {
        let ranked = versions.sorted { lhs, rhs in
            if lhs.modified != rhs.modified { return lhs.modified > rhs.modified }
            return Array(rhs.value).lexicographicallyPrecedes(Array(lhs.value))
        }
        let winner = ranked[0]
        let others = versions.count - 1
        let from = winner.source.map { " from \($0)" } ?? ""
        let summary = others == 0
            ? "Kept the only version of \(name)."
            : "Kept the newest version of \(name)\(from); \(others == 1 ? "the other version was" : "\(others) other versions were") discarded."
        return MergeResult(value: winner.value, summary: summary)
    }

    /// What merging the records of a history or headline file gave.
    private struct RecordsMerge {
        /// The merged file's JSON; `nil` when the newest version holds every
        /// record as it is.
        var json: JSONValue?
        /// Records taken from a version other than the newest.
        var recordsAdded: Int
        /// Records that differed between versions, as `valuations: 2026-09-30 conto-fineco`.
        var conflicts: [String]
    }

    /// Every record from every version of `file`, by key: the newest
    /// version merged with each older one in turn (``RecordMerger``, no
    /// base, ours = what's merged so far). Each version is read as loading
    /// reads it (`records` takes what it holds out of the loaded library);
    /// what the model doesn't know is then kept from each version, newest
    /// first.
    private static func mergeRecords<File: RecordFile>(_ ranked: [ParsedVersion], of file: LibraryFile,
                                                       empty: File, records: (Library) -> File?) -> RecordsMerge {
        let versions = ranked.map { records(LibraryLoader.decode(file, from: $0.data).library) ?? empty }
        var merged = versions[0]
        var conflicts: [String] = []
        for older in versions.dropFirst() {
            let merge = RecordMerger.merge(base: nil, ours: merged, theirs: older, empty: empty, rule: .ours)
            merged = merge.value
            let new = merge.conflicts.filter { !conflicts.contains($0) }
            conflicts += new
        }
        let added = merged.recordCount - versions[0].recordCount
        guard merged != versions[0], var json = try? CanonicalJSON.json(encoding: merged) else {
            return RecordsMerge(json: nil, recordsAdded: added, conflicts: conflicts)
        }
        for version in ranked {
            json = KeyPreservation.preserving(version.json, known: nil, in: json, for: file)
        }
        return RecordsMerge(json: json, recordsAdded: added, conflicts: conflicts)
    }

    private static func summary(name: String, versions: Int, added: Int, conflicts: Int) -> String {
        guard versions > 1 else { return "Kept the only version of \(name)." }
        var parts: [String] = []
        if added > 0 {
            parts.append("added \(added) record\(added == 1 ? "" : "s") that only an older version had")
        }
        if conflicts > 0 {
            parts.append("kept the newest version of \(conflicts) record\(conflicts == 1 ? "" : "s") changed on both sides")
        }
        if parts.isEmpty { return "Merged \(versions) versions of \(name); they had the same records." }
        return "Merged \(versions) versions of \(name): " + parts.joined(separator: "; ") + "."
    }
}

extension RecordFile {
    /// How many records the file holds.
    fileprivate var recordCount: Int {
        Self.recordLists.reduce(0) { $0 + $1.count(in: self) }
    }
}

extension RecordListing {
    /// How many records the list holds in `file`.
    fileprivate func count(in file: File) -> Int {
        file[keyPath: records].count
    }
}
