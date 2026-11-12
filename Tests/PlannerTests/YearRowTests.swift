import Foundation
import Model
@testable import Planner
import Testing
import TestSupport

/// Every year of the deterministic and the median path adds up (``YearRow``,
/// PLANNER.md, "The yearly step"): its cash, and its value from the year
/// before through half the year's returns, what went in and out in the
/// middle of the year, and the other half.
///
/// The returns are worked out apart from the engine. Where every class has
/// the same return and no volatility, the deterministic run grows every
/// account alike, by that return over the part of the year simulated.
/// Where every account holds equity alone, a run grows every account by
/// that run's equity draw (`MarketScenarios`), so the median path's years
/// must be one run's draws. Elsewhere a year's growth must lie between its
/// classes' lowest and highest: in the deterministic run, between their
/// lowest median and their highest mean, since a mix grows at its own
/// median.
struct YearRowTests {
    /// 200 runs, and only the ages the headline needs: the paths are what's checked.
    let options = PlannerOptions(mode: .fast(runs: 200), ageScan: .headline, solveSustainableSpending: false,
                                 solveAssetsNeeded: false)

    // MARK: The example library

    @Test(arguments: ["base", "part-time-from-50"])
    func theExampleLibrarysPathsAddUp(_ id: String) async throws {
        let library = try Fixtures.exampleLibrary()
        let plan = try #require(library.plans[PlanID(rawValue: id)])
        let result = try await Planner.run(plan: plan, library: library, options: options)
        let start = result.start.planAssets.doubleValue
        let (model, scenarios) = try scenarios(of: plan, library: library, options: options)
        let classes = model.portfolio.classes

        expectYearsAddUp(result.expectedPath, start: start, growth: .between { t in
            medianGrowth(of: classes, assumptions: plan.assumptions, fraction: model.frames[t].fraction)
        }, "\(id), deterministic")

        // The median run's own draws, class by class.
        let engine = try await Engine.make(model: model, ages: [result.focusAge], maxAge: result.focusAge)
        let run = Planner.medianRun(
            try await engine.evaluateInDetail(age: result.focusAge, spending: model.spending.retired).outcomes)
        expectYearsAddUp(result.medianPath, start: start, growth: .between { t in
            let factors = classes.indices.map { scenarios.factors[(run * scenarios.years + t) * classes.count + $0] }
            return factors.min()!...factors.max()!
        }, "\(id), median")
        #expect(result.expectedPath.years.contains { YearRow(detail: $0).sold > 0 })
        #expect(result.expectedPath.years.contains { $0.savings > 0 })
    }

    /// The example library's plans with every class at 4% and no
    /// volatility: the deterministic run grows every account by 4% a year,
    /// compounded over the part of the first year simulated.
    @Test(arguments: ["base", "part-time-from-50"])
    func theExampleLibrarysDeterministicRunAtOneReturn(_ id: String) async throws {
        let library = try Fixtures.exampleLibrary()
        var plan = try #require(library.plans[PlanID(rawValue: id)])
        plan.assumptions = Self.oneReturn(plan.assumptions, "0.04")
        let result = try await Planner.run(plan: plan, library: library, options: options)
        let path = result.expectedPath
        #expect(path.years.first.map { $0.fraction < 1 } == true)
        expectYearsAddUp(path, start: result.start.planAssets.doubleValue,
                         growth: .exactly { pow(1.04, path.years[$0].fraction) }, "\(id) at 4%")
    }

    // MARK: Made-up plans with everything

    /// Taxable money in equity, bonds and cash, a pre-tax account open now,
    /// a pre-tax pension fund from 60 and a taxable account from 62, each
    /// paid into, and a credit card the plan pays off at the start.
    static func library(allEquity: Bool = false) -> Library {
        let mix: AssetMix = allEquity ? [.equity: 1] : [.equity: d("0.7"), .bonds: d("0.3")]
        return Sample.library(birth: "1978-03-20", on: "2026-09-30", [
            SampleAccount(id: "broker", mix: mix, balance: 420_000),
            SampleAccount(id: "cash", kind: .cash, mix: allEquity ? [.equity: 1] : nil, balance: 15_000),
            SampleAccount(id: "ira", mix: mix, balance: 90_000, withdrawalTaxRate: d("0.2")),
            SampleAccount(id: "fund", kind: .pensionFund, mix: allEquity ? [.equity: 1] : [.bonds: 1],
                          balance: 60_000, availableFromAge: 60, withdrawalTaxRate: d("0.15")),
            SampleAccount(id: "later", mix: mix, balance: 30_000, availableFromAge: 62),
            SampleAccount(id: "card", kind: .creditCard, mix: nil, balance: -4_000),
        ])
    }

