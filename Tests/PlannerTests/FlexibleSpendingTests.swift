import Foundation
import Model
@testable import Planner
import TaxKit
import Testing

/// Flexible spending (PLANNER.md, "Flexible spending"): the guardrails rule
/// cuts retirement spending when the withdrawal rate rises 20% above the
/// first retirement year's, never below the floor, and restores it when the
/// rate falls 20% below, never above 100%; a run fails only when even the
/// floor can't be paid. On the flat test system with no taxes and no
/// volatility, with market paths chosen by hand, so every number is exact.
struct FlexibleSpendingTests {
    /// Born 1966-01-01: 59 on the start date, retiring at once, funding ages
    /// 60–70 (2026–2036), every year whole.
    static func library(balance: Decimal = 100_000) -> Library {
        Sample.library(birth: "1966-01-01", on: "2025-12-31", [SampleAccount(id: "broker", balance: balance)])
    }

    static func plan(retired: String = "4000", equityReturn: String = "0", volatility: String = "0",
                     flexible: FlexibleSpending? = FlexibleSpending(), phases: [SpendingPhase] = [],
                     runs: Int = 50) -> PlanDocument {
        var plan = Sample.plan(retire: .age(59), endAge: 70, retired: retired, equityReturn: equityReturn,
                               volatility: volatility, inflation: "0", runs: runs)
        plan.spending.flexible = flexible
        plan.spending.phases = phases
        return plan
    }

    static func engine(_ plan: PlanDocument, _ library: Library = library()) async throws -> (Engine, PlanModel) {
        let (interpreted, issues) = PlanInterpreter.interpret(
            plan: plan, library: library, registry: Sample.registry(),
            options: PlannerOptions(maxRetirementAge: 62, solveSustainableSpending: false))
        let model = try #require(interpreted, "\(issues)")
        let engine = try await Engine.make(model: model, ages: [model.currentAge], maxAge: model.currentAge)
        return (engine, model)
    }

    /// Run 0 of the plan with equity's yearly factors given, traced.
    static func trace(_ plan: PlanDocument, equity: [Double], library: Library = library()) async throws
        -> (outcome: RunOutcome, years: [YearDetail], steps: [FlexibleStep?]) {
        let (engine, model) = try await engine(plan, library)
        let portfolio = engine.portfolio
        let classes = portfolio.classCount
        let column = try #require(portfolio.classes.firstIndex(of: .equity))
        var factors = [Double](repeating: 1, count: equity.count * classes)
        for (t, factor) in equity.enumerated() { factors[t * classes + column] = factor }
        let scenarios = MarketScenarios(factors: factors, expectedFactors: factors, runs: 1, years: equity.count,
                                        classes: classes)
        var simulator = PathSimulator(schedule: engine.schedules[model.currentAge]!, scenarios: scenarios,
                                      portfolio: portfolio, model: model, flexible: engine.flexibleSpending)
        let recorder = PathRecorder()
        let (outcome, years) = simulator.tracedRun(0, spending: model.spending.retired, recorder: recorder)
        // The traced run ends as the same run untraced.
        let untraced = simulator.run(0, spending: model.spending.retired)
        #expect(untraced.failedYear == outcome.failedYear && untraced.finalValue == outcome.finalValue)
        return (outcome, years, recorder.years.map(\.flexible))
    }

    /// A crash in the first year, two flat years, a recovery, then flat.
    static let crash: [Double] = [0.6, 1, 1, 2.5, 1, 1, 1, 1, 1, 1, 1]

    static func same(_ values: [Double], _ expected: [Double]) -> Bool {
        values.count == expected.count && zip(values, expected).allSatisfy { abs($0 - $1) < 1e-6 }
    }

    // MARK: The rule, year by year

