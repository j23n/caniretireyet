import Foundation
import Model

/// What to fetch: instruments, currencies and index months, each with the
/// dates it needs a value on. It holds no amounts.
///
/// A check-in on a date (``init(library:checkInOn:indices:indexWindow:)``)
/// needs that one date; filling in the past (``init(library:through:indices:)``)
/// needs every past date the library is missing a value on. Both are
/// fetched by ``PriceService/fetch(_:in:refresh:progress:)``.
public struct PriceNeeds: Hashable, Sendable {
    /// An instrument and the dates it needs a price on.
    public struct InstrumentDates: Hashable, Sendable {
        public var instrument: InstrumentID
        /// The instrument as the library has it; `nil` when it's missing.
        public var details: Instrument?
        /// Sorted.
        public var dates: [CalendarDate]

        public init(instrument: InstrumentID, details: Instrument?, dates: [CalendarDate]) {
            self.instrument = instrument
            self.details = details
            self.dates = dates.sorted()
        }
    }

    /// A currency and the dates it needs a rate against the base currency on.
    public struct RateDates: Hashable, Sendable {
        public var quote: CurrencyCode
        /// Sorted.
        public var dates: [CalendarDate]

        public init(quote: CurrencyCode, dates: [CalendarDate]) {
            self.quote = quote
            self.dates = dates.sorted()
        }
    }

    /// Months of an index to fetch.
    public struct IndexMonths: Hashable, Sendable {
        public var index: IndexID
        /// The months without a value, sorted.
        public var months: [YearMonth]

        public init(index: IndexID, months: [YearMonth]) {
            self.index = index
            self.months = months
        }
    }

    /// How many months back a check-in fills in index values.
    public static let defaultIndexWindow = 24

    /// The last date anything is needed on: a check-in's date, or today.
    public var date: CalendarDate
    public var baseCurrency: CurrencyCode
    /// Instruments with a price source, whose prices are fetched, sorted by ID.
    public var instruments: [InstrumentDates]
    /// Instruments without a price source, priced by hand, sorted by ID.
    public var manualInstruments: [InstrumentDates]
    /// Instruments held but missing from the library, sorted.
    public var unknownInstruments: [InstrumentDates]
    /// Currencies to fetch against the base currency, sorted.
    public var rates: [RateDates]
    /// Index months to fetch, one entry per index with missing months.
    public var indices: [IndexMonths]

    public init(
        date: CalendarDate, baseCurrency: CurrencyCode, instruments: [InstrumentDates] = [],
        manualInstruments: [InstrumentDates] = [], unknownInstruments: [InstrumentDates] = [],
        rates: [RateDates] = [], indices: [IndexMonths] = []
    ) {
        self.date = date
        self.baseCurrency = baseCurrency
        self.instruments = instruments
        self.manualInstruments = manualInstruments
        self.unknownInstruments = unknownInstruments
        self.rates = rates
        self.indices = indices.filter { !$0.months.isEmpty }
    }

    /// One instrument's price on `date`, and the rate of its currency when
    /// that isn't `baseCurrency` (*Update Prices*, *Test price fetch*).
    public init(instrument: Instrument, date: CalendarDate, baseCurrency: CurrencyCode) {
        let need = InstrumentDates(instrument: instrument.id, details: instrument, dates: [date])
        let fetched = Self.isFetched(instrument.priceSource)
        self.init(date: date, baseCurrency: baseCurrency, instruments: fetched ? [need] : [],
                  manualInstruments: fetched ? [] : [need],
                  rates: !fetched || instrument.currency == baseCurrency ? []
                      : [RateDates(quote: instrument.currency, dates: [date])])
    }

    /// What a check-in on `date` needs from `library`:
    ///
    /// - **Instruments:** those that the trades of each account open on the
    ///   date leave it holding.
    /// - **Currencies:** every held instrument's currency, and every open
    ///   account's, other than the base currency.
    /// - **Index months:** for each of `indices` (`nil`: the library's own,
    ///   `Library.inflationIndices`), the months that have ended by the date
    ///   and have no value yet, from the month of the library's first
    ///   valuation, at most `indexWindow` months back.
    public init(library: Library, checkInOn date: CalendarDate, indices: [IndexID]? = nil,
                indexWindow: Int = defaultIndexWindow) {
        let base = library.settings.baseCurrency
        let openAccounts = library.accounts(openOn: date)
        var held: Set<InstrumentID> = []
        for account in openAccounts where account.recordsTrades {
            held.formUnion(library.heldQuantities(of: account.id, on: date).keys)
        }
        var currencies = Set(openAccounts.map(\.currency))
        var dates: [InstrumentID: Set<CalendarDate>] = [:]
        for id in held {
            dates[id] = [date]
            if let instrument = library.instruments[id] { currencies.insert(instrument.currency) }
        }
        currencies.remove(base)
        self.init(library: library, date: date, prices: dates,
                  rates: currencies.sorted().map { RateDates(quote: $0, dates: [date]) },
                  indices: (indices ?? library.inflationIndices).map {
                      IndexMonths.missing(of: $0, in: library, upTo: date, window: indexWindow)
                  })
    }

