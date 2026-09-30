import Foundation
import Model

/// What filling in past prices needs, worked out from a library: the dates
/// the library values a position on, or converts an amount into the base
/// currency on, that have no price or FX rate recorded for that very day,
/// and the index months it's missing. It holds no amounts: only
/// instruments, currencies and dates.
///
/// - **Dates.** Each valuation of an account open on its date, up to today;
///   and each month end on which an account's latest valuation is carried
///   forward (the charts value it there), in a month where the account has
///   no valuation of its own. For an account that records trades: its
///   valuations' dates, the dates of its transfers and openings (valued at
///   market for its flows), and every month end from its first valuation or
///   trade, holding what its trades leave then.
/// - **Prices.** On those dates, every instrument held (quantity not zero)
///   that has no price record dated that day. Instruments with a price
///   source are fetched; those without are listed with their dates, to type
///   in or to give a source; instruments missing from the library are
///   listed as unknown.
/// - **FX rates.** On those dates, every currency other than the base
///   currency that an amount is in (a balance, cash, or a held instrument's
///   price) with no rate against the base currency, either way round,
///   dated that day.
/// - **Index months.** For each index, the months from the first
///   valuation's through the last that has ended by today without a value.
public struct PastPriceNeeds: Hashable, Sendable {
    /// An instrument and the dates it needs a price on.
    public struct InstrumentDates: Hashable, Sendable, Identifiable {
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

        public var id: InstrumentID { instrument }
    }

    /// A currency and the dates it needs a rate against the base currency on.
    public struct RateDates: Hashable, Sendable, Identifiable {
        public var quote: CurrencyCode
        /// Sorted.
        public var dates: [CalendarDate]

        public init(quote: CurrencyCode, dates: [CalendarDate]) {
            self.quote = quote
            self.dates = dates.sorted()
        }

        public var id: CurrencyCode { quote }
    }

    /// The day the needs were worked out for; nothing after it is needed.
    public var today: CalendarDate
    public var baseCurrency: CurrencyCode
    /// Instruments with a price source, whose prices are fetched, sorted by ID.
    public var instruments: [InstrumentDates]
    /// Instruments without a price source, priced by hand, sorted by ID.
    public var manualInstruments: [InstrumentDates]
    /// Instruments held in positions but missing from the library, sorted.
    public var unknownInstruments: [InstrumentDates]
    /// Currencies to fetch against the base currency, sorted.
    public var rates: [RateDates]
    /// Index months to fetch, one entry per index with missing months.
    public var indices: [CheckInPriceNeeds.IndexMonths]

    public init(
        today: CalendarDate, baseCurrency: CurrencyCode, instruments: [InstrumentDates] = [],
        manualInstruments: [InstrumentDates] = [], unknownInstruments: [InstrumentDates] = [],
        rates: [RateDates] = [], indices: [CheckInPriceNeeds.IndexMonths] = []
    ) {
        self.today = today
        self.baseCurrency = baseCurrency
        self.instruments = instruments
        self.manualInstruments = manualInstruments
        self.unknownInstruments = unknownInstruments
        self.rates = rates
        self.indices = indices.filter { !$0.months.isEmpty }
    }

