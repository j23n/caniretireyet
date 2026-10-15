import Foundation
import Model

/// Fetches prices, FX rates and inflation-index values: what a check-in
/// needs on its date, and what filling in the past needs on every date the
/// library is missing a value on. Both are a ``PriceNeeds`` fetched by
/// ``fetch(_:in:refresh:progress:)``, in as few requests as possible:
///
/// - **Prices** are dated the day they're needed on, in the instrument's
///   currency and per its unit. Quotes in another currency or unit
///   (gold-api's USD per troy ounce) are converted with ECB rates and kept
///   to six significant digits.
/// - **FX rates** are fetched against the library's base currency, as the
///   latest ECB rate on or before each date, and dated that day.
/// - **Index values** are the months the library is missing of each index it
///   uses (`Library.inflationIndices`: its own, and one for each plan's
///   currency), each dated the last day of its month.
///
/// A failure affects only its own item and is reported with a readable
/// reason; fetching never throws. Each request's answer is cached, so
/// re-opening a check-in doesn't fetch again. Only symbols, currencies and
/// dates are sent, never amounts.
///
/// Free APIs allow only a few calls a minute, so at most
/// ``maxConcurrentFetches`` instruments, currencies and indices are fetched
/// at once, across every fetch of the service and its copies.
public struct PriceService: Sendable {
    /// Instrument providers by the `priceSource.provider` they handle.
    public let instrumentProviders: [PriceProvider: any InstrumentPriceProvider]
    public let fxProvider: FrankfurterProvider
    /// Makes the provider of an index, or `nil` for none.
    let makeIndexProvider: @Sendable (IndexID) -> (any InflationIndexProvider)?
    public let cache: PriceCache
    let today: @Sendable () -> CalendarDate
    /// Shared by every fetch (see ``maxConcurrentFetches``).
    let limit: FetchLimit

    /// The default for ``maxConcurrentFetches``.
    public static let defaultMaxConcurrentFetches = 4

    /// The most instruments, currencies and indices fetched at once.
    public var maxConcurrentFetches: Int { limit.limit }

    /// How many days before the first date wanted a range of FX rates starts:
    /// a long range may come back with a rate a week.
    static let rateLookbackDays = 14

    /// A service with the given providers; `makeIndexProvider` makes the
    /// provider of an index. `today` is what the providers count as today
    /// (by default the device's current date). `maxConcurrentFetches` caps
    /// the requests sent at once.
    public init(
        instrumentProviders: [any InstrumentPriceProvider], fxProvider: FrankfurterProvider,
        makeIndexProvider: @escaping @Sendable (IndexID) -> (any InflationIndexProvider)?,
        today: @escaping @Sendable () -> CalendarDate = { CalendarDate.today() },
        maxConcurrentFetches: Int = PriceService.defaultMaxConcurrentFetches
    ) {
        self.instrumentProviders = Dictionary(
            instrumentProviders.map { ($0.provider, $0) }, uniquingKeysWith: { _, last in last })
        self.fxProvider = fxProvider
        self.makeIndexProvider = makeIndexProvider
        self.cache = PriceCache()
        self.today = today
        self.limit = FetchLimit(maxConcurrentFetches)
    }

    /// The provider of `index`; `nil` when there's none.
    public func indexProvider(for index: IndexID) -> (any InflationIndexProvider)? {
        makeIndexProvider(index)
    }

    /// The indices `library` uses (`Library.inflationIndices`: its own, and
    /// one for each plan's currency) that this service can fetch, sorted.
    public func indices(for library: Library) -> [IndexID] {
        library.inflationIndices.filter { indexProvider(for: $0) != nil }
    }

    /// The instrument price sources ``standard(client:policy:today:maxConcurrentFetches:)``
    /// fetches from, in the order a picker offers them: Yahoo Finance (also
    /// for crypto, as `BTC-EUR`) and gold-api.com. An instrument whose
    /// source names another provider has its prices typed in
    /// (``PriceNeeds/isFetched(_:)``).
    public static let standardInstrumentProviders: [PriceProvider] = [.yahoo, .goldAPI]

    /// The standard providers: Yahoo Finance and gold-api.com for
    /// instruments (``standardInstrumentProviders``), Frankfurter for ECB
    /// rates, and for inflation indices Eurostat for the HICP of every
    /// country that has one and of the euro area (`hicp-de`, `hicp-ea`, …),
    /// the BLS for `cpi-us` and the ONS for `cpi-gb`.
    public static func standard(
        client: any HTTPClient = URLSessionHTTPClient(), policy: RequestPolicy = .standard,
        today: @escaping @Sendable () -> CalendarDate = { CalendarDate.today() },
        maxConcurrentFetches: Int = PriceService.defaultMaxConcurrentFetches
    ) -> PriceService {
        PriceService(
            instrumentProviders: [
                YahooChartProvider(client: client, policy: policy),
                GoldAPIProvider(client: client, policy: policy),
            ],
            fxProvider: FrankfurterProvider(client: client, policy: policy),
            makeIndexProvider: { index -> (any InflationIndexProvider)? in
                if let eurostat = EurostatIndexProvider(index: index, client: client, policy: policy) { return eurostat }
                if let bls = BLSIndexProvider(index: index, client: client, policy: policy) { return bls }
                if let ons = ONSIndexProvider(index: index, client: client, policy: policy) { return ons }
                return nil
            },
            today: today, maxConcurrentFetches: maxConcurrentFetches)
    }

    /// What a check-in on `date` needs, with the library's indices this
    /// service provides (``indices(for:)``).
    public func needs(for library: Library, on date: CalendarDate) -> PriceNeeds {
        PriceNeeds(library: library, checkInOn: date, indices: indices(for: library))
    }

    /// What filling in the past would fetch for `library` up to today, with
    /// the library's indices this service provides (``indices(for:)``).
    public func pastPriceNeeds(for library: Library) -> PriceNeeds {
        PriceNeeds(library: library, through: today(), indices: indices(for: library))
    }

    /// Fetches what a check-in on `date` needs. With `refresh`, the cache is
    /// cleared first.
    public func fetch(for library: Library, on date: CalendarDate, refresh: Bool = false) async -> FetchedPrices {
        await fetch(needs(for: library, on: date), in: library, refresh: refresh)
    }
}
