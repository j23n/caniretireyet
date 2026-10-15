import Foundation
import Model

// Fetching a `PriceNeeds` (docs/PLAN.md, "Prices and FX"): a check-in's one
// date and filling in the past's many go through the same steps.

extension PriceService {
    /// Fetches what `needs` asks for, in as few requests as possible, and
    /// returns the records to save and a result per item:
    ///
    /// 1. **Instruments.** Those asking the same provider for the same
    ///    symbol share their requests. The provider's routes are tried in
    ///    order, each with one request for the whole range of dates it
    ///    covers that are still unfilled: one Yahoo Finance request for
    ///    twelve years of an ETF, or gold-api.com for today's gold and
    ///    Yahoo's `GC=F` futures for the days before. Each date takes the
    ///    latest value on or before it (``PriceHistory/quote(onOrBefore:)``).
    /// 2. **FX rates.** Then one request per currency, for the rates `needs`
    ///    asks for and those that convert a price into its instrument's
    ///    currency. A conversion rate `library` has for the day is used as it
    ///    is and isn't fetched.
    /// 3. **Indices.** One request per index, alongside the instruments.
    ///
    /// Each instrument's routes, index and currency waits its turn with the
    /// service's other fetches (``maxConcurrentFetches`` at once), and hands
    /// `progress` a step. Every answer is cached; with `refresh`, the cache
    /// is cleared first. It never throws: what couldn't be fetched is in the
    /// results, with why, and so are the instruments whose prices are typed
    /// in. Save the records with ``FetchedPrices/merge(into:policy:)``.
    public func fetch(_ needs: PriceNeeds, in library: Library? = nil, refresh: Bool = false,
                      progress: (@Sendable (FetchProgress) async -> Void)? = nil) async -> FetchedPrices {
        if refresh { await cache.removeAll() }
        let base = needs.baseCurrency
        let today = self.today()

        // Instruments asking for the same symbol share it.
        var groups: [String: SymbolGroup] = [:]
        var groupOrder: [String] = []
        var groupOf: [InstrumentID: String] = [:]
        for need in needs.instruments {
            guard let source = need.details?.priceSource else { continue }
            let key = "\(source.provider.rawValue) \(source.symbol)"
            if groups[key] == nil {
                groupOrder.append(key)
                groups[key] = SymbolGroup(key: key, provider: instrumentProviders[source.provider], source: source)
            }
            groups[key]?.dates.formUnion(need.dates)
            groupOf[need.instrument] = key
        }

        // 1 and 3: instruments and indices.
        let limit = self.limit
        let steps = groupOrder.count + needs.indices.count
        var total = steps + needs.rates.count
        var done = 0
        var quotes: [String: FetchedQuotes] = [:]
        var indexResults: [PriceResult] = []
        var indexRecords: [IndexRecord] = []
        await withTaskGroup(of: StepOutput.self) { tasks in
            for key in groupOrder {
                guard let group = groups[key] else { continue }
                tasks.addTask { await limit.run { StepOutput.quotes(await self.fetchQuotes(group, today: today)) } }
            }
            for need in needs.indices {
                tasks.addTask {
                    await limit.run {
                        let (result, records) = await self.fetchIndex(need)
                        return StepOutput.index(result, records)
                    }
                }
            }
            for await output in tasks {
                switch output {
                case .quotes(let fetched):
                    quotes[fetched.key] = fetched
                case .index(let result, let records):
                    indexResults.append(result)
                    indexRecords += records
                }
                done += 1
                await progress?(FetchProgress(done: done, total: total))
            }
        }

        // The library's own rates for a day, either way round.
        var libraryRates: [FXKey: Decimal] = [:]
        if let library {
            for month in library.months.values {
                for rate in month.fx where rate.rate > 0 {
                    if rate.base == base {
                        libraryRates[rate.key] = rate.rate
                    } else if rate.quote == base {
                        libraryRates[FXKey(base: base, quote: rate.base, date: rate.date)] = 1 / rate.rate
                    }
                }
            }
        }

        // 2: rates, including those converting a price into its instrument's currency.
        var rateDates: [CurrencyCode: Set<CalendarDate>] = [:]
        for need in needs.rates { rateDates[need.quote, default: []].formUnion(need.dates) }
        for need in needs.instruments {
            guard let instrument = need.details, let key = groupOf[need.instrument], let fetched = quotes[key] else {
                continue
            }
            for date in need.dates {
                guard let quote = fetched.quotes[date], quote.currency != instrument.currency else { continue }
                for currency in [quote.currency, instrument.currency]
                where currency != base && libraryRates[FXKey(base: base, quote: currency, date: date)] == nil {
                    rateDates[currency, default: []].insert(date)
                }
            }
        }
        let currencies = rateDates.keys.sorted()
        total = steps + currencies.count
        var fetchedRates: [CurrencyCode: FetchedRates] = [:]
        await withTaskGroup(of: FetchedRates.self) { tasks in
            for currency in currencies {
                let dates = rateDates[currency, default: []].sorted()
                tasks.addTask { await limit.run { await self.fetchRates(base: base, quote: currency, dates: dates) } }
            }
            for await rates in tasks {
                fetchedRates[rates.quote] = rates
                done += 1
                await progress?(FetchProgress(done: done, total: total))
            }
        }
        func rate(_ currency: CurrencyCode, on date: CalendarDate) -> Decimal? {
            if currency == base { return 1 }
            return fetchedRates[currency]?.rates[date]?.rate ?? libraryRates[FXKey(base: base, quote: currency, date: date)]
        }

        // Prices in each instrument's currency and unit.
        var prices: [PriceRecord] = []
        var results: [PriceResult] = []
        for need in needs.instruments {
            let item = PriceItem.instrument(need.instrument)
            guard let instrument = need.details, let key = groupOf[need.instrument], let group = groups[key],
                  let fetched = quotes[key]
            else {
                results.append(PriceResult(item: item, needed: need.dates, reason: "It has no price source."))
                continue
            }
            var filled: [(date: CalendarDate, origin: QuoteOrigin)] = []
            var used: [CalendarDate: Quote] = [:]
            var observed: [CalendarDate: CalendarDate] = [:]
            var conversionFailure: PriceFetchError?
            for date in need.dates {
                guard let quote = fetched.quotes[date] else { continue }
                do {
                    let price = try PriceConversion.price(of: quote, for: instrument, base: base) { rate($0, on: date) }
                    let origin = quote.origin ?? group.origin
                    prices.append(PriceRecord(instrument: instrument.id, date: date, price: price,
                                              currency: instrument.currency, source: origin.source))
                    filled.append((date, origin))
                    used[date] = quote
                    observed[date] = quote.observedOn
                } catch {
                    conversionFailure = conversionFailure ?? error
                }
            }
            var reasons: [String] = []
            if filled.count < need.dates.count {
                if let reason = fetched.reason { reasons.append(reason) }
                if var failure = conversionFailure {
                    if case .missingFX(let from, let to, nil) = failure {
                        let why = [from, to].compactMap { fetchedRates[$0]?.reason }.first
                        failure = .missingFX(from: from, to: to, reason: why)
                    }
                    reasons.append(failure.description)
                }
            }
            results.append(PriceResult(
                item: item, needed: need.dates, filled: filled.map(\.date), origin: group.origin,
                sources: SourceRun.runs(filled), quotes: used, observedOn: observed, asOf: observed.values.max(),
                fetchedAt: fetched.fetchedAt, reason: reasons.isEmpty ? nil : reasons.joined(separator: " ")))
        }
        for need in needs.manualInstruments {
            results.append(PriceResult(
                item: .instrument(need.instrument), needed: need.dates,
                reason: "It has no price source. Type its prices in, or choose a source to fetch them from.",
                isManual: true))
        }
        for need in needs.unknownInstruments {
            results.append(PriceResult(
                item: .instrument(need.instrument), needed: need.dates,
                reason: PriceFetchError.unknownInstrument(need.instrument).description, isUnknown: true))
        }

        // Rates: the ones fetched, for the days that need one.
        var fx: [FXRecord] = []
        for currency in currencies {
            let needed = rateDates[currency, default: []].sorted()
            let fetched = fetchedRates[currency]
            let origin = QuoteOrigin(source: fxProvider.source, service: fxProvider.name, symbol: "\(base)/\(currency)")
            var filled: [(date: CalendarDate, origin: QuoteOrigin)] = []
            var observed: [CalendarDate: CalendarDate] = [:]
            for date in needed {
                guard let observation = fetched?.rates[date] else { continue }
                fx.append(FXRecord(base: base, quote: currency, date: date, rate: observation.rate,
                                   source: fxProvider.source))
                filled.append((date, origin))
                observed[date] = observation.observedOn
            }
            results.append(PriceResult(
                item: .fx(base: base, quote: currency), needed: needed, filled: filled.map(\.date), origin: origin,
                sources: SourceRun.runs(filled), observedOn: observed, asOf: observed.values.max(),
                fetchedAt: fetched?.fetchedAt, reason: filled.count < needed.count ? fetched?.reason : nil))
        }

        return FetchedPrices(date: needs.date, prices: prices, fx: fx, indices: indexRecords,
                             results: results + indexResults)
    }