    /// Works out what `library` is missing up to `today`, for `indices`.
    public init(library: Library, today: CalendarDate, indices: [IndexID] = [.hicpIT]) {
        let base = library.settings.baseCurrency
        var prices: [PriceKey: PriceRecord] = [:]
        var rates: Set<FXKey> = []
        for month in library.months.values {
            for price in month.prices { prices[price.key] = price }
            for rate in month.fx {
                rates.insert(rate.key)
                rates.insert(FXKey(base: rate.quote, quote: rate.base, date: rate.date))
            }
        }

        var priceDates: [InstrumentID: Set<CalendarDate>] = [:]
        var rateDates: [CurrencyCode: Set<CalendarDate>] = [:]
        func needRate(_ currency: CurrencyCode, on date: CalendarDate) {
            guard currency != base, !rates.contains(FXKey(base: base, quote: currency, date: date)) else { return }
            rateDates[currency, default: []].insert(date)
        }

        func needPrice(_ instrument: InstrumentID, on date: CalendarDate) {
            if let price = prices[PriceKey(instrument: instrument, date: date)] {
                needRate(price.currency, on: date)
            } else {
                priceDates[instrument, default: []].insert(date)
                if let instrument = library.instruments[instrument] {
                    needRate(instrument.currency, on: date)
                }
            }
        }

        // Accounts that record trades hold what their trades leave.
        for account in library.accounts.values where account.recordsTrades {
            let end = min(today, account.closed ?? today)
            for (date, held) in Self.tradeDates(of: account, in: library, through: end)
            where account.isOpen(on: date) {
                needRate(account.currency, on: date)
                for instrument in held.keys { needPrice(instrument, on: date) }
            }
            // A trade priced in another currency, without an amount, is converted at its date's rate.
            for trade in library.trades(for: account.id) where trade.amount == nil && trade.price != nil {
                if let currency = trade.currency ?? trade.instrument.flatMap({ library.instruments[$0]?.currency }),
                   currency != account.currency, trade.date <= end {
                    needRate(currency, on: trade.date)
                }
            }
        }

        let valuationsByAccount = Dictionary(grouping: library.months.values.flatMap(\.valuations), by: \.account)
        for (accountID, unsorted) in valuationsByAccount {
            guard let account = library.accounts[accountID], !account.recordsTrades else { continue }
            let valuations = unsorted.sortedByKey()
            let end = min(today, account.closed ?? today)
            for (index, valuation) in valuations.enumerated() where valuation.date <= end {
                let next = index + 1 < valuations.count ? valuations[index + 1].date : nil
                for date in Self.dates(of: valuation, next: next, through: end) where account.isOpen(on: date) {
                    if let balance = valuation.balance {
                        if balance != 0 { needRate(account.currency, on: date) }
                        continue
                    }
                    if let cash = valuation.cash, cash != 0 { needRate(account.currency, on: date) }
                    for position in valuation.positions where position.quantity != 0 {
                        needPrice(position.instrument, on: date)
                    }
                }
            }
        }

        var fetched: [InstrumentDates] = []
        var manual: [InstrumentDates] = []
        var unknown: [InstrumentDates] = []
        for (id, dates) in priceDates.sorted(by: { $0.key < $1.key }) {
            let entry = InstrumentDates(instrument: id, details: library.instruments[id], dates: Array(dates))
            if let instrument = entry.details {
                if CheckInPriceNeeds.isFetched(instrument.priceSource) {
                    fetched.append(entry)
                } else {
                    manual.append(entry)
                }
            } else {
                unknown.append(entry)
            }
        }
        self.init(
            today: today, baseCurrency: base, instruments: fetched, manualInstruments: manual,
            unknownInstruments: unknown,
            rates: rateDates.sorted { $0.key < $1.key }.map { RateDates(quote: $0.key, dates: Array($0.value)) },
            indices: indices.map { Self.missingMonths(of: $0, in: library, today: today) })
    }

    /// The dates `valuation` is valued on: its own, and the month ends after
    /// it (from the next month on) before the account's next valuation, up
    /// to `end`.
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

    static func dates(of valuation: Valuation, next: CalendarDate?, through end: CalendarDate) -> [CalendarDate] {
        var dates = [valuation.date]
        var month = valuation.date.yearMonth.next
        while month.lastDay <= end, next.map({ month.lastDay < $0 }) ?? true {
            dates.append(month.lastDay)
            month = month.next
        }
        return dates
    }

    /// The months without a value for `index`, from the month of the first
    /// valuation through the last month that has ended by `today`.
    static func missingMonths(of index: IndexID, in library: Library, today: CalendarDate) -> CheckInPriceNeeds.IndexMonths {
        let last = today.isEndOfMonth ? today.yearMonth : today.yearMonth.previous
        guard let first = library.checkInDates.first?.yearMonth, first <= last else {
            return CheckInPriceNeeds.IndexMonths(index: index, months: [])
        }
        let recorded = Set(library.indexValues(for: index).map(\.date.yearMonth))
        var months: [YearMonth] = []
        var month = first
        while month <= last {
            if !recorded.contains(month) { months.append(month) }
            month = month.next
        }
        return CheckInPriceNeeds.IndexMonths(index: index, months: months)
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

    /// The dates `instrument` needs a price on, whichever list it's in.
    public func dates(for instrument: InstrumentID) -> [CalendarDate] {
        (instruments + manualInstruments + unknownInstruments).first { $0.instrument == instrument }?.dates ?? []
    }
}
