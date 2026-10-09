import Foundation
import Model
import Planner
import Tracker

/// A made-up plan engine for previews: plausible, smooth numbers from a few
/// formulas, so the Plan and Overview screens can be designed without
/// running the Planner (a full run takes about a minute in a Debug build).
/// Not a simulation; never used in the app itself.
///
/// It reacts to the what-if sliders (retirement age, spending, saving,
/// equity return) the way a real engine would, roughly. Its retirement
/// years are the Planner's kind of `YearDetail` (gross income by source,
/// the two taxes, spending, savings) with made-up amounts: the plan's
/// pensions, withdrawals, its windfalls. They go
/// through the same mapping as a Planner run (``PlanResultsMapping``), so
/// income is shown after tax with the taxes on top, in the same colours,
/// and the markers read the same. The details the Planner adds are made up
/// too (key numbers, the what-if's saving, a warning, the headline to
/// record), so every card has something to show, and a run asked for its
/// progress reports made-up progress through the Planner's phases, so the
/// progress view does too. Deterministic: the same request gives the same
/// results.
struct PreviewPlanEngine: PlanEngine {
    var version: String { "preview" }
    /// How long a run takes (a quick estimate a tenth of it). A run
    /// reporting its progress pretends to take about 20 times this (a quick
    /// estimate 5 times); `.zero` reports every step at once.
    var delay: Duration = .milliseconds(60)

