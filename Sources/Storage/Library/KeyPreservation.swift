import Model

/// Which keys of a file the model knows, so a rewrite can keep the others:
/// fields a newer app version wrote, or notes added by hand.
///
/// Files the model can read, other than history and headline files, keep
/// unknown keys at any depth (``preserving(_:known:in:for:)``): a key is
/// unknown when reading the old file and writing it back would drop it.
///
/// History and headline files, and files the model can't read, follow the
/// rules here: keys of the old file's top-level object that aren't in
/// ``knownKeys`` are copied into the new one. The same happens for nested
/// objects with fixed keys (``objects``) and for records in lists
/// (``records``), which are matched by their key (account + date, …) rather
/// than their position. In history and headline files, records in the old
/// file that the model can't read at all are kept as they are (the loader
/// skips them with an issue), so a rewrite never destroys data that failed
/// to load.
struct KeyPreservation: Sendable {
    var knownKeys: Set<String>
    var objects: [String: KeyPreservation] = [:]
    var records: [String: RecordList] = [:]

    /// A list of keyed records inside an object.
    struct RecordList: Sendable {
        /// The fields that make up a record's key, in sort order (date first).
        var keyFields: [String]
        var rule: KeyPreservation
        /// Whether a record in the old file is readable by the model. When
        /// set, old records that aren't are kept; when `nil`, they're dropped.
        var isReadable: (@Sendable (JSONValue) -> Bool)?
    }

    /// `new` with the keys the model doesn't know copied from `old`.
    func preserving(_ old: JSONValue, in new: JSONValue) -> JSONValue {
        guard case .object(var result) = new, case .object(let previous) = old else { return new }
        for (key, value) in previous where !knownKeys.contains(key) && result[key] == nil {
            result[key] = value
        }
        for (key, rule) in objects {
            if let newValue = result[key], let oldValue = previous[key] {
                result[key] = rule.preserving(oldValue, in: newValue)
            }
        }
        for (key, list) in records {
            guard case .array(let oldRecords)? = previous[key] else { continue }
            let newRecords = result[key]?.arrayValue ?? []
            let merged = list.preserving(oldRecords, in: newRecords)
            if !merged.isEmpty || result[key] != nil { result[key] = .array(merged) }
        }
        return .object(result)
    }
}

extension KeyPreservation.RecordList {
    /// `new` with unknown keys copied from the old record with the same key,
    /// followed by any old records the model can't read.
    func preserving(_ old: [JSONValue], in new: [JSONValue]) -> [JSONValue] {
        var oldByKey: [RecordKey: JSONValue] = [:]
        for record in old {
            if let key = key(of: record) { oldByKey[key] = record }
        }
        let newKeys = Set(new.compactMap(key(of:)))
        var result = new.map { record in
            key(of: record).flatMap { oldByKey[$0] }.map { rule.preserving($0, in: record) } ?? record
        }
        guard let isReadable else { return result }
        for record in old where !isReadable(record) {
            if let key = key(of: record), newKeys.contains(key) { continue }
            result.append(record)
        }
        return result
    }

    /// The record's key, or `nil` if a key field is missing or isn't a
    /// string or number.
    func key(of record: JSONValue) -> RecordKey? {
        var parts: [String] = []
        for field in keyFields {
            switch record[field] {
            case .string(let text)?: parts.append(text)
            case .number(let number)?: parts.append(number.fileString)
            default: return nil
            }
        }
        return RecordKey(parts: parts)
    }
}

// MARK: - Unknown keys at any depth

extension KeyPreservation {
    /// `new`, the model's JSON of `file`, with what the model doesn't know
    /// kept from `old`, the file on disk. `known` is the model's view of
    /// `old`: what loading it and writing it back gives, or `nil` if it
    /// can't be loaded.
    ///
    /// History and headline files, and files the model can't load, follow
    /// the file's rule (``rule(for:)``). Other files keep every key of `old`
    /// that `known` doesn't have, at any depth: in nested objects, and in
    /// list items matched to the new list's items by a natural key (an
    /// `id`, `name`, `header`, `from`, … that every item has, different in
    /// each), else by their other values or position (``ListMatching``).
    /// Unknown keys holding nothing (`null`, `[]`, `{}`) aren't kept.
    static func preserving(_ old: JSONValue, known: JSONValue?, in new: JSONValue, for file: LibraryFile) -> JSONValue {
        guard let known, !file.mergesRecords else { return rule(for: file).preserving(old, in: new) }
        return keepingUnknown(old, known: known, in: new)
    }

