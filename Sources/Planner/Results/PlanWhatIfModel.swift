import Foundation
import Model

/// What if's levers (UI.md, "What if"): when you stop working, take-home
/// pay while working (a change on top of every work phase), and spending
/// a month in retirement. Each starts at the plan's own value; moving one
/// sets that field of a `PlanWhatIf`. Values are `Double`, as a slider
/// takes them.
public enum PlanWhatIfSlider: String, CaseIterable, Hashable, Sendable, Identifiable {
    case retirementAge
    case takeHome
    case spending

    public var id: String { rawValue }

    /// The step a drag moves in: a year of age, 50 a month of pay or spending.
    public var step: Double {
        switch self {
        case .retirementAge: 1
        case .takeHome: 50
        case .spending: 50
        }
    }
}

/// The levers' values and ranges for one plan and its results.
public struct PlanWhatIfModel: Hashable, Sendable {
    public var plan: PlanDocument
    /// The plan's own results (without what-if changes).
    public var results: PlanResults?
    public var whatIf: PlanWhatIf

    public init(plan: PlanDocument, results: PlanResults?, whatIf: PlanWhatIf) {
        self.plan = plan
        self.results = results
        self.whatIf = whatIf
    }

    // MARK: The plan's own values

    /// The plan's retirement age, or the earliest age when it asks for that.
    public var planRetirementAge: Int? {
        plan.retirement.age.age ?? results?.headline.targetAge ?? results?.headline.earliestAge
    }

    /// Whether the plan stops work as early as it can, rather than at an age of its own.
    public var planRetiresEarliest: Bool { plan.retirement.age.age == nil }

    public var planSpending: Decimal { plan.spending.retired }

    /// Each work phase's take-home pay a month, in the plan's order, for
    /// the phases with pay set.
    public var planTakeHome: [Decimal] {
        plan.work.compactMap(\.netIncome).map { $0 / 12 }
    }

    /// Whether the lever can be used: the age needs results (for today's
    /// age), take-home pay a work phase with pay.
    public func isAvailable(_ slider: PlanWhatIfSlider) -> Bool {
        switch slider {
        case .retirementAge: planRetirementAge != nil
        case .takeHome: !planTakeHome.isEmpty
        case .spending: true
        }
    }

    // MARK: Levers

    public func range(_ slider: PlanWhatIfSlider) -> ClosedRange<Double> {
        switch slider {
        case .retirementAge:
            let current = Double(results?.details.currentAge ?? max(18, (planRetirementAge ?? 55) - 20))
            let end = Double(min(75, plan.effectiveEndAge - 1))
            return current...max(current + 1, end)
        case .takeHome:
            // Half the highest pay either way, in hundreds, at least 1.000.
            let most = planTakeHome.map(\.doubleValue).max() ?? 0
            let reach = max(1_000, (most / 2 / 100).rounded(.up) * 100)
            return -reach...reach
        case .spending:
            let own = planSpending.doubleValue / 12
            return 0...max(5_000, (own * 2 / 100).rounded(.up) * 100)
        }
    }

    /// The value the lever shows: the what-if's, else the plan's; spending
    /// a month, as the plan's words say it (the plan keeps it a year); pay
    /// as the change a month, zero as planned.
    public func value(_ slider: PlanWhatIfSlider) -> Double {
        switch slider {
        case .retirementAge: Double(whatIf.retirementAge ?? planRetirementAge ?? 55)
        case .takeHome: (whatIf.takeHomeChange ?? 0).doubleValue
        case .spending: (whatIf.retiredSpending ?? planSpending).doubleValue / 12
        }
    }

    /// Whether the lever is moved away from the plan's value.
    public func isChanged(_ slider: PlanWhatIfSlider) -> Bool {
        switch slider {
        case .retirementAge: whatIf.retirementAge != nil
        case .takeHome: whatIf.takeHomeChange != nil
        case .spending: whatIf.retiredSpending != nil
        }
    }

    /// The what-if after moving `slider` to `value` (snapped to its step).
    /// Moving it back to the plan's value clears that field.
    public func setting(_ slider: PlanWhatIfSlider, to value: Double) -> PlanWhatIf {
        var whatIf = whatIf
        let snapped = (value / slider.step).rounded() * slider.step
        switch slider {
        case .retirementAge:
            let age = Int(snapped.rounded())
            whatIf.retirementAge = age == planRetirementAge ? nil : age
        case .takeHome:
            let change = Int(snapped.rounded())
            whatIf.takeHomeChange = change == 0 ? nil : Decimal(change)
        case .spending:
            // A month on the lever, a year in the plan; back within half a
            // step of the plan's own is the plan's own.
            let own = planSpending.doubleValue / 12
            whatIf.retiredSpending = abs(snapped - own) < slider.step / 2 ? nil : Decimal(Int((snapped * 12).rounded()))
        }
        return whatIf
    }

    /// The plan with the what-if written in (*Apply*): the age into when
    /// work stops, the pay into each work phase, the spending into spending
    /// in retirement, which every retired chapter spends.
    public var kept: PlanDocument {
        whatIf.applied(to: plan)
    }
}
