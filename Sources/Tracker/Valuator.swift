import Foundation
import Model

/// Computes account values and net worth on any date, following
/// FILE_FORMAT.md, "How values are computed":
///
/// 1. The account's latest valuation on or before the date carries forward.
/// 2. Positions are valued at the latest price on or before the date.
/// 3. Amounts are converted to the base currency at the latest FX rate on or
///    before the date: direct, inverse, or crossed via a pivot currency.
/// 4. An account counts only between its `opened` and `closed` dates.
///
/// Missing prices and FX rates are reported as problems, never counted as
/// zero. Build one valuator per library snapshot and query it for many
/// dates; lookups are binary searches.
///
/// An account whose holdings come from its trades (``Model/ValuationMode/trades``)
/// is valued from a ``snapshot(of:on:)``: the positions its trades leave
/// (``TradeLedger``) and its cash by the cash rule (``tradeCash(of:on:)``),
/// as if that were its latest valuation (docs/TRADES.md).
public struct Valuator: Sendable {
    public let baseCurrency: CurrencyCode
    public let accounts: [AccountID: Account]
    /// Instruments by ID, for asset mixes. A position in an instrument that
    /// isn't here counts as asset class `other`.
    public let instruments: [InstrumentID: Instrument]
    public let prices: PriceTable
    public let fx: FXTable
    private let valuationsByAccount: [AccountID: [Valuation]]
    /// One ledger per account that records trades, with or without trades.
    let ledgers: [AccountID: TradeLedger]
    /// Trades of accounts that don't record trades (or don't exist): left out.
    let ignoredTrades: [Trade]

    /// A valuator over a library snapshot.
    public init(library: Library) {
        self.init(
            baseCurrency: library.settings.baseCurrency,
            accounts: Array(library.accounts.values),
            valuations: library.months.values.flatMap(\.valuations),
            prices: PriceTable(library: library),
            fx: FXTable(library: library),
            instruments: Array(library.instruments.values),
            trades: library.months.values.flatMap(\.trades))
    }