    // MARK: - Instruments

    /// Instruments that share their requests: the same provider and symbol.
    struct SymbolGroup: Sendable {
        var key: String
        var provider: (any InstrumentPriceProvider)?
        var source: PriceSource
        /// Every date any of them needs.
        var dates: Set<CalendarDate> = []

        /// The symbol's own source: "Yahoo Finance · VWCE.DE".
        var origin: QuoteOrigin {
            QuoteOrigin(source: provider?.source ?? DataSource(rawValue: source.provider.rawValue),
                        service: provider?.name ?? source.provider.rawValue, symbol: source.symbol)
        }
    }

    /// The quotes a symbol group got, by the date they're for.
    struct FetchedQuotes: Sendable {
        var key: String
        var quotes: [CalendarDate: Quote]
        /// Why some dates have no value, as sentences.
        var reason: String?
        /// When the latest answer was fetched.
        var fetchedAt: Date?
    }

    private struct CachedHistory: Sendable {
        let history: PriceHistory
        let fetchedAt: Date
    }

    /// Tries the group's routes in order, each for the dates the routes
    /// before it didn't fill (and it covers), with one request for all of
    /// them.
    private func fetchQuotes(_ group: SymbolGroup, today: CalendarDate) async -> FetchedQuotes {
        let symbol = group.source.symbol
        var result = FetchedQuotes(key: group.key, quotes: [:])
        guard let provider = group.provider else {
            result.reason = PriceFetchError.unsupportedProvider(group.source.provider).description
            return result
        }
        let routes = provider.routes(symbol: symbol, today: today)
        guard !routes.isEmpty else {
            result.reason = "\(provider.name) has no prices for \(symbol): type them in, "
                + "or choose a price source that has them."
            return result
        }
        var remaining = group.dates.sorted()
        var reasons: [String] = []
        for route in routes {
            let eligible = remaining.filter(route.covers)
            guard let first = eligible.first, let last = eligible.last else { continue }
            var from = first.adding(days: -PriceHistory.dailyTolerance)
            if let earliest = route.earliest { from = max(from, earliest) }
            let range = HistoryRange(from: from, through: last, monthEndsOnly: eligible.allSatisfy(\.isEndOfMonth),
                                     today: today)
            do {
                let key = "\(route.name) \(range.from)..\(range.through)" + (range.monthEndsOnly ? " month ends" : "")
                let cached = try await cache.value(for: key) {
                    CachedHistory(history: try await route.fetch(range), fetchedAt: Date())
                }
                result.fetchedAt = max(result.fetchedAt ?? cached.fetchedAt, cached.fetchedAt)
                var unfilled: [CalendarDate] = []
                for date in eligible {
                    if var quote = cached.history.quote(onOrBefore: date) {
                        quote.origin = cached.history.origin
                        result.quotes[date] = quote
                    } else {
                        unfilled.append(date)
                    }
                }
                if let first = unfilled.first, let last = unfilled.last {
                    let dates = unfilled.count == 1 ? "\(first)" : "\(unfilled.count) dates from \(first) to \(last)"
                    reasons.append("\(route.name) has no value for \(dates).")
                }
            } catch {
                reasons.append(Self.fetchError(error, service: route.name).description)
            }
            remaining.removeAll { result.quotes[$0] != nil }
            if remaining.isEmpty { break }
        }
        if !remaining.isEmpty {
            // Say first when a route's reach is what left dates out.
            let limits = routes.filter { route in remaining.contains { !route.covers($0) } }.compactMap(\.limitReason)
            result.reason = (limits + reasons).joined(separator: " ")
        }
        return result
    }

