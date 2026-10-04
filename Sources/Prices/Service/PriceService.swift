import Foundation
import Model

/// Fetches the prices, FX rates and inflation-index values a check-in needs.
///
/// Given a library and a check-in date, it works out what's needed
/// (``CheckInPriceNeeds``), fetches everything concurrently, and returns
/// records for the check-in's price list (``CheckInPrices``):
///
/// - **Prices** are dated the check-in date, in the instrument's currency and
///   per its unit. Quotes in another currency or unit (gold-api's USD per
///   troy ounce) are converted with ECB rates and kept to six significant
///   digits.
/// - **FX rates** are fetched against the library's base currency, as the
///   latest ECB rate on or before the date, and dated the check-in date.
/// - **Index values** are the months the library is missing of each index it
///   uses (`Library.inflationIndices`: its own, and one for each plan's
///   currency), each dated the last day of its month.
///
/// A failure affects only its own entry and is reported with a readable
/// reason; ``fetch(for:on:refresh:)`` never throws. Results are cached by
/// provider, symbol and date, so re-opening a check-in doesn't fetch again.
/// Only symbols, currencies and dates are sent, never amounts.
///
/// Free APIs allow only a few calls a minute, so at most
/// ``maxConcurrentFetches`` instruments are fetched at once, across every
/// fetch of the service and its copies, and a provider that prices several
/// symbols per call (``BatchQuoteProvider``: CoinGecko's spot prices) is
/// asked once for all of a fetch's instruments.
///
/// For a date its provider has no price for (gold-api.com only has today's;
/// CoinGecko's free API only the last year), an instrument's price comes
/// from the provider's history routes instead: gold from Yahoo Finance's
/// `GC=F`, an old bitcoin price from `BTC-EUR`. The price list names the
/// stand-in ("Yahoo Finance · GC=F (history)") and the record its source.
///
/// ``fillPastPrices(_:in:progress:)`` fills in every past date a library
/// is missing a price, rate or index value for, a range per instrument at a
/// time (PastPrices.swift).
public struct PriceService: Sendable {
    /// Instrument providers by the `priceSource.provider` they handle.
    public let instrumentProviders: [PriceProvider: any InstrumentPriceProvider]
    public let fxProvider: any FXRateProvider
    /// Index providers by index.
    public let indexProviders: [IndexID: any PriceIndexProvider]
    /// Makes the provider of an index that isn't in ``indexProviders``, or
    /// `nil` for none: the standard service's builds Eurostat's series for
    /// any HICP.
    let makeIndexProvider: @Sendable (IndexID) -> (any PriceIndexProvider)?
    public let cache: PriceCache
    let today: @Sendable () -> CalendarDate
    /// Shared by every instrument fetch (see ``maxConcurrentFetches``).
    let limit: FetchLimit

    /// The default for ``maxConcurrentFetches``.
    public static let defaultMaxConcurrentFetches = 4

    /// The most instruments whose prices are fetched at once.
    public var maxConcurrentFetches: Int { limit.limit }

    /// A service with the given providers. `makeIndexProvider` provides the
    /// indices `indexProviders` doesn't. `today` decides whether a check-in
    /// is in the past (by default the device's current date).
    /// `maxConcurrentFetches` caps the instruments fetched at once.
    public init(
        instrumentProviders: [any InstrumentPriceProvider], fxProvider: any FXRateProvider,
        indexProviders: [any PriceIndexProvider] = [],
        makeIndexProvider: @escaping @Sendable (IndexID) -> (any PriceIndexProvider)? = { _ in nil },
        cache: PriceCache = PriceCache(),
        today: @escaping @Sendable () -> CalendarDate = { CalendarDate.today() },
        maxConcurrentFetches: Int = PriceService.defaultMaxConcurrentFetches
    ) {
        self.instrumentProviders = Dictionary(
            instrumentProviders.map { ($0.provider, $0) }, uniquingKeysWith: { _, last in last })
        self.fxProvider = fxProvider
        self.indexProviders = Dictionary(indexProviders.map { ($0.index, $0) }, uniquingKeysWith: { _, last in last })
        self.makeIndexProvider = makeIndexProvider
        self.cache = cache
        self.today = today
        self.limit = FetchLimit(maxConcurrentFetches)
    }

