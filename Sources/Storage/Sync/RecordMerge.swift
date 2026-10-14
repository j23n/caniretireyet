import Model

/// How a three-way merge settles a record that both sides changed, each in
/// its own way.
enum RecordConflictRule: Hashable, Sendable {
    /// Take our version, whatever it is (a deletion too).
    case ours
    /// Take our version, unless we deleted the record and they changed it:
    /// then keep theirs, so a change is never lost to a deletion.
    case oursUnlessDeleted
}

/// The result of a three-way merge of a history or headline file.
struct RecordMerge<Value: Sendable>: Sendable {
    /// The merged file.
    var value: Value
    /// The records both sides changed, each in its own way, as
    /// `valuations: 2026-09-30 conto-fineco`; the rule decided which won.
    var conflicts: [String]

    init(value: Value, conflicts: [String] = []) {
        self.value = value
        self.conflicts = conflicts
    }
}

/// Three-way merges of keyed records (PLAN.md, "Merging, saving and undo"): a common
/// base and two versions changed from it, "ours" and "theirs".
///
/// Record by record, matched by key, in each of the file's record lists
/// (``RecordFile/recordLists``):
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
/// theirs = the files before the import. A sync conflict uses it with no
/// base, ours = the newest version and theirs = each other version in turn.
enum RecordMerger {
    /// Merges the records of a history or headline file. `nil` is a file
    /// with no records; `empty` is the file without records, which the
    /// merged records go into.
    static func merge<File: RecordFile>(base: File?, ours: File?, theirs: File?, empty: File,
                                        rule: RecordConflictRule) -> RecordMerge<File> {
        var conflicts: [String] = []
        var merged = empty
        for list in File.recordLists {
            list.merge(base ?? empty, ours ?? empty, theirs ?? empty, into: &merged, rule: rule,
                       conflicts: &conflicts)
        }
        return RecordMerge(value: merged, conflicts: conflicts)
    }
}

extension RecordListing {
    /// Merges the list's records in `base`, `ours` and `theirs` by key into
    /// `merged`, sorted by key. Within one list, the last record with a key
    /// counts, as when loading. A conflict is listed as
    /// `valuations: 2026-09-30 conto-fineco`.
    func merge(_ base: File, _ ours: File, _ theirs: File, into merged: inout File, rule: RecordConflictRule,
               conflicts: inout [String]) {
        func byKey(_ file: File) -> [Record.Key: Record] {
            Dictionary(file[keyPath: records].map { ($0.key, $0) }, uniquingKeysWith: { _, last in last })
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
                conflicts.append("\(name): \(key)")
                chosen = rule == .oursUnlessDeleted && mine == nil ? other : mine
            }
            if let chosen { result.append(chosen) }
        }
        merged[keyPath: records] = result
    }
}