    /// A valuator over explicit data. For duplicate valuation or trade keys
    /// the last one wins. Trades count only for accounts that record trades.
    public init(baseCurrency: CurrencyCode, accounts: [Account], valuations: [Valuation], prices: PriceTable,
                fx: FXTable, instruments: [Instrument] = [], trades: [Trade] = []) {
        self.baseCurrency = baseCurrency
        self.accounts = Dictionary(accounts.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
        self.instruments = Dictionary(instruments.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
        var byKey: [ValuationKey: Valuation] = [:]
        for valuation in valuations { byKey[valuation.key] = valuation }
        self.valuationsByAccount = Dictionary(grouping: byKey.values, by: \.account).mapValues { $0.sortedByKey() }
        self.prices = prices
        self.fx = fx
        var tradesByKey: [TradeKey: Trade] = [:]
        for trade in trades { tradesByKey[trade.key] = trade }
        let tradesByAccount = Dictionary(grouping: tradesByKey.values, by: \.account)
        var ledgers: [AccountID: TradeLedger] = [:]
        for account in self.accounts.values where account.recordsTrades {
            ledgers[account.id] = TradeLedger(account: account, trades: tradesByAccount[account.id] ?? [],
                                              instruments: self.instruments, fx: fx)
        }
        self.ledgers = ledgers
        ignoredTrades = tradesByKey.values.filter { ledgers[$0.account] == nil }.sortedByKey()
    }

    /// An account's valuations, sorted by date.
    public func valuations(for account: AccountID) -> [Valuation] {
        valuationsByAccount[account] ?? []
    }

    /// The account's latest valuation dated on or before `date`.
    public func latestValuation(for account: AccountID, onOrBefore date: CalendarDate) -> Valuation? {
        guard let valuations = valuationsByAccount[account],
              let index = valuations.lastIndex(onOrBefore: date, date: \.date)
        else { return nil }
        return valuations[index]
    }

    /// The account's latest valuation dated strictly before `date`: the one a
    /// valuation on `date` follows.
    public func previousValuation(for account: AccountID, before date: CalendarDate) -> Valuation? {
        guard let valuations = valuationsByAccount[account],
              let index = valuations.lastIndex(onOrBefore: date.adding(days: -1), date: \.date)
        else { return nil }
        return valuations[index]
    }

    /// The account's value on `date`, or `nil` if there's no such account.
    public func value(of account: AccountID, on date: CalendarDate) -> AccountValue? {
        accounts[account].map { value(of: $0, on: date) }
    }

    /// `valuation` valued on `date` as if it were its account's latest one,
    /// at the prices and FX rates of that date and whatever the account's
    /// opened and closed dates: for example, last month's quantities at
    /// today's prices. `nil` if the account is unknown.
    public func value(of valuation: Valuation, on date: CalendarDate) -> AccountValue? {
        accounts[valuation.account].map { value(of: $0, valuation: valuation, on: date) }
    }

    /// Net worth on `date`: every account included in net worth that counts on the date.
    public func netWorth(on date: CalendarDate) -> NetWorth {
        total(on: date) { $0.includedInNetWorth }
    }

    /// The total of the accounts selected by `include` that count on `date`,
    /// e.g. `{ $0.includedInPlan }` for the plan's assets.
    public func total(on date: CalendarDate, including include: (Account) -> Bool) -> NetWorth {
        let values = accounts.values
            .filter { include($0) && $0.isOpen(on: date) }
            .sorted { $0.id < $1.id }
            .map { value(of: $0, on: date) }
        return NetWorth(date: date, currency: baseCurrency, accounts: values)
    }

    // MARK: - Computing one account

    /// `account`'s value on `date`, in `currency` (the base currency when `nil`).
    func value(of account: Account, on date: CalendarDate, in currency: CurrencyCode? = nil) -> AccountValue {
        let target = currency ?? baseCurrency
        func result(_ status: AccountValue.Status, _ problems: [ValuationProblem] = []) -> AccountValue {
            AccountValue(account: account.id, date: date, currency: target, status: status,
                         valuation: nil, components: [], problems: problems)
        }

        if date < account.opened { return result(.notOpenYet) }
        if let closed = account.closed, date > closed { return result(.closed) }
        guard let valuation = carried(account, on: date) else {
            return result(.noValuation, [.noValuation(account: account.id)])
        }
        return value(of: account, valuation: valuation, on: date, cashIsDerived: account.recordsTrades, in: target)
    }

    /// What `account` holds at the end of `date`: its latest valuation on
    /// or before the date, or for a trades account its ``tradeSnapshot(of:on:)``.
    func carried(_ account: Account, on date: CalendarDate) -> Valuation? {
        account.recordsTrades ? tradeSnapshot(of: account, on: date) : latestValuation(for: account.id, onOrBefore: date)
    }

    /// Values one valuation of `account` on `date`, whatever the account's
    /// status. For a trades account, the valuation's positions are those its
    /// trades leave on the valuation's date (see ``tradeSnapshot(for:in:)``),
    /// and its cash comes from the cash rule when it has none, or when
    /// `cashIsDerived` (a snapshot). Amounts are converted to `currency`
    /// (the base currency when `nil`).
    func value(of account: Account, valuation original: Valuation, on date: CalendarDate,
               cashIsDerived: Bool = false, in currency: CurrencyCode? = nil) -> AccountValue {
        let target = currency ?? baseCurrency
        var valuation = original
        var problems: [ValuationProblem] = []
        if account.recordsTrades {
            valuation = tradeSnapshot(for: original, in: account)
            // A trade whose cash effect needs a missing FX rate leaves derived cash incomplete.
            problems = tradeCashProblems(of: account, for: original, derived: cashIsDerived || original.cash == nil)
        }
        var components: [ValueComponent] = []

        func add(_ kind: ValueComponent.Kind, amount: Decimal?, currency: CurrencyCode?, quantity: Decimal? = nil,
                 price: PriceRecord? = nil) {
            var quote: FXQuote?
            var value: Decimal?
            if let amount, let currency {
                if amount == 0 || currency == target {
                    value = amount
                } else if let found = fx.quote(from: currency, to: target, on: date) {
                    quote = found
                    value = found.convert(amount)
                } else {
                    let problem = ValuationProblem.missingFX(account: account.id, from: currency, to: target)
                    if !problems.contains(problem) { problems.append(problem) }
                }
            }
            components.append(ValueComponent(kind: kind, quantity: quantity, price: price, amount: amount,
                                             currency: currency, fx: quote, value: value))
        }

        if let balance = valuation.balance {
            add(.balance, amount: balance, currency: account.currency)
        } else {
            if let cash = valuation.cash {
                add(.cash, amount: cash, currency: account.currency)
            }
            for position in valuation.positions {
                let kind = ValueComponent.Kind.position(position.instrument)
                if let price = prices.latest(for: position.instrument, onOrBefore: date) {
                    add(kind, amount: position.quantity * price.price, currency: price.currency,
                        quantity: position.quantity, price: price)
                } else if position.quantity == 0 {
                    add(kind, amount: 0, currency: account.currency, quantity: 0)
                } else {
                    problems.append(.missingPrice(account: account.id, instrument: position.instrument))
                    add(kind, amount: nil, currency: nil, quantity: position.quantity)
                }
            }
        }
        return AccountValue(account: account.id, date: date, currency: target, status: .valued,
                            valuation: valuation, components: components, problems: problems)
    }
}
