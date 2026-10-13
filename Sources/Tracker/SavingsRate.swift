import Foundation
import Model

/// How much of the money that came in was saved over a period (PROGRESS.md,
/// "Savings rate"). What was saved is worked out from balances and trades:
/// the new money of every account in net worth, as the Overview's *This
/// year* splits it, so money moved between your accounts cancels out, a
/// refund lowers what was spent and a loan's principal repaid is saved. What
/// came in is the money in that cash and savings accounts record, plus what
/// was paid into pension funds and TFR, pay that never reaches a cash
/// account. What was spent is the rest. Only accounts in net worth count,
/// on both sides. In the base currency.
public struct SavingsRate: Hashable, Sendable {
    /// The money in it's worked out from.
    public var moneyInOut: MoneyInOutSummary
    /// The days counted, the days the pay that came in covers: from the
    /// valuation the counted values of the account the most came into are
    /// measured from (exclusive) through ``through``.
    public var from: CalendarDate
    public var through: CalendarDate
    /// New money into pension funds and TFR over those days, each account's
    /// at least zero: money taken out of them isn't income.
    public var pensionContributions: Decimal
    /// Pension accounts whose new money is what the main plan pays in,
    /// because a check-in left their flow empty. Sorted.
    public var plannedContributionAccounts: [AccountID]
    /// What each account in net worth saved over those days
    /// (``Valuator/saved(after:through:)``): its new money, less what a new
    /// account's first value already held.
    public var savedByAccount: [AccountID: Decimal]
    /// Whether every price and exchange rate the new money needs was known.
    public var isPriced: Bool

    public init(moneyInOut: MoneyInOutSummary, from: CalendarDate, through: CalendarDate,
                pensionContributions: Decimal = 0, plannedContributionAccounts: [AccountID] = [],
                savedByAccount: [AccountID: Decimal] = [:], isPriced: Bool = true) {
        self.moneyInOut = moneyInOut
        self.from = from
        self.through = through
        self.pensionContributions = pensionContributions
        self.plannedContributionAccounts = plannedContributionAccounts
        self.savedByAccount = savedByAccount
        self.isPriced = isPriced
    }

    /// The account kinds whose new money counts as pay that was saved.
    public static let pensionKinds: Set<AccountKind> = [.pensionFund, .tfr]

    /// What came in: money in, plus the pension contributions.
    public var income: Decimal { moneyInOut.moneyIn + pensionContributions }

    /// What was saved: every account's new money over the days, added up.
    public var saved: Decimal {
        savedByAccount.keys.sorted().reduce(Decimal(0)) { $0 + (savedByAccount[$1] ?? 0) }
    }

    /// What was spent: what came in less what was saved. Below zero when
    /// more was saved than came in, usually because some income wasn't
    /// recorded.
    public var spent: Decimal { income - saved }

    /// ``spent`` scaled to a year by the days counted, rounded to cents.
    public var spentPerYear: Decimal {
        (spent * 365 / Decimal(max(1, from.days(to: through)))).rounded(scale: 2)
    }

    /// ``saved`` over ``income``; negative when more was spent than came in.
    /// `nil` when nothing came in.
    public var rate: Decimal? {
        income > 0 ? saved / income : nil
    }
}

extension Valuator {
    /// The savings rate over the money in recorded by valuations dated from
    /// `from` through `through` (``moneyInOut(from:through:accounts:)``) of
    /// the accounts in net worth,
    /// with what was saved (``saved(after:through:)``) and the new money
    /// into pension funds and TFR (``SavingsRate/pensionKinds``) over the
    /// days the pay covers: those of the account the most came into, so an
    /// account checked rarely, or recording money in for longer, doesn't
    /// stretch them. `nil` when no money in and out was counted.
    public func savingsRate(from: CalendarDate, through: CalendarDate) -> SavingsRate? {
        let counted = cameInAccounts
        let cash = accounts.values.filter { counted.contains($0.id) }
        let money = moneyInOut(from: from, through: through, accounts: counted)
        guard let measuredFrom = money.measuredFrom else { return nil }
        let pay = cash.sorted { $0.id < $1.id }
            .map { moneyInOut(from: from, through: through, accounts: [$0.id]) }
            .filter { $0.moneyIn > 0 }
            .max { $0.moneyIn < $1.moneyIn }
        let start = pay?.measuredFrom ?? measuredFrom
        var contributions: Decimal = 0
        var planned: [AccountID] = []
        for account in accounts.values.sorted(by: { $0.id < $1.id })
        where SavingsRate.pensionKinds.contains(account.kind) && account.includedInNetWorth
            && account.isOpen(onAnyDayFrom: start, through: through) {
            let paid = change(of: account, from: start, to: through)
            guard paid.change.newMoney > 0 else { continue }
            contributions += paid.change.newMoney
            if paid.isFlowFromPlan { planned.append(account.id) }
        }
        let saved = saved(after: start, through: through)
        return SavingsRate(moneyInOut: money, from: start, through: through, pensionContributions: contributions,
                           plannedContributionAccounts: planned, savedByAccount: saved.byAccount,
                           isPriced: saved.isPriced)
    }

