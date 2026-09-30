import Foundation
import Model

/// A change in value between two dates, split for the waterfall chart:
/// `start + market + newMoney + other == end`, exactly.
public struct ValueChange: Hashable, Sendable {
    public var start: Decimal
    /// Returns: price and FX movement, interest, reinvested dividends.
    public var market: Decimal
    /// Money added (+) or taken out (−): recorded flows, or for holdings
    /// without one, the changes in quantity and cash.
    public var newMoney: Decimal
    /// What can't be explained: the change of a balance account without a
    /// recorded flow, apart from FX movement.
    public var other: Decimal
    public var end: Decimal

    public init(start: Decimal, market: Decimal, newMoney: Decimal, other: Decimal, end: Decimal) {
        self.start = start
        self.market = market
        self.newMoney = newMoney
        self.other = other
        self.end = end
    }

    /// No value and no change.
    public static let zero = ValueChange(start: 0, market: 0, newMoney: 0, other: 0, end: 0)

    /// `end − start`.
    public var change: Decimal { end - start }

    /// The change as a fraction of the start value, e.g. 0.142 for +14.2%;
    /// `nil` when the start is zero.
    public var relativeChange: Decimal? {
        start == 0 ? nil : change / abs(start)
    }

    /// Two changes added part by part, e.g. two accounts.
    public static func + (lhs: ValueChange, rhs: ValueChange) -> ValueChange {
        ValueChange(start: lhs.start + rhs.start, market: lhs.market + rhs.market,
                    newMoney: lhs.newMoney + rhs.newMoney, other: lhs.other + rhs.other, end: lhs.end + rhs.end)
    }
}

/// How one account changed between two dates, in the base currency.
public struct AccountChange: Hashable, Sendable, Identifiable {
    public let account: AccountID
    public let change: ValueChange
    /// The flows recorded in the period, converted to the base currency at
    /// each valuation's date; zero when there was no new valuation. `nil`
    /// when a valuation in the period has no flow (unknown).
    public let flow: Decimal?
    /// Missing prices and FX rates. Parts that couldn't be valued count as zero.
    public let problems: [ValuationProblem]

    public var id: AccountID { account }

    /// Whether the money in and out over the period is known.
    public var isFlowKnown: Bool { flow != nil }
}

/// The change of every account in a scope between two dates, and the total:
/// the data for the "since last check-in" waterfall.
public struct ChangeReport: Hashable, Sendable {
    public let from: CalendarDate
    public let to: CalendarDate
    /// The base currency.
    public let currency: CurrencyCode
    /// The sum over accounts.
    public let total: ValueChange
    /// Every account that counted on some day of the period, sorted by ID.
    public let accounts: [AccountChange]

    /// Accounts with a valuation in the period that has no flow.
    public var unknownFlowAccounts: [AccountID] {
        accounts.filter { !$0.isFlowKnown }.map(\.account)
    }

    /// Everything missing, across accounts.
    public var problems: [ValuationProblem] {
        accounts.flatMap(\.problems)
    }

    /// Whether every value was known.
    public var isComplete: Bool {
        accounts.allSatisfy(\.problems.isEmpty)
    }

    /// The change of one account, if it's in the report.
    public func change(of account: AccountID) -> AccountChange? {
        accounts.first { $0.account == account }
    }
}

extension Valuator {
    /// How the accounts in `scope` changed from `from` to `to`, split into
    /// market, new money and other (FILE_FORMAT.md, "How values are computed",
    /// and PROGRESS.md):
    ///
    /// - **Flow known** (every valuation in the period has a `flow`, or there
    ///   was none): new money is the flows, and market is the rest. For
    ///   holdings with the default flow, that's the old quantities' price and
    ///   FX change; a lower flow (reinvested dividends) or a purchase below
    ///   the check-in price counts as market too.
    /// - **Holdings, flow unknown:** market is the old quantities (and cash)
    ///   at the new prices and rates, minus the start value; new money is the
    ///   rest, i.e. the changes in quantity and cash.
    /// - **Balance, flow unknown:** market is only the FX effect on the old
    ///   balance, and the rest is other.
    /// - **Trades accounts:** values are snapshots (``snapshot(of:on:)``),
    ///   and new money is the account's ``TradeFlow``s in the period
    ///   (deposits, withdrawals, transfers and residuals), each converted at
    ///   its date; the stored `flow`s aren't used. Dividends, interest and
    ///   fees are market. Without a price for a transfer, the flow is unknown.
    /// - An account that closes in the period ends at zero: its value on the
    ///   closing day leaves as new money. One that opens starts at zero.
    public func change(from: CalendarDate, to: CalendarDate, in scope: NetWorthScope = .netWorth) -> ChangeReport {
        let changes = accounts.values
            .filter { scope.includes($0) && $0.opened <= to && ($0.closed.map { $0 >= from } ?? true) }
            .sorted { $0.id < $1.id }
            .map { change(of: $0, from: from, to: to) }
        let total = changes.reduce(ValueChange.zero) { $0 + $1.change }
        return ChangeReport(from: from, to: to, currency: baseCurrency, total: total, accounts: changes)
    }

