import Foundation
import Model

// Filling in past prices (docs/PLAN.md, "Prices and FX"): every date the
// library values a position on without a price for that day, and the FX
// rates and index months it's missing, fetched a range at a time.

extension PriceService {
    /// How many history requests run at once.
    static let pastPriceConcurrency = 4
    /// How many days before the first date wanted a range of FX rates starts:
    /// a long range may come back with a rate a week.
    static let rateLookbackDays = 14

    /// What filling in past prices would fetch for `library` up to today,
    /// with the library's indices this service provides (``indices(for:)``).
    public func pastPriceNeeds(for library: Library) -> PastPriceNeeds {
        PastPriceNeeds(library: library, today: today(), indices: indices(for: library))
    }

    /// Fetches what `needs` asks for, in as few requests as possible, and
    /// returns the records to save and a result per item:
    ///
    /// 1. **Instruments.** Those asking the same provider for the same
    ///    symbol share one history (``InstrumentPriceProvider/cacheSymbol(for:)``).
    ///    The provider's history routes are tried in order, each with one
    ///    request for the whole range of dates it covers that are still
    ///    unfilled: one Yahoo Finance request for twelve years of an ETF, or
    ///    CoinGecko for the last year of a coin and Yahoo's `BTC-EUR` for
    ///    the years before. Each date takes the latest value on or before it
    ///    (``PriceHistory/quote(onOrBefore:)``).
    /// 2. **FX rates.** Then one request per currency, for the rates the
    ///    library is missing and those that convert a price into its
    ///    instrument's currency. A rate the library has for the day converts
    ///    as it is and isn't fetched.
    /// 3. **Indices.** One request per index, alongside the instruments.
    ///
    /// Prices are converted into each instrument's currency and unit as in a
    /// check-in. It never throws: what couldn't be fetched is in the
    /// results, with why, and so are the instruments whose prices are typed
    /// in. `library` supplies the rates for conversions; save the records
    /// with ``PastPriceFill/insertMissing(into:)``, which never replaces one.
    public func fillPastPrices(
        _ needs: PastPriceNeeds, in library: Library,
        progress: (@Sendable (PastPriceProgress) async -> Void)? = nil
    ) async -> PastPriceFill {
        let base = needs.baseCurrency
        let today = needs.today

        // Instruments asking for the same history share it.
        var groups: [String: HistoryGroup] = [:]
        var groupOrder: [String] = []
        var groupOf: [InstrumentID: String] = [:]
        for need in needs.instruments {
            guard let instrument = need.details, let source = instrument.priceSource else { continue }
            let provider = instrumentProviders[source.provider]
            let request = QuoteRequest(symbol: source.symbol, date: today, currency: instrument.currency, today: today)
            let key = "\(source.provider.rawValue) \(provider?.cacheSymbol(for: request) ?? source.symbol)"
            if groups[key] == nil {
                groupOrder.append(key)
                groups[key] = HistoryGroup(key: key, provider: provider, source: source, currency: instrument.currency)
            }
            groups[key]?.dates.formUnion(need.dates)
            groupOf[instrument.id] = key
        }

        // 1 and 3: histories and indices.
        let steps: [PastPriceStep] = groupOrder.compactMap { groups[$0] }.map { .history($0) }
            + needs.indices.map { .index($0) }
        var total = steps.count + needs.rates.count
        var done = 0
        var histories: [String: FetchedHistory] = [:]
        var indexResults: [PastPriceResult] = []
        var indexRecords: [IndexRecord] = []
        await Self.run(steps, maxConcurrent: Self.pastPriceConcurrency) { (step: PastPriceStep) -> PastPriceStepOutput in
            switch step {
            case .history(let group): .history(await self.fetchHistory(group, today: today))
            case .index(let need): .index(await self.fetchIndex(need))
            }
        } received: { (output: PastPriceStepOutput) in
            switch output {
            case .history(let history):
                histories[history.key] = history
            case .index(let (result, records)):
                indexResults.append(result)
                indexRecords += records
            }
            done += 1
            await progress?(PastPriceProgress(done: done, total: total))
        }

        // The library's own rates for a day, either way round.
        var libraryRates: [FXKey: Decimal] = [:]
        for month in library.months.values {
            for rate in month.fx where rate.rate > 0 {
                if rate.base == base {
                    libraryRates[rate.key] = rate.rate
                } else if rate.quote == base {
                    libraryRates[FXKey(base: base, quote: rate.base, date: rate.date)] = 1 / rate.rate
                }
            }
        }

        // 2: rates, including those converting a price into its instrument's currency.
        var rateDates: [CurrencyCode: Set<CalendarDate>] = [:]
        for need in needs.rates { rateDates[need.quote, default: []].formUnion(need.dates) }
        for need in needs.instruments {
            guard let instrument = need.details, let key = groupOf[instrument.id], let history = histories[key] else {
                continue
            }
            for date in need.dates {
                guard let quote = history.quotes[date], quote.currency != instrument.currency else { continue }
                for currency in [quote.currency, instrument.currency]
                where currency != base && libraryRates[FXKey(base: base, quote: currency, date: date)] == nil {
                    rateDates[currency, default: []].insert(date)
                }
            }
        }
        let currencies = rateDates.keys.sorted()
        let wanted = currencies.map { (currency: $0, dates: rateDates[$0, default: []].sorted()) }
        total = steps.count + currencies.count
        var fetchedRates: [CurrencyCode: FetchedRates] = [:]
        await Self.run(wanted, maxConcurrent: Self.pastPriceConcurrency) { want in
            await self.fetchRates(base: base, quote: want.currency, dates: want.dates)
        } received: { rates in
            fetchedRates[rates.quote] = rates
            done += 1
            await progress?(PastPriceProgress(done: done, total: total))
        }
        func rate(_ currency: CurrencyCode, on date: CalendarDate) -> Decimal? {
            if currency == base { return 1 }
            return libraryRates[FXKey(base: base, quote: currency, date: date)]
                ?? fetchedRates[currency]?.rates[date]?.rate
        }

        // Prices in each instrument's currency and unit.
        var prices: [PriceRecord] = []
        var instrumentResults: [PastPriceResult] = []
        for need in needs.instruments {
            let item = PriceListEntry.Item.instrument(need.instrument)
            guard let instrument = need.details, let key = groupOf[instrument.id], let group = groups[key],
                  let history = histories[key]
            else {
                instrumentResults.append(PastPriceResult(item: item, needed: need.dates,
                                                         reason: "It has no price source."))
                continue
            }
            let ownOrigin = QuoteOrigin(source: group.provider?.source ?? DataSource(rawValue: group.source.provider.rawValue),
                                        service: group.provider?.name ?? group.source.provider.rawValue,
                                        symbol: group.source.symbol)
            var filled: [(date: CalendarDate, origin: QuoteOrigin)] = []
            var observed: [CalendarDate: CalendarDate] = [:]
            var conversionFailure: PriceFetchError?
            for date in need.dates {
                guard let quote = history.quotes[date] else { continue }
                do {
                    let price = try Self.convert(quote, to: instrument, base: base) { rate($0, on: date) }
                    let origin = quote.origin ?? ownOrigin
                    prices.append(PriceRecord(instrument: instrument.id, date: date, price: price,
                                              currency: instrument.currency, source: origin.source))
                    filled.append((date, origin))
                    observed[date] = quote.observedOn
                } catch {
                    conversionFailure = conversionFailure ?? error
                }
            }
            var reasons: [String] = []
            if filled.count < need.dates.count {
                if let reason = history.reason { reasons.append(reason) }
                if var failure = conversionFailure {
                    if case .missingFX(let from, let to, nil) = failure {
                        let why = [from, to].compactMap { fetchedRates[$0]?.reason }.first
                        failure = .missingFX(from: from, to: to, reason: why)
                    }
                    reasons.append(failure.description)
                }
            }
            instrumentResults.append(PastPriceResult(
                item: item, needed: need.dates, filled: filled.map(\.date), sources: PastPriceSource.runs(filled),
                observedOn: observed, reason: reasons.isEmpty ? nil : reasons.joined(separator: " ")))
        }
        for need in needs.manualInstruments {
            instrumentResults.append(PastPriceResult(
                item: .instrument(need.instrument), needed: need.dates,
                reason: "It has no price source. Type its prices in, or choose a source to fetch them from.",
                isManual: true))
        }
        for need in needs.unknownInstruments {
            instrumentResults.append(PastPriceResult(
                item: .instrument(need.instrument), needed: need.dates,
                reason: PriceFetchError.unknownInstrument(need.instrument).description, isUnknown: true))
        }

        // Rates: the ones fetched, for the days without one.
        var fx: [FXRecord] = []
        var rateResults: [PastPriceResult] = []
        for currency in currencies {
            let needed = rateDates[currency, default: []].sorted()
            let fetched = fetchedRates[currency]
            var filled: [(date: CalendarDate, origin: QuoteOrigin)] = []
            var observed: [CalendarDate: CalendarDate] = [:]
            let origin = QuoteOrigin(source: fxProvider.source, service: fxProvider.name, symbol: "\(base)/\(currency)")
            for date in needed {
                guard let observation = fetched?.rates[date] else { continue }
                fx.append(FXRecord(base: base, quote: currency, date: date, rate: observation.rate,
                                   source: fxProvider.source))
                filled.append((date, origin))
                observed[date] = observation.observedOn
            }
            rateResults.append(PastPriceResult(
                item: .fx(base: base, quote: currency), needed: needed, filled: filled.map(\.date),
                sources: PastPriceSource.runs(filled), observedOn: observed,
                reason: filled.count < needed.count ? fetched?.reason : nil))
        }

        return PastPriceFill(
            prices: prices, fx: fx, indices: indexRecords,
            results: instrumentResults + rateResults + indexResults.sorted { $0.item < $1.item })
    }

