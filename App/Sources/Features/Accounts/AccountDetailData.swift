import Foundation
import Model
import Tracker

// An account's detail page, computed without SwiftUI so it can be checked
// on Linux: value and change, history with new-money ticks, a trades
// account's holdings and statements, and other accounts' values (UI.md,
// "Account detail").

/// A new-money event on the account's history chart.
struct AccountSavedTick: Hashable, Sendable, Identifiable {
    var date: CalendarDate
    /// In the account's currency: added (+) or taken out (−).
    var amount: Decimal

    var id: CalendarDate { date }
}

/// One position of a trades account, as the detail shows it: Tracker's
/// ``Tracker/Holding``, with the instrument's name and unit, and its share.
struct AccountHoldingRow: Hashable, Sendable, Identifiable {
    var holding: Holding
    var name: String
    var unit: InstrumentUnit?
    /// The position's share of the account's value (positions and cash),
    /// when known; set for trades accounts' holdings (``TradeHoldings``).
    var share: Double? = nil

    var id: InstrumentID { holding.instrument }
    var instrument: InstrumentID { holding.instrument }
    var quantity: Decimal { holding.quantity }
    /// The latest price on or before the date, in the price's currency.
    var price: PriceRecord? { holding.price }
    /// The value in the account's currency; `nil` without a price or rate.
    var amount: Decimal? { holding.amount }
    /// The purchase cost in the account's currency, if recorded.
    var costBasis: Decimal? { holding.costBasis }
    /// `amount − costBasis`, in the account's currency.
    var gain: Decimal? { holding.unrealizedGain }

    /// The average cost per unit (*costo medio*), in the account's currency.
    var averageCost: Decimal? {
        guard let costBasis, quantity > 0 else { return nil }
        return costBasis / quantity
    }

    /// The gain as a fraction of the cost.
    var gainFraction: Double? {
        guard let gain, let costBasis, costBasis != 0 else { return nil }
        return (gain / abs(costBasis)).doubleValue
    }
}

/// The value in the base currency, under the value of an account in
/// another currency.
enum AccountBaseValue: Hashable, Sendable {
    /// Converted at the date's rate.
    case known(Decimal)
    /// No exchange rate to the base currency on or before the date.
    case rateMissing
}

/// One valuation in the account's list.
struct AccountValuationRow: Hashable, Sendable, Identifiable {
    var valuation: Valuation
    /// The value on its own date, in the account's currency; `nil` when a
    /// price or rate is missing.
    var amount: Decimal?
    /// The value on its own date, in the base currency (what could be valued).
    var value: Decimal
    /// What was saved since the value before, in the account's currency
    /// (Tracker's `Valuator.saved(_:previous:)`): recorded, or worked out
    /// from the balances; `nil` when it's unknown, as for the first value.
    var saved: Decimal? = nil
    /// For a cash or savings account's value that records money in and
    /// out: the money moved between your own accounts, in the account's
    /// currency (Tracker's `Valuator.moved(_:previous:)`); `nil` otherwise.
    var moved: Decimal? = nil

    var id: ValuationKey { valuation.key }

    /// Whether the value records money in and out (both of them).
    var recordsMoneyInOut: Bool { valuation.moneyIn != nil && valuation.moneyOut != nil }
}

/// A value of a trades account that records what a statement showed, as a
/// check on the trades (docs/TRADES.md, "Reconciliation"): a cash other
/// than the trades give, or the positions it listed.
struct AccountStatementRow: Hashable, Sendable, Identifiable {
    var valuation: Valuation
    /// The statement's cash minus the cash the trades give on its date, in
    /// the account's currency: money added (+) or taken out (−) that no
    /// trade records, which counts as saved. `nil` when the value
    /// records no cash, or the same cash as the trades.
    var cashDifference: Decimal?
    /// How many instruments' quantities differ from what the trades give
    /// (``Tracker/Valuator/reconcile(_:)``).
    var mismatchCount: Int

    var id: ValuationKey { valuation.key }

    /// The cash the statement shows, in the account's currency, when it
    /// differs from the trades.
    var cash: Decimal? { cashDifference == nil ? nil : valuation.cash }

    /// "2 positions listed, as the trades give", "2 positions listed, 1
    /// differs from the trades"; `nil` when the statement lists none.
    var positionsText: String? {
        let count = valuation.positions.count
        guard count > 0 else { return nil }
        let listed = Wording.count(count, "position") + " listed"
        return mismatchCount == 0
            ? listed + ", as the trades give"
            : listed + ", " + "\(mismatchCount) differ\(mismatchCount == 1 ? "s" : "") from the trades"
    }
}

