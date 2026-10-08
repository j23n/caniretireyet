import Foundation
import Model

/// The prices, FX rates and index values fetched for a check-in, and one
/// entry per item for the check-in's price list, including what couldn't be
/// fetched and why.
public struct CheckInPrices: Hashable, Sendable {
    /// The check-in date.
    public var date: CalendarDate
    /// One price per fetched instrument, dated the check-in date, in the
    /// instrument's currency and per its unit, sorted by instrument.
    public var prices: [PriceRecord]
    /// Rates against the base currency (1 base = rate × quote), dated the
    /// check-in date, sorted. Includes rates used only to convert a quote.
    public var fx: [FXRecord]
    /// Index values the library doesn't have yet, each dated the last day of
    /// its month, sorted.
    public var indices: [IndexRecord]
    /// The price list: instruments by ID, then FX rates, then indices. An
    /// index is listed only when the library is missing months of it.
    public var entries: [PriceListEntry]

    public init(
        date: CalendarDate, prices: [PriceRecord] = [], fx: [FXRecord] = [], indices: [IndexRecord] = [],
        entries: [PriceListEntry] = []
    ) {
        self.date = date
        self.prices = prices
        self.fx = fx
        self.indices = indices
        self.entries = entries
    }

    /// The entries that couldn't be fetched.
    public var failures: [PriceListEntry] {
        entries.filter { $0.failure != nil }
    }

    /// Whether everything was fetched (manual prices aside).
    public var isComplete: Bool {
        failures.isEmpty
    }

    /// The entry for an item, if it's on the list.
    public func entry(for item: PriceListEntry.Item) -> PriceListEntry? {
        entries.first { $0.item == item }
    }
}

/// One line of a check-in's price list: an instrument, an FX rate or an
/// index, and how fetching it went.
public struct PriceListEntry: Hashable, Sendable {
    /// What the entry is about.
    public enum Item: Hashable, Comparable, Sendable, CustomStringConvertible {
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

        public static func < (lhs: Item, rhs: Item) -> Bool {
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

    /// How fetching went.
    public enum Outcome: Hashable, Sendable {
        /// Fetched now, or earlier and taken from the cache.
        case fetched(FetchDetails)
        /// The instrument has no price source: its price is entered by hand.
        case manual
        /// It couldn't be fetched; the price can be entered by hand.
        case failed(PriceFetchError)
    }

    public var item: Item
    /// The provider's source, e.g. `yahoo` or `ecb`; `nil` when there's none.
    /// For a price from a stand-in (gold futures for a past date), the
    /// stand-in's.
    public var source: DataSource?
    /// The symbol sent to the provider, e.g. `VWCE.DE` or `EUR/USD`; `GC=F`
    /// for gold from its futures.
    public var symbol: String?
    public var outcome: Outcome
    /// A word shown after the source when the value comes from a stand-in
    /// for the instrument's own source: `history` in "Yahoo Finance · GC=F
    /// (history)". `nil` otherwise.
    public var note: String?

    public init(item: Item, source: DataSource? = nil, symbol: String? = nil, outcome: Outcome,
                note: String? = nil) {
        self.item = item
        self.source = source
        self.symbol = symbol
        self.outcome = outcome
        self.note = note
    }

    /// The error, if the entry failed.
    public var failure: PriceFetchError? {
        if case .failed(let error) = outcome { error } else { nil }
    }

    /// A readable reason, if the entry failed.
    public var failureReason: String? {
        failure?.description
    }

    /// The details, if the entry was fetched.
    public var details: FetchDetails? {
        if case .fetched(let details) = outcome { details } else { nil }
    }

    /// What the provider resolved ``symbol`` to, if it had to, e.g.
    /// `ethereum` for CoinGecko's `ETH`: shown as "ETH → ethereum".
    public var resolvedSymbol: String? {
        details?.quote?.resolvedSymbol
    }
}

/// Where a fetched value came from and when.
public struct FetchDetails: Hashable, Sendable {
    /// The day the value is from, e.g. Friday's close for a Sunday check-in.
    /// For an index, the last day of the latest month published.
    public var observedOn: CalendarDate?
    /// When it was fetched. A value from the cache keeps its original time.
    public var fetchedAt: Date
    /// For instruments: the provider's quote before conversion into the
    /// instrument's currency and unit, e.g. USD per troy ounce.
    public var quote: Quote?

    public init(observedOn: CalendarDate? = nil, fetchedAt: Date, quote: Quote? = nil) {
        self.observedOn = observedOn
        self.fetchedAt = fetchedAt
        self.quote = quote
    }
}
