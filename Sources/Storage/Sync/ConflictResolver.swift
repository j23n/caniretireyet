import Foundation
import Model

/// One version of a file in a sync conflict: its contents (or a model
/// value) and when it was last modified.
public struct ConflictVersion<Value: Sendable>: Sendable {
    public var value: Value
    public var modified: Date
    /// Where the version comes from, for the description, e.g. the name of
    /// the device that saved it.
    public var source: String?

    public init(_ value: Value, modified: Date, source: String? = nil) {
        self.value = value
        self.modified = modified
        self.source = source
    }
}

/// The result of resolving a sync conflict.
public struct MergeResult<Value: Sendable>: Sendable {
    /// The merged value.
    public var value: Value
    /// A short description of what was merged, for the Sync screen.
    public var summary: String
    /// Records taken from a version other than the newest.
    public var recordsAdded: Int
    /// Records that differed between versions; the newest version's was kept.
    public var conflictingRecords: [String]

    public init(value: Value, summary: String, recordsAdded: Int = 0, conflictingRecords: [String] = []) {
        self.value = value
        self.summary = summary
        self.recordsAdded = recordsAdded
        self.conflictingRecords = conflictingRecords
    }
}

/// Resolves sync conflicts: two or more versions of the same file saved on
/// different devices before they synced (FILE_FORMAT.md, "Sync conflicts").
///
/// - History and headline files merge record by record: every record from
///   every version is kept, matched by its key (account + date, instrument +
///   date, currency pair + date, index + date, check-in date). When versions
///   disagree about a record, the most recently modified version wins.
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
    public static func merge(path: String, _ versions: [ConflictVersion<Data>]) -> MergeResult<Data> {
        precondition(!versions.isEmpty, "A conflict needs at least one version")
        guard let file = LibraryFile(path: path), file.mergesRecords else {
            return newest(versions, identity: { $0 }, name: path)
        }
        let parsed = versions.compactMap { version -> (json: ConflictVersion<JSONValue>, data: Data)? in
            guard let json = try? CanonicalJSON.parse(version.value), json.objectValue != nil else { return nil }
            return (ConflictVersion(json, modified: version.modified, source: version.source), version.value)
        }
        guard !parsed.isEmpty else { return newest(versions, identity: { $0 }, name: path) }
        let lists = isMonth(file) ? KeyPreservation.RecordList.monthLists : KeyPreservation.RecordList.headlineLists
        var result = mergeRecords(parsed.map(\.json), lists: lists, name: path)
        let unreadable = versions.count - parsed.count
        if unreadable > 0 {
            result.summary += " \(unreadable == 1 ? "1 version wasn't" : "\(unreadable) versions weren't") valid JSON "
                + "and \(unreadable == 1 ? "was" : "were") left out."
        }
        // When the newest version already holds the result, keep its bytes.
        let newestVersion = rank(parsed.map(\.json))[0]
        if result.value == newestVersion.value,
           let original = parsed.first(where: {
               $0.json.value == newestVersion.value && $0.json.modified == newestVersion.modified
           }) {
            return MergeResult(value: original.data, summary: result.summary, recordsAdded: result.recordsAdded,
                               conflictingRecords: result.conflictingRecords)
        }
        return MergeResult(value: CanonicalJSON.data(for: result.value), summary: result.summary,
                           recordsAdded: result.recordsAdded, conflictingRecords: result.conflictingRecords)
    }

    /// Merges versions of a month's history file record by record.
    public static func merge(_ versions: [ConflictVersion<MonthFile>]) throws -> MergeResult<MonthFile> {
        try mergeModel(versions, lists: KeyPreservation.RecordList.monthLists) { "history for \($0.month)" }
    }

    /// Merges versions of a headline file record by record.
    public static func merge(_ versions: [ConflictVersion<HeadlineFile>]) throws -> MergeResult<HeadlineFile> {
        try mergeModel(versions, lists: KeyPreservation.RecordList.headlineLists) { _ in "headlines" }
    }

    /// Keeps the most recently modified version.
    public static func newest<Value: Encodable & Sendable>(_ versions: [ConflictVersion<Value>], name: String)
        -> MergeResult<Value> {
        newest(versions, identity: { (try? CanonicalJSON.data(encoding: $0)) ?? Data() }, name: name)
    }

    // MARK: Internals

    private static func isMonth(_ file: LibraryFile) -> Bool {
        if case .month = file { true } else { false }
    }

    private static func mergeModel<Value: Codable & Sendable>(
        _ versions: [ConflictVersion<Value>], lists: [String: KeyPreservation.RecordList],
        name: (Value) -> String
    ) throws -> MergeResult<Value> {
        precondition(!versions.isEmpty, "A conflict needs at least one version")
        let parsed = try versions.map {
            ConflictVersion(try CanonicalJSON.json(encoding: $0.value), modified: $0.modified, source: $0.source)
        }
        let merged = mergeRecords(parsed, lists: lists, name: name(versions[0].value))
        let value = try LenientDecoding.decode(Value.self, from: merged.value)
        return MergeResult(value: value, summary: merged.summary, recordsAdded: merged.recordsAdded,
                           conflictingRecords: merged.conflictingRecords)
    }

    /// The versions, newest first; ties broken by canonical bytes, descending.
    private static func rank(_ versions: [ConflictVersion<JSONValue>]) -> [ConflictVersion<JSONValue>] {
        let keyed = versions.map { ($0, Array(CanonicalJSON.data(for: $0.value))) }
        return keyed.sorted { lhs, rhs in
            if lhs.0.modified != rhs.0.modified { return lhs.0.modified > rhs.0.modified }
            return rhs.1.lexicographicallyPrecedes(lhs.1)
        }.map(\.0)
    }

    private static func newest<Value: Sendable>(
        _ versions: [ConflictVersion<Value>], identity: (Value) -> Data, name: String
    ) -> MergeResult<Value> {
        precondition(!versions.isEmpty, "A conflict needs at least one version")
        let winner = versions.map { ($0, Array(identity($0.value))) }.max { lhs, rhs in
            if lhs.0.modified != rhs.0.modified { return lhs.0.modified < rhs.0.modified }
            return lhs.1.lexicographicallyPrecedes(rhs.1)
        }!.0
        let others = versions.count - 1
        let from = winner.source.map { " from \($0)" } ?? ""
        let summary = others == 0
            ? "Kept the only version of \(name)."
            : "Kept the newest version of \(name)\(from); \(others == 1 ? "the other version was" : "\(others) other versions were") discarded."
        return MergeResult(value: winner.value, summary: summary)
    }

    /// Every record from every version, by key; for a key in several
    /// versions, the newest version's record. Everything else in the file
    /// comes from the newest version.
    private static func mergeRecords(
        _ versions: [ConflictVersion<JSONValue>], lists: [String: KeyPreservation.RecordList], name: String
    ) -> MergeResult<JSONValue> {
        let ranked = rank(versions)
        guard case .object(var merged) = ranked[0].value else { return MergeResult(value: ranked[0].value, summary: "") }
        var added = 0
        var conflicts: [String] = []
        for (listName, list) in lists.sorted(by: { $0.key < $1.key }) {
            var chosen: [RecordKey: JSONValue] = [:]
            var unkeyed: [JSONValue] = []
            var present = false
            for (rank, version) in ranked.enumerated() {
                guard case .array(let records)? = version.value[listName] else { continue }
                present = true
                for record in records {
                    guard let key = list.key(of: record) else {
                        if !unkeyed.contains(record) {
                            unkeyed.append(record)
                            if rank > 0 { added += 1 }
                        }
                        continue
                    }
                    if let kept = chosen[key] {
                        if kept != record, !conflicts.contains("\(listName): \(key)") {
                            conflicts.append("\(listName): \(key)")
                        }
                    } else {
                        chosen[key] = record
                        if rank > 0 { added += 1 }
                    }
                }
            }
            guard present else { continue }
            merged[listName] = .array(chosen.sorted { $0.key < $1.key }.map(\.value) + unkeyed)
        }
        let result = JSONValue.object(merged)
        return MergeResult(value: result, summary: summary(name: name, versions: versions.count, added: added,
                                                           conflicts: conflicts.count),
                           recordsAdded: added, conflictingRecords: conflicts)
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