    /// What filling in the past would fetch for `library` up to `today`: the
    /// dates the library values a position on, or converts an amount into
    /// the base currency on, that have no price or FX rate recorded for that
    /// very day, and the index months it's missing.
    ///
    /// - **Dates.** For an account that records trades: its valuations'
    ///   dates, the dates of its transfers and openings (valued at market
    ///   for its flows), and every month end from its first valuation or
    ///   trade, holding what its trades leave then. For a balance account:
    ///   each valuation's date, and each month end on which its latest
    ///   balance is carried forward, up to today.
    /// - **Prices.** On those dates, every instrument held (quantity not
    ///   zero) that has no price record dated that day.
    /// - **FX rates.** On those dates, every currency other than the base
    ///   currency that an amount is in (a balance, or a held instrument's
    ///   price) with no rate against the base currency, either way round,
    ///   dated that day.
    /// - **Index months.** For each of `indices` (`nil`: the library's own),
    ///   the months from the first valuation's through the last that has
    ///   ended by today without a value.
    public init(library: Library, through today: CalendarDate, indices: [IndexID]? = nil) {
        let base = library.settings.baseCurrency
        var prices: Set<PriceKey> = []
        var recordedRates: Set<FXKey> = []
        var priceCurrency: [PriceKey: CurrencyCode] = [:]
        for month in library.months.values {
            for price in month.prices {
                prices.insert(price.key)
                priceCurrency[price.key] = price.currency
            }
            for rate in month.fx {
                recordedRates.insert(rate.key)
                recordedRates.insert(FXKey(base: rate.quote, quote: rate.base, date: rate.date))
            }
        }

        var priceDates: [InstrumentID: Set<CalendarDate>] = [:]
        var rateDates: [CurrencyCode: Set<CalendarDate>] = [:]
        func needRate(_ currency: CurrencyCode, on date: CalendarDate) {
            guard currency != base, !recordedRates.contains(FXKey(base: base, quote: currency, date: date)) else {
                return
            }
            rateDates[currency, default: []].insert(date)
        }
        func needPrice(_ instrument: InstrumentID, on date: CalendarDate) {
            let key = PriceKey(instrument: instrument, date: date)
            if let currency = priceCurrency[key] {
                needRate(currency, on: date)
            } else {
                priceDates[instrument, default: []].insert(date)
                if let instrument = library.instruments[instrument] { needRate(instrument.currency, on: date) }
            }
        }

        // Accounts that record trades hold what their trades leave.
        for account in library.accounts.values where account.recordsTrades {
            let end = min(today, account.closed ?? today)
            for (date, held) in Self.tradeDates(of: account, in: library, through: end) where account.isOpen(on: date) {
                needRate(account.currency, on: date)
                for instrument in held.keys { needPrice(instrument, on: date) }
            }
            // A trade priced in another currency, without an amount, is converted at its date's rate.
            for trade in library.trades(for: account.id) where trade.amount == nil && trade.price != nil {
                let currency = trade.priceCurrency(instruments: library.instruments, accountCurrency: account.currency)
                if currency != account.currency, trade.date <= end { needRate(currency, on: trade.date) }
            }
        }

        // Balance accounts: their balances, carried forward to month ends.
        let valuationsByAccount = Dictionary(grouping: library.months.values.flatMap(\.valuations), by: \.account)
        for (accountID, unsorted) in valuationsByAccount {
            guard let account = library.accounts[accountID], !account.recordsTrades else { continue }
            let valuations = unsorted.sortedByKey()
            let end = min(today, account.closed ?? today)
            for (index, valuation) in valuations.enumerated() where valuation.date <= end {
                guard let balance = valuation.balance, balance != 0 else { continue }
                let next = index + 1 < valuations.count ? valuations[index + 1].date : nil
                for date in Self.dates(of: valuation, next: next, through: end) where account.isOpen(on: date) {
                    needRate(account.currency, on: date)
                }
            }
        }

        self.init(library: library, date: today, prices: priceDates,
                  rates: rateDates.sorted { $0.key < $1.key }.map { RateDates(quote: $0.key, dates: Array($0.value)) },
                  indices: (indices ?? library.inflationIndices).map {
                      IndexMonths.missing(of: $0, in: library, upTo: today, window: nil)
                  })
    }