    func run(_ request: PlanRunRequest, progress: PlanProgressHandler? = nil) async throws -> PlanResults {
        if let progress {
            try await Self.pretendToRun(request, delay: delay, report: progress)
        } else if delay > .zero {
            try await Task.sleep(for: request.mode == .fast ? delay / 10 : delay)
        }
        try Task.checkCancellation()
        let plan = request.plan
        let library = request.library
        guard let birth = library.settings.person?.birthDate else {
            throw PlanEngineError.invalidPlan("Add your birth date in Settings to run a plan.")
        }
        let today = request.asOf
        let age = birth.wholeYears(to: today)
        let whatIf = request.whatIf ?? PlanWhatIf()
        let target = whatIf.retirementAge ?? plan.retirement.age.age ?? 55
        let endAge = plan.effectiveEndAge
        let spending = (whatIf.retiredSpending ?? plan.spending.retired).doubleValue
        let saving = whatIf.monthlySaving.map { $0.doubleValue * 12 } ?? 18_000
        // Equity's typical year, as the what-if slider moves it.
        let planEquity = plan.assumptions.returnAssumption(for: .equity)?.medianReturn ?? 0.05
        let equity = whatIf.equityReturn?.doubleValue ?? planEquity
        let confidence = plan.simulation.effectiveConfidence.doubleValue
        let valuator = Valuator(library: library)
        let start = valuator.total(on: today, in: .planAssets)

        // Chance of success by retirement age: a logistic curve whose middle
        // moves with spending, saving, returns and the starting portfolio.
        let middle = 44 + spending / 6_000 - saving / 9_000 - start.total.doubleValue / 200_000
            - (equity - planEquity) * 120
        func success(_ retirementAge: Int) -> Double {
            let raw = 1 / (1 + exp(-(Double(retirementAge) - middle) / 1.6))
            let pensionStep = retirementAge >= 67 ? 0.03 : 0
            return min(1, raw + pensionStep)
        }
        let ages = Array(max(age, 40)...70)
        let curve = ages.map { SuccessPoint(age: $0, success: success($0)) }
        let earliest = ages.first { success($0) >= confidence }
        let earliestDate = earliest.map { birth.adding(years: $0) }

        // Portfolio percentiles at each year end, in today's euros, and the
        // retirement years in the Planner's terms.
        let lastYear = birth.year + endAge
        let pensions = Self.pensions(of: plan)
        let events = Self.events(of: plan, birthYear: birth.year)
        var median = start.total.doubleValue
        var fan: [FanPoint] = [FanPoint(date: today.dateValue, p10: median, p25: median, p50: median, p75: median,
                                        p90: median)]
        var years: [BaselineYear] = []
        var retiredYears: [YearDetail] = []
        for year in today.year...lastYear {
            let yearAge = year - birth.year
            let retired = yearAge >= target
            let windfall = events[year]?.filter { $0.amount > 0 } ?? []
            let received = windfall.reduce(0) { $0 + $1.amount }
            let expenses = -(events[year]?.filter { $0.amount < 0 }.reduce(0) { $0 + $1.amount } ?? 0)
            let started = pensions.filter { yearAge >= $0.age }
            let pension = started.reduce(0) { $0 + $1.perYear }
            let factor = plan.spending.factor(atAge: yearAge).doubleValue
            let need = retired ? spending * factor : 0
            // The wealth tax, and the tax on the gains in what's sold, which the
            // withdrawal pays for too. Pensions are after tax.
            let wealthTax = retired ? median * 0.002 : 0
            let withdrawal = retired ? max(0, (need + expenses + wealthTax - pension) / 0.95) : 0
            let taxes = wealthTax + withdrawal * 0.05
            // What's saved: while working the plan's saving, retired the income
            // from outside the plan's accounts less spending, expenses and
            // taxes (negative while drawing down); windfalls are saved too.
            let savings = retired ? pension + received - need - expenses - taxes : saving + received - expenses
            median = max(0, median * (1 + 0.6 * equity + 0.01) + savings)
            let spread = 0.11 * Double(year - today.year + 1).squareRoot()
            let point = FanPoint(
                date: YearMonth(year: year, month: 12)!.lastDay.dateValue,
                p10: median * exp(-1.28 * spread), p25: median * exp(-0.67 * spread), p50: median,
                p75: median * exp(0.67 * spread), p90: median * exp(1.28 * spread))
            fan.append(point)
            years.append(BaselineYear(
                year: year, expected: Self.rounded(median * 1.02), p10: Self.rounded(point.p10),
                p25: Self.rounded(point.p25), p50: Self.rounded(point.p50), p75: Self.rounded(point.p75),
                p90: Self.rounded(point.p90), savings: retired ? nil : Self.rounded(saving)))
            guard retired else { continue }
            var income = [IncomeItem(kind: .withdrawal, id: "withdrawals", label: "Withdrawals", amount: withdrawal)]
            income += started.map {
                IncomeItem(kind: .pension, id: "pension-\($0.index)", label: $0.name, amount: $0.perYear)
            }
            income += windfall.map { IncomeItem(kind: .windfall, id: $0.name, label: $0.name, amount: $0.amount) }
            retiredYears.append(YearDetail(
                year: year, age: yearAge, endAssets: median, spending: need,
                expenses: expenses, income: income.filter { $0.amount > 0 },
                investmentTax: withdrawal * 0.05, wealthTax: wealthTax, savings: savings))
        }
        let income = PlanResultsMapping.income(retiredYears)
        let taxes = PlanResultsMapping.taxes(retiredYears)
        let spendingLine = retiredYears.map {
            YearValue(year: $0.year, value: PlanResultsMapping.whole($0.spending, $0))
        }

        var timeline = [
            TimelineMarker(kind: .retirement, year: birth.year + target, age: target, label: "Retirement"),
            TimelineMarker(kind: .accessible, year: birth.year + 67, age: 67, label: "Fondo pensione"),
        ]
        timeline += pensions.map {
            TimelineMarker(kind: .pensionStart, year: birth.year + $0.age, age: $0.age, label: $0.name)
        }
        timeline += events.flatMap { year, happening in
            happening.map {
                TimelineMarker(kind: $0.amount > 0 ? .windfall : .expense, year: year, age: year - birth.year,
                               label: $0.name)
            }
        }
        timeline.sort { ($0.year, $0.label) < ($1.year, $1.label) }
        let markers = PlanResultsMapping.markers(timeline, birthDate: birth,
                                                 retirementDate: birth.adding(years: target))

        let atTarget = success(target)
        let successNow = success(age)
        // What retiring today needs: decades of spending before the pensions, after tax.
        let readiness = successNow >= confidence ? max(1, start.total.doubleValue / (spending * 30))
            : min(0.99, start.total.doubleValue / (spending * 34))
        let headline = PlanHeadline(
            confidence: confidence, earliestAge: earliest, earliestDate: earliestDate, targetAge: target,
            successAtTarget: atTarget, successToday: successNow, sustainableSpending: Self.rounded(spending * 1.07 - 900),
            readiness: readiness)
        let accounts = library.accounts.values.filter { $0.includedInPlan && $0.isOpen(on: today) }.map(\.id).sorted()

        // What the Planner adds, for the age the charts are for (the fan
        // above stays the target age's).
        let focusAge = request.focusAge ?? whatIf.retirementAge ?? plan.retirement.age.age ?? earliest ?? 55
        let planHash = Planner.planHash(plan)
        let details = PlanResultDetails(
            planHash: planHash, currentAge: age, endAge: endAge,
            assetsNeeded: AssetsNeeded(age: age, outcome: .found, scale: 1 / readiness,
                                       amount: start.total.doubleValue / readiness, success: confidence,
                                       readiness: readiness),
            sustainableSpendingAge: target,
            issues: [PlanIssue(.warning, code: "planner.noAssetMix",
                               message: "TFR has no asset mix (assetClasses); the plan treats it as cash.",
                               section: .portfolio, account: "tfr")],
            focus: PlanFocusDetails(
                age: focusAge, retirementDate: birth.adding(years: focusAge),
                success: curve.first { $0.age == focusAge }?.success,
                medianAtRetirement: years.first { $0.year == birth.year + focusAge }?.p50.doubleValue,
                medianAtEnd: years.last?.p50.doubleValue,
                lifetimeTaxes: taxes.reduce(0) { $0 + $1.amount } + 180_000,
                monthlySaving: Decimal((whatIf.monthlySaving ?? 1_500).doubleValue.rounded()),
                bridges: [PlanBridgeFailure(name: "Fondo pensione", accessibleFromAge: 67, share: 0.03)]),
            headline: Headline(
                date: today, confidence: Self.recorded(confidence), earliestAge: earliest, engine: version,
                planHash: planHash, readiness: Planner.recordedReadiness(readiness),
                successAtTarget: Self.recorded(atTarget)))
        return PlanResults(
            plan: plan.id, computedAt: Date(), mode: request.mode,
            runs: request.mode == .fast ? 200 : plan.simulation.effectiveRuns, engine: version, headline: headline,
            successByAge: curve, portfolio: fan, markers: markers, income: income, taxes: taxes, spending: spendingLine,
            start: BaselineStart(date: today, value: start.total), accounts: accounts, years: years,
            details: details, currency: library.settings.baseCurrency)
    }

