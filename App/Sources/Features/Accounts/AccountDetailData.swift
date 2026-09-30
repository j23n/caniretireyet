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

    var id: InstrumentID { instrument }

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

/// Everything the account detail shows.
struct AccountDetailData: Hashable, Sendable {
    var account: Account
    /// The date the page reports on: today, or the closing date.
    var date: CalendarDate
    /// The value in the base currency on ``date`` (what could be valued).
    var value: Decimal
    var isComplete: Bool
    /// The value in the account's own currency, when it isn't the base currency.
    var amountInAccountCurrency: Decimal?
    /// The latest valuation on or before ``date``.
    var latest: Valuation?
    /// The change from the valuation before the latest one to the latest one.
    var change: ValueChange?
    /// The date of the valuation before the latest one.
    var changeFrom: CalendarDate?
    /// The value over time (month ends), from the first valuation.
    var history: [ChartPoint]
    /// New-money events, oldest first.
    var flows: [AccountFlowTick]
    /// The positions of the latest valuation, for holdings.
    var holdings: [AccountHoldingRow]
    /// Cash held alongside positions, in the account's currency.
    var cash: Decimal?
    /// Every valuation, newest first.
    var valuations: [AccountValuationRow]
    /// Set when the latest value is too old.
    var stale: StaleAccount?
    /// The chart's values that use a price more than 31 days older than
    /// their date, for a note under the chart; `nil` when there are none.
    var oldPrices: OldPriceSummary?

    /// Whether the account holds positions (now, or by its kind's default).
    var showsPositions: Bool {
        !holdings.isEmpty || (latest.map { !$0.isBalance } ?? (account.valuationMode == .holdings))
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
        let date = account.closed.map { min($0, today) } ?? today
        self.date = date
        let current = valuator.value(of: account.id, on: date)
        value = current?.knownValue ?? 0
        isComplete = current?.isComplete ?? true
        latest = valuator.latestValuation(for: account.id, onOrBefore: date)
        if account.currency != valuator.baseCurrency, let latest {
            amountInAccountCurrency = valuator.amountInAccountCurrency(of: latest, on: date)
        }
        if let latest, let previous = valuator.previousValuation(for: account.id, before: latest.date) {
            change = valuator.change(of: account.id, from: previous.date, to: latest.date)?.change
            changeFrom = previous.date
        }
        history = valuator.series(of: account.id, through: date).chartPoints
        let all = valuator.valuations(for: account.id)
        if let first = all.first?.date {
            oldPrices = OldPriceSummary(valuator.oldPrices(of: account.id,
                                                           on: DateGrid.monthEnds(from: first, through: date)))
        }
        flows = all.compactMap { valuation in
            guard let flow = valuation.flow, flow != 0 else { return nil }
            return AccountFlowTick(date: valuation.date, amount: flow)
        }
        holdings = valuator.holdings(of: account.id, on: date).map { holding in
            let instrument = library.instruments[holding.instrument]
            return AccountHoldingRow(
                instrument: holding.instrument, name: instrument?.name ?? holding.instrument.rawValue,
                unit: instrument?.unit, quantity: holding.quantity, price: holding.price, amount: holding.amount,
                value: holding.value, costBasis: holding.costBasis)
        }
        cash = latest.flatMap { $0.isBalance ? nil : $0.cash }
        valuations = all.reversed().map { valuation in
            AccountValuationRow(
                valuation: valuation,
                amount: valuator.amountInAccountCurrency(of: valuation, on: valuation.date),
                value: valuator.value(of: valuation, on: valuation.date)?.knownValue ?? 0)
        }
        stale = account.isClosed ? nil : valuator.staleness(of: account.id, on: today, threshold: stalenessThreshold)
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