    /// The change between the latest check-in on or before `date` and the
    /// one before it; `nil` with fewer than two check-ins. A check-in is a
    /// date with a valuation of any account.
    public func changeSinceLastCheckIn(asOf date: CalendarDate, in scope: NetWorthScope = .netWorth) -> ChangeReport? {
        guard let latest = latestCheckIn(onOrBefore: date), let previous = previousCheckIn(before: latest) else {
            return nil
        }
        return change(from: previous, to: latest, in: scope)
    }

    /// How one account changed from `from` to `to`; `nil` if it's unknown.
    public func change(of account: AccountID, from: CalendarDate, to: CalendarDate) -> AccountChange? {
        accounts[account].map { change(of: $0, from: from, to: to) }
    }

    func change(of account: Account, from: CalendarDate, to: CalendarDate) -> AccountChange {
        var problems: [ValuationProblem] = []
        func valued(_ valuation: Valuation?, on date: CalendarDate) -> Decimal {
            guard let valuation else { return 0 }
            let value = value(of: account, valuation: valuation, on: date)
            for problem in value.problems where !problems.contains(problem) { problems.append(problem) }
            return value.knownValue
        }

        let startValuation = account.isOpen(on: from) ? carried(account, on: from) : nil
        let closing = account.closed.flatMap { $0 < to ? $0 : nil }
        let endDate = closing ?? to
        let endValuation = account.opened <= endDate ? carried(account, on: endDate) : nil
        if endValuation == nil && account.isOpen(on: endDate) { problems.append(.noValuation(account: account.id)) }

        let start = valued(startValuation, on: from)
        let end = valued(endValuation, on: endDate)
        let heldAtEnd = valued(startValuation, on: endDate)
        let heldMarket = heldAtEnd - start
        let flow = recordedFlows(of: account, after: from, through: endDate, problems: &problems)

        var parts = ValueChange(start: start, market: 0, newMoney: 0, other: 0, end: end)
        if let flow {
            parts.newMoney = flow
            parts.market = end - start - flow
        } else if endValuation?.isBalance ?? false {
            parts.market = heldMarket
            parts.other = end - start - heldMarket
        } else {
            parts.market = heldMarket
            parts.newMoney = end - heldAtEnd
        }
        if closing != nil {
            parts.newMoney -= end
            parts.end = 0
        }
        return AccountChange(account: account.id, change: parts, flow: flow, problems: problems)
    }

    /// The flows of the account's valuations dated after `from` through
    /// `through`, each converted at its own date; zero if there are none,
    /// `nil` if one is unknown. For a trades account, its ``TradeFlow``s
    /// instead: deposits, withdrawals, transfers and residuals.
    func recordedFlows(of account: Account, after from: CalendarDate, through: CalendarDate,
                       problems: inout [ValuationProblem]) -> Decimal? {
        if account.recordsTrades {
            return tradeFlowsInBaseCurrency(of: account, after: from, through: through, problems: &problems)?
                .reduce(0) { $0 + $1.amount }
        }
        var total: Decimal = 0
        var known = true
        for valuation in valuations(for: account.id) where valuation.date > from && valuation.date <= through {
            guard let flow = valuation.flow else {
                known = false
                continue
            }
            if flow == 0 || account.currency == baseCurrency {
                total += flow
            } else if let converted = fx.convert(flow, from: account.currency, to: baseCurrency, on: valuation.date) {
                total += converted
            } else {
                let problem = ValuationProblem.missingFX(account: account.id, from: account.currency, to: baseCurrency)
                if !problems.contains(problem) { problems.append(problem) }
                known = false
            }
        }
        return known ? total : nil
    }
}
