import Foundation
import Model

/// What-if changes applied on top of a plan for one run, without saving it
/// (UI.md, "What if"). `nil` fields keep the plan's value.
public struct PlanWhatIf: Hashable, Sendable {
    public var retirementAge: Int?
    /// Yearly spending in retirement, in today's money.
    public var retiredSpending: Decimal?
    /// Take-home pay a month more (or less, below zero) in every work
    /// phase, in today's money.
    public var takeHomeChange: Decimal?

    public init(retirementAge: Int? = nil, retiredSpending: Decimal? = nil, takeHomeChange: Decimal? = nil) {
        self.retirementAge = retirementAge
        self.retiredSpending = retiredSpending
        self.takeHomeChange = takeHomeChange
    }

    public var isEmpty: Bool {
        retirementAge == nil && retiredSpending == nil && takeHomeChange == nil
    }

    /// `plan` with these changes: the retirement age, retirement spending
    /// (which its later phases spend a share of), and take-home pay, a
    /// month's change twelve times a year in each work phase with pay set,
    /// never below zero. Given the day the plan starts from
    /// (`PlanDocument.startDate(in:today:)`), phases that ended before it
    /// keep their pay.
    public func applied(to plan: PlanDocument, start: CalendarDate? = nil) -> PlanDocument {
        var plan = plan
        if let retirementAge {
            plan.retirement.age = .age(retirementAge)
        }
        if let retiredSpending {
            plan.spending.retired = max(0, retiredSpending)
        }
        if let takeHomeChange, takeHomeChange != 0 {
            for index in plan.work.indices where plan.work[index].isGoing(on: start) {
                guard let income = plan.work[index].netIncome else { continue }
                plan.work[index].netIncome = max(0, income + takeHomeChange * 12)
            }
        }
        return plan
    }
}

extension WorkPhase {
    /// Whether the phase hasn't ended before `start`, the day a plan starts
    /// from; any phase when `start` is `nil`.
    func isGoing(on start: CalendarDate?) -> Bool {
        guard let start, let last = until.date else { return true }
        return last >= start
    }
}
