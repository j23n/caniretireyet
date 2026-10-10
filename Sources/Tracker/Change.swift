import Foundation
import Model

/// A change in value between two dates, split for the waterfall chart:
/// `start + market + newMoney + other == end`, exactly.
public struct ValueChange: Hashable, Sendable {
    public var start: Decimal
    /// Returns: price and FX movement, interest, reinvested dividends.
    public var market: Decimal
    /// Money added (+) or taken out (−): recorded flows, or without one,
    /// for holdings the changes in quantity and cash, and for a balance
    /// what a check-in would have filled in (or what the main plan pays in).
    public var newMoney: Decimal
    /// What can't be explained: an account's first value without a
    /// recorded flow (what it held when its records start), and the change
    /// of a balance without a flow, apart from FX movement, when a price or
    /// an exchange rate its new money needs is missing.
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

/// How one account changed between two dates, in the base currency (or in
/// the account's own, from ``Valuator/change(of:from:to:in:)``).
public struct AccountChange: Hashable, Sendable, Identifiable {
    public let account: AccountID
    public let change: ValueChange
    /// The flows recorded in the period, converted to the change's currency
    /// at each valuation's date; zero when there was no new valuation. `nil`
    /// when a valuation in the period has no flow (unknown).
    public let flow: Decimal?
    /// Missing prices and FX rates. Parts that couldn't be valued count as zero.
    public let problems: [ValuationProblem]
    /// Whether the new money of values without a flow is what the main plan
    /// pays into the account: a balance the check-in asks about, left empty.
    public let isFlowFromPlan: Bool
    /// Whether the new money of values without a flow is what a check-in
    /// would have filled in (``Valuator/defaultFlow(for:previous:paid:)``):
    /// a balance's whole change since the value before, e.g. an imported
    /// one's.
    public let isFlowAutomatic: Bool

    public init(account: AccountID, change: ValueChange, flow: Decimal?, problems: [ValuationProblem],
                isFlowFromPlan: Bool = false, isFlowAutomatic: Bool = false) {
        self.account = account
        self.change = change
        self.flow = flow
        self.problems = problems
        self.isFlowFromPlan = isFlowFromPlan
        self.isFlowAutomatic = isFlowAutomatic
    }

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

    /// Accounts with a valuation in the period that has no flow, whose new
    /// money couldn't be filled in: a balance's change counts as other.
    public var unknownFlowAccounts: [AccountID] {
        accounts.filter { !$0.isFlowKnown && !$0.isFlowFromPlan && !$0.isFlowAutomatic }.map(\.account)
    }

    /// Balances with a valuation in the period that has no flow, whose new
    /// money is what a check-in would have filled in: the whole change
    /// since the value before (an imported history's, typically).
    public var automaticFlowAccounts: [AccountID] {
        accounts.filter { !$0.isFlowKnown && $0.isFlowAutomatic }.map(\.account)
    }

    /// Balances the check-in asks about with a valuation in the period that
    /// has no flow: what the main plan pays into them counts as new money,
    /// and the rest as market.
    public var plannedFlowAccounts: [AccountID] {
        accounts.filter { !$0.isFlowKnown && $0.isFlowFromPlan }.map(\.account)
    }

    /// Everything missing, across accounts.
    public var problems: [ValuationProblem] {
        accounts.flatMap(\.problems)
    }

    /// Whether every value was known.
    public var isComplete: Bool {
        accounts.allSatisfy(\.problems.isEmpty)
    }

