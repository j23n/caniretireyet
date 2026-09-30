import Model

/// How a three-way merge settles a record that both sides changed, each in
/// its own way.
public enum RecordConflictRule: Hashable, Sendable {
    /// Take our version, whatever it is (a deletion too).
    case ours
    /// Take our version, unless we deleted the record and they changed it:
    /// then keep theirs, so a change is never lost to a deletion.
    case oursUnlessDeleted
}

/// The result of a three-way merge of a history or headline file.
public struct RecordMerge<Value: Sendable>: Sendable {
    /// The merged file.
    public var value: Value
    /// The records both sides changed, each in its own way, as
    /// `valuations: 2026-09-30 conto-fineco`; the rule decided which won.
    public var conflicts: [String]

    public init(value: Value, conflicts: [String] = []) {
        self.value = value
        self.conflicts = conflicts
    }
}

/// Three-way merges of keyed records (FILE_FORMAT.md, "Saving"): a common
/// base and two versions changed from it, "ours" and "theirs".
///
/// Record by record, matched by key:
///
/// - changed (added, edited or deleted) on one side only: that side's
///   version;
/// - changed the same way on both: that version;
/// - changed differently on both: a conflict, settled by the
///   ``RecordConflictRule``.
///
/// Saving uses it with base = the library as loaded, ours = the library
/// being saved and theirs = the file on disk. Undoing an import uses it with
/// base = the files as the import wrote them, ours = the files now and
/// theirs = the files before the import.
public enum RecordMerger {
    /// Merges the records of a month's history file. `nil` is a month with
    /// no records.
    public static func merge(base: MonthFile?, ours: MonthFile?, theirs: MonthFile?, month: YearMonth,
                             rule: RecordConflictRule) -> RecordMerge<MonthFile> {
        let empty = MonthFile(month: month)
        let (base, ours, theirs) = (base ?? empty, ours ?? empty, theirs ?? empty)
        var conflicts: [String] = []
        var merged = MonthFile(month: month)
        merged.valuations = merge(base.valuations, ours.valuations, theirs.valuations, rule: rule, list: "valuations",
                                  conflicts: &conflicts) { "\($0.date) \($0.account)" }
        merged.prices = merge(base.prices, ours.prices, theirs.prices, rule: rule, list: "prices",
                              conflicts: &conflicts) { "\($0.date) \($0.instrument)" }
        merged.fx = merge(base.fx, ours.fx, theirs.fx, rule: rule, list: "fx",
                          conflicts: &conflicts) { "\($0.date) \($0.base) \($0.quote)" }
        merged.indices = merge(base.indices, ours.indices, theirs.indices, rule: rule, list: "indices",
                               conflicts: &conflicts) { "\($0.date) \($0.index)" }
        merged.trades = merge(base.trades, ours.trades, theirs.trades, rule: rule, list: "trades",
                              conflicts: &conflicts) { "\($0.date) \($0.account) \($0.id)" }
        return RecordMerge(value: merged, conflicts: conflicts)
    }

    /// Merges the headlines of a headline file. `nil` is a file with no
    /// headlines.
    public static func merge(base: HeadlineFile?, ours: HeadlineFile?, theirs: HeadlineFile?,
                             rule: RecordConflictRule) -> RecordMerge<HeadlineFile> {
        var conflicts: [String] = []
        let headlines = merge(base?.headlines ?? [], ours?.headlines ?? [], theirs?.headlines ?? [], rule: rule,
                              list: "headlines", conflicts: &conflicts) { "\($0)" }
        return RecordMerge(value: HeadlineFile(headlines: headlines), conflicts: conflicts)
    }

    /// Merges one list of records by key, sorted by key. Within one list,
    /// the last record with a key counts, as when loading.
    static func merge<Record: KeyedRecord & Equatable>(
        _ base: [Record], _ ours: [Record], _ theirs: [Record], rule: RecordConflictRule, list: String,
        conflicts: inout [String], describe: (Record.Key) -> String
    ) -> [Record] {
        func byKey(_ records: [Record]) -> [Record.Key: Record] {
            Dictionary(records.map { ($0.key, $0) }, uniquingKeysWith: { _, last in last })
        }
        let (base, ours, theirs) = (byKey(base), byKey(ours), byKey(theirs))
        var result: [Record] = []
        for key in Set(base.keys).union(ours.keys).union(theirs.keys).sorted() {
            let (original, mine, other) = (base[key], ours[key], theirs[key])
            let chosen: Record?
            if mine == original {
                chosen = other
            } else if other == original || mine == other {
                chosen = mine
            } else {
                conflicts.append("\(list): \(describe(key))")
                chosen = rule == .oursUnlessDeleted && mine == nil ? other : mine
            }
            if let chosen { result.append(chosen) }
        }
        return result
    }
}
