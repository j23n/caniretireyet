import Foundation
import Model
import Tracker

// An account's detail page, computed without SwiftUI so it can be checked
// on Linux: value and change, history with new-money ticks, positions and
// valuations (UI.md, "Account detail").

/// A new-money event on the account's history chart.
struct AccountFlowTick: Hashable, Sendable, Identifiable {
    var date: CalendarDate
    /// In the account's currency: added (+) or taken out (−).
    var amount: Decimal

    var id: CalendarDate { date }
}

/// One position of a holdings account, as the detail shows it.
struct AccountHoldingRow: Hashable, Sendable, Identifiable {
    var instrument: InstrumentID
    var name: String
    var unit: InstrumentUnit?
    var quantity: Decimal
    /// The latest price on or before the date, in the price's currency.
    var price: PriceRecord?
    /// The value in the account's currency; `nil` without a price or rate.
    var amount: Decimal?
    /// The value in the base currency; `nil` without a price or rate.
    var value: Decimal?
    /// The purchase cost in the account's currency, if recorded.
    var costBasis: Decimal?
    /// The position's share of the account's value (positions and cash),
    /// when known; set for trades accounts' holdings (``TradeHoldings``).
    var share: Double? = nil

    var id: InstrumentID { instrument }

    /// The average cost per unit (*costo medio*), in the account's currency.
    var averageCost: Decimal? {
        guard let costBasis, quantity > 0 else { return nil }
        return costBasis / quantity
    }

    /// `amount − costBasis`, in the account's currency.
    var gain: Decimal? {
        guard let amount, let costBasis else { return nil }
        return amount - costBasis
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

    var id: ValuationKey { valuation.key }
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
    /// The value in the base currency on ``date`` (what could be valued).
    var value: Decimal
    var isComplete: Bool
    /// For an account in another currency than the base one: its value in
    /// the base currency, or that the rate is missing. `nil` for an account
    /// in the base currency, or when a price is missing too.
    var baseValue: AccountBaseValue?
    /// The latest valuation on or before ``date``.
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
    var flows: [AccountFlowTick]
    /// The positions of the latest valuation, for holdings.
    var holdings: [AccountHoldingRow]
    /// Cash held alongside positions, in the account's currency.
    var cash: Decimal?
    /// Every valuation, newest first.
    var valuations: [AccountValuationRow]
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
    /// How many trades the account has (a trades account's list shows them).
    var tradeCount = 0

    /// Whether the account records trades (``Model/Account/recordsTrades``).
    var recordsTrades: Bool { account.recordsTrades }

    /// The currency the page shows amounts in: the account's own.
    var currency: CurrencyCode { account.currency }

    /// Whether the account's currency isn't the base currency.
    var isForeign: Bool { account.currency != baseCurrency }

    /// Whether the account holds positions (now, or by its kind's default).
    var showsPositions: Bool {
        !recordsTrades
            && (!holdings.isEmpty || (latest.map { !$0.isBalance } ?? (account.valuationMode == .holdings)))
    }

    /// Whether *Switch to Trade History…* is offered: an open account that
    /// records positions (brokerage, crypto, metals, or any holdings account).
    var canSwitchToTrades: Bool {
        !account.isClosed && account.valuationMode == .holdings
    }

    /// Whether *Switch to Snapshots…* is offered: an open trades account.
    var canSwitchToSnapshots: Bool {
        !account.isClosed && recordsTrades
    }

    /// The date *Add Past Value…* starts on: the last day of the month
    /// before the account's first value (or before ``date`` without one),
    /// so the history fills in a month at a time.
    var pastValueDate: CalendarDate {
        Self.pastValueDate(firstValue: valuations.last?.valuation.date, date: date)
    }

    /// The month end before `firstValue` (or before `date` without one).
    static func pastValueDate(firstValue: CalendarDate?, date: CalendarDate) -> CalendarDate {
        (firstValue ?? date).startOfMonth.adding(days: -1)
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
        value = current?.knownValue ?? 0
        isComplete = current?.isComplete ?? true
        if account.currency != valuator.baseCurrency, let current, current.status == .valued {
            if current.isComplete {
                baseValue = .known(current.knownValue)
            } else if current.problems.contains(.missingFX(account: account.id, from: account.currency,
                                                           to: valuator.baseCurrency)) {
                baseValue = .rateMissing
            }
        }
        // A trades account's latest state is its snapshot: dated its latest valuation or trade.
        latest = account.recordsTrades
            ? valuator.snapshot(of: account.id, on: date) : valuator.latestValuation(for: account.id, onOrBefore: date)
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
        if account.recordsTrades {
            // Deposits, withdrawals, transfers and residuals, on their own dates.
            var byDate: [CalendarDate: Decimal] = [:]
            for flow in valuator.tradeFlows(of: account.id, after: nil, through: date) {
                if let amount = flow.amount { byDate[flow.date, default: 0] += amount }
            }
            flows = byDate.filter { $0.value != 0 }.sorted { $0.key < $1.key }
                .map { AccountFlowTick(date: $0.key, amount: $0.value) }
        } else {
            flows = all.compactMap { valuation in
                guard let flow = valuation.flow, flow != 0 else { return nil }
                return AccountFlowTick(date: valuation.date, amount: flow)
            }
        }
        holdings = valuator.holdings(of: account.id, on: date).map { holding in
            let instrument = library.instruments[holding.instrument]
            return AccountHoldingRow(
                instrument: holding.instrument, name: instrument?.name ?? holding.instrument.rawValue,
                unit: instrument?.unit, quantity: holding.quantity, price: holding.price, amount: holding.amount,
                value: holding.value, costBasis: holding.costBasis)
        }
        if account.recordsTrades {
            cash = valuator.tradeCash(of: account.id, on: date)
            let trades = TradeHoldings(rows: holdings, cash: cash)
            tradeHoldings = trades
            holdings = trades.rows
            incomeYears = TradeIncomeYear.years(of: account.id, valuator: valuator)
            tradeCount = valuator.ledger(for: account.id)?.entries.count ?? 0
        } else {
            cash = latest.flatMap { $0.isBalance ? nil : $0.cash }
        }
        tradeIssues = TradeIssueNote.notes(for: account.id, library: library, valuator: valuator)
        valuations = all.reversed().map { valuation in
            AccountValuationRow(
                valuation: valuation,
                amount: valuator.amountInAccountCurrency(of: valuation, on: valuation.date),
                value: valuator.value(of: valuation, on: valuation.date)?.knownValue ?? 0)
        }
        stale = account.isClosed
            ? nil : AccountStaleness.stale(account.id, valuator: valuator, on: today, threshold: stalenessThreshold)
        emptySince = AccountStaleness.emptySince(account, valuator: valuator, on: today, threshold: stalenessThreshold)
    }
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