    /// `new` with the members of `old` that `known` lacks, recursively.
    static func keepingUnknown(_ old: JSONValue, known: JSONValue, in new: JSONValue) -> JSONValue {
        switch (old, known, new) {
        case (.object(let old), .object(let known), .object(var result)):
            for (key, value) in old {
                if let knownValue = known[key] {
                    if let newValue = result[key] { result[key] = keepingUnknown(value, known: knownValue, in: newValue) }
                } else if result[key] == nil, !value.holdsNothing {
                    result[key] = value
                }
            }
            return .object(result)
        case (.array(let old), .array(let known), .array(var result)):
            let knownIndex = Dictionary(ListMatching.pairs(old: old, new: known).map { ($0.old, $0.new) },
                                        uniquingKeysWith: { first, _ in first })
            for pair in ListMatching.pairs(old: old, new: result) {
                guard let knownPosition = knownIndex[pair.old] else { continue }
                result[pair.new] = keepingUnknown(old[pair.old], known: known[knownPosition], in: result[pair.new])
            }
            return .array(result)
        default:
            return new
        }
    }
}

/// Pairs the items of two versions of a list that hold the same thing.
enum ListMatching {
    /// The fields that can identify a list item, tried in order.
    static let naturalKeys = [
        "id", "date", "year", "name", "header", "index", "account", "instrument", "scheme", "regime", "from", "fromAge",
    ]

    /// Pairs of positions in `old` and `new`: first by the first natural key
    /// that every item of both lists has, with a different value in each.
    /// An item left over (renamed, say) is paired with the leftover old item
    /// that has the most members with the same value, or else with the one
    /// at its position.
    static func pairs(old: [JSONValue], new: [JSONValue]) -> [(old: Int, new: Int)] {
        var oldFor: [Int: Int] = [:]
        var used = Set<Int>()
        if let field = naturalKey(old, new) {
            var positions: [String: Int] = [:]
            for (position, item) in old.enumerated() {
                if let key = item[field].flatMap(keyText) { positions[key] = position }
            }
            for (position, item) in new.enumerated() {
                if let key = item[field].flatMap(keyText), let match = positions[key] {
                    oldFor[position] = match
                    used.insert(match)
                }
            }
        }
        for position in new.indices where oldFor[position] == nil {
            let best = old.indices.filter { !used.contains($0) }
                .map { (old: $0, shared: sharedMembers(old[$0], new[position]), distance: abs($0 - position)) }
                .max { ($0.shared, -$0.distance) < ($1.shared, -$1.distance) }
            guard let best, best.shared > 0 || best.old == position else { continue }
            oldFor[position] = best.old
            used.insert(best.old)
        }
        return oldFor.sorted { $0.key < $1.key }.map { (old: $0.value, new: $0.key) }
    }

    /// How many members two objects have with the same value.
    static func sharedMembers(_ a: JSONValue, _ b: JSONValue) -> Int {
        guard case .object(let first) = a, case .object(let second) = b else { return 0 }
        return first.filter { key, value in
            guard let other = second[key] else { return false }
            return other == value || (keyText(other) != nil && keyText(other) == keyText(value))
        }.count
    }

    /// The first natural key every item of both lists has as text or a
    /// number, with no value twice in one list.
    static func naturalKey(_ old: [JSONValue], _ new: [JSONValue]) -> String? {
        guard !old.isEmpty, !new.isEmpty else { return nil }
        return naturalKeys.first { field in
            [old, new].allSatisfy { items in
                let keys = items.compactMap { $0[field].flatMap(keyText) }
                return keys.count == items.count && Set(keys).count == keys.count
            }
        }
    }

    /// A key value as text: a string, or a number in its shortest form, so
    /// `75` and `"75"` match.
    static func keyText(_ value: JSONValue) -> String? {
        switch value {
        case .string(let text): text
        case .number(let number): number.fileString
        default: nil
        }
    }
}