    @Test func aCrashCutsToTheFloorAndARecoveryRestoresIt() async throws {
        let (outcome, years, steps) = try await Self.trace(Self.plan(), equity: Self.crash)
        // 2026: 4,000 of 100,000 is the first rate, 4%; the crash leaves 57,600.
        // 2027: 4,000 / 57,600 = 6.9% > 4.8%: cut to 90%. 2028: 3,600 / 54,000 = 6.7%: cut to 80%, the floor.
        // 2029: 3,200 / 50,800 = 6.3%: a cut is due at the floor. ×2.5 → 119,000.
        // 2030: 3,200 / 119,000 = 2.7% < 3.2%: raised to 90%. 2031: 3,600 / 115,400 = 3.1%: back to 100%.
        // Then 4,000 / 111,400 = 3.6% and later rates stay between the guardrails: no raise above 100%.
        #expect(Self.same(years.map(\.spending), [4000, 3600, 3200, 3200, 3600, 4000, 4000, 4000, 4000, 4000, 4000]))
        #expect(steps.map { $0?.action } == ["start", "cut", "cut", "floor", "raise", "raise", "hold", "hold", "hold",
                                              "hold", "hold"])
        #expect(Self.same(years.compactMap(\.spendingLevel), [1, 0.9, 0.8, 0.8, 0.9, 1, 1, 1, 1, 1, 1]))
        #expect(Self.same(years.compactMap(\.plannedSpending), Array(repeating: 4000, count: 11)))
        let first = try #require(steps[0])
        #expect(abs((first.initialRate ?? 0) - 0.04) < 1e-12 && abs(first.assets - 100_000) < 1e-6)
        let second = try #require(steps[1])
        #expect(abs((second.rate ?? 0) - 4000.0 / 57_600) < 1e-12 && abs(second.draw - 4000) < 1e-9)
        #expect(close(years[3].endAssets, 119_000))
        #expect(outcome.failure == nil)
        #expect(outcome.lowestLevel == 0.8 && outcome.yearsBelowPlan == 4)
        #expect(close(outcome.finalValue, 111_400 - 5 * 4000))
    }

    @Test func withoutTheRuleTheSameCrashSpendsThePlansAmount() async throws {
        let (outcome, years, steps) = try await Self.trace(Self.plan(flexible: nil), equity: Self.crash)
        #expect(Self.same(years.map(\.spending), Array(repeating: 4000, count: 11)))
        #expect(years.allSatisfy { $0.spendingLevel == nil && $0.plannedSpending == nil })
        #expect(steps.allSatisfy { $0 == nil })
        #expect(outcome.lowestLevel == 1 && outcome.yearsBelowPlan == 0)
        // So is a rule that's switched off.
        let off = try await Self.trace(Self.plan(flexible: FlexibleSpending(enabled: false, cut: d("0.2"))),
                                       equity: Self.crash)
        #expect(off.years == years)
    }

    @Test func phasesScaleWithTheLevel() async throws {
        // 75% of the spending from 62 (2028): the level and the phase multiply.
        let plan = Self.plan(phases: [SpendingPhase(fromAge: 62, factor: d("0.75"))])
        let (_, years, steps) = try await Self.trace(plan, equity: Self.crash)
        // 2028: 0.9 × 0.75 × 4,000 = 2,700 of 54,000 is 5% > 4.8%: cut to 80%, so 0.8 × 0.75 × 4,000 = 2,400.
        // 2029: 2,400 / 51,600 = 4.65%: holds. ×2.5 → 123,000. 2030: 2,400 / 123,000 = 2.0%: raised to 90%.
        #expect(Self.same(Array(years.map(\.spending).prefix(5)), [4000, 3600, 2400, 2400, 2700]))
        #expect(Array(steps.prefix(5)).map { $0?.action } == ["start", "cut", "cut", "hold", "raise"])
        #expect(Self.same(Array(years.compactMap(\.plannedSpending).prefix(3)), [4000, 4000, 3000]))
    }

    @Test func customStepsAndGuardrails() async throws {
        // Cuts of 25% down to 50%, with guardrails of 50% above and 10% below.
        let rule = FlexibleSpending(cut: d("0.25"), floor: d("0.5"), upperGuardrail: d("0.5"), lowerGuardrail: d("0.1"))
        let (_, years, steps) = try await Self.trace(Self.plan(flexible: rule), equity: Self.crash)
        // 2027: 6.9% > 6%: cut to 75% (3,000). 2028: 3,000 / 54,600 = 5.5%: holds.
        #expect(Self.same(Array(years.map(\.spending).prefix(3)), [4000, 3000, 3000]))
        #expect(Array(steps.prefix(3)).map { $0?.action } == ["start", "cut", "hold"])
    }

    // MARK: Failure means spending below the floor

    @Test func moneyRunningShortForcesSpendingDownToTheFloorFirst() async throws {
        // 11,500 at 0%, 3,000 a year, guardrails too wide to cut: 2029 has
        // 2,500 left, which is above the floor of 2,400, so spending is forced
        // down to it instead of failing; 2030 has nothing.
        let rule = FlexibleSpending(upperGuardrail: 10)
        let library = Self.library(balance: 11_500)
        let flat = Array(repeating: 1.0, count: 11)
        let (outcome, years, steps) = try await Self.trace(Self.plan(retired: "3000", flexible: rule), equity: flat,
                                                           library: library)
        #expect(outcome.failure?.year == 2030 && outcome.failure?.reason == .depleted)
        #expect(Self.same(Array(years.map(\.spending).prefix(4)), [3000, 3000, 3000, 2500]))
        let forced = try #require(steps[3])
        #expect(forced.level == 1 && abs(forced.paidLevel - 2500.0 / 3000) < 1e-12)
        #expect(outcome.lowestLevel == 0)
        #expect(outcome.yearsBelowPlan == 8, "2029 forced down, then 2030–2036 from the failure on")
        // Spending fixed in real terms fails a year earlier.
        let fixed = try await Self.trace(Self.plan(retired: "3000", flexible: nil), equity: flat, library: library)
        #expect(fixed.outcome.failure?.year == 2029)
    }

    @Test func aRunFailsWhenEvenTheFloorCantBePaid() async throws {
        // 20,000 at 0%, 4,000 a year: cuts to 3,600 and 3,200, then the floor
        // runs out in 2031 with 2,800 left.
        let flat = Array(repeating: 1.0, count: 11)
        let (outcome, years, steps) = try await Self.trace(Self.plan(), equity: flat,
                                                           library: Self.library(balance: 20_000))
        #expect(Self.same(Array(years.map(\.spending).prefix(5)), [4000, 3600, 3200, 3200, 3200]))
        #expect(outcome.failure == RunFailure(year: 2031, age: 65, reason: .depleted))
        #expect(steps[5]?.level == 0.8)
        #expect(outcome.lowestLevel == 0)
    }

    // MARK: Results and searches

    @Test func theResultSummarisesCutsAcrossRuns() async throws {
        // −3% a year with no volatility: every run is the deterministic one.
        let result = try await Sample.run(Self.plan(equityReturn: "-0.03"), Self.library())
        let summary = try #require(result.flexibleSpending)
        let levels = result.expectedPath.years.compactMap(\.spendingLevel)
        #expect(levels.count == 11 && levels.first == 1 && levels.last == 0.8)
        let below = levels.filter { $0 < 1 - 1e-9 }.count
        #expect(below > 0)
        #expect(summary.age == 59 && summary.retirementYears == 11 && summary.runs == 50)
        #expect(summary.cut == 0.1 && summary.floor == 0.8 && summary.upperGuardrail == 0.2)
        #expect(summary.shareWithCut == 1 && summary.failureRate == 0)
        #expect(summary.medianLowestLevel == 0.8 && summary.p10LowestLevel == 0.8)
        #expect(summary.p10LowestSpending == 3200 && summary.floorSpending == 3200)
        #expect(summary.medianYearsBelow == below && summary.p90YearsBelow == below)
        #expect(abs(summary.medianShareBelow - Double(below) / 11) < 1e-12)
        // The yearly percentiles of the spending paid follow the deterministic run.
        let spending = result.fan.compactMap(\.spending)
        #expect(spending.count == result.fan.count)
        for (year, percentiles) in zip(result.expectedPath.years, spending) {
            #expect(abs(percentiles.p10 - year.spending) < 1e-6 && abs(percentiles.p90 - year.spending) < 1e-6)
        }
        // Without the rule there's no summary and no spending percentiles.
        let fixed = try await Sample.run(Self.plan(equityReturn: "-0.03", flexible: nil), Self.library())
        #expect(fixed.flexibleSpending == nil && fixed.fan.allSatisfy { $0.spending == nil })
    }

    @Test func nothingChangesWhenTheRuleIsOff() async throws {
        let library = Self.library()
        let fixed = try await Sample.run(Self.plan(equityReturn: "0.03", volatility: "0.17", flexible: nil), library)
        let off = try await Sample.run(Self.plan(equityReturn: "0.03", volatility: "0.17",
                                                 flexible: FlexibleSpending(enabled: false, floor: d("0.5"))), library)
        #expect(off.answer == fixed.answer && off.successCurve == fixed.successCurve && off.fan == fixed.fan)
        #expect(off.expectedPath == fixed.expectedPath && off.medianPath == fixed.medianPath)
        #expect(off.failures == fixed.failures && off.flexibleSpending == nil)
    }

    @Test func everySearchUsesTheRule() async throws {
        // Without taxes, the rule never spends more than the plan, so every
        // run that succeeds without it succeeds with it, at every age and amount.
        let library = Sample.library(birth: "1980-01-01", on: "2025-12-31", [SampleAccount(id: "broker", balance: 300_000)])
        func plan(_ flexible: FlexibleSpending?) -> PlanDocument {
            var plan = Sample.plan(retire: .age(55), endAge: 90, working: "30000", retired: "20000",
                                   equityReturn: "0.05", volatility: "0.17",
                                   work: [Sample.employee(from: "2026-01-01", gross: "60000")], inflation: "0",
                                   runs: 300)
            plan.spending.flexible = flexible
            return plan
        }
        let options = PlannerOptions(maxRetirementAge: 62)
        let fixed = try await Sample.run(plan(nil), library, options: options)
        let flexible = try await Sample.run(plan(FlexibleSpending()), library, options: options)
        for (with, without) in zip(flexible.successCurve, fixed.successCurve) {
            #expect(with.age == without.age && with.success >= without.success, "\(with.age)")
        }
        #expect(zip(flexible.successCurve, fixed.successCurve).contains { $0.success > $1.success })
        let earliest = try #require(flexible.answer.earliestAge)
        #expect(earliest <= fixed.answer.earliestAge ?? .max)
        let spending = try #require(flexible.answer.sustainableSpending)
        let fixedSpending = try #require(fixed.answer.sustainableSpending)
        #expect(spending.age == fixedSpending.age && spending.perYear > fixedSpending.perYear)
        #expect(spending.success >= flexible.settings.confidence)
        let needed = try #require(flexible.answer.assetsNeeded?.amount)
        let fixedNeeded = try #require(fixed.answer.assetsNeeded?.amount)
        #expect(needed < fixedNeeded)
        #expect(flexible.flexibleSpending?.age == flexible.focusAge)
    }

    // MARK: Checks

    @Test func settingsOutOfRangeAreErrors() {
        let library = Self.library()
        for rule in [FlexibleSpending(cut: 0), FlexibleSpending(cut: d("1.5")), FlexibleSpending(floor: d("-0.1")),
                     FlexibleSpending(floor: d("1.2")), FlexibleSpending(upperGuardrail: d("-0.2")),
                     FlexibleSpending(lowerGuardrail: d("1.5"))] {
            let issues = Planner.validate(plan: Self.plan(flexible: rule), library: library, registry: Sample.registry())
            #expect(issues.contains { $0.isError && $0.code == "planner.flexibleSpending" && $0.section == .spending },
                    "\(rule)")
        }
        // Off, its settings aren't checked; the defaults are fine.
        let off = Planner.validate(plan: Self.plan(flexible: FlexibleSpending(enabled: false, cut: 0)),
                                   library: library, registry: Sample.registry())
        #expect(!off.contains { $0.code == "planner.flexibleSpending" })
        let defaults = Planner.validate(plan: Self.plan(), library: library, registry: Sample.registry())
        #expect(!defaults.contains { $0.isError })
    }
}
