import Model

/// Which existing records fetched ones replace when they're saved.
public enum MergePolicy: Hashable, Sendable {
    /// Only records the library doesn't have are added: filling in the
    /// past, which never replaces anything; `retire prices --apply`.
    case keepExisting
    /// Fetched records also replace other fetched or imported ones; a value
    /// typed in by hand stays: a check-in, *Update Prices*.
    case replaceFetched
    /// Fetched records replace any: `retire prices --apply --overwrite`, or
    /// choosing to replace a typed price.
    case replaceAll
}

/// What saving fetched records did, or would do, by
/// ``Library/merge(prices:fx:indices:policy:)``.
public struct PriceMerge: Hashable, Sendable {
    /// What happens to one fetched record.
    public enum Outcome: Hashable, Sendable {
        /// The library had none for its key: it's added.
        case added
        /// The library had a different one: it's replaced.
        case replaced
        /// The library has the same record: nothing to write.
        case identical
        /// The library has a different one that stays (see ``MergePolicy``).
        case kept

        /// Whether the record is written.
        public var writes: Bool { self == .added || self == .replaced }
    }

    /// Records written, by kind.
    public var prices = 0
    public var fx = 0
    public var indices = 0
    public var added = 0
    public var replaced = 0
    public var identical = 0
    public var kept = 0

    public init() {}

    /// How many records were written.
    public var written: Int { added + replaced }

    /// The one rule for saving a fetched record over `existing` (whether it's
    /// the same, and its source): a value typed in by hand beats a fetched
    /// one unless the policy replaces everything.
    static func outcome(_ existing: (isSame: Bool, source: DataSource?)?, policy: MergePolicy) -> Outcome {
        guard let existing else { return .added }
        if existing.isSame { return .identical }
        switch policy {
        case .keepExisting: return .kept
        case .replaceFetched: return existing.source == .manual ? .kept : .replaced
        case .replaceAll: return .replaced
        }
    }

    mutating func count(_ outcome: Outcome) {
        switch outcome {
        case .added: added += 1
        case .replaced: replaced += 1
        case .identical: identical += 1
        case .kept: kept += 1
        }
    }
}

extension Library {
    /// What saving the fetched `price` by `policy` would do.
    public func mergeOutcome(of price: PriceRecord, policy: MergePolicy) -> PriceMerge.Outcome {
        PriceMerge.outcome(self.price(price.key).map { (isSame: $0 == price, source: $0.source) }, policy: policy)
    }

    /// What saving the fetched `rate` by `policy` would do. A rate the
    /// library has the other way round (1 quote = rate × base) counts as
    /// a different one.
    public func mergeOutcome(of rate: FXRecord, policy: MergePolicy) -> PriceMerge.Outcome {
        if let existing = fxRate(rate.key) {
            return PriceMerge.outcome((isSame: existing == rate, source: existing.source), policy: policy)
        }
        let inverse = fxRate(FXKey(base: rate.quote, quote: rate.base, date: rate.date))
        return PriceMerge.outcome(inverse.map { (isSame: false, source: $0.source) }, policy: policy)
    }

    /// What saving the fetched index `value` by `policy` would do.
    public func mergeOutcome(of value: IndexRecord, policy: MergePolicy) -> PriceMerge.Outcome {
        PriceMerge.outcome(indexValue(value.key).map { (isSame: $0 == value, source: $0.source) }, policy: policy)
    }

    /// Saves fetched records, each into its month's file, by `policy`: the
    /// check-in, *Update Prices*, filling in the past and `retire prices`
    /// all save through here.
    @discardableResult
    public mutating func merge(prices: [PriceRecord] = [], fx: [FXRecord] = [], indices: [IndexRecord] = [],
                               policy: MergePolicy) -> PriceMerge {
        var merge = PriceMerge()
        for price in prices {
            let outcome = mergeOutcome(of: price, policy: policy)
            merge.count(outcome)
            if outcome.writes {
                upsert(price)
                merge.prices += 1
            }
        }
        for rate in fx {
            let outcome = mergeOutcome(of: rate, policy: policy)
            merge.count(outcome)
            if outcome.writes {
                upsert(rate)
                merge.fx += 1
            }
        }
        for value in indices {
            let outcome = mergeOutcome(of: value, policy: policy)
            merge.count(outcome)
            if outcome.writes {
                upsert(value)
                merge.indices += 1
            }
        }
        return merge
    }
}