extension JSONValue {
    /// Whether the value holds no data: `null`, `[]` or `{}`.
    var holdsNothing: Bool {
        switch self {
        case .null: true
        case .array(let items): items.isEmpty
        case .object(let members): members.isEmpty
        default: false
        }
    }
}

/// A record's key as the strings of its key fields, compared field by field
/// (date first, then IDs), which is the order records are written in.
struct RecordKey: Hashable, Comparable, Sendable, CustomStringConvertible {
    var parts: [String]

    static func < (lhs: RecordKey, rhs: RecordKey) -> Bool {
        lhs.parts.lexicographicallyPrecedes(rhs.parts)
    }

    var description: String { parts.joined(separator: " ") }
}

// MARK: - Rules for each file

extension KeyPreservation {
    init<T: KnownKeysProviding>(_ type: T.Type, objects: [String: KeyPreservation] = [:],
                                records: [String: RecordList] = [:]) {
        self.init(knownKeys: T.knownKeys, objects: objects, records: records)
    }

    static let settings = KeyPreservation(LibrarySettings.self, objects: ["person": .init(Person.self)])

    static let account = KeyPreservation(Account.self, objects: ["includeIn": .init(IncludeIn.self)])

    static let instrument = KeyPreservation(Instrument.self, objects: ["priceSource": .init(PriceSource.self)])

    static let month = KeyPreservation(MonthFile.self, records: RecordList.monthLists)

    static let plan = KeyPreservation(PlanDocument.self, objects: [
        "retirement": .init(PlanRetirement.self),
        "tax": .init(PlanTax.self),
        "spending": .init(PlanSpending.self),
        "portfolio": .init(PlanPortfolio.self),
        "assumptions": .init(PlanAssumptions.self),
        "withdrawals": .init(PlanWithdrawals.self),
        "simulation": .init(PlanSimulation.self),
    ])

    static let importProfile = KeyPreservation(ImportProfile.self, objects: [
        "file": .init(ImportFileSettings.self),
        "defaults": .init(ImportFormat.self, objects: [
            "date": .init(ImportDateFormat.self), "number": .init(ImportNumberFormat.self),
        ]),
        "constants": .init(ImportConstants.self),
        "matches": .init(ImportMatches.self),
    ])

    static let baseline = KeyPreservation(Baseline.self, objects: [
        "headline": .init(HeadlineSummary.self),
        "start": .init(BaselineStart.self),
    ], records: [
        "years": RecordList(keyFields: ["year"], rule: .init(BaselineYear.self), isReadable: nil),
    ])

    static let headlines = KeyPreservation(HeadlineFile.self, records: RecordList.headlineLists)

    /// The rule for a library file.
    static func rule(for file: LibraryFile) -> KeyPreservation {
        switch file {
        case .settings: settings
        case .account: account
        case .instrument: instrument
        case .month: month
        case .plan: plan
        case .importProfile: importProfile
        case .baseline: baseline
        case .headlines: headlines
        }
    }
}

extension KeyPreservation.RecordList {
    /// The record lists of a month file, keyed as the model keys them.
    static let monthLists: [String: Self] = [
        "valuations": Self(
            keyFields: ["date", "account"],
            rule: KeyPreservation(Valuation.self, records: [
                "positions": Self(keyFields: ["instrument"], rule: .init(Position.self), isReadable: nil),
            ]),
            isReadable: { LenientDecoding.decodes(Valuation.self, from: $0) }),
        "prices": Self(keyFields: ["date", "instrument"], rule: .init(PriceRecord.self),
                       isReadable: { LenientDecoding.decodes(PriceRecord.self, from: $0) }),
        "fx": Self(keyFields: ["date", "base", "quote"], rule: .init(FXRecord.self),
                   isReadable: { LenientDecoding.decodes(FXRecord.self, from: $0) }),
        "indices": Self(keyFields: ["date", "index"], rule: .init(IndexRecord.self),
                        isReadable: { LenientDecoding.decodes(IndexRecord.self, from: $0) }),
    ]

    /// The record list of a headline file: one headline per check-in date.
    static let headlineLists: [String: Self] = [
        "headlines": Self(keyFields: ["date"], rule: .init(Headline.self),
                          isReadable: { LenientDecoding.decodes(Headline.self, from: $0) }),
    ]
}
