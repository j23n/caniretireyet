import Model

/// What a check-in needs fetched, worked out from a library and the check-in
/// date. It holds no amounts: only instruments, currencies and months.
///
/// - **Instruments:** those held (quantity not zero) in the latest valuation,
///   on or before the date, of each account open on the date, and any others
///   asked for, such as positions added in a check-in. The ones with a
///   `priceSource` are fetched (``isFetched(_:)``); the rest are priced by
///   hand.
/// - **Currencies:** every held instrument's currency, every other fetched
///   one's, and every open account's currency other than the base currency,
///   each fetched against the base.
/// - **Index months:** for each index the library uses (by default
///   `Library.inflationIndices`), the months that have ended by the date and have no value yet, from the
///   month of the library's first valuation, at most ``defaultIndexWindow``
///   months back.
public struct CheckInPriceNeeds: Hashable, Sendable {
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

    /// How many months back index values are filled in.
    public static let defaultIndexWindow = 24

    public var date: CalendarDate
    public var baseCurrency: CurrencyCode
    /// Held instruments with a price source, sorted by ID.
    public var instruments: [Instrument]
    /// Held instruments without a price source, priced by hand, sorted.
    public var manualInstruments: [InstrumentID]
    /// Instruments held in positions but missing from the library, sorted.
    public var unknownInstruments: [InstrumentID]
    /// Currencies to fetch against the base currency, sorted.
    public var currencies: [CurrencyCode]
    /// Index months to fetch, one entry per index.
    public var indices: [IndexMonths]

    public init(
        date: CalendarDate, baseCurrency: CurrencyCode, instruments: [Instrument] = [],
        manualInstruments: [InstrumentID] = [], unknownInstruments: [InstrumentID] = [],
        currencies: [CurrencyCode] = [], indices: [IndexMonths] = []
    ) {
        self.date = date
        self.baseCurrency = baseCurrency
        self.instruments = instruments
        self.manualInstruments = manualInstruments
        self.unknownInstruments = unknownInstruments
        self.currencies = currencies
        self.indices = indices
    }

    /// What one instrument's price on `date` needs: the instrument, and the
    /// rate of its currency when that isn't `baseCurrency`.
    public init(instrument: Instrument, date: CalendarDate, baseCurrency: CurrencyCode) {
        self.init(date: date, baseCurrency: baseCurrency, instruments: [instrument],
                  currencies: instrument.currency == baseCurrency ? [] : [instrument.currency])
    }

    /// Works out what a check-in on `date` needs from `library`, with the
    /// months missing of `indices` (`nil`: the library's own,
    /// `Library.inflationIndices`), and also `extra` instruments the
    /// library doesn't hold on `date`, e.g. positions added in a check-in.
    public init(
        library: Library, date: CalendarDate, indices: [IndexID]? = nil, indexWindow: Int = defaultIndexWindow,
        including extra: [InstrumentID] = []
    ) {
        let base = library.settings.baseCurrency
        let openAccounts = library.accounts(openOn: date)

        var held: Set<InstrumentID> = []
        for account in openAccounts {
            if account.recordsTrades {
                // What its trades leave it holding.
                held.formUnion(library.heldQuantities(of: account.id, on: date).keys)
                continue
            }
            guard let valuation = library.valuations(for: account.id).last(where: { $0.date <= date }),
                  valuation.balance == nil
            else { continue }
            for position in valuation.positions where position.quantity != 0 {
                held.insert(position.instrument)
            }
        }

        var fetched: [Instrument] = []
        var manual: [InstrumentID] = []
        var unknown: [InstrumentID] = []
        var currencies = Set(openAccounts.map(\.currency))
        for id in held.sorted() {
            guard let instrument = library.instruments[id] else {
                unknown.append(id)
                continue
            }
            currencies.insert(instrument.currency)
            if Self.isFetched(instrument.priceSource) {
                fetched.append(instrument)
            } else {
                manual.append(id)
            }
        }
        // Instruments it doesn't hold: their currency only when their price is fetched.
        for id in Set(extra).subtracting(held) {
            guard let instrument = library.instruments[id] else {
                unknown.append(id)
                continue
            }
            if Self.isFetched(instrument.priceSource) {
                fetched.append(instrument)
                currencies.insert(instrument.currency)
            } else {
                manual.append(id)
            }
        }
        currencies.remove(base)

        self.init(
            date: date, baseCurrency: base, instruments: fetched.sorted { $0.id < $1.id },
            manualInstruments: manual.sorted(), unknownInstruments: unknown.sorted(), currencies: currencies.sorted(),
            indices: (indices ?? library.inflationIndices).map {
                IndexMonths.missing(of: $0, in: library, upTo: date, window: indexWindow)
            })
    }

    /// Whether prices from `source` are fetched: there is one, its provider
    /// isn't `manual`, and it names a symbol. Otherwise they're typed in.
    public static func isFetched(_ source: PriceSource?) -> Bool {
        guard let source else { return false }
        return source.provider.rawValue != "manual" && !source.symbol.isEmpty
    }
}

extension CheckInPriceNeeds.IndexMonths {
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
