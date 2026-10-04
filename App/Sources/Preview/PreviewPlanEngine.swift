import Foundation
import Model
import Planner
import Tracker

/// A made-up plan engine for previews: plausible, smooth numbers from a few
/// formulas, so the Plan and Overview screens can be designed without
/// running the Planner. Not a simulation; never used in the app itself.
///
/// It reacts to the what-if sliders (retirement age, spending, saving,
/// equity return) the way a real engine would, roughly. Its retirement
/// years are the Planner's kind of `YearDetail` (gross income by source,
/// taxes by line, spending, savings) with made-up amounts: the plan's
/// pensions, a pension fund from 57, withdrawals, its windfalls. They go
/// through the same mapping as a Planner run (``PlanResultsMapping``), so
/// income is shown after tax with the taxes on top, in the same colours,
/// and the markers read the same. Fast and deterministic: the same request
/// gives the same results.
struct PreviewPlanEngine: PlanEngine {
    var version: String { "preview" }
    /// A pause that makes runs feel like work; `.zero` in tests.
    var delay: Duration = .milliseconds(120)

    func run(_ request: PlanRunRequest) async throws -> PlanResults {
        if delay > .zero { try await Task.sleep(for: request.mode == .fast ? delay / 10 : delay) }
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
            let fund = yearAge >= 57 && retired ? 3_000.0 : 0
            let factor = plan.spending.factor(atAge: yearAge).doubleValue
            let need = retired ? spending * factor : 0
            // Taxes on pensions and payouts, last year's wealth tax, and the tax on
            // gains withheld on what's sold, which the withdrawal pays for too.
            let incomeTax = retired ? (pension + fund) * 0.2 : 0
            let wealthTax = retired ? median * 0.002 : 0
            let withdrawal = retired ? max(0, (need + expenses + incomeTax + wealthTax - pension - fund) / 0.95) : 0
            let taxes = incomeTax + wealthTax + withdrawal * 0.05
            // What's saved: while working the plan's saving, retired the income
            // from outside the plan's accounts less spending, expenses and
            // taxes (negative while drawing down); windfalls are saved too.
            let savings = retired ? pension + received - need - expenses - taxes : saving + received - expenses
            let startAssets = median
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
            income.append(IncomeItem(kind: .payout, id: "fondo-pensione", label: "Pension fund", amount: fund))
            income += windfall.map { IncomeItem(kind: .windfall, id: $0.name, label: $0.name, amount: $0.amount) }
            retiredYears.append(YearDetail(
                year: year, age: yearAge, startAssets: startAssets, endAssets: median, spending: need,
                expenses: expenses, income: income.filter { $0.amount > 0 },
                taxes: [
                    AmountItem(id: "it.irpef", label: "IRPEF", amount: incomeTax),
                    AmountItem(id: "it.capitalGains", label: "Tax on gains", amount: withdrawal * 0.05),
                    AmountItem(id: "it.wealthTax", label: "Wealth tax", amount: wealthTax),
                ],
                savings: savings))
        }
        let registry = AppTaxRegistry.standard
        let income = PlanResultsMapping.income(retiredYears, plan: plan, registry: registry)
        let taxes = PlanResultsMapping.taxes(retiredYears)
        let spendingLine = retiredYears.map {
            YearValue(year: $0.year, value: PlanResultsMapping.whole($0.spending, $0))
        }

        var timeline = [
            TimelineMarker(kind: .retirement, year: birth.year + target, age: target, label: "Retirement"),
            TimelineMarker(kind: .accessible, year: birth.year + 57, age: 57, label: "Pension fund"),
        ]
        timeline += pensions.map {
            TimelineMarker(kind: .pensionStart, year: birth.year + $0.age, age: $0.age, label: $0.name,
                           amount: $0.perYear)
        }
        timeline += events.flatMap { year, happening in
            happening.map {
                TimelineMarker(kind: $0.amount > 0 ? .windfall : .expense, year: year, age: year - birth.year,
                               label: $0.name, amount: $0.amount)
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
            fiProgress: min(1, start.total.doubleValue / (spending * 25 * 0.75)), readiness: readiness)
        let accounts = library.accounts.values.filter { $0.includedInPlan && $0.isOpen(on: today) }.map(\.id).sorted()
        return PlanResults(
            plan: plan.id, computedAt: Date(), mode: request.mode,
            runs: request.mode == .fast ? 200 : plan.simulation.effectiveRuns, engine: version, headline: headline,
            successByAge: curve, portfolio: fan, markers: markers, income: income, taxes: taxes, spending: spendingLine,
            failure: PlanFailureSummary(share: 1 - atTarget, typicalAge: 84, bridgeShare: 0.03, bridgeAge: 57),
            start: BaselineStart(date: today, value: start.total), accounts: accounts, taxParameters: ["it": today.year],
            years: years)
    }

    private static func rounded(_ value: Double) -> Decimal {
        Decimal(wholeNumber: value)
    }

    /// The plan's pensions as the preview pays them: a fixed pension its
    /// amount from its age, a public scheme a made-up 14.200 a year from its
    /// chosen age, or 67.
    static func pensions(of plan: PlanDocument) -> [(index: Int, name: String, age: Int, perYear: Double)] {
        plan.pensions.enumerated().map { index, pension in
            let name = PlanResultsMapping.pensionName(pension, registry: AppTaxRegistry.standard)
            if pension.scheme == .fixed {
                return (index, name, pension.fromAge ?? 67, pension.perYear?.doubleValue ?? 0)
            }
            return (index, name, pension.claim?.age ?? 67, 14_200)
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
}
