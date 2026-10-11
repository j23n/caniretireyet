import Foundation
import Model

/// What a plan saves while you work: the take-home pay of the work phase in
/// force less spending while working. The crossover milestone and Trends'
/// reference savings rate count a year's saving this way.
extension PlanDocument {
    /// The work phase in force on `date`: the last one that started on or
    /// before it and hasn't ended before it. A phase until retirement
    /// hasn't ended. `nil` between phases or after work.
    public func workPhase(on date: CalendarDate) -> WorkPhase? {
        work.last { phase in
            phase.from <= date && (phase.until.date.map { $0 >= date } ?? true)
        }
    }

    /// A year's saving while working: the take-home pay of the work phase
    /// in force on `date` less spending while working, with that pay.
    /// Negative when the plan spends more than the pay. `nil` without a
    /// work phase in force on `date`, or its pay.
    public func workingSaving(on date: CalendarDate) -> (pay: Decimal, saving: Decimal)? {
        guard let pay = workPhase(on: date)?.netIncome else { return nil }
        return (pay, pay - spending.working)
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