    private static func rounded(_ value: Double) -> Decimal {
        Decimal(wholeNumber: value)
    }

    /// A chance as headlines record it, to 3 decimals.
    private static func recorded(_ value: Double) -> Decimal {
        Decimal(wholeNumber: value * 1_000) / 1_000
    }

    /// The plan's pensions as the preview pays them: each its amount from its age.
    static func pensions(of plan: PlanDocument) -> [(index: Int, name: String, age: Int, perYear: Double)] {
        plan.pensions.enumerated().map { index, pension in
            let name = plan.pensionName(index)
            return (index, name, pension.fromAge ?? 67, pension.perYear?.doubleValue ?? 0)
        }
    }

    /// The plan's events in the deterministic run (likely enough to count),
    /// by year: positive amounts are windfalls, negative ones expenses.
    static func events(of plan: PlanDocument, birthYear: Int) -> [Int: [(name: String, amount: Double)]] {
        var byYear: [Int: [(name: String, amount: Double)]] = [:]
        for event in plan.events where event.isInDeterministicRun {
            let year = switch event.timing {
            case .age(let age): birthYear + age
            case .year(let year): year
            }
            byYear[year, default: []].append((event.name, event.amount.doubleValue))
        }
        return byYear
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
        let phases: [(PlannerProgress.Phase, share: Double, total: Int)] = [
            (.earliestAge, 0.76, ages.count), (.simulating, 0.05, runs), (.sustainableSpending, 0.14, 14),
            (.assetsNeeded, 0.04, 9), (.summarising, 0.01, 1),
        ]
        var start = 0.0
        for (index, phase) in phases.enumerated() {
            let end = index == phases.count - 1 ? 1 : start + phase.share
            if fraction < end || index == phases.count - 1 {
                let within = min(1, max(0, (fraction - start) / phase.share))
                return PlanRunProgress(mode: mode, planner: PlannerProgress(
                    phase: phase.0, completed: Int(within * Double(phase.total)), total: phase.total,
                    fraction: fraction, ages: phase.0 == .earliestAge ? ages : nil, runs: runs))
            }
            start = end
        }
        return .starting(mode)
    }
}
