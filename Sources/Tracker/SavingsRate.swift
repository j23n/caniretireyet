import Foundation
import Model

/// How much of the money that came in was kept over a period (PROGRESS.md,
/// "Savings rate"): money in less money out on cash and savings accounts
/// (``MoneyInOutSummary``), plus what was paid into pension funds and TFR,
/// pay that never reaches a cash account, on both sides. In the base
/// currency.
public struct SavingsRate: Hashable, Sendable {
    /// The money in and out it's worked out from.
    public var moneyInOut: MoneyInOutSummary
    /// The days the pension contributions are counted over, the days the
    /// money in and out cover: from ``MoneyInOutSummary/measuredFrom``
    /// (exclusive) through ``MoneyInOutSummary/through``.
    public var from: CalendarDate
    public var through: CalendarDate
    /// New money into pension funds and TFR over those days, each account's
    /// at least zero: money taken out of them isn't income.
    public var pensionContributions: Decimal
    /// Pension accounts whose new money is what the main plan pays in,
    /// because a check-in left their flow empty. Sorted.
    public var plannedContributionAccounts: [AccountID]

    public init(moneyInOut: MoneyInOutSummary, from: CalendarDate, through: CalendarDate,
                pensionContributions: Decimal = 0, plannedContributionAccounts: [AccountID] = []) {
        self.moneyInOut = moneyInOut
        self.from = from
        self.through = through
        self.pensionContributions = pensionContributions
        self.plannedContributionAccounts = plannedContributionAccounts
    }

    /// The account kinds whose new money counts as pay that was saved.
    public static let pensionKinds: Set<AccountKind> = [.pensionFund, .tfr]

    /// What came in: money in, plus the pension contributions.
    public var income: Decimal { moneyInOut.moneyIn + pensionContributions }

    /// What was kept: money in less money out, plus the pension contributions.
    public var saved: Decimal { moneyInOut.net + pensionContributions }

    /// ``saved`` over ``income``; negative when more went out than came in.
    /// `nil` when nothing came in.
    public var rate: Decimal? {
        income > 0 ? saved / income : nil
    }
}

extension Valuator {
    /// The savings rate over the money in and out recorded by valuations
    /// dated from `from` through `through` (``moneyInOut(from:through:accounts:)``),
    /// with the new money into pension funds and TFR (``SavingsRate/pensionKinds``)
    /// over the days those valuations cover. `nil` when no money in and out
    /// was counted.
    public func savingsRate(from: CalendarDate, through: CalendarDate) -> SavingsRate? {
        let money = moneyInOut(from: from, through: through)
        guard let start = money.measuredFrom else { return nil }
        var contributions: Decimal = 0
        var planned: [AccountID] = []
        for account in accounts.values.sorted(by: { $0.id < $1.id })
        where SavingsRate.pensionKinds.contains(account.kind) && account.isOpen(onAnyDayFrom: start, through: through) {
            let paid = change(of: account, from: start, to: through)
            guard paid.change.newMoney > 0 else { continue }
            contributions += paid.change.newMoney
            if paid.isFlowFromPlan { planned.append(account.id) }
        }
        return SavingsRate(moneyInOut: money, from: start, through: through, pensionContributions: contributions,
                           plannedContributionAccounts: planned)
    }

    /// ``savingsRate(from:through:)`` over the twelve months that end on `date`.
    public func savingsRate(overYearEndingOn date: CalendarDate) -> SavingsRate? {
        savingsRate(from: date.adding(years: -1).adding(days: 1), through: date)
    }
}
