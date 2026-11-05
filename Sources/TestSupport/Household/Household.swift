import Foundation
import Model

/// A simulated household with known truth (``HouseholdSimulator``): how it
/// started, what truly happened to its money (its events) and the markets,
/// and what its person records for the app (``records``). ``truth`` plays
/// the events; ``library()`` writes what a careful person would give the
/// app. All of it is made up.
public struct Household: Sendable {
    /// The seed it was made from.
    public var seed: UInt64
    /// The first check-in, a 31 December: every account's first value.
    public var start: CalendarDate
    /// The last day, a 31 December: the last check-in.
    public var end: CalendarDate
    public var opening: HouseholdOpening
    /// What happened, by date and then ID.
    public var events: [HouseholdEvent]
    public var markets: HouseholdMarkets
    /// Whether it has a car account (worth nothing until a car is bought).
    public var hasCar: Bool
    /// Whether it holds the dollar stock.
    public var hasStock: Bool
    /// The day the second savings account opens, when it does.
    public var onlineOpened: CalendarDate?
    public var records: HouseholdRecords

    public init(seed: UInt64, start: CalendarDate, end: CalendarDate, opening: HouseholdOpening,
                events: [HouseholdEvent], markets: HouseholdMarkets, hasCar: Bool, hasStock: Bool,
                onlineOpened: CalendarDate?, records: HouseholdRecords) {
        self.seed = seed
        self.start = start
        self.end = end
        self.opening = opening
        self.events = events
        self.markets = markets
        self.hasCar = hasCar
        self.hasStock = hasStock
        self.onlineOpened = onlineOpened
        self.records = records
    }

    /// Every account, in a fixed order.
    public var accounts: [AccountID] {
        typealias A = HouseholdAccount
        return [A.current, A.savings, A.card, A.broker, A.pension, A.mortgage]
            + (hasCar ? [A.car] : []) + (onlineOpened == nil ? [] : [A.online])
    }

    /// The instruments the broker can hold.
    public var instruments: [InstrumentID] {
        [HouseholdAccount.etf] + (hasStock ? [HouseholdAccount.stock] : [])
    }

    /// Every month end after ``start`` through ``end``.
    public var monthEnds: [CalendarDate] {
        Household.monthEnds(after: start, through: end)
    }

    /// The dates the person checks in: ``start`` and every month end but
    /// the skipped ones.
    public var checkIns: [CalendarDate] {
        [start] + monthEnds.filter { !records.skippedCheckIns.contains($0) }
    }

    /// The calendar years it covers whole.
    public var years: [Int] {
        Array((start.year + 1)...end.year)
    }

    /// The same household with only some of its events, such as a failing
    /// seed's events reduced to the fewest that still fail.
    public func with(events: [HouseholdEvent]) -> Household {
        var household = self
        household.events = events
        return household
    }

    /// What truly happened, day by day.
    public var truth: HouseholdTruth {
        HouseholdTruth(self)
    }
}

/// What the person of a simulated household records, besides what a
/// careful person would: the options that leave the app to guess.
public struct HouseholdRecords: Hashable, Sendable {
    /// Month ends without a check-in: no account has a value then.
    public var skippedCheckIns: Set<CalendarDate>
    /// Check-ins whose pension value is typed without what was paid in.
    public var pensionWithoutSaved: Set<CalendarDate>

    public init(skippedCheckIns: Set<CalendarDate> = [], pensionWithoutSaved: Set<CalendarDate> = []) {
        self.skippedCheckIns = skippedCheckIns
        self.pensionWithoutSaved = pensionWithoutSaved
    }
}

/// What truly happened to a simulated household's money: each account's
/// value at the end of every day, the money that moved into it, what each
/// day's events count as (``HouseholdTotals``) and the bank statements'
/// lines. In euros.
public struct HouseholdTruth: Sendable {
    public let start: CalendarDate
    public let accounts: [AccountID]
    /// The statement lines of the current account and the savings accounts, in order.
    public let lines: [HouseholdLine]
    /// Days whose money moved doesn't add up to what their events count as:
    /// a mistake in the simulator itself. Empty.
    public let inconsistencies: [String]
    /// Each account's value at the end of each day.
    private let values: [AccountID: [Decimal]]
    /// Each account's money moved in from outside it, added up through each day.
    private let flowsThrough: [AccountID: [Decimal]]
    /// What the events count as, added up through each day.
    private let totalsThrough: [HouseholdTotals]
    private let cash: [Decimal]
    private let held: [[InstrumentID: Decimal]]

