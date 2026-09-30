import Foundation
import Model
import Planner
import TaxKit
import Testing

/// The app's SwiftUI previews build sample results from the public
/// initialisers alone (this file doesn't use `@testable`).
struct PreviewSampleTests {
    static func sampleResult() -> PlanResult {
        let plan = PlanDocument(id: "preview", name: "Preview", retirement: PlanRetirement(age: .age(55)),
                                spending: PlanSpending(working: 30_000, retired: 30_000))
        let year = YearDetail(
            year: 2044, age: 56, startAssets: 600_000, endAssets: 590_000, spending: 30_000,
            income: [IncomeItem(kind: .withdrawal, id: "it.ordinary", label: "Ordinary account", amount: 31_000),
                     IncomeItem(kind: .pension, id: "pension-1", label: "State pension", amount: 4_800)],
            taxes: [AmountItem(id: "it.capitalGains", label: "Tax on gains", amount: 1_000)], savings: -31_000)
        let failure = RunFailure(year: 2061, age: 73, reason: .locked(LockedMoney(
            wrapper: "it.pensionFund", name: "Pension fund", value: 20_000, accessibleFromAge: 67,
            reason: "Locked until 67")))
        return PlanResult(
            plan: plan, planHash: Planner.planHash(plan), taxParameters: ["it": 2026],
            start: PlanStart(date: "2026-09-30", age: 38, planAssets: 161_505,
                             buckets: [BucketSummary(wrapper: "it.ordinary", name: "Ordinary account", category: .taxable,
                                                     receivesSavings: true, value: 120_000, costBasis: 90_000)]),
            settings: SimulationSettings(runs: 2000, seed: 1, confidence: 0.9, inflation: 0.02, endAge: 95),
            answer: PlanAnswer(canRetireNow: false, confidence: 0.9, currentAge: 38, successIfRetiringNow: 0.02,
                               earliestAge: 55, earliestDate: "2043-04-12", targetAge: 55, successAtTarget: 0.91,
                               sustainableSpending: SustainableSpending(age: 55, perYear: 36_500, success: 0.9),
                               fiNumber: 780_000, fiProgress: 0.21),
            successCurve: [AgeSuccess(age: 55, retirementDate: "2043-04-12", success: 0.91, runs: 2000,
                                      pensionStartAges: ["pension-0": 71])],
            focusAge: 55,
            fan: [FanYear(year: 2044, age: 56, p10: 400_000, p25: 500_000, p50: 590_000, p75: 700_000, p90: 820_000,
                          expected: 600_000)],
            expectedPath: PathDetail(retirementAge: 55, years: [year]),
            medianPath: PathDetail(retirementAge: 55, failure: failure, years: [year]),
            failures: FailureSummary(runs: 2000, failed: 180, failureRate: 0.09, medianFailureAge: 81,
                                     byAge: [AgeCount(age: 81, count: 180)], bridgeFailures: 20,
                                     bridges: [BridgeFailure(wrapper: "it.pensionFund", name: "Pension fund",
                                                             accessibleFromAge: 67, count: 20, share: 0.01)]),
            markers: [TimelineMarker(kind: .retirement, year: 2043, age: 55, label: "Retirement")],
            issues: [PlanIssue(.warning, code: "preview.note", message: "A sample warning.", section: .tax)])
    }

    @Test func aSampleResultCanBeBuiltFromPublicInitialisers() {
        let result = Self.sampleResult()
        #expect(result.engine == Planner.engineVersion)
        #expect(result.success(atAge: 55) == 0.91)
        #expect(result.expectedPath.years.first?.totalTax == 1_000)
        #expect(result.headline().earliestAge == 55)
    }
}