    /// Whether every price and exchange rate was known, an account without
    /// a value yet aside (``NetWorth/isPriced``).
    public var isPriced: Bool {
        problems.allSatisfy(\.isNotTrackedYet)
    }
}

extension Valuator {
    /// How the accounts in `scope` changed from `from` to `to`, split into
    /// market, new money and other (docs/schema/README.md, "How values are computed",
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
    /// - **Balance the check-in asks about, flow unknown** (pension fund,
    ///   TFR, property, other; ``FlowDefault/ask``): each value's flow where
    ///   one was entered, else what the main plan pays into the account since
    ///   the value before (``PlannedContributions``) is new money, and
    ///   market is the rest. The account's first value without a flow is
    ///   other: what it held when its records start.
    /// - **Other balances, flow unknown** (an imported history, typically):
    ///   each value's flow where one was entered, else what a check-in would
    ///   have filled in (``defaultFlow(for:previous:paid:)``), the whole
    ///   change since the value before, is new money, and market is the
    ///   rest, the FX effect. The account's first value without a flow is
    ///   other. Without a price or an exchange rate for that, market is only
    ///   the FX effect on the old balance, and the rest is other.
    /// - **Trades accounts:** values are snapshots (``snapshot(of:on:)``),
    ///   and new money is the account's ``TradeFlow``s in the period
    ///   (deposits, withdrawals, transfers and residuals), each converted at
    ///   its date; the stored `flow`s aren't used. Dividends, interest and
    ///   fees are market. Without a price for a transfer, the flow is unknown.
    /// - An account that closes in the period ends at zero: its value on the
    ///   closing day leaves as new money. One that opens starts at zero.
    public func change(from: CalendarDate, to: CalendarDate, in scope: NetWorthScope = .netWorth) -> ChangeReport {
        let changes = accounts.values
            .filter { scope.includes($0) && $0.isOpen(onAnyDayFrom: from, through: to) }
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

    /// 31 December of the year before `date`, where "this year" starts for
    /// the Overview's hero and its *This year*; `nil` when net worth has no
    /// value by then, so a library started this year has no change this year.
    public func endOfLastYear(before date: CalendarDate) -> CalendarDate? {
        guard let yearEnd = YearMonth(year: date.year - 1, month: 12)?.lastDay, yearEnd < date,
              let first = firstValuationDate(in: .netWorth), first <= yearEnd
        else { return nil }
        return yearEnd
    }

    /// How net worth changed from 31 December of last year to `date`
    /// (``endOfLastYear(before:)``), split into markets, new money and
    /// other, for the Overview's *This year*; `nil` without a value by 31
    /// December.
    public func changeThisYear(asOf date: CalendarDate) -> ChangeReport? {
        endOfLastYear(before: date).map { change(from: $0, to: date, in: .netWorth) }
    }

    /// How `account` changed, in `currency` (the base currency when `nil`).
    func change(of account: Account, from: CalendarDate, to: CalendarDate,
                in currency: CurrencyCode? = nil) -> AccountChange {
        let target = currency ?? baseCurrency
        var problems: [ValuationProblem] = []
        func valued(_ valuation: Valuation?, on date: CalendarDate) -> Decimal {
            guard let valuation else { return 0 }
            let value = value(of: account, valuation: valuation, on: date, in: target)
            for problem in value.problems { problems.appendIfNew(problem) }
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
        let flow = recordedFlows(of: account, after: from, through: endDate, in: target, problems: &problems)

        var parts = ValueChange(start: start, market: 0, newMoney: 0, other: 0, end: end)
        var isFlowFromPlan = false
        var isFlowAutomatic = false
        if let flow {
            parts.newMoney = flow
            parts.market = end - start - flow
        } else if endValuation?.isBalance ?? false, !account.recordsTrades,
                  let filled = filledFlows(of: account, after: from, through: endDate, in: target,
                                           problems: &problems) {
            if account.kind.defaultFlow == .ask { isFlowFromPlan = true } else { isFlowAutomatic = true }
            parts.newMoney = filled.newMoney
            parts.other = filled.firstValue
            parts.market = end - start - filled.newMoney - filled.firstValue
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
        return AccountChange(account: account.id, change: parts, flow: flow, problems: problems,
                             isFlowFromPlan: isFlowFromPlan, isFlowAutomatic: isFlowAutomatic)
    }

    /// The new money of a balance from its values dated after `from`
    /// through `through`: each one's flow where one was entered, else, for
    /// a balance the check-in asks about, what the main plan pays into the
    /// account since the value before (``contributions``), and for any
    /// other, what a check-in would have filled in
    /// (``defaultFlow(for:previous:paid:)``); converted to `currency` at
    /// the value's date. The account's first value, without a flow, is
    /// `firstValue` instead: what it held when its records start, not money
    /// paid in. `nil` without a price or an exchange rate.
    func filledFlows(of account: Account, after from: CalendarDate, through: CalendarDate,
                     in currency: CurrencyCode, problems: inout [ValuationProblem])
        -> (newMoney: Decimal, firstValue: Decimal)? {
        func convert(_ amount: Decimal, from source: CurrencyCode, on date: CalendarDate) -> Decimal? {
            converted(amount, from: source, to: currency, on: date, for: account.id, problems: &problems)
        }
        var newMoney: Decimal = 0
        var firstValue: Decimal = 0
        var previous: Valuation?
        for valuation in valuations(for: account.id) {
            defer { previous = valuation }
            guard valuation.date > from, valuation.date <= through else { continue }
            if let flow = valuation.flow {
                guard let amount = convert(flow, from: account.currency, on: valuation.date) else { return nil }
                newMoney += amount
            } else if let previous, account.kind.defaultFlow == .ask {
                let planned = contributions.amount(into: account.id, after: previous.date, through: valuation.date)
                guard let amount = convert(planned, from: baseCurrency, on: valuation.date) else { return nil }
                newMoney += amount
            } else if let previous {
                guard let automatic = defaultFlow(for: valuation, previous: previous),
                      let amount = convert(automatic, from: account.currency, on: valuation.date) else { return nil }
                newMoney += amount
            } else {
                let value = value(of: account, valuation: valuation, on: valuation.date, in: currency)
                for problem in value.problems { problems.appendIfNew(problem) }
                firstValue += value.knownValue
            }
        }
        return (newMoney, firstValue)
    }

    /// The flows of the account's valuations dated after `from` through
    /// `through`, each converted at its own date; zero if there are none,
    /// `nil` if one is unknown. For a trades account, its ``TradeFlow``s
    /// instead: deposits, withdrawals, transfers and residuals. Converted to
    /// `currency` (the base currency when `nil`).
    func recordedFlows(of account: Account, after from: CalendarDate, through: CalendarDate,
                       in currency: CurrencyCode? = nil, problems: inout [ValuationProblem]) -> Decimal? {
        let target = currency ?? baseCurrency
        if account.recordsTrades {
            return convertedTradeFlows(of: account, after: from, through: through, to: target, problems: &problems)?
                .reduce(0) { $0 + $1.amount }
        }
        var total: Decimal = 0
        var known = true
        for valuation in valuations(for: account.id) where valuation.date > from && valuation.date <= through {
            guard let flow = valuation.flow,
                  let amount = converted(flow, from: account.currency, to: target, on: valuation.date,
                                         for: account.id, problems: &problems)
            else {
                known = false
                continue
            }
            total += amount
        }
        return known ? total : nil
    }
}