    init(_ household: Household) {
        start = household.start
        accounts = household.accounts
        var state = HouseholdState(household.opening)
        let days = household.start.days(to: household.end)
        let byDate = Dictionary(grouping: household.events, by: \.date)
        var values = Dictionary(uniqueKeysWithValues: accounts.map { ($0, [Decimal]()) })
        var flowsThrough = values
        var totalsThrough: [HouseholdTotals] = []
        var lines: [HouseholdLine] = []
        var inconsistencies: [String] = []
        var cash: [Decimal] = []
        var held: [[InstrumentID: Decimal]] = []
        for index in 0...days {
            let date = household.start.adding(days: index)
            var totals = totalsThrough.last ?? HouseholdTotals()
            var flows: [AccountID: Decimal] = [:]
            var counted = HouseholdTotals()
            if index > 0 {
                for event in (byDate[date] ?? []).sorted(by: { $0.id < $1.id }) {
                    let effect = state.apply(event)
                    flows.merge(effect.flows, uniquingKeysWith: +)
                    counted = counted + effect.totals
                    lines += effect.lines
                }
            }
            let moved = flows.values.reduce(Decimal(0), +)
            let expected = counted.saved + counted.oneOffs + counted.startedWith
            if moved != expected {
                inconsistencies.append("\(date): money moved \(moved), events count \(expected)")
            }
            totals = totals + counted
            totalsThrough.append(totals)
            let worth = state.values(on: date, markets: household.markets)
            for account in accounts {
                values[account, default: []].append(worth[account] ?? 0)
                flowsThrough[account, default: []].append((flowsThrough[account]?.last ?? 0) + (flows[account] ?? 0))
            }
            cash.append(state.brokerCash)
            held.append(state.holdings.filter { $0.value != 0 })
        }
        self.values = values
        self.flowsThrough = flowsThrough
        self.totalsThrough = totalsThrough
        self.lines = lines
        self.inconsistencies = inconsistencies
        self.cash = cash
        self.held = held
    }

    private func index(_ date: CalendarDate) -> Int {
        min(max(start.days(to: date), 0), totalsThrough.count - 1)
    }

    /// The account's value at the end of `date`, in euros.
    public func value(of account: AccountID, on date: CalendarDate) -> Decimal {
        values[account]?[index(date)] ?? 0
    }

    /// Net worth at the end of `date`: every account.
    public func netWorth(on date: CalendarDate) -> Decimal {
        accounts.reduce(Decimal(0)) { $0 + value(of: $1, on: date) }
    }

    /// The broker's cash at the end of `date`.
    public func brokerCash(on date: CalendarDate) -> Decimal {
        cash[index(date)]
    }

    /// What the broker holds at the end of `date`.
    public func holdings(on date: CalendarDate) -> [InstrumentID: Decimal] {
        held[index(date)]
    }

    /// The money that moved into `account` from outside it after `from` through `through`.
    public func moved(into account: AccountID, after from: CalendarDate, through: CalendarDate) -> Decimal {
        guard let flows = flowsThrough[account] else { return 0 }
        return flows[index(through)] - flows[index(from)]
    }

    /// What markets did to `account` after `from` through `through`: its
    /// change, less the money that moved into it.
    public func markets(of account: AccountID, after from: CalendarDate, through: CalendarDate) -> Decimal {
        value(of: account, on: through) - value(of: account, on: from) - moved(into: account, after: from,
                                                                              through: through)
    }

    /// What happened after `from` through `through`.
    public func totals(after from: CalendarDate, through: CalendarDate) -> HouseholdTotals {
        let before = totalsThrough[index(from)]
        let after = totalsThrough[index(through)]
        var totals = HouseholdTotals()
        totals.pay = after.pay - before.pay
        totals.pension = after.pension - before.pension
        totals.tax = after.tax - before.tax
        totals.spent = after.spent - before.spent
        totals.oneOffs = after.oneOffs - before.oneOffs
        totals.startedWith = after.startedWith - before.startedWith
        totals.markets = accounts.reduce(Decimal(0)) { $0 + markets(of: $1, after: from, through: through) }
        totals.change = netWorth(on: through) - netWorth(on: from)
        return totals
    }

    /// The money in and out of `account`'s lines after `from` through `through`.
    public func moneyInOut(of account: AccountID, after from: CalendarDate, through: CalendarDate)
        -> HouseholdMoneyInOut {
        var money = HouseholdMoneyInOut()
        for line in lines where line.account == account && line.date > from && line.date <= through {
            money.add(line)
        }
        return money
    }
}