    /// The provider of `index`: the one given for it, else the one
    /// `makeIndexProvider` makes; `nil` when there's none.
    public func indexProvider(for index: IndexID) -> (any PriceIndexProvider)? {
        indexProviders[index] ?? makeIndexProvider(index)
    }

    /// The indices `library` uses (`Library.inflationIndices`: its own, and
    /// one for each plan's currency) that this service can fetch, sorted.
    public func indices(for library: Library) -> [IndexID] {
        library.inflationIndices.filter { indexProvider(for: $0) != nil }
    }

    /// The standard providers: Yahoo Finance, CoinGecko and gold-api.com for
    /// instruments, Frankfurter for ECB rates, and Eurostat for the HICP of
    /// every country that has one and of the euro area (`hicp-de`,
    /// `hicp-ea`, …).
    public static func standard(
        client: any HTTPClient = URLSessionHTTPClient(), credentials: any CredentialsProvider = StaticCredentials(),
        policy: RequestPolicy = .standard, cache: PriceCache = PriceCache(),
        today: @escaping @Sendable () -> CalendarDate = { CalendarDate.today() },
        maxConcurrentFetches: Int = PriceService.defaultMaxConcurrentFetches
    ) -> PriceService {
        PriceService(
            instrumentProviders: [
                YahooChartProvider(client: client, policy: policy),
                CoinGeckoProvider(client: client, credentials: credentials, policy: policy),
                GoldAPIProvider(client: client, policy: policy),
            ],
            fxProvider: FrankfurterProvider(client: client, policy: policy),
            makeIndexProvider: { index in
                EurostatIndexProvider.Series.hicp(index).map {
                    EurostatIndexProvider(series: $0, client: client, policy: policy)
                }
            },
            cache: cache, today: today, maxConcurrentFetches: maxConcurrentFetches)
    }

    /// What a check-in on `date` needs, with the library's indices this
    /// service provides (``indices(for:)``).
    public func needs(for library: Library, on date: CalendarDate) -> CheckInPriceNeeds {
        CheckInPriceNeeds(library: library, date: date, indices: indices(for: library))
    }

    /// Fetches what a check-in on `date` needs. With `refresh`, the cache is
    /// cleared first.
    public func fetch(for library: Library, on date: CalendarDate, refresh: Bool = false) async -> CheckInPrices {
        await fetch(needs(for: library, on: date), refresh: refresh)
    }

    /// Fetches `needs`, e.g. after adding an instrument the check-in now holds.
    public func fetch(_ needs: CheckInPriceNeeds, refresh: Bool = false) async -> CheckInPrices {
        if refresh { await cache.removeAll() }
        let today = self.today()
        await startBatches(needs, today: today)

        var entries: [PriceListEntry] = []
        var prices: [PriceRecord] = []
        var fx: [FXKey: FXRecord] = [:]
        var indices: [IndexRecord] = []

        await withTaskGroup(of: Part.self) { group in
            for currency in needs.currencies {
                group.addTask { await self.fxPart(quote: currency, needs: needs) }
            }
            for instrument in needs.instruments {
                group.addTask { await self.instrumentPart(instrument, needs: needs, today: today) }
            }
            for need in needs.indices where !need.months.isEmpty {
                group.addTask { await self.indexPart(need, date: needs.date) }
            }
            for await part in group {
                switch part {
                case .instrument(let entry, let price, let rates):
                    entries.append(entry)
                    if let price { prices.append(price) }
                    for rate in rates { fx[rate.key] = rate }
                case .fx(let entry, let rate):
                    entries.append(entry)
                    if let rate { fx[rate.key] = rate }
                case .index(let entry, let records):
                    entries.append(entry)
                    indices += records
                }
            }
        }

        entries += needs.manualInstruments.map { PriceListEntry(item: .instrument($0), outcome: .manual) }
        entries += needs.unknownInstruments.map {
            PriceListEntry(item: .instrument($0), outcome: .failed(.unknownInstrument($0)))
        }
        return CheckInPrices(
            date: needs.date, prices: prices.sortedByKey(), fx: fx.values.sortedByKey(),
            indices: indices.sortedByKey(), entries: entries.sorted { $0.item < $1.item })
    }

