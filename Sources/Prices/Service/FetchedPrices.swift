import Foundation
import Model

/// What ``PriceService/fetch(_:in:refresh:progress:)`` fetched: the records
/// to save, and a result for every instrument, FX rate and index it was
/// asked for, including those whose values have to be typed in and why.
public struct FetchedPrices: Hashable, Sendable {
    /// The last date anything was needed on (``PriceNeeds/date``): a
    /// check-in's date, or today.
    public var date: CalendarDate
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
    /// One result per item, sorted: instruments by ID, then rates, then indices.
    public var results: [PriceResult]

    public init(date: CalendarDate, prices: [PriceRecord] = [], fx: [FXRecord] = [], indices: [IndexRecord] = [],
                results: [PriceResult] = []) {
        self.date = date
        self.prices = prices.sortedByKey()
        self.fx = fx.sortedByKey()
        self.indices = indices.sortedByKey()
        self.results = results.sorted { $0.item < $1.item }
    }

    /// How many records there are to save.
    public var recordCount: Int { prices.count + fx.count + indices.count }

    /// The result for an item, if it was asked for.
    public func result(for item: PriceItem) -> PriceResult? {
        results.first { $0.item == item }
    }

    /// The results that failed (``PriceResult/isFailure``).
    public var failures: [PriceResult] {
        results.filter(\.isFailure)
    }

    /// Whether everything was fetched (prices typed in aside).
    public var isComplete: Bool {
        failures.isEmpty
    }

    /// Saves the records into `library`, each into its month's file, by
    /// `policy` (``Library/merge(prices:fx:indices:policy:)``).
    @discardableResult
    public func merge(into library: inout Library, policy: MergePolicy) -> PriceMerge {
        library.merge(prices: prices, fx: fx, indices: indices, policy: policy)
    }
}

/// What a price result is about: an instrument, an FX rate or an index.
public enum PriceItem: Hashable, Comparable, Sendable, CustomStringConvertible {
    case instrument(InstrumentID)
    /// 1 base = rate × quote.
    case fx(base: CurrencyCode, quote: CurrencyCode)
    case index(IndexID)

    public var description: String {
        switch self {
        case .instrument(let id): id.rawValue
        case .fx(let base, let quote): "\(base)/\(quote)"
        case .index(let id): id.rawValue
        }
    }

    public static func < (lhs: PriceItem, rhs: PriceItem) -> Bool {
        (lhs.rank, lhs.description) < (rhs.rank, rhs.description)
    }

    private var rank: Int {
        switch self {
        case .instrument: 0
        case .fx: 1
        case .index: 2
        }
    }
}

/// How fetching one instrument, rate or index went.
public struct PriceResult: Hashable, Sendable {
    /// Where the item stands.
    public enum Status: Hashable, Sendable {
        /// Every date was filled.
        case filled
        /// Some dates were filled; ``PriceResult/reason`` says why not the rest.
        case partlyFilled
        /// None could be fetched; ``PriceResult/reason`` says why.
        case notFilled
        /// The instrument has no price source: its prices are typed in, or
        /// it's given a source.
        case manual
        /// A position refers to an instrument that isn't in the library.
        case unknownInstrument
    }

    public var item: PriceItem
    /// The dates a value was needed on, sorted.
    public var needed: [CalendarDate]
    /// The dates now filled, sorted.
    public var filled: [CalendarDate]
    /// The item's own source: "Yahoo Finance · VWCE.DE", "Frankfurter (ECB) ·
    /// EUR/USD". `nil` for an instrument without a source.
    public var origin: QuoteOrigin?
    /// Where the values came from: one run per source, oldest first, e.g.
    /// Yahoo Finance's `GC=F` futures up to three days ago, then gold-api.com.
    public var sources: [SourceRun]
    /// For an instrument: the provider's quote of each filled date, before
    /// it was converted into the instrument's currency and unit.
    public var quotes: [CalendarDate: Quote]
    /// The day each filled value is from, by the date it's for: Friday's
    /// close for a Sunday month end.
    public var observedOn: [CalendarDate: CalendarDate]
    /// The day of the newest value the source answered with: for an index,
    /// the last day of the latest month published, even when that month
    /// wasn't missing.
    public var asOf: CalendarDate?
    /// When the values were fetched; a value from the cache keeps its
    /// original time. `nil` when no request succeeded.
    public var fetchedAt: Date?
    /// Why the dates in ``missing`` weren't filled, as sentences.
    public var reason: String?
    /// Whether the item has no price source or isn't in the library.
    public var isManual: Bool
    public var isUnknown: Bool

    public init(item: PriceItem, needed: [CalendarDate], filled: [CalendarDate] = [], origin: QuoteOrigin? = nil,
                sources: [SourceRun] = [], quotes: [CalendarDate: Quote] = [:],
                observedOn: [CalendarDate: CalendarDate] = [:], asOf: CalendarDate? = nil, fetchedAt: Date? = nil,
                reason: String? = nil, isManual: Bool = false, isUnknown: Bool = false) {
        self.item = item
        self.needed = needed.sorted()
        self.filled = filled.sorted()
        self.origin = origin
        self.sources = sources
        self.quotes = quotes
        self.observedOn = observedOn
        self.asOf = asOf
        self.fetchedAt = fetchedAt
        self.reason = reason
        self.isManual = isManual
        self.isUnknown = isUnknown
    }

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

    /// Whether fetching it failed: an instrument or rate with dates left
    /// unfilled, an unknown instrument, or an index whose request failed.
    /// Index months not published yet and prices typed in by hand aren't
    /// failures.
    public var isFailure: Bool {
        switch status {
        case .filled, .manual: false
        case .unknownInstrument: true
        case .notFilled, .partlyFilled:
            if case .index = item { fetchedAt == nil } else { true }
        }
    }

    /// Why it failed, if it did.
    public var failureReason: String? {
        isFailure ? reason : nil
    }

    /// The source a price list names: where the newest value came from, or
    /// the item's own source.
    public var shownOrigin: QuoteOrigin? {
        sources.last?.origin ?? origin
    }
}

/// A run of dates filled from one source.
public struct SourceRun: Hashable, Sendable {
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
    static func runs(_ values: [(date: CalendarDate, origin: QuoteOrigin)]) -> [SourceRun] {
        var runs: [SourceRun] = []
        for value in values.sorted(by: { $0.date < $1.date }) {
            if let last = runs.last, last.origin == value.origin {
                runs[runs.count - 1].last = value.date
                runs[runs.count - 1].count += 1
            } else {
                runs.append(SourceRun(origin: value.origin, first: value.date, last: value.date, count: 1))
            }
        }
        return runs
    }
}

/// How far a fetch has got: steps done (an instrument's prices, a
/// currency's rates, an index) out of those known so far.
public struct FetchProgress: Hashable, Sendable {
    public var done: Int
    public var total: Int

    public init(done: Int, total: Int) {
        self.done = done
        self.total = total
    }

    /// Done as a fraction, 0 to 1.
    public var fraction: Double {
        total > 0 ? min(1, Double(done) / Double(total)) : 0
    }
}
