import Foundation
import Model

/// What a plan saves while you work: the take-home pay of the work phase in
/// force, with what's paid on top of it into accounts, less spending while
/// working. The crossover milestone and Trends' reference savings rate
/// count a year's saving this way.
extension PlanDocument {
    /// A year's saving while working: the pay of the work phase in force
    /// on `date` less spending while working, with that pay. The pay is
    /// the phase's take-home pay plus the yearly contributions paid on top
    /// of it then (``contributionsOnTopOfPay(on:)``), as the savings rate
    /// counts what's paid into a pension as came in and as saved.
    /// Negative when the plan spends more than the pay. `nil` without a
    /// work phase in force on `date`, or its pay. The phase in force is the
    /// last one that started on or before `date` and hasn't ended before it;
    /// a phase until retirement hasn't ended.
    public func workingSaving(on date: CalendarDate) -> (pay: Decimal, saving: Decimal)? {
        let phase = work.last { $0.from <= date && ($0.until.date.map { $0 >= date } ?? true) }
        guard let takeHome = phase?.netIncome else { return nil }
        let pay = takeHome + contributionsOnTopOfPay(on: date)
        return (pay, pay - spending.working)
    }

    /// What's paid a year on top of take-home pay into accounts on `date`:
    /// the yearly contributions marked so
    /// (``Model/PlanContribution/isPaidOnTopOfPay``) that haven't stopped
    /// before it; one until retirement hasn't stopped. One into an account
    /// the plan excludes (`portfolio.exclude`) isn't the plan's, as a run
    /// leaves it out.
    public func contributionsOnTopOfPay(on date: CalendarDate) -> Decimal {
        let excluded = Set(portfolio.exclude)
        return contributions
            .filter { contribution in
                contribution.isPaidOnTopOfPay && !contribution.isOneOff && !excluded.contains(contribution.account)
                    && (contribution.effectiveUntil.date.map { $0 >= date } ?? true)
            }
            .reduce(Decimal(0)) { $0 + $1.perYear }
    }

    /// The plan's own savings rate while working (PROGRESS.md, "Trends"): a
    /// year's saving (``workingSaving(on:)``) over the pay; negative when
    /// it spends more than the pay. `nil` without a work phase in force on
    /// `date`, or with no pay.
    public func workingSavingsRate(on date: CalendarDate) -> Decimal? {
        guard let working = workingSaving(on: date), working.pay > 0 else { return nil }
        return working.saving / working.pay
    }
}
