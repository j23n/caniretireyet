import Model

/// Which keys of a file the model knows, so a rewrite can keep the others:
/// fields a newer app version wrote, or notes added by hand.
///
/// When a file is rewritten, keys of the old file's top-level object that
/// aren't in ``knownKeys`` are copied into the new one. The same happens for
/// nested objects with fixed keys (``objects``) and for records in lists
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