    // MARK: - Parts

    private enum Part: Sendable {
        case instrument(PriceListEntry, PriceRecord?, [FXRecord])
        case fx(PriceListEntry, FXRecord?)
        case index(PriceListEntry, [IndexRecord])
    }

    private struct CachedQuote: Sendable {
        let quote: Quote
        let fetchedAt: Date
    }

    private struct CachedRate: Sendable {
        let observation: FXObservation
        let fetchedAt: Date
    }

    private struct CachedIndex: Sendable {
        let records: [IndexRecord]
        let fetchedAt: Date
    }

    private func instrumentPart(_ instrument: Instrument, needs: CheckInPriceNeeds, today: CalendarDate) async -> Part {
        let item = PriceListEntry.Item.instrument(instrument.id)
        guard let priceSource = instrument.priceSource else {
            return .instrument(PriceListEntry(item: item, outcome: .manual), nil, [])
        }
        guard let provider = instrumentProviders[priceSource.provider] else {
            let entry = PriceListEntry(item: item, symbol: priceSource.symbol,
                                       outcome: .failed(.unsupportedProvider(priceSource.provider)))
            return .instrument(entry, nil, [])
        }
        let request = QuoteRequest(symbol: priceSource.symbol, date: needs.date, currency: instrument.currency,
                                   today: today)
        func entry(_ outcome: PriceListEntry.Outcome, origin: QuoteOrigin? = nil) -> PriceListEntry {
            PriceListEntry(item: item, source: origin?.source ?? provider.source,
                           symbol: origin?.symbol ?? priceSource.symbol, outcome: outcome, note: origin?.note)
        }
        do {
            let key = PriceCache.Key(provider: provider.provider.rawValue, symbol: provider.cacheSymbol(for: request),
                                     date: needs.date)
            let limit = self.limit
            let cached = try await cache.value(for: key) {
                try await limit.run {
                    CachedQuote(quote: try await Self.quoteOrHistory(provider, request), fetchedAt: Date())
                }
            }
            let (price, rates) = try await convert(cached.quote, for: instrument, needs: needs)
            let record = PriceRecord(instrument: instrument.id, date: needs.date, price: price,
                                     currency: instrument.currency, source: cached.quote.origin?.source ?? provider.source)
            let details = FetchDetails(observedOn: cached.quote.observedOn, observedAt: cached.quote.observedAt,
                                       fetchedAt: cached.fetchedAt, quote: cached.quote)
            return .instrument(entry(.fetched(details), origin: cached.quote.origin), record, rates)
        } catch {
            return .instrument(entry(.failed(Self.fetchError(error, service: provider.name))), nil, [])
        }
    }

    /// The provider's quote for the request, or, when the provider says it
    /// has none for that date (``InstrumentPriceProvider/triesHistory(after:for:)``:
    /// gold-api.com on a past date, CoinGecko beyond its free year), the
    /// latest value on or before the date from its history routes, which
    /// names its origin. If no route has one, the provider's own error is
    /// thrown, unless a route failed in a way worth retrying (offline, a
    /// timeout, a rate limit), whose error is thrown instead.
    static func quoteOrHistory(_ provider: any InstrumentPriceProvider, _ request: QuoteRequest) async throws -> Quote {
        do {
            return try await provider.quote(for: request)
        } catch {
            return try await history(after: error, provider, request)
        }
    }

