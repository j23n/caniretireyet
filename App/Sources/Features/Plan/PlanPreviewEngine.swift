import Foundation
import Model
import Planner

/// For the Plan screens' previews: the made-up `PreviewPlanEngine`, with
/// the details the Planner adds (key numbers, pensions, the what-if's
/// saving, net income by year, a warning), so every card has something to
/// show. Never used in the app itself.
struct PlanPreviewEngine: PlanEngine {
    var version: String { "preview" }
    var delay: Duration = .milliseconds(60)

    func run(_ request: PlanRunRequest) async throws -> PlanResults {
        var results = try await PreviewPlanEngine(delay: delay).run(request)
        let plan = request.plan
        let birth = request.library.settings.person?.birthDate ?? "1988-04-12"
        let whatIf = request.whatIf ?? PlanWhatIf()
        let focusAge = request.focusAge ?? whatIf.retirementAge ?? plan.retirement.age.age
            ?? results.headline.earliestAge ?? 55
        let saving = whatIf.monthlySaving ?? 1_500
        let medianAtFocus = results.years.first { $0.year == birth.year + focusAge }?.p50.doubleValue
        let netIncome = results.years.map { year -> YearValue in
            let age = year.year - birth.year
            let working = age < focusAge
            return YearValue(year: year.year, value: working ? 46_000 + Double(year.year % 7) * 300 : 16_500)
        }
        results.details = PlanResultDetails(
            planHash: Planner.planHash(plan), currentAge: birth.wholeYears(to: request.asOf),
            endAge: plan.effectiveEndAge, birthDate: birth, fiNumber: 780_000,
            sustainableSpendingAge: results.headline.targetAge, scansEveryAge: request.mode == .full,
            pensionSteps: [PlanPensionStep(age: 64, pensions: ["INPS"]), PlanPensionStep(age: 67, pensions: ["INPS"])],
            issues: [PlanIssue(.warning, code: "preview.impatriati",
                               message: "Impatriati doesn't apply to forfettario income: 2029 is lost.",
                               section: .tax, year: 2029, regime: "it.impatriati-2024")],
            focus: PlanFocusDetails(
                age: focusAge, retirementDate: birth.adding(years: focusAge),
                success: results.successByAge.first { $0.age == focusAge }?.success,
                medianAtRetirement: medianAtFocus, medianAtEnd: results.years.last?.p50.doubleValue,
                lifetimeTaxes: results.taxes.reduce(0) { $0 + $1.amount } + 180_000,
                netIncome: netIncome,
                pensions: [
                    PlanPensionStart(index: 0, name: "INPS (contributory system)", scheme: "it.inps", age: 67,
                                     perYear: 14_200),
                    PlanPensionStart(index: 1, name: "State pension from previous country", scheme: "fixed", age: 67,
                                     perYear: 4_800),
                ],
                monthlySaving: Decimal(saving.doubleValue.rounded()),
                bridges: [PlanBridgeFailure(name: "Pension fund", accessibleFromAge: 57, share: 0.03)]))
        results.failure?.bridgeName = "Pension fund"
        return results
    }
}