    // MARK: - Rates and indices

    /// The rates one currency got, by the date they're for.
    struct FetchedRates: Sendable {
        var quote: CurrencyCode
        var rates: [CalendarDate: FXObservation]
        var reason: String?
        var fetchedAt: Date?
    }

    private struct CachedRates: Sendable {
        let history: FXHistory
        let fetchedAt: Date
    }

    /// Rates for `dates` in one request of the FX provider's history.
    private func fetchRates(base: CurrencyCode, quote: CurrencyCode, dates: [CalendarDate]) async -> FetchedRates {
        var result = FetchedRates(quote: quote, rates: [:])
        guard let first = dates.first, let last = dates.last else { return result }
        let provider = fxProvider
        let from = first.adding(days: -Self.rateLookbackDays)
        do {
            let key = "\(provider.source.rawValue) \(base)/\(quote) \(from)..\(last)"
            let cached = try await cache.value(for: key) {
                CachedRates(history: try await provider.rates(base: base, quote: quote, from: from, through: last),
                            fetchedAt: Date())
            }
            result.fetchedAt = cached.fetchedAt
            for date in dates {
                if let rate = cached.history.rate(onOrBefore: date) { result.rates[date] = rate }
            }
            let unfilled = dates.filter { result.rates[$0] == nil }
            if let first = unfilled.first, let last = unfilled.last {
                let range = unfilled.count == 1 ? "\(first)" : "\(unfilled.count) dates from \(first) to \(last)"
                result.reason = "\(provider.name) has no \(base)/\(quote) rate for \(range)."
            }
        } catch {
            result.reason = Self.fetchError(error, service: provider.name).description
        }
        return result
    }