    /// Retiring at 56 on 40,000 a year (0.9 from 75), with flexible
    /// spending, work until then, a pension from 67, part-time income to
    /// 60, contributions, a windfall that may not come and a one-off
    /// expense, investment income taxed at 26% and a wealth tax; the target
    /// mix moves at retirement.
    static func plan(allEquity: Bool = false, flexible: Bool = true) -> PlanDocument {
        var plan = Sample.plan(
            retire: .age(56), endAge: 92, working: "38000", retired: "40000", volatility: "0.17",
            equityYield: "0.02",
            work: [Sample.work(from: "2026-01-01", net: "61000", growth: "0.01")],
            pensions: [PlanPension(name: "State pension", fromAge: 67, perYear: d("12000"))],
            income: [PlanIncome(name: "Part-time", from: .retirement, untilAge: 60, perYear: d("9000"))],
            contributions: [PlanContribution(account: "fund", perYear: d("4000")),
                            PlanContribution(account: "later", amount: d("10000"), year: 2030),
                            PlanContribution(account: "ira", perYear: d("2000"))],
            events: [PlanEvent(name: "Inheritance", timing: .age(63), amount: d("120000"), probability: d("0.7")),
                     PlanEvent(name: "Roof", timing: .year(2033), amount: d("-30000"))],
            investmentRate: "0.26", wealthRate: "0.002", wealthAllowance: "50000", unrealizedGainShare: "0.3",
            runs: 400, seed: 3)
        plan.spending.phases = [SpendingPhase(fromAge: 75, factor: d("0.9"))]
        if flexible { plan.spending.flexible = FlexibleSpending(enabled: true) }
        if allEquity {
            plan.assumptions.returns[.bonds] = nil
        } else {
            plan.assumptions.returns[.bonds] = ReturnAssumption(medianReal: d("0.015"), volatility: d("0.06"))
            plan.portfolio.targetMix = [.equity: d("0.7"), .bonds: d("0.3")]
            plan.portfolio.targetMixByAge = [TargetMixStep(fromAge: .retirement,
                                                           mix: [.equity: d("0.5"), .bonds: d("0.5")])]
        }
        return plan
    }

    /// Every class at one return with no volatility, so the deterministic
    /// run grows every account alike: the cash, the taxes, the debt and
    /// every account's money are then checked to the cent.
    @Test(arguments: [true, false])
    func aPlanWithEverythingAddsUp(flexible: Bool) async throws {
        var plan = Self.plan(flexible: flexible)
        plan.assumptions = Self.oneReturn(plan.assumptions, "0.03")
        let library = Self.library()
        let result = try await Planner.run(plan: plan, library: library, options: options)
        let path = result.expectedPath
        expectYearsAddUp(path, start: result.start.planAssets.doubleValue,
                         growth: .exactly { pow(1.03, path.years[$0].fraction) }, "deterministic")
        // The plan pays the card off from the cash at the start.
        #expect(result.start.planAssets == result.start.trackedAssets)
        #expect(result.issues.contains { $0.code == "planner.debtIncluded" })
        #expect(path.years.contains { YearRow(detail: $0).sold > 0 && $0.withdrawalTax > 0 })
        #expect(path.years.contains { $0.wealthTax > 0 && $0.investmentTax > 0 })
        #expect(path.years.contains { YearRow(detail: $0).windfalls > 0 })
        #expect(path.years.contains { $0.expenses > 0 })

        // Its median run, with the classes' own medians.
        let real = try await Planner.run(plan: Self.plan(flexible: flexible), library: library, options: options)
        let (model, scenarios) = try scenarios(of: Self.plan(flexible: flexible), library: library,
                                               options: options)
        let engine = try await Engine.make(model: model, ages: [56], maxAge: 56)
        let run = Planner.medianRun(try await engine.evaluateInDetail(age: 56, spending: 40_000).outcomes)
        let classes = model.portfolio.classes.count
        expectYearsAddUp(real.medianPath, start: real.start.planAssets.doubleValue, growth: .between { t in
            let factors = (0..<classes).map { scenarios.factors[(run * scenarios.years + t) * classes + $0] }
            return factors.min()!...factors.max()!
        }, "median")
    }