    /// The accounts whose money in counts as came in: the cash and savings
    /// accounts in net worth.
    public var cameInAccounts: Set<AccountID> {
        Set(accounts.values.filter { $0.kind.recordsMoneyInOut && $0.includedInNetWorth }.map(\.id))
    }

    /// `report`'s split of net worth's change with its new money as the
    /// savings rate counts what was saved (``saved(after:through:)``) over
    /// its days: the part of new accounts' first values counted as what
    /// they already held moves to other. For the Overview's bars.
    public func savedSplit(of report: ChangeReport) -> ValueChange {
        var change = report.total
        let saved = saved(after: report.from, through: report.to).byAccount.values.reduce(Decimal(0), +)
        change.other += change.newMoney - saved
        change.newMoney = saved
        return change
    }

    /// ``savingsRate(from:through:)`` over the twelve months that end on `date`.
    public func savingsRate(overYearEndingOn date: CalendarDate) -> SavingsRate? {
        savingsRate(from: date.adding(years: -1).adding(days: 1), through: date)
    }

    /// What each account in net worth saved after `from` through `through`
    /// (PROGRESS.md, "Savings rate"): its new money as
    /// ``change(from:to:in:)`` splits net worth's change, less the part of a
    /// new account's first value that it already held. A check-in fills in
    /// a new account's whole amount as its flow; as Trends' *put in*
    /// counts it (``moneySources(_:through:)``), that flow stays saved only
    /// as far as negative new money of accounts with a record before it, from
    /// the check-in before to the one it's in, offsets it (money moved from
    /// an account already tracked), shared over that stretch's first values
    /// in proportion to their flows. A debt's first flow, negative, stays
    /// only as far as money moved into cash and savings accounts already
    /// tracked offsets it (a loan paid out into the current account,
    /// ``movedIn(_:after:through:)``), so a debt you start tracking isn't
    /// spent, and doesn't take a month's saving with it.
    public func saved(after from: CalendarDate, through: CalendarDate)
        -> (byAccount: [AccountID: Decimal], isPriced: Bool) {
        let report = change(from: from, to: through, in: .netWorth)
        var saved: [AccountID: Decimal] = [:]
        for account in report.accounts { saved[account.account] = account.change.newMoney }
        let cuts = Set(checkInDates(in: .netWorth, through: through).filter { $0 > from } + [through]).sorted()
        var firstValues: [CalendarDate: Set<AccountID>] = [:]
        for account in report.accounts {
            guard let record = firstRecordDate(of: account.account), record > from, record <= through,
                  let end = cuts.first(where: { $0 >= record })
            else { continue }
            firstValues[end, default: []].insert(account.account)
        }
        for end in firstValues.keys.sorted() {
            guard let firsts = firstValues[end] else { continue }
            let start = cuts.last(where: { $0 < end }) ?? from
            let stretch = change(from: start, to: end, in: .netWorth)
            var takenOut: Decimal = 0
            var putIn: Decimal = 0
            var assets: [(account: AccountID, flow: Decimal)] = []
            var debts: [(account: AccountID, flow: Decimal)] = []
            for account in stretch.accounts {
                if firsts.contains(account.account) {
                    let flow = account.flow ?? 0
                    if flow > 0 { assets.append((account: account.account, flow: flow)) }
                    if flow < 0 { debts.append((account: account.account, flow: flow)) }
                } else {
                    takenOut += max(-account.change.newMoney, 0)
                    putIn += movedIn(account, after: start, through: end) ?? 0
                }
            }
            // Each first flow stays saved in the share of them the other side offsets.
            for (flows, offset) in [(assets, takenOut), (debts, putIn)] {
                let total = flows.reduce(Decimal(0)) { $0 + abs($1.flow) }
                let share: Decimal = total == 0 ? 0 : min(offset / total, 1)
                for first in flows {
                    saved[first.account, default: 0] -= first.flow * (1 - share)
                }
            }
        }
        return (saved, report.isPriced)
    }

    /// What moved into a cash or savings account from your other accounts
    /// after `from` through `through`, in the base currency: the sum of its
    /// valuations' ``Model/Valuation/moved`` where positive. Where one of
    /// them doesn't record money in and out, the new money of `change`, its
    /// change over those days, where positive, as nothing tells a transfer
    /// apart. `nil` for other kinds.
    func movedIn(_ change: AccountChange, after from: CalendarDate, through: CalendarDate) -> Decimal? {
        guard let account = accounts[change.account], account.kind.recordsMoneyInOut else { return nil }
        var total: Decimal = 0
        for valuation in valuations(for: account.id) where valuation.date > from && valuation.date <= through {
            guard let moved = valuation.moved,
                  let inBase = fx.convert(moved, from: account.currency, to: baseCurrency, on: valuation.date)
            else { return max(change.change.newMoney, 0) }
            total += max(inBase, 0)
        }
        return total
    }
}
