import Foundation
import Model

/// How much of the money that came in was saved over a period (PROGRESS.md,
/// "Savings rate"). What was saved is worked out from balances and trades:
/// the new money of every account in net worth, as the Overview's *This
/// year* splits it, so money moved between your accounts cancels out, a
/// refund lowers what was spent and a loan's principal repaid is saved. What
/// came in is the money in that cash and savings accounts record, plus what
/// was paid into pension funds and TFR, pay that never reaches a cash
/// account. What was spent is the rest. In the base currency.
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
    /// `from` through `through` (``moneyInOut(from:through:accounts:)``),
    /// with what was saved (``saved(after:through:)``) and the new money
    /// into pension funds and TFR (``SavingsRate/pensionKinds``) over the
    /// days the pay covers: those of the account the most came into, so an
    /// account checked rarely, or recording money in for longer, doesn't
    /// stretch them. `nil` when no money in and out was counted.
    public func savingsRate(from: CalendarDate, through: CalendarDate) -> SavingsRate? {
        let money = moneyInOut(from: from, through: through)
        guard let counted = money.measuredFrom else { return nil }
        let pay = accounts.values.filter(\.kind.recordsMoneyInOut).sorted { $0.id < $1.id }
            .map { moneyInOut(from: from, through: through, accounts: [$0.id]) }
            .filter { $0.moneyIn > 0 }
            .max { $0.moneyIn < $1.moneyIn }
        let start = pay?.measuredFrom ?? counted
        var contributions: Decimal = 0
        var planned: [AccountID] = []
        for account in accounts.values.sorted(by: { $0.id < $1.id })
        where SavingsRate.pensionKinds.contains(account.kind) && account.isOpen(onAnyDayFrom: start, through: through) {
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
    /// in proportion to their flows.
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
            var offset: Decimal = 0
            var flows: [(account: AccountID, flow: Decimal)] = []
            for account in stretch.accounts {
                if firsts.contains(account.account) {
                    flows.append((account: account.account, flow: max(account.flow ?? 0, 0)))
                } else {
                    offset += max(-account.change.newMoney, 0)
                }
            }
            let total = flows.reduce(Decimal(0)) { $0 + $1.flow }
            let share: Decimal = total == 0 ? 0 : min(offset / total, 1)
            for first in flows where first.flow > 0 {
                saved[first.account, default: 0] -= first.flow * (1 - share)
            }
        }
        return (saved, report.isPriced)
    }
}