    /// Sorts the instruments in `prices` into fetched, typed in and unknown.
    private init(library: Library, date: CalendarDate, prices: [InstrumentID: Set<CalendarDate>],
                 rates: [RateDates], indices: [IndexMonths]) {
        var fetched: [InstrumentDates] = []
        var manual: [InstrumentDates] = []
        var unknown: [InstrumentDates] = []
        for (id, dates) in prices.sorted(by: { $0.key < $1.key }) {
            let entry = InstrumentDates(instrument: id, details: library.instruments[id], dates: Array(dates))
            if let instrument = entry.details {
                if Self.isFetched(instrument.priceSource) {
                    fetched.append(entry)
                } else {
                    manual.append(entry)
                }
            } else {
                unknown.append(entry)
            }
        }
        self.init(date: date, baseCurrency: library.settings.baseCurrency, instruments: fetched,
                  manualInstruments: manual, unknownInstruments: unknown, rates: rates, indices: indices)
    }

    /// Whether prices from `source` are fetched: its provider is one the
    /// standard service fetches from (``PriceService/standardInstrumentProviders``)
    /// and it names a symbol. Otherwise they're typed in, also for a
    /// provider the app no longer fetches from, such as `coingecko`.
    public static func isFetched(_ source: PriceSource?) -> Bool {
        guard let source else { return false }
        return PriceService.standardInstrumentProviders.contains(source.provider) && !source.symbol.isEmpty
    }

    /// The dates a trades account is valued on through `end`, with what it
    /// holds then (quantities not zero): each valuation's date, each date a
    /// transfer or opening is valued at market for its flow, and each month
    /// end from its first valuation or trade.
    static func tradeDates(of account: Account, in library: Library,
                           through end: CalendarDate) -> [(CalendarDate, [InstrumentID: Decimal])] {
        let trades = library.trades(for: account.id).inProcessingOrder()
        var dates = Set(library.valuations(for: account.id).map(\.date))
        dates.formUnion(trades.filter { $0.type.isFlow && $0.instrument != nil }.map(\.date))
        guard let first = (Array(dates) + trades.map(\.date)).min(), first <= end else { return [] }
        var month = first.yearMonth
        while month.lastDay <= end {
            dates.insert(month.lastDay)
            month = month.next
        }
        var held = HeldQuantities()
        var next = trades.startIndex
        var result: [(CalendarDate, [InstrumentID: Decimal])] = []
        for date in dates.sorted() where date <= end {
            while next < trades.endIndex, trades[next].date <= date {
                held.apply(trades[next])
                next += 1
            }
            result.append((date, held.held))
        }
        return result
    }

    /// The dates `valuation` is valued on: its own, and the month ends after
    /// it (from the next month on) before the account's next valuation, up
    /// to `end`.
    static func dates(of valuation: Valuation, next: CalendarDate?, through end: CalendarDate) -> [CalendarDate] {
        var dates = [valuation.date]
        var month = valuation.date.yearMonth.next
        while month.lastDay <= end, next.map({ month.lastDay < $0 }) ?? true {
            dates.append(month.lastDay)
            month = month.next
        }
        return dates
    }

    // MARK: - Counts

    /// Whether nothing is missing.
    public var isEmpty: Bool {
        instruments.isEmpty && manualInstruments.isEmpty && unknownInstruments.isEmpty && rates.isEmpty
            && indices.isEmpty
    }

    /// Whether anything can be fetched (instruments with a price source,
    /// rates or index months).
    public var hasFetchable: Bool {
        !instruments.isEmpty || !rates.isEmpty || !indices.isEmpty
    }

    /// How many prices would be fetched.
    public var priceCount: Int { instruments.reduce(0) { $0 + $1.dates.count } }
    /// How many prices have to be typed in (no price source, or unknown instrument).
    public var manualPriceCount: Int {
        (manualInstruments + unknownInstruments).reduce(0) { $0 + $1.dates.count }
    }
    /// How many FX rates would be fetched.
    public var rateCount: Int { rates.reduce(0) { $0 + $1.dates.count } }
    /// How many index months would be fetched.
    public var indexMonthCount: Int { indices.reduce(0) { $0 + $1.months.count } }
}

extension PriceNeeds.IndexMonths {
    /// The months without a value for `index`, from the month of the first
    /// valuation through the last month that has ended by `date`. With a
    /// `window` (a check-in's), at most that many months back, and from
    /// `date`'s month in a library without any valuation; without one (a
    /// fill), none in such a library.
    static func missing(of index: IndexID, in library: Library, upTo date: CalendarDate, window: Int?) -> Self {
        let last = date.isEndOfMonth ? date.yearMonth : date.yearMonth.previous
        var start = library.checkInDates.first?.yearMonth
        if let window {
            start = max(last.adding(months: -(max(1, window) - 1)), start ?? date.yearMonth)
        }
        guard let first = start, first <= last else { return Self(index: index, months: []) }
        let recorded = Set(library.indexValues(for: index).map(\.date.yearMonth))
        var months: [YearMonth] = []
        var month = first
        while month <= last {
            if !recorded.contains(month) { months.append(month) }
            month = month.next
        }
        return Self(index: index, months: months)
    }

    /// Of `records`, the index's values, those of the missing months.
    func values(among records: [IndexRecord]) -> [IndexRecord] {
        let missing = Set(months)
        return records.filter { missing.contains($0.date.yearMonth) }
    }
}
