import Foundation
import Model

/// Computes account values and net worth on any date, following
/// docs/schema/README.md, "How values are computed":
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
/// Each account's records are an ``AccountHistory``, which decides once
/// where its holdings come from. An account whose holdings come from its
/// trades (``Model/ValuationMode/trades``) is valued from a
/// ``snapshot(of:on:)``: the positions its trades leave (``TradeLedger``)
/// and its cash by the cash rule (``tradeCash(of:on:)``), as if that were
/// its latest valuation (docs/TRADES.md).
public struct Valuator: Sendable {
    public let baseCurrency: CurrencyCode
    public let accounts: [AccountID: Account]
    /// Instruments by ID, for asset mixes. A position in an instrument that
    /// isn't here counts as asset class `other`.
    public let instruments: [InstrumentID: Instrument]
    public let prices: PriceTable
    public let fx: FXTable
    /// Every account's records, and those of valuations of unknown
    /// accounts; an account that records trades has a ledger, with or
    /// without trades.
    private let histories: [AccountID: AccountHistory]
    /// Trades of accounts that don't record trades (or don't exist): left out.
    let ignoredTrades: [Trade]

    /// A valuator over a library snapshot. For duplicate valuation or trade
    /// keys the last one wins. Trades count only for accounts that record trades.
    public init(library: Library) {
        baseCurrency = library.settings.baseCurrency
        accounts = library.accounts
        instruments = library.instruments
        var byKey: [ValuationKey: Valuation] = [:]
        for valuation in library.months.values.flatMap(\.valuations) { byKey[valuation.key] = valuation }
        let valuationsByAccount = Dictionary(grouping: byKey.values, by: \.account).mapValues { $0.sortedByKey() }
        prices = PriceTable(library: library)
        let fx = FXTable(library: library)
        self.fx = fx
        var tradesByKey: [TradeKey: Trade] = [:]
        for trade in library.months.values.flatMap(\.trades) { tradesByKey[trade.key] = trade }
        let tradesByAccount = Dictionary(grouping: tradesByKey.values, by: \.account)
        var histories: [AccountID: AccountHistory] = [:]
        for id in Set(valuationsByAccount.keys).union(library.accounts.keys) {
            let ledger = library.accounts[id].flatMap { account in
                account.recordsTrades
                    ? TradeLedger(account: account, trades: tradesByAccount[id] ?? [],
                                  instruments: library.instruments, fx: fx)
                    : nil
            }
            histories[id] = AccountHistory(account: id, valuations: valuationsByAccount[id] ?? [], ledger: ledger)
        }
        self.histories = histories
        ignoredTrades = tradesByKey.values.filter { histories[$0.account]?.ledger == nil }.sortedByKey()
    }

    /// An account's records; empty for an account without any.
    func history(of account: AccountID) -> AccountHistory {
        histories[account] ?? AccountHistory(account: account, valuations: [], ledger: nil)
    }

    /// The ledgers of the accounts that record trades, by account.
    var ledgers: [AccountID: TradeLedger] {
        histories.compactMapValues(\.ledger)
    }

    /// An account's valuations, sorted by date.
    public func valuations(for account: AccountID) -> [Valuation] {
        history(of: account).valuations
    }

    /// The account's latest valuation dated on or before `date`.
    public func latestValuation(for account: AccountID, onOrBefore date: CalendarDate) -> Valuation? {
        history(of: account).latestValuation(onOrBefore: date)
    }

    /// The account's latest valuation dated strictly before `date`: the one a
    /// valuation on `date` follows.
    public func previousValuation(for account: AccountID, before date: CalendarDate) -> Valuation? {
        history(of: account).latestValuation(onOrBefore: date.adding(days: -1))
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
        return value(of: account, valuation: valuation, on: date, in: target)
    }

    /// What `account` holds at the end of `date`, before it's held
    /// (``AccountHistory/record(on:)``): its latest valuation on or before
    /// the date, or for a trades account the date of its latest record.
    func carried(_ account: Account, on date: CalendarDate) -> Valuation? {
        history(of: account.id).record(on: date)
    }

    /// Values one valuation of `account` on `date`, whatever the account's
    /// status, as its account holds it (``AccountHistory/held(_:)``): for a
    /// trades account, the positions its trades leave on the valuation's
    /// date, and its cash by the cash rule when it has none. A balance is
    /// estimated on `date` from the account's depreciation, as
    /// `Account.estimated(_:from:on:)` says. Amounts are converted to
    /// `currency` (the base currency when `nil`).
    func value(of account: Account, valuation original: Valuation, on date: CalendarDate,
               in currency: CurrencyCode? = nil) -> AccountValue {
        let target = currency ?? baseCurrency
        let valuation = history(of: account.id).held(original)
        // A trade whose cash effect needs a missing FX rate leaves derived cash incomplete.
        var problems = original.cash == nil ? tradeCashProblems(of: account, on: original.date) : []
        var components: [ValueComponent] = []

        func add(_ kind: ValueComponent.Kind, amount: Decimal?, currency: CurrencyCode?, quantity: Decimal? = nil,
                 price: PriceRecord? = nil) {
            var value: Decimal?
            if let amount, let currency {
                value = converted(amount, from: currency, to: target, on: date, for: account.id, problems: &problems)
            }
            components.append(ValueComponent(kind: kind, quantity: quantity, price: price, currency: currency,
                                             value: value))
        }

        if let balance = valuation.balance {
            add(.balance, amount: account.estimated(balance, from: valuation.date, on: date),
                currency: account.currency)
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

    /// `amount` in `source` converted into `target` at the latest FX rate on
    /// or before `date`, or as it is when it's zero or already in `target`.
    /// `nil` without a rate; the missing rate is then added to `problems`
    /// (once) for `account`.
    func converted(_ amount: Decimal, from source: CurrencyCode, to target: CurrencyCode, on date: CalendarDate,
                   for account: AccountID, problems: inout [ValuationProblem]) -> Decimal? {
        if amount == 0 || source == target { return amount }
        if let value = fx.convert(amount, from: source, to: target, on: date) { return value }
        problems.appendIfNew(.missingFX(account: account, from: source, to: target))
        return nil
    }
}