    // MARK: - Instruments

    /// Instruments that share one history: the same provider and symbol
    /// (and currency, for a provider that quotes in any).
    struct HistoryGroup: Sendable {
        var key: String
        var provider: (any InstrumentPriceProvider)?
        var source: PriceSource
        var currency: CurrencyCode
        /// Every date any of them needs.
        var dates: Set<CalendarDate> = []
    }

    /// The values a history group got, by the date they're for.
    struct FetchedHistory: Sendable {
        var key: String
        var quotes: [CalendarDate: Quote]
        /// Why some dates have no value, as sentences.
        var reason: String?
    }

    /// Tries the group's history routes in order, each for the dates the
    /// routes before it didn't fill (and it covers), with one request for
    /// all of them.
    private func fetchHistory(_ group: HistoryGroup, today: CalendarDate) async -> FetchedHistory {
        let symbol = group.source.symbol
        var result = FetchedHistory(key: group.key, quotes: [:])
        guard let provider = group.provider else {
            result.reason = PriceFetchError.unsupportedProvider(group.source.provider).description
            return result
        }
        let routes = provider.historyRoutes(symbol: symbol, currency: group.currency, today: today)
        guard !routes.isEmpty else {
            result.reason = "\(provider.name) has no price history for \(symbol): type the prices in, "
                + "or choose a price source that has one."
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
                let history = try await route.fetch(range)
                var unfilled: [CalendarDate] = []
                for date in eligible {
                    if var quote = history.quote(onOrBefore: date) {
                        quote.origin = history.origin
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

    /// A quote as a price in the instrument's currency and per its unit,
    /// converted with `rate` (1 base = rate × currency) and kept to six
    /// significant digits when converted.
    static func convert(
        _ quote: Quote, to instrument: Instrument, base: CurrencyCode, rate: (CurrencyCode) -> Decimal?
    ) throws(PriceFetchError) -> Decimal {
        let unit = quote.unit ?? instrument.unit
        var price = try PriceConversion.price(quote.price, per: unit, to: instrument.unit)
        if quote.currency != instrument.currency {
            var rates: [CurrencyCode: Decimal] = [:]
            for currency in [quote.currency, instrument.currency] where currency != base {
                guard let value = rate(currency) else {
                    throw .missingFX(from: quote.currency, to: instrument.currency, reason: nil)
                }
                rates[currency] = value
            }
            price = try PriceConversion.amount(price, from: quote.currency, to: instrument.currency, base: base,
                                               rates: rates)
        }
        let converted = quote.currency != instrument.currency || unit != instrument.unit
        return converted ? price.rounded(significantDigits: PriceConversion.significantDigits) : price
    }

    // MARK: - Rates and indices

    /// The rates one currency got, by the date they're for.
    struct FetchedRates: Sendable {
        var quote: CurrencyCode
        var rates: [CalendarDate: FXObservation]
        var reason: String?
    }

    /// Rates for `dates` in one request of the FX provider's history, or,
    /// for a provider without one, a request per date.
    private func fetchRates(base: CurrencyCode, quote: CurrencyCode, dates: [CalendarDate]) async -> FetchedRates {
        var result = FetchedRates(quote: quote, rates: [:])
        guard let first = dates.first, let last = dates.last else { return result }
        let pair = "\(base)/\(quote)"
        if let provider = fxProvider as? any FXHistoryProvider {
            do {
                let history = try await provider.rates(base: base, quote: quote,
                                                       from: first.adding(days: -Self.rateLookbackDays), through: last)
                for date in dates {
                    if let rate = history.rate(onOrBefore: date) { result.rates[date] = rate }
                }
                let unfilled = dates.filter { result.rates[$0] == nil }
                if let first = unfilled.first, let last = unfilled.last {
                    let range = unfilled.count == 1 ? "\(first)" : "\(unfilled.count) dates from \(first) to \(last)"
                    result.reason = "\(fxProvider.name) has no \(pair) rate for \(range)."
                }
            } catch {
                result.reason = Self.fetchError(error, service: fxProvider.name).description
            }
        } else {
            // No ranged history: a request per date, as a check-in would.
            for date in dates {
                do {
                    result.rates[date] = try await fxProvider.rate(base: base, quote: quote, onOrBefore: date)
                } catch {
                    result.reason = Self.fetchError(error, service: fxProvider.name).description
                }
            }
        }
        return result
    }

    /// The missing months of an index, from one request for all of them.
    private func fetchIndex(_ need: CheckInPriceNeeds.IndexMonths) async -> (PastPriceResult, [IndexRecord]) {
        let item = PriceListEntry.Item.index(need.index)
        let needed = need.months.map(\.lastDay)
        guard let provider = indexProvider(for: need.index), let first = need.months.first, let last = need.months.last
        else {
            return (PastPriceResult(item: item, needed: needed, reason: "There's no provider for the \(need.index) index."),
                    [])
        }
        do {
            let missing = Set(need.months)
            let records = try await provider.values(from: first, through: last)
                .filter { missing.contains($0.date.yearMonth) }
            let origin = QuoteOrigin(source: provider.source, service: provider.name, symbol: need.index.rawValue)
            let reason = records.count < needed.count
                ? "\(provider.name) has no value for \(needed.count - records.count == 1 ? "1 month" : "\(needed.count - records.count) months") "
                    + "(the latest months may not be published yet)."
                : nil
            return (PastPriceResult(item: item, needed: needed, filled: records.map(\.date),
                                    sources: PastPriceSource.runs(records.map { ($0.date, origin) }),
                                    observedOn: Dictionary(records.map { ($0.date, $0.date) }, uniquingKeysWith: { a, _ in a }),
                                    reason: reason),
                    records)
        } catch {
            return (PastPriceResult(item: item, needed: needed,
                                    reason: Self.fetchError(error, service: provider.name).description), [])
        }
    }

    // MARK: - Running

    /// Runs `work` on each input, at most `maxConcurrent` at a time, and
    /// hands each output to `received` as it arrives.
    static func run<Input: Sendable, Output: Sendable>(
        _ inputs: [Input], maxConcurrent: Int, _ work: @escaping @Sendable (Input) async -> Output,
        received: (Output) async -> Void
    ) async {
        await withTaskGroup(of: Output.self) { group in
            var next = 0
            func startNext() {
                guard next < inputs.count else { return }
                let input = inputs[next]
                next += 1
                group.addTask { await work(input) }
            }
            for _ in 0..<max(1, maxConcurrent) { startNext() }
            for await output in group {
                await received(output)
                startNext()
            }
        }
    }
}

/// One fetch of filling in past prices.
enum PastPriceStep: Sendable {
    case history(PriceService.HistoryGroup)
    case index(CheckInPriceNeeds.IndexMonths)
}

/// What one ``PastPriceStep`` got.
enum PastPriceStepOutput: Sendable {
    case history(PriceService.FetchedHistory)
    case index((PastPriceResult, [IndexRecord]))
}