    private struct CachedIndex: Sendable {
        let records: [IndexRecord]
        let fetchedAt: Date
    }

    /// The missing months of an index, from one request for all of them.
    private func fetchIndex(_ need: PriceNeeds.IndexMonths) async -> (PriceResult, [IndexRecord]) {
        let item = PriceItem.index(need.index)
        let needed = need.months.map(\.lastDay)
        guard let provider = indexProvider(for: need.index), let first = need.months.first, let last = need.months.last
        else {
            return (PriceResult(item: item, needed: needed, reason: "There's no provider for the \(need.index) index."),
                    [])
        }
        let origin = QuoteOrigin(source: provider.source, service: provider.name, symbol: need.index.rawValue)
        // Ask for a few months more than missing, so the answer says which
        // month was published last even when none of the missing ones is.
        let start = min(first, last.adding(months: -2))
        do {
            let key = "\(provider.source.rawValue) \(need.index) \(start)..\(last)"
            let cached = try await cache.value(for: key) {
                CachedIndex(records: try await provider.values(from: start, through: last), fetchedAt: Date())
            }
            let records = need.values(among: cached.records)
            let unpublished = needed.count - records.count
            let reason = unpublished > 0
                ? "\(provider.name) has no value for \(unpublished == 1 ? "1 month" : "\(unpublished) months") "
                    + "(the latest months may not be published yet)."
                : nil
            let result = PriceResult(
                item: item, needed: needed, filled: records.map(\.date), origin: origin,
                sources: SourceRun.runs(records.map { ($0.date, origin) }),
                observedOn: Dictionary(records.map { ($0.date, $0.date) }, uniquingKeysWith: { first, _ in first }),
                asOf: cached.records.map(\.date).max(), fetchedAt: cached.fetchedAt, reason: reason)
            return (result, records)
        } catch {
            return (PriceResult(item: item, needed: needed, origin: origin,
                                reason: Self.fetchError(error, service: provider.name).description), [])
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

/// What one step of a fetch got: a symbol's quotes, or an index's months.
private enum StepOutput: Sendable {
    case quotes(PriceService.FetchedQuotes)
    case index(PriceResult, [IndexRecord])
}