/// Everything the account detail shows. Amounts are in the account's own
/// currency (``currency``), which needs no exchange rate: a dollar account
/// in a euro library shows dollars, with its value in euros under it
/// (``baseValue``) when the rate is known (UI.md, "Account detail").
struct AccountDetailData: Hashable, Sendable {
    var account: Account
    /// The library's base currency.
    var baseCurrency: CurrencyCode
    /// The date the page reports on: today, or the closing date.
    var date: CalendarDate
    /// The value in the account's currency on ``date`` (what could be valued).
    var amount: Decimal
    /// Whether ``amount`` is fully known: no price missing, nor a rate for a
    /// position priced in another currency.
    var amountIsComplete: Bool
    /// For an account in another currency than the base one: its value in
    /// the base currency, or that the rate is missing. `nil` for an account
    /// in the base currency, or when a price is missing too.
    var baseValue: AccountBaseValue?
    /// The latest valuation on or before ``date``; for a trades account, its
    /// snapshot (``Tracker/Valuator/snapshot(of:on:)``).
    var latest: Valuation?
    /// The change from the valuation before the latest one to the latest
    /// one, in the account's currency.
    var change: ValueChange?
    /// The date of the valuation before the latest one.
    var changeFrom: CalendarDate?
    /// The value over time (month ends) in the account's currency, from the
    /// first valuation. A point that couldn't be valued is incomplete: a
    /// gap in the chart, never a zero.
    var history: [ChartPoint]
    /// What the chart's values are missing (prices, and rates for positions
    /// priced in another currency); `nil` when they're complete.
    var missing: MissingValues?
    /// For an account in another currency: the dates its own currency has
    /// no rate to the base currency, which leave it out of net worth then;
    /// `nil` when there are none.
    var missingBaseRates: MissingValues?
    /// New-money events, oldest first.
    var savedTicks: [AccountSavedTick]
    /// For an account that records trades: the positions its trades hold.
    var holdings: [AccountHoldingRow] = []
    /// For an account that records trades: its cash, in the account's currency.
    var cash: Decimal?
    /// The values the page lists, newest first: every valuation of an
    /// account that doesn't record trades. A trades account lists its
    /// trades instead, and its ``statements``.
    var valuations: [AccountValuationRow] = []
    /// For an account that records trades: its values that record a
    /// statement, newest first (``AccountStatementRow``). Its other values
    /// only follow the trades, so they aren't listed.
    var statements: [AccountStatementRow] = []
    /// Set when the latest value is too old, unless the account is empty
    /// (``AccountStaleness``).
    var stale: StaleAccount?
    /// The day an open account has held nothing since, when that's longer
    /// ago than the staleness threshold: the detail suggests closing it on
    /// that day ("This account has been empty since 1 Jan 2022. Close it?").
    var emptySince: CalendarDate?
    /// The chart's values that use a price more than 31 days older than
    /// their date, for a note under the chart; `nil` when there are none.
    var oldPrices: OldPriceSummary?
    /// For an account that records trades: its holdings with average cost
    /// and share, and its cash and total (docs/TRADES.md).
    var tradeHoldings: TradeHoldings?
    /// For an account that records trades: its income and gains by year, newest first.
    var incomeYears: [TradeIncomeYear] = []
    /// What's wrong with the account's trades, in words: for a trades
    /// account, and for another one with trades that are left out.
    var tradeIssues: [TradeIssueNote] = []

    /// Whether the account records trades (``Model/Account/recordsTrades``).
    var recordsTrades: Bool { account.recordsTrades }

    /// The currency the page shows amounts in: the account's own.
    var currency: CurrencyCode { account.currency }

    /// Whether the values show money in, money out and moved: a cash or
    /// savings account's (``Model/AccountKind/recordsMoneyInOut``).
    var valuationsShowMoneyInOut: Bool { account.kind.recordsMoneyInOut }

    /// Whether the values show the interest: a savings account's
    /// (``Model/AccountKind/recordsInterest``).
    var valuationsShowInterest: Bool { account.kind.recordsInterest }

    /// What *moved* means, under a cash or savings account's values; `nil`
    /// for other accounts, and without values.
    var movedNote: String? {
        guard valuationsShowMoneyInOut, !valuations.isEmpty else { return nil }
        return "Moved is the part of the change that money in and out"
            + (valuationsShowInterest ? " and interest" : "") + " don't explain: money moved between your own "
            + "accounts."
    }

    /// The page's sections between the chart and the details, in order:
    /// the same on iPhone and the Mac.
    var sections: [AccountDetailSection] {
        var sections: [AccountDetailSection] = []
        if !tradeIssues.isEmpty { sections.append(.tradeIssues) }
        if tradeHoldings != nil { sections.append(.holdings) }
        if recordsTrades {
            sections.append(.trades)
            if !incomeYears.isEmpty { sections.append(.income) }
            if !statements.isEmpty { sections.append(.statements) }
        } else {
            sections.append(.values)
        }
        return sections
    }

