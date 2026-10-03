import Foundation
import Model
import Planner

/// For the Plan screens' previews: the made-up `PreviewPlanEngine`, with
/// the details the Planner adds (key numbers, pensions, the what-if's
/// saving, net income by year, a warning), so every card has something to
/// show, and made-up progress through the Planner's phases, so the progress
/// view has something to show too. Never used in the app itself.
struct PlanPreviewEngine: PlanEngine {
    var version: String { "preview" }
    /// How long a full run pretends to take is about 20 times this (fast
    /// runs a quarter of that); `.zero` reports every step at once.
    var delay: Duration = .milliseconds(60)

    func run(_ request: PlanRunRequest) async throws -> PlanResults {
        try await run(request, reporting: nil)
    }

    func run(_ request: PlanRunRequest, progress: @escaping PlanProgressHandler) async throws -> PlanResults {
        try await run(request, reporting: progress)
    }

    private func run(_ request: PlanRunRequest, reporting progress: PlanProgressHandler?) async throws
        -> PlanResults {
        if let progress {
            try await Self.pretendToRun(request, delay: delay, report: progress)
        }
        var results = try await PreviewPlanEngine(delay: progress == nil ? delay : .zero).run(request)
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
        let currentAge = birth.wholeYears(to: request.asOf)
        let assetsNeeded = results.headline.readiness.map { readiness in
            AssetsNeeded(age: currentAge, outcome: .found, scale: 1 / readiness,
                         amount: results.start.value.doubleValue / readiness, success: results.headline.confidence,
                         readiness: readiness)
        }
        results.details = PlanResultDetails(
            planHash: Planner.planHash(plan), currentAge: currentAge,
            endAge: plan.effectiveEndAge, birthDate: birth, fiNumber: 780_000, assetsNeeded: assetsNeeded,
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

    /// Reports made-up progress through the Planner's phases, as a real run
    /// would: the age scan most of the time, then the focus age's runs, the
    /// spending bisection, the search for what retiring today needs and the
    /// summary. Stops when cancelled.
    static func pretendToRun(_ request: PlanRunRequest, delay: Duration, report: PlanProgressHandler) async throws {
        let runs = request.mode == .fast ? 250 : request.plan.simulation.effectiveRuns
        let birth = request.library.settings.person?.birthDate ?? "1988-04-12"
        let current = birth.wholeYears(to: request.asOf)
        let ages = current...max(current, 75)
        let ticks = request.mode == .fast ? 6 : 24
        let pause = delay * (request.mode == .fast ? 5 : 20) / ticks
        for tick in 0...ticks {
            try Task.checkCancellation()
            report(progress(at: Double(tick) / Double(ticks), runs: runs, ages: ages, mode: request.mode))
            if pause > .zero, tick < ticks { try await Task.sleep(for: pause) }
        }
    }

    /// Where a made-up run is when `fraction` of it is done.
    static func progress(at fraction: Double, runs: Int, ages: ClosedRange<Int>, mode: PlanRunMode)
        -> PlanRunProgress {
        // The phases' shares of a run, as measured on the example plan.
        let phases: [(PlanRunProgress.Phase, share: Double, total: Int)] = [
            (.earliestAge, 0.76, ages.count), (.simulating, 0.05, runs), (.sustainableSpending, 0.14, 14),
            (.assetsNeeded, 0.04, 9), (.summarising, 0.01, 1),
        ]
        var start = 0.0
        for (index, phase) in phases.enumerated() {
            let end = index == phases.count - 1 ? 1 : start + phase.share
            if fraction < end || index == phases.count - 1 {
                let within = min(1, max(0, (fraction - start) / phase.share))
                return PlanRunProgress(phase: phase.0, completed: Int(within * Double(phase.total)), total: phase.total,
                                       fraction: fraction, ages: phase.0 == .earliestAge ? ages : nil, mode: mode)
            }
            start = end
        }
        return .starting(mode)
    }
}
