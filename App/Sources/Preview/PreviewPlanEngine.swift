import Foundation
import Model
import Tracker

/// A made-up plan engine for previews: plausible, smooth numbers from a few
/// formulas, so the Plan and Overview screens can be designed before the
/// Planner lands. Not a simulation; never used in the app itself.
///
/// It reacts to the what-if sliders (retirement age, spending, saving,
/// equity return) the way a real engine would, roughly.
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
        let equity = whatIf.equityReturn?.doubleValue ?? 0.045
        let confidence = plan.simulation.effectiveConfidence.doubleValue
        let valuator = Valuator(library: library)
        let start = valuator.total(on: today, in: .planAssets)

        // Chance of success by retirement age: a logistic curve whose middle
        // moves with spending, saving, returns and the starting portfolio.
        let middle = 44 + spending / 6_000 - saving / 9_000 - start.total.doubleValue / 200_000 - (equity - 0.045) * 120
        func success(_ retirementAge: Int) -> Double {
            let raw = 1 / (1 + exp(-(Double(retirementAge) - middle) / 1.6))
            let pensionStep = retirementAge >= 67 ? 0.03 : 0
            return min(1, raw + pensionStep)
        }
        let ages = Array(max(age, 40)...70)
        let curve = ages.map { SuccessPoint(age: $0, success: success($0)) }
        let earliest = ages.first { success($0) >= confidence }
        let earliestDate = earliest.map { birth.adding(years: $0) }

        // Portfolio percentiles at each year end, in today's euros.
        let lastYear = birth.year + endAge
        var median = start.total.doubleValue
        var fan: [FanPoint] = [FanPoint(date: today.dateValue, p10: median, p25: median, p50: median, p75: median,
                                        p90: median)]
        var years: [BaselineYear] = []
        var income: [IncomeSegment] = []
        var taxes: [IncomeSegment] = []
        var spendingLine: [YearValue] = []
        for year in today.year...lastYear {
            let yearAge = year - birth.year
            let retired = yearAge >= target
            let pension = yearAge >= 67 ? 14_200.0 : 0
            let fund = yearAge >= 57 && retired ? 3_000.0 : 0
            let factor = plan.spending.factor(atAge: yearAge).doubleValue
            let need = retired ? spending * factor : 0
            let withdrawal = max(0, need - pension - fund)
            median = max(0, median * (1 + 0.6 * equity + 0.01) + (retired ? -withdrawal : saving))
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
            if retired {
                income += [
                    IncomeSegment(year: year, source: "Withdrawals", amount: withdrawal, color: .series(0)),
                    IncomeSegment(year: year, source: "INPS", amount: pension, color: .series(1)),
                    IncomeSegment(year: year, source: "Pension fund", amount: fund, color: .series(2)),
                ].filter { $0.amount > 0 }
                taxes += [
                    IncomeSegment(year: year, source: "IRPEF", amount: (pension + fund) * 0.2, color: .series(0)),
                    IncomeSegment(year: year, source: "Tax on gains", amount: withdrawal * 0.05, color: .series(1)),
                    IncomeSegment(year: year, source: "Wealth tax", amount: median * 0.002, color: .series(2)),
                ].filter { $0.amount > 0 }
                spendingLine.append(YearValue(year: year, value: need))
            }
        }

        var markers = [ChartMarker(date: birth.adding(years: target).dateValue, label: "Retire at \(target)",
                                   systemImage: "figure.walk")]
        markers.append(ChartMarker(date: birth.adding(years: 57).dateValue, label: "Pension fund 57",
                                   systemImage: "lock.open"))
        markers.append(ChartMarker(date: birth.adding(years: 67).dateValue, label: "INPS 67", systemImage: "building.columns"))
        for event in plan.events {
            let date: CalendarDate = switch event.timing {
            case .age(let eventAge): birth.adding(years: eventAge)
            case .year(let year): YearMonth(year: year, month: 1)!.firstDay
            }
            markers.append(ChartMarker(date: date.dateValue, label: event.name, systemImage: "star"))
        }

        let atTarget = success(target)
        let headline = PlanHeadline(
            confidence: confidence, earliestAge: earliest, earliestDate: earliestDate, targetAge: target,
            successAtTarget: atTarget, successToday: success(age), sustainableSpending: Self.rounded(spending * 1.07 - 900),
            fiProgress: min(1, start.total.doubleValue / (spending * 25 * 0.75)))
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
        Decimal(Int(value.rounded()))
    }
}
