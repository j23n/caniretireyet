import Model

/// What a check-in needs fetched, worked out from a library and the check-in
/// date. It holds no amounts: only instruments, currencies and months.
///
/// - **Instruments:** those held (quantity not zero) in the latest valuation,
///   on or before the date, of each account open on the date. The ones with a
///   `priceSource` are fetched; the rest are priced by hand.
/// - **Currencies:** every held instrument's currency and every open account's
///   currency other than the base currency, each fetched against the base.
/// - **Index months:** for each index, the months that have ended by the date
///   and have no value yet, from the month of the library's first valuation,
///   at most ``defaultIndexWindow`` months back.
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

    /// Works out what a check-in on `date` needs from `library`.
    public init(
        library: Library, date: CalendarDate, indices: [IndexID] = [.hicpIT], indexWindow: Int = defaultIndexWindow
    ) {
        let base = library.settings.baseCurrency
        let openAccounts = library.accounts(openOn: date)

        var held: Set<InstrumentID> = []
        for account in openAccounts {
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
        currencies.remove(base)

        self.init(
            date: date, baseCurrency: base, instruments: fetched, manualInstruments: manual,
            unknownInstruments: unknown, currencies: currencies.sorted(),
            indices: indices.map { Self.missingMonths(of: $0, in: library, upTo: date, window: indexWindow) })
    }

    /// Whether prices from `source` are fetched: there is one, and its
    /// provider isn't `manual`.
    static func isFetched(_ source: PriceSource?) -> Bool {
        guard let source else { return false }
        return source.provider.rawValue != "manual" && !source.symbol.isEmpty
    }

    /// The months without a value for `index`, from the month of the first
    /// valuation (or of `date`, in a library without any), at most `window`
    /// months back, to the last month that has ended by `date`.
    static func missingMonths(of index: IndexID, in library: Library, upTo date: CalendarDate, window: Int) -> IndexMonths {
        let last = date.isEndOfMonth ? date.yearMonth : date.yearMonth.previous
        let historyStart = library.checkInDates.first?.yearMonth ?? date.yearMonth
        let first = max(last.adding(months: -(max(1, window) - 1)), historyStart)
        guard first <= last else { return IndexMonths(index: index, months: []) }
        let recorded = Set(library.indexValues(for: index).map(\.date.yearMonth))
        var months: [YearMonth] = []
        var month = first
        while month <= last {
            if !recorded.contains(month) { months.append(month) }
            month = month.next
        }
        return IndexMonths(index: index, months: months)
    }
}
