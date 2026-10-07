import Foundation
import Model

/// The What-if sliders (UI.md, "What if"): retirement age, spending, saving
/// per month and equity's typical year (its median real return, as the
/// defaults are given). Each starts at the plan's own value; moving
/// one sets that field of a `PlanWhatIf`. Values are `Double` for `Slider`.
enum PlanWhatIfSlider: String, CaseIterable, Hashable, Sendable, Identifiable {
    case retirementAge
    case spending
    case saving
    case equityReturn

    var id: String { rawValue }

    var title: String {
        switch self {
        case .retirementAge: "Stop working at"
        case .spending: "Spending"
        case .saving: "Saving"
        case .equityReturn: "Shares, above inflation"
        }
    }

    /// The step a drag moves in: a year of age, 50 a month of spending or
    /// saving, a quarter of a percent of return.
    var step: Double {
        switch self {
        case .retirementAge: 1
        case .spending: 50
        case .saving: 50
        case .equityReturn: 0.0025
        }
    }
}

/// The sliders' values and ranges for one plan and its results.
struct PlanWhatIfModel: Hashable, Sendable {
    var plan: PlanDocument
    /// The plan's own results (without what-if changes).
    var results: PlanResults?
    var whatIf: PlanWhatIf

    // MARK: The plan's own values

    /// The plan's retirement age, or the earliest age when it asks for that.
    var planRetirementAge: Int? {
        plan.retirement.age.age ?? results?.headline.targetAge ?? results?.headline.earliestAge
    }

    var planSpending: Decimal { plan.spending.retired }

    /// Saving per month while working, from the plan's own run.
    var planSaving: Decimal? { results?.details?.focus.monthlySaving }

    /// Equity's median real return in the plan (the typical year), to a
    /// hundredth of a percent: as written, or derived from the mean.
    var planEquityReturn: Decimal {
        PlanAssumptions.rounded(plan.assumptions.returnAssumption(for: .equity)?.impliedMedianReal ?? 0)
    }

    /// Whether the slider can be used: the age needs results (for today's
    /// age), saving needs the plan's own saving.
    func isAvailable(_ slider: PlanWhatIfSlider) -> Bool {
        switch slider {
        case .retirementAge: planRetirementAge != nil
        case .spending, .equityReturn: true
        case .saving: planSaving != nil
        }
    }

    // MARK: Sliders

    func range(_ slider: PlanWhatIfSlider) -> ClosedRange<Double> {
        switch slider {
        case .retirementAge:
            let current = Double(results?.details?.currentAge ?? max(18, (planRetirementAge ?? 55) - 20))
            let end = Double(min(75, plan.effectiveEndAge - 1))
            return current...max(current + 1, end)
        case .spending:
            let own = planSpending.doubleValue / 12
            return 0...max(5_000, (own * 2 / 100).rounded(.up) * 100)
        case .saving:
            let own = planSaving?.doubleValue ?? 0
            let most = own + plan.spending.working.doubleValue / 12
            return 0...max(own * 2, (most / 100).rounded(.up) * 100, 1_000)
        case .equityReturn:
            return -0.02...0.08
        }
    }

    /// The value the slider shows: the what-if's, else the plan's; spending
    /// a month, as the plan's words say it (the plan keeps it a year).
    func value(_ slider: PlanWhatIfSlider) -> Double {
        switch slider {
        case .retirementAge: Double(whatIf.retirementAge ?? planRetirementAge ?? 55)
        case .spending: (whatIf.retiredSpending ?? planSpending).doubleValue / 12
        case .saving: (whatIf.monthlySaving ?? planSaving ?? 0).doubleValue
        case .equityReturn: (whatIf.equityReturn ?? planEquityReturn).doubleValue
        }
    }

    /// Whether the slider is moved away from the plan's value.
    func isChanged(_ slider: PlanWhatIfSlider) -> Bool {
        switch slider {
        case .retirementAge: whatIf.retirementAge != nil
        case .spending: whatIf.retiredSpending != nil
        case .saving: whatIf.monthlySaving != nil
        case .equityReturn: whatIf.equityReturn != nil
        }
    }

    /// The what-if after moving `slider` to `value` (snapped to its step).
    /// Moving it back to the plan's value clears that field.
    func setting(_ slider: PlanWhatIfSlider, to value: Double) -> PlanWhatIf {
        var whatIf = whatIf
        let snapped = (value / slider.step).rounded() * slider.step
        switch slider {
        case .retirementAge:
            let age = Int(snapped.rounded())
            whatIf.retirementAge = age == planRetirementAge ? nil : age
        case .spending:
            // A month on the slider, a year in the plan; back within half a
            // step of the plan's own is the plan's own.
            let own = planSpending.doubleValue / 12
            whatIf.retiredSpending = abs(snapped - own) < slider.step / 2 ? nil : Decimal(Int((snapped * 12).rounded()))
        case .saving:
            let amount = Decimal(Int(snapped.rounded()))
            whatIf.monthlySaving = amount == planSaving ? nil : amount
        case .equityReturn:
            let rate = Decimal(Int((snapped * 10_000).rounded())) / 10_000
            whatIf.equityReturn = rate == planEquityReturn ? nil : rate
        }
        return whatIf
    }

    /// The plan with the what-if written in ("Keep").
    var kept: PlanDocument {
        whatIf.applied(to: plan, baseMonthlySaving: planSaving)
    }
}