    init(account: Account, library: Library, valuator: Valuator, today: CalendarDate, stalenessThreshold: Int) {
        self.account = account
        baseCurrency = valuator.baseCurrency
        let date = account.closed.map { min($0, today) } ?? today
        self.date = date
        let own = valuator.value(of: account.id, on: date, in: .account)
        amount = own?.knownValue ?? 0
        amountIsComplete = own?.isComplete ?? true
        let current = valuator.value(of: account.id, on: date)
        if account.currency != valuator.baseCurrency, let current, current.status == .valued {
            if current.isComplete {
                baseValue = .known(current.knownValue)
            } else if current.problems.contains(.missingFX(account: account.id, from: account.currency,
                                                           to: valuator.baseCurrency)) {
                baseValue = .rateMissing
            }
        }
        // A trades account's latest state is its snapshot: dated its latest valuation or trade.
        latest = valuator.snapshot(of: account.id, on: date)
        if let latest, let previous = valuator.previousValuation(for: account.id, before: latest.date) {
            change = valuator.change(of: account.id, from: previous.date, to: latest.date, in: .account)?.change
            changeFrom = previous.date
        }
        history = valuator.series(of: account.id, in: .account, through: date).chartPoints
        let all = valuator.valuations(for: account.id)
        if let first = valuator.firstRecordDate(of: account.id), first <= date {
            let dates = DateGrid.monthEnds(from: first, through: date)
            oldPrices = OldPriceSummary(valuator.oldPrices(of: account.id, on: dates))
            missing = valuator.missingValues(of: account.id, on: dates, in: .account)
            if account.currency != valuator.baseCurrency {
                missingBaseRates = valuator.missingValues(of: account.id, on: dates, in: .base)?.filter { gap in
                    if case .rate(let from, _) = gap.item { from == account.currency } else { false }
                }
            }
        }
        savedTicks = valuator.savedByDate(of: account.id, through: date).map {
            AccountSavedTick(date: $0.date, amount: $0.amount)
        }
        if account.recordsTrades {
            let rows = valuator.holdings(of: account.id, on: date).map { holding in
                let instrument = library.instruments[holding.instrument]
                return AccountHoldingRow(holding: holding, name: instrument?.name ?? holding.instrument.rawValue,
                                         unit: instrument?.unit)
            }
            cash = valuator.tradeCash(of: account.id, on: date)
            let trades = TradeHoldings(rows: rows, cash: cash)
            tradeHoldings = trades
            holdings = trades.rows
            incomeYears = TradeIncomeYear.years(of: account.id, valuator: valuator)
            statements = Self.statements(of: account.id, valuations: all, valuator: valuator)
        } else {
            let recordsMoneyInOut = account.kind.recordsMoneyInOut
            valuations = all.indices.reversed().map { index in
                let valuation = all[index]
                let previous = index > 0 ? all[index - 1] : nil
                return AccountValuationRow(
                    valuation: valuation,
                    amount: valuator.amountInAccountCurrency(of: valuation, on: valuation.date),
                    value: valuator.value(of: valuation, on: valuation.date)?.knownValue ?? 0,
                    saved: valuator.saved(valuation, previous: previous),
                    moved: recordsMoneyInOut ? valuator.moved(valuation, previous: previous) : nil)
            }
        }
        tradeIssues = TradeIssueNote.notes(for: account.id, library: library, valuator: valuator)
        stale = account.isClosed
            ? nil : AccountStaleness.stale(account.id, valuator: valuator, on: today, threshold: stalenessThreshold)
        emptySince = AccountStaleness.emptySince(account, valuator: valuator, on: today, threshold: stalenessThreshold)
    }
}

extension AccountDetailData {
    /// The values of trades account `account` that record a statement,
    /// newest first: those whose cash differs from what the trades give on
    /// their date, or that list positions. `valuations` are the account's,
    /// oldest first.
    static func statements(of account: AccountID, valuations: [Valuation], valuator: Valuator)
        -> [AccountStatementRow] {
        guard let last = valuations.last?.date else { return [] }
        // A residual is a value's cash minus the trades' (docs/TRADES.md, "Flows").
        var differences: [CalendarDate: Decimal] = [:]
        for flow in valuator.tradeFlows(of: account, after: nil, through: last) where flow.trade == nil {
            if let amount = flow.amount { differences[flow.date] = amount }
        }
        return valuations.reversed().compactMap { valuation in
            let difference = differences[valuation.date]
            guard difference != nil || !valuation.positions.isEmpty else { return nil }
            return AccountStatementRow(valuation: valuation, cashDifference: difference,
                                       mismatchCount: valuator.reconcile(valuation).count)
        }
    }
}

/// A section of an account's page (``AccountDetailData/sections``).
enum AccountDetailSection: Hashable {
    /// What's wrong with its trades.
    case tradeIssues
    /// A trades account's holdings (``AccountDetailData/tradeHoldings``).
    case holdings
    /// A trades account's trades, by month.
    case trades
    /// A trades account's income and gains by year.
    case income
    /// A trades account's values that record a statement.
    case statements
    /// Another account's values.
    case values
}

/// The accounts money could have gone to when `account` closes on `date`:
/// every other account not closed before that day (including ones opened
/// later), in display order.
enum AccountSuccessors {
    static func candidates(for account: AccountID, closingOn date: CalendarDate, in library: Library) -> [Account] {
        library.accounts.values
            .filter { $0.id != account && ($0.closed.map { $0 >= date } ?? true) }
            .sortedForDisplay()
    }
}
