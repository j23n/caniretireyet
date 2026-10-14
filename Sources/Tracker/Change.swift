import Foundation
import Model

/// A change in value between two dates, split for the waterfall chart:
/// `start + market + newMoney + other == end`, exactly.
public struct ValueChange: Hashable, Sendable {
    public var start: Decimal
    /// Returns: price and FX movement, interest, reinvested dividends.
    public var market: Decimal
    /// Money added (+) or taken out (−): the values' flows
    /// (``Valuator/flow(of:previous:)``).
    public var newMoney: Decimal
    /// What can't be explained: an account's first value without a
    /// recorded flow (what it held when its records start), and the change
    /// of a balance without a flow, apart from FX movement: one that asks
    /// for a flow and has none, or one whose new money needs a missing
    /// price or exchange rate.
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
    /// The flows of the period's valuations (``Valuator/flow(of:previous:)``),
    /// converted to the change's currency at each valuation's date; zero
    /// when there was no new valuation. `nil` when one has no flow: a
    /// balance that asks for one without it, the account's first value, or
    /// a price or rate missing.
    public let flow: Decimal?
    /// Missing prices and FX rates. Parts that couldn't be valued count as zero.
    public let problems: [ValuationProblem]

    public init(account: AccountID, change: ValueChange, flow: Decimal?, problems: [ValuationProblem]) {
        self.account = account
        self.change = change
        self.flow = flow
        self.problems = problems
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

    /// Accounts whose new money couldn't be worked out, because a price or
    /// an exchange rate it needs is missing: their change counts as other.
    public var unknownFlowAccounts: [AccountID] {
        accounts.filter { !$0.isFlowKnown && !$0.problems.isEmpty }.map(\.account)
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
    /// - **Flow known** (every valuation in the period has a flow,
    ///   ``flow(of:previous:)``, or there was none): new money is the flows,
    ///   and market is the rest. A balance's flow is worked out from its
    ///   balances (the whole change, less the interest for savings), so its
    ///   market is the FX effect; one the check-in asks about records it.
    /// - **Balance, flow unknown:** when only the account's first value has
    ///   none, the other values' flows are new money, the first value is
    ///   other (what it held when its records start), and market is the
    ///   rest. Otherwise (a balance that asks for a flow without one,
    ///   ``Model/Account/asksForFlow``, or a price or an exchange rate
    ///   missing), market is only the FX effect on the old balance, and the
    ///   rest is other.
    /// - **Trades accounts:** values are snapshots (``snapshot(of:on:)``),
    ///   and new money is the account's ``TradeFlow``s in the period
    ///   (deposits, withdrawals, transfers and residuals), each converted at
    ///   its date. Dividends, interest and fees are market. Without a price
    ///   for a transfer, the flow is unknown: market is the old holdings at
    ///   the new prices and rates, and new money the rest.
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
        guard let yearEnd = YearMonth(year: date.year - 1, month: 12)?.lastDay,
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
        if let flow {
            parts.newMoney = flow
            parts.market = end - start - flow
        } else if endValuation?.isBalance ?? false,
                  let filled = filledFlows(of: account, after: from, through: endDate, in: target,
                                           problems: &problems) {
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
        if account.changeIsNewMoney {
            parts.newMoney += parts.market
            parts.market = 0
        }
        if closing != nil {
            parts.newMoney -= end
            parts.end = 0
        }
        return AccountChange(account: account.id, change: parts, flow: flow, problems: problems)
    }

    /// The new money of a balance from its values dated after `from`
    /// through `through`: each one's flow (``flow(of:previous:)``),
    /// converted to `currency` at the value's date. The account's first
    /// value is `firstValue` instead: what it held when its records start,
    /// not money paid in. `nil` when another value has no flow.
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
            if let flow = self.flow(of: valuation, previous: previous) {
                guard let amount = convert(flow, from: account.currency, on: valuation.date) else { return nil }
                newMoney += amount
            } else if previous != nil {
                return nil
            } else {
                let value = value(of: account, valuation: valuation, on: valuation.date, in: currency)
                for problem in value.problems { problems.appendIfNew(problem) }
                firstValue += value.knownValue
            }
        }
        return (newMoney, firstValue)
    }

    /// The flows of the account's valuations dated after `from` through
    /// `through` (``flow(of:previous:)``), each converted at its own date;
    /// zero if there are none, `nil` if one is unknown. For a trades account, its ``TradeFlow``s
    /// instead: deposits, withdrawals, transfers and residuals. Converted to
    /// `currency` (the base currency when `nil`).
    func recordedFlows(of account: Account, after from: CalendarDate, through: CalendarDate,
                       in currency: CurrencyCode? = nil, problems: inout [ValuationProblem]) -> Decimal? {
        let target = currency ?? baseCurrency
        if history(of: account.id).ledger != nil {
            return convertedTradeFlows(of: account, after: from, through: through, to: target, problems: &problems)?
                .reduce(0) { $0 + $1.amount }
        }
        var total: Decimal = 0
        var known = true
        var previous: Valuation?
        for valuation in valuations(for: account.id) {
            defer { previous = valuation }
            guard valuation.date > from, valuation.date <= through else { continue }
            guard let flow = self.flow(of: valuation, previous: previous),
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

extension Account {
    /// Whether all of the account's change in value is new money, never
    /// markets: belongings'. So its loss of value is spent (PROGRESS.md,
    /// "Savings rate"), and a typed value trues up what was estimated
    /// before it.
    var changeIsNewMoney: Bool {
        kind == .belongings
    }

    /// The share of its value the account is estimated to lose a year
    /// (``Model/Account/depreciation``): a belongings account's, when it's
    /// above 0 and below 1. `nil` otherwise, as other kinds ignore it.
    var lossOfValue: Decimal? {
        guard kind == .belongings, let rate = depreciation, rate > 0, rate < 1 else { return nil }
        return rate
    }

    /// `balance`, a value dated `from`, as estimated on `date` from
    /// ``lossOfValue``: less that share a year, compounding over whole
    /// years and in proportion over the days left, rounded to cents.
    /// Unchanged without a loss of value, or on `from` itself.
    func estimated(_ balance: Decimal, from: CalendarDate, on date: CalendarDate) -> Decimal {
        guard let rate = lossOfValue, date > from else { return balance }
        let days = from.days(to: date)
        var factor = Decimal(1)
        for _ in 0..<(days / 365) { factor *= 1 - rate }
        factor *= 1 - rate * Decimal(days % 365) / 365
        return (balance * factor).rounded(scale: 2)
    }
}