    /// With equity alone, every account grows by the run's equity draw, so
    /// both paths are checked to the cent, and the median path is the draws
    /// of one run: the median one, its spending cut along the way.
    @Test func withEquityAloneThePathsAreTheirDraws() async throws {
        let plan = Self.plan(allEquity: true)
        let library = Self.library(allEquity: true)
        let result = try await Planner.run(plan: plan, library: library, options: options)
        let (model, scenarios) = try scenarios(of: plan, library: library, options: options)
        #expect(model.portfolio.classes == [.equity])
        let start = result.start.planAssets.doubleValue

        let median = 1 + (plan.assumptions.returnAssumption(for: .equity)?.medianReturn ?? 0)
        let expected = result.expectedPath
        expectYearsAddUp(expected, start: start, growth: .exactly { pow(median, expected.years[$0].fraction) },
                         "deterministic")

        func draw(_ run: Int, _ t: Int) -> Double { scenarios.factors[run * scenarios.years + t] }
        let path = result.medianPath
        let first = try #require(path.years.first)
        // The first year ends at start × F + saved × √F: solved for √F.
        let half = (-first.savings + (first.savings * first.savings + 4 * start * first.endAssets).squareRoot())
            / (2 * start)
        let growth = half * half
        let runs = (0..<scenarios.runs).filter { abs(draw($0, 0) - growth) <= 1e-9 * growth }
        let engine = try await Engine.make(model: model, ages: [56], maxAge: 56)
        let medianRun = Planner.medianRun(try await engine.evaluateInDetail(age: 56, spending: 40_000).outcomes)
        #expect(runs == [medianRun])
        expectYearsAddUp(path, start: start, growth: .exactly { draw(medianRun, $0) }, "median")
        #expect(path.years.contains { ($0.spendingLevel ?? 1) < 1 })
    }

    /// Mostly pre-tax money and a debt larger than the taxable money: the
    /// rest of the debt comes out of the pre-tax account open now, after its
    /// tax. That tax is in the first year's tax on withdrawals, paid at the
    /// start, so the first year's cash adds up without it.
    @Test func aDebtPaidFromPreTaxMoneyAddsUp() async throws {
        let library = Sample.library(birth: "1966-05-05", on: "2026-09-30", [
            SampleAccount(id: "cash", kind: .cash, mix: nil, balance: 6_000),
            SampleAccount(id: "ira", mix: [.equity: d("0.6"), .bonds: d("0.4")], balance: 500_000,
                          withdrawalTaxRate: d("0.25")),
            SampleAccount(id: "loan", kind: .loan, mix: nil, balance: -36_000),
        ])
        var plan = Sample.plan(retire: .age(60), endAge: 95, retired: "26000", volatility: "0.17",
                               pensions: [PlanPension(name: "State pension", fromAge: 67, perYear: d("10000"))],
                               investmentRate: "0.26", runs: 300)
        plan.assumptions = Self.oneReturn(plan.assumptions, "0.02")
        let result = try await Planner.run(plan: plan, library: library, options: options)
        let first = try #require(result.expectedPath.years.first)
        // 30,000 of the loan after the cash, from money taxed at 25%: 40,000 out, 10,000 of it tax.
        #expect(abs(first.debtWithdrawalTax - 10_000) < 1e-6)
        #expect(abs(result.start.planAssets.doubleValue - (506_000 - 36_000 - 10_000)) < 0.01)
        let path = result.expectedPath
        expectYearsAddUp(path, start: result.start.planAssets.doubleValue,
                         growth: .exactly { pow(1.02, path.years[$0].fraction) }, "deterministic")
    }

    // MARK: Helpers

    /// `assumptions` with every class at `rate` a year and no volatility:
    /// a mix of them grows at `rate` too, whatever it holds.
    static func oneReturn(_ assumptions: PlanAssumptions, _ rate: String) -> PlanAssumptions {
        var changed = assumptions
        for assetClass in AssetClass.knownValues + Array(assumptions.returns.keys) {
            changed.returns[assetClass] = ReturnAssumption(real: d(rate), volatility: 0)
        }
        return changed
    }
}
