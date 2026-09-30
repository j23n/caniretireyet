import Foundation

/// The whole library in memory: every file in the folder, as model values.
///
/// Storage loads and saves it; this type does no file I/O. Collections are
/// keyed the way files are named, so each entry maps to one file.
public struct Library: Hashable, Sendable {
    /// `library.json`.
    public var settings: LibrarySettings
    /// `accounts/<id>.json`.
    public var accounts: [AccountID: Account]
    /// `instruments/<id>.json`.
    public var instruments: [InstrumentID: Instrument]
    /// `history/YYYY/YYYY-MM.json`.
    public var months: [YearMonth: MonthFile]
    /// `plans/<id>.json`.
    public var plans: [PlanID: PlanDocument]
    /// `imports/<id>.json`.
    public var importProfiles: [ImportProfileID: ImportProfile]
    /// `projections/<plan-id>/`. Kept even when the plan is deleted.
    public var projections: [PlanID: PlanProjections]

    public init(
        settings: LibrarySettings = LibrarySettings(),
        accounts: [Account] = [],
        instruments: [Instrument] = [],
        months: [MonthFile] = [],
        plans: [PlanDocument] = [],
        importProfiles: [ImportProfile] = [],
        projections: [PlanID: PlanProjections] = [:]
    ) {
        self.settings = settings
        self.accounts = Dictionary(accounts.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
        self.instruments = Dictionary(instruments.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
        self.months = Dictionary(months.map { ($0.month, $0) }, uniquingKeysWith: { _, last in last })
        self.plans = Dictionary(plans.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
        self.importProfiles = Dictionary(importProfiles.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
        self.projections = projections
    }
}

/// Saved projections for one plan: `projections/<plan-id>/`.
public struct PlanProjections: Hashable, Sendable {
    /// `baselines/<id>.json`.
    public var baselines: [BaselineID: Baseline]
    /// `headlines/<year>.json`, keyed by year.
    public var headlines: [Int: HeadlineFile]

    public init(baselines: [BaselineID: Baseline] = [:], headlines: [Int: HeadlineFile] = [:]) {
        self.baselines = baselines
        self.headlines = headlines
    }
}

// MARK: - Queries

extension Library {
    /// All accounts, sorted by name, then ID.
    public var sortedAccounts: [Account] {
        accounts.values.sorted { ($0.name, $0.id) < ($1.name, $1.id) }
    }

    /// The accounts that count on `date` (between opened and closed), sorted by name.
    public func accounts(openOn date: CalendarDate) -> [Account] {
        sortedAccounts.filter { $0.isOpen(on: date) }
    }

    /// Every valuation, sorted by date, then account.
    public var allValuations: [Valuation] {
        months.values.flatMap(\.valuations).sortedByKey()
    }

    /// Every price, sorted by date, then instrument.
    public var allPrices: [PriceRecord] {
        months.values.flatMap(\.prices).sortedByKey()
    }

    /// Every FX rate, sorted by date, then currency pair.
    public var allFXRates: [FXRecord] {
        months.values.flatMap(\.fx).sortedByKey()
    }

    /// Every index value, sorted by date, then index.
    public var allIndexValues: [IndexRecord] {
        months.values.flatMap(\.indices).sortedByKey()
    }

    /// Every trade, sorted by key: date, account, ID.
    public var allTrades: [Trade] {
        months.values.flatMap(\.trades).sortedByKey()
    }

    /// An account's valuations, sorted by date.
    public func valuations(for account: AccountID) -> [Valuation] {
        months.values.flatMap { $0.valuations.filter { $0.account == account } }.sortedByKey()
    }

    /// An account's trades, sorted by key (date, then ID). Use
    /// ``Swift/Sequence/inProcessingOrder()`` for the order they apply in.
    public func trades(for account: AccountID) -> [Trade] {
        months.values.flatMap { $0.trades.filter { $0.account == account } }.sortedByKey()
    }

    /// The trade with this key, if there is one.
    public func trade(_ key: TradeKey) -> Trade? {
        months[key.date.yearMonth]?.trades.first { $0.key == key }
    }

    /// The quantity of each instrument an account's trades leave it holding
    /// at the end of `date` (trades on the date included), leaving out
    /// instruments back at zero. Empty for an account without trades.
    public func heldQuantities(of account: AccountID, on date: CalendarDate) -> [InstrumentID: Decimal] {
        HeldQuantities(trades(for: account).filter { $0.date <= date }).held
    }

    /// An instrument's prices, sorted by date.
    public func prices(for instrument: InstrumentID) -> [PriceRecord] {
        months.values.flatMap { $0.prices.filter { $0.instrument == instrument } }.sortedByKey()
    }

    /// The rates recorded for one currency pair (1 base = rate × quote), sorted by date.
    public func fxRates(base: CurrencyCode, quote: CurrencyCode) -> [FXRecord] {
        months.values.flatMap { $0.fx.filter { $0.base == base && $0.quote == quote } }.sortedByKey()
    }

    /// An index's values, sorted by date.
    public func indexValues(for index: IndexID) -> [IndexRecord] {
        months.values.flatMap { $0.indices.filter { $0.index == index } }.sortedByKey()
    }

    /// The distinct dates with at least one valuation, sorted.
    public var checkInDates: [CalendarDate] {
        Set(months.values.flatMap { $0.valuations.map(\.date) }).sorted()
    }

    /// The date of the most recent valuation, if any.
    public var latestCheckInDate: CalendarDate? {
        months.values.lazy.flatMap { $0.valuations.map(\.date) }.max()
    }

    /// A plan's baselines, sorted by creation date.
    public func baselines(for plan: PlanID) -> [Baseline] {
        (projections[plan]?.baselines.values).map { $0.sorted { $0.created < $1.created } } ?? []
    }

    /// A plan's recorded headlines across all years, sorted by date.
    public func headlines(for plan: PlanID) -> [Headline] {
        (projections[plan]?.headlines.values).map { $0.flatMap(\.headlines).sortedByKey() } ?? []
    }
}

// MARK: - Editing history

extension Library {
    /// Adds a valuation, or replaces the one with the same account and date.
    /// It goes into its date's month file, which stays sorted.
    public mutating func upsert(_ valuation: Valuation) {
        let month = valuation.date.yearMonth
        var file = months[month] ?? MonthFile(month: month)
        Self.upsert(valuation, into: &file.valuations)
        months[month] = file
    }

    /// Adds a price, or replaces the one with the same instrument and date.
    public mutating func upsert(_ price: PriceRecord) {
        let month = price.date.yearMonth
        var file = months[month] ?? MonthFile(month: month)
        Self.upsert(price, into: &file.prices)
        months[month] = file
    }

    /// Adds an FX rate, or replaces the one with the same pair and date.
    public mutating func upsert(_ rate: FXRecord) {
        let month = rate.date.yearMonth
        var file = months[month] ?? MonthFile(month: month)
        Self.upsert(rate, into: &file.fx)
        months[month] = file
    }

    /// Adds an index value, or replaces the one with the same index and date.
    public mutating func upsert(_ value: IndexRecord) {
        let month = value.date.yearMonth
        var file = months[month] ?? MonthFile(month: month)
        Self.upsert(value, into: &file.indices)
        months[month] = file
    }

    /// Adds a trade, or replaces the one with the same key (account, date
    /// and ID). It goes into its date's month file, which stays sorted.
    public mutating func upsert(_ trade: Trade) {
        let month = trade.date.yearMonth
        var file = months[month] ?? MonthFile(month: month)
        Self.upsert(trade, into: &file.trades)
        months[month] = file
    }

    /// Removes the trade with this key, returning it if there was one. An
    /// emptied month file stays in `months`.
    @discardableResult
    public mutating func removeTrade(_ key: TradeKey) -> Trade? {
        let month = key.date.yearMonth
        guard let index = months[month]?.trades.firstIndex(where: { $0.key == key }) else { return nil }
        return months[month]?.trades.remove(at: index)
    }

    /// Removes the valuation with this key, returning it if there was one.
    /// An emptied month file stays in `months` (Storage decides whether to delete the file).
    @discardableResult
    public mutating func removeValuation(_ key: ValuationKey) -> Valuation? {
        let month = key.date.yearMonth
        guard let index = months[month]?.valuations.firstIndex(where: { $0.key == key }) else { return nil }
        return months[month]?.valuations.remove(at: index)
    }

    private static func upsert<Record: KeyedRecord>(_ record: Record, into records: inout [Record]) {
        if let index = records.firstIndex(where: { $0.key == record.key }) {
            records[index] = record
        } else {
            let index = records.firstIndex { record.key < $0.key } ?? records.endIndex
            records.insert(record, at: index)
        }
    }
}