    /// After the provider's quote for the request failed with `error`: the
    /// latest value on or before the date from its history routes, when
    /// the error means it has none for that date (see ``quoteOrHistory(_:_:)``);
    /// else `error` again.
    static func history(after error: any Error, _ provider: any InstrumentPriceProvider,
                        _ request: QuoteRequest) async throws -> Quote {
        let failure = fetchError(error, service: provider.name)
        guard provider.triesHistory(after: failure, for: request) else { throw error }
        let range = HistoryRange(from: request.date.adding(days: -PriceHistory.dailyTolerance),
                                 through: request.date, today: request.today)
        var transient: PriceFetchError?
        for route in provider.historyRoutes(symbol: request.symbol, currency: request.currency,
                                            today: request.today) where route.covers(request.date) {
            do {
                let history = try await route.fetch(range)
                if var quote = history.quote(onOrBefore: request.date) {
                    quote.origin = history.origin
                    return quote
                }
            } catch {
                let routeFailure = fetchError(error, service: route.name)
                if routeFailure.isTransient, transient == nil { transient = routeFailure }
            }
        }
        throw transient ?? error
    }

    /// For each provider that prices several symbols per call
    /// (``BatchQuoteProvider``), asks once for all of `needs`' instruments
    /// it prices that aren't cached yet, and caches each one's quote from
    /// that answer, so their parts find them there instead of asking one
    /// by one. A quote the answer fails with tries the history routes, as
    /// in ``quoteOrHistory(_:_:)``. A single instrument is left to its part.
    private func startBatches(_ needs: CheckInPriceNeeds, today: CalendarDate) async {
        var groups: [PriceProvider: [(key: PriceCache.Key, request: QuoteRequest)]] = [:]
        for instrument in needs.instruments {
            guard let priceSource = instrument.priceSource,
                  let provider = instrumentProviders[priceSource.provider], provider is any BatchQuoteProvider
            else { continue }
            let request = QuoteRequest(symbol: priceSource.symbol, date: needs.date, currency: instrument.currency,
                                       today: today)
            let key = PriceCache.Key(provider: provider.provider.rawValue, symbol: provider.cacheSymbol(for: request),
                                     date: needs.date)
            groups[priceSource.provider, default: []].append((key, request))
        }
        for (id, items) in groups.sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
            guard let provider = instrumentProviders[id] as? any BatchQuoteProvider else { continue }
            var keys: Set<PriceCache.Key> = []
            var fresh: [(key: PriceCache.Key, request: QuoteRequest)] = []
            for item in items where keys.insert(item.key).inserted {
                if await !cache.contains(item.key) { fresh.append(item) }
            }
            guard fresh.count > 1 else { continue }
            let requests = fresh.map { $0.request }
            let limit = self.limit
            let batch = Task { await limit.run { await provider.quotes(for: requests) } }
            for (index, item) in fresh.enumerated() {
                await cache.start(item.key) {
                    let quote: Quote
                    switch await batch.value[index] {
                    case .success(let answered):
                        quote = answered
                    case .failure(let error):
                        quote = try await limit.run { try await Self.history(after: error, provider, item.request) }
                    }
                    return CachedQuote(quote: quote, fetchedAt: Date())
                }
            }
        }
    }

    /// The quote as a price in the instrument's currency and per its unit,
    /// and the FX rates used to convert it.
    private func convert(
        _ quote: Quote, for instrument: Instrument, needs: CheckInPriceNeeds
    ) async throws -> (Decimal, [FXRecord]) {
        let quoteUnit = quote.unit ?? instrument.unit
        var price = try PriceConversion.price(quote.price, per: quoteUnit, to: instrument.unit)
        var used: [FXRecord] = []
        if quote.currency != instrument.currency {
            var rates: [CurrencyCode: Decimal] = [:]
            for currency in [quote.currency, instrument.currency] where currency != needs.baseCurrency {
                do {
                    let cached = try await rate(base: needs.baseCurrency, quote: currency, date: needs.date)
                    rates[currency] = cached.observation.rate
                    used.append(FXRecord(base: needs.baseCurrency, quote: currency, date: needs.date,
                                         rate: cached.observation.rate, source: fxProvider.source))
                } catch {
                    let reason = Self.fetchError(error, service: fxProvider.name).description
                    throw PriceFetchError.missingFX(from: quote.currency, to: instrument.currency, reason: reason)
                }
            }
            price = try PriceConversion.amount(price, from: quote.currency, to: instrument.currency,
                                               base: needs.baseCurrency, rates: rates)
        }
        let converted = quote.currency != instrument.currency || quoteUnit != instrument.unit
        return (converted ? price.rounded(significantDigits: PriceConversion.significantDigits) : price, used)
    }

    private func fxPart(quote: CurrencyCode, needs: CheckInPriceNeeds) async -> Part {
        let base = needs.baseCurrency
        let item = PriceListEntry.Item.fx(base: base, quote: quote)
        let symbol = "\(base)/\(quote)"
        do {
            let cached = try await rate(base: base, quote: quote, date: needs.date)
            let record = FXRecord(base: base, quote: quote, date: needs.date, rate: cached.observation.rate,
                                  source: fxProvider.source)
            let details = FetchDetails(observedOn: cached.observation.observedOn, fetchedAt: cached.fetchedAt)
            return .fx(PriceListEntry(item: item, source: fxProvider.source, symbol: symbol,
                                      outcome: .fetched(details)), record)
        } catch {
            let failure = Self.fetchError(error, service: fxProvider.name)
            return .fx(PriceListEntry(item: item, source: fxProvider.source, symbol: symbol,
                                      outcome: .failed(failure)), nil)
        }
    }

    private func rate(base: CurrencyCode, quote: CurrencyCode, date: CalendarDate) async throws -> CachedRate {
        let provider = fxProvider
        let key = PriceCache.Key(provider: provider.source.rawValue, symbol: "\(base)/\(quote)", date: date)
        return try await cache.value(for: key) {
            CachedRate(observation: try await provider.rate(base: base, quote: quote, onOrBefore: date),
                       fetchedAt: Date())
        }
    }

    private func indexPart(_ need: CheckInPriceNeeds.IndexMonths, date: CalendarDate) async -> Part {
        let item = PriceListEntry.Item.index(need.index)
        guard let provider = indexProvider(for: need.index), let first = need.months.first, let last = need.months.last
        else {
            let failure = PriceFetchError.noData(service: "Prices", detail: "no provider for the \(need.index) index")
            return .index(PriceListEntry(item: item, outcome: .failed(failure)), [])
        }
        // Ask for a few months more than missing, so the answer says which
        // month was published last even when none of the missing ones is.
        let start = min(first, last.adding(months: -2))
        do {
            let key = PriceCache.Key(provider: provider.source.rawValue, symbol: "\(need.index) \(start)..\(last)",
                                     date: date)
            let cached = try await cache.value(for: key) {
                CachedIndex(records: try await provider.values(from: start, through: last), fetchedAt: Date())
            }
            let missing = Set(need.months)
            let records = cached.records.filter { missing.contains($0.date.yearMonth) }
            let details = FetchDetails(observedOn: cached.records.map(\.date).max(), fetchedAt: cached.fetchedAt)
            return .index(PriceListEntry(item: item, source: provider.source, outcome: .fetched(details)), records)
        } catch {
            let failure = Self.fetchError(error, service: provider.name)
            return .index(PriceListEntry(item: item, source: provider.source, outcome: .failed(failure)), [])
        }
    }

    /// Any error as a ``PriceFetchError``.
    static func fetchError(_ error: any Error, service: String) -> PriceFetchError {
        switch error {
        case let error as PriceFetchError: error
        case is CancellationError: .cancelled
        default: .network(service: service, message: String(describing: error))
        }
    }
}
