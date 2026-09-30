import Model

/// What filling in past prices fetched (``PriceService/fillPastPrices(_:in:progress:)``):
/// the records to save, and a result for every instrument, FX rate and
/// index that was missing something, including those whose values have to
/// be typed in and why.
public struct PastPriceFill: Hashable, Sendable {
    /// Prices in each instrument's currency and per its unit, dated the day
    /// they're needed on, sorted by key. Their `source` is the service that
    /// answered, e.g. `yahoo` for gold from `GC=F`.
    public var prices: [PriceRecord]
    /// Rates against the base currency (1 base = rate × quote), dated the day
    /// they're needed on, sorted. Includes the rates used to convert a price
    /// into its instrument's currency.
    public var fx: [FXRecord]
    /// Index values, each dated the last day of its month, sorted.
    public var indices: [IndexRecord]
    /// Instruments (fetched, then typed in, then unknown, each sorted by
    /// ID), then rates, then indices.
    public var results: [PastPriceResult]

    public init(prices: [PriceRecord] = [], fx: [FXRecord] = [], indices: [IndexRecord] = [],
                results: [PastPriceResult] = []) {
        self.prices = prices.sortedByKey()
        self.fx = fx.sortedByKey()
        self.indices = indices.sortedByKey()
        self.results = results
    }

    /// How many records there are to save.
    public var recordCount: Int { prices.count + fx.count + indices.count }

    /// The result for an item, if it was missing anything.
    public func result(for item: PriceListEntry.Item) -> PastPriceResult? {
        results.first { $0.item == item }
    }

    /// The results for instruments.
    public var instrumentResults: [PastPriceResult] {
        results.filter { if case .instrument = $0.item { true } else { false } }
    }

    /// Adds the records `library` doesn't have yet, each into its month's
    /// file. A record is never replaced: not one typed in, not one read from
    /// a file (an import, a journal), not one fetched before, even if it
    /// arrived after the needs were worked out. An FX rate recorded the
    /// other way round (1 quote = rate × base) counts as there.
    @discardableResult
    public func insertMissing(into library: inout Library) -> PastPriceInsertion {
        var inserted = PastPriceInsertion()
        for price in prices {
            if library.months[price.date.yearMonth]?.prices.contains(where: { $0.key == price.key }) == true {
                inserted.kept += 1
            } else {
                library.upsert(price)
                inserted.prices += 1
            }
        }
        for rate in fx {
            let inverse = FXKey(base: rate.quote, quote: rate.base, date: rate.date)
            if library.months[rate.date.yearMonth]?.fx.contains(where: { $0.key == rate.key || $0.key == inverse })
                == true {
                inserted.kept += 1
            } else {
                library.upsert(rate)
                inserted.fx += 1
            }
        }
        for value in indices {
            if library.months[value.date.yearMonth]?.indices.contains(where: { $0.key == value.key }) == true {
                inserted.kept += 1
            } else {
                library.upsert(value)
                inserted.indices += 1
            }
        }
        return inserted
    }
}

/// What ``PastPriceFill/insertMissing(into:)`` added, and how many records
/// it left alone because the library had them by then.
public struct PastPriceInsertion: Hashable, Sendable {
    public var prices = 0
    public var fx = 0
    public var indices = 0
    /// Records the library already had.
    public var kept = 0

    public init() {}

    /// How many records were added.
    public var added: Int { prices + fx + indices }
}

/// How filling in one instrument, rate or index went.
public struct PastPriceResult: Hashable, Sendable, Identifiable {
    /// Where the item stands.
    public enum Status: Hashable, Sendable {
        /// Every date was filled.
        case filled
        /// Some dates were filled; ``PastPriceResult/reason`` says why not the rest.
        case partlyFilled
        /// None could be fetched; ``PastPriceResult/reason`` says why.
        case notFilled
        /// The instrument has no price source: its prices are typed in, or
        /// it's given a source.
        case manual
        /// A position refers to an instrument that isn't in the library.
        case unknownInstrument
    }

    public var item: PriceListEntry.Item
    /// The dates a value was needed on, sorted.
    public var needed: [CalendarDate]
    /// The dates now filled, sorted.
    public var filled: [CalendarDate]
    /// Where the values came from: one run per source, oldest first, e.g.
    /// Yahoo Finance's `ETH-EUR` up to a year ago, then CoinGecko.
    public var sources: [PastPriceSource]
    /// The day each filled value is from, by the date it's for: Friday's
    /// close for a Sunday month end.
    public var observedOn: [CalendarDate: CalendarDate]
    /// Why the dates in ``missing`` weren't filled, as sentences.
    public var reason: String?
    /// Whether the item has no price source or isn't in the library.
    public var isManual: Bool
    public var isUnknown: Bool

    public init(item: PriceListEntry.Item, needed: [CalendarDate], filled: [CalendarDate] = [],
                sources: [PastPriceSource] = [], observedOn: [CalendarDate: CalendarDate] = [:],
                reason: String? = nil, isManual: Bool = false, isUnknown: Bool = false) {
        self.item = item
        self.needed = needed.sorted()
        self.filled = filled.sorted()
        self.sources = sources
        self.observedOn = observedOn
        self.reason = reason
        self.isManual = isManual
        self.isUnknown = isUnknown
    }

    public var id: PriceListEntry.Item { item }

    /// The dates still without a value, sorted.
    public var missing: [CalendarDate] {
        let filled = Set(self.filled)
        return needed.filter { !filled.contains($0) }
    }

    public var status: Status {
        if isUnknown { return .unknownInstrument }
        if isManual { return .manual }
        if filled.isEmpty { return needed.isEmpty ? .filled : .notFilled }
        return filled.count < needed.count ? .partlyFilled : .filled
    }

    /// The instrument, for an instrument's result.
    public var instrument: InstrumentID? {
        if case .instrument(let id) = item { id } else { nil }
    }
}

/// A run of dates filled from one source.
public struct PastPriceSource: Hashable, Sendable {
    public var origin: QuoteOrigin
    /// The first and last date filled from it.
    public var first: CalendarDate
    public var last: CalendarDate
    /// How many dates it filled.
    public var count: Int

    public init(origin: QuoteOrigin, first: CalendarDate, last: CalendarDate, count: Int) {
        self.origin = origin
        self.first = first
        self.last = last
        self.count = count
    }

    /// The runs of `values` (each date's origin), oldest first: consecutive
    /// dates from the same origin make one run.
    static func runs(_ values: [(date: CalendarDate, origin: QuoteOrigin)]) -> [PastPriceSource] {
        var runs: [PastPriceSource] = []
        for value in values.sorted(by: { $0.date < $1.date }) {
            if let last = runs.last, last.origin == value.origin {
                runs[runs.count - 1].last = value.date
                runs[runs.count - 1].count += 1
            } else {
                runs.append(PastPriceSource(origin: value.origin, first: value.date, last: value.date, count: 1))
            }
        }
        return runs
    }
}

/// How far filling in past prices has got: steps done (an instrument's
/// history, a currency's rates, an index) out of those known so far.
public struct PastPriceProgress: Hashable, Sendable {
    public var done: Int
    public var total: Int
    /// What just finished: an instrument's symbol, a currency pair, an index.
    public var finished: String?

    public init(done: Int, total: Int, finished: String? = nil) {
        self.done = done
        self.total = total
        self.finished = finished
    }

    /// Done as a fraction, 0 to 1.
    public var fraction: Double {
        total > 0 ? min(1, Double(done) / Double(total)) : 0
    }
}
