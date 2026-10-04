import Foundation
import Model
@testable import Planner
import TaxKit
import Testing

/// A target mix that changes with age (PLANNER.md, "Rebalancing"): each
/// year the taxable buckets are rebalanced, saved into and drawn from
/// toward the mix in force at that year's age, a `retirement` step follows
/// each candidate retirement age, and the switch is a taxed sale. On the
/// flat test system with no volatility, so every number is exact.
struct TargetMixTests {
    /// Born 1970-01-01: 55 on the start date, 56 in 2026, 62 in 2032.
    static func library(mix: AssetMix = [.equity: 1], balance: Decimal = 100_000) -> Library {
        Sample.library(birth: "1970-01-01", on: "2025-12-31", [SampleAccount(id: "broker", mix: mix, balance: balance)])
    }

    static func plan(retire: AgeChoice = .age(55), equityReturn: String = "0.05", gainShare: String? = nil,
                     target: AssetMix? = nil, steps: [TargetMixStep] = []) -> PlanDocument {
        var plan = Sample.plan(retire: retire, endAge: 62, retired: "0", equityReturn: equityReturn, inflation: "0",
                               unrealizedGainShare: gainShare, runs: 20)
        plan.portfolio.targetMix = target
        plan.portfolio.targetMixByAge = steps
        return plan
    }

    static func engine(_ plan: PlanDocument, _ library: Library, system: FlatTaxSystem = FlatTaxSystem(),
                       ages: [Int]? = nil) async throws -> (Engine, PlanModel) {
        let (interpreted, issues) = PlanInterpreter.interpret(
            plan: plan, library: library, registry: Sample.registry(system),
            options: PlannerOptions(maxRetirementAge: 62, solveSustainableSpending: false))
        let model = try #require(interpreted, "\(issues)")
        let ages = ages ?? [model.currentAge]
        let engine = try await Engine.make(model: model, ages: ages, maxAge: ages.max()!)
        return (engine, model)
    }

    /// The deterministic run at `age`, traced: per year, the liquid bucket's
    /// share of each class after rebalancing, and the run's years.
    static func shares(_ engine: Engine, age: Int) throws -> (shares: [[AssetClass: Double]], years: [YearDetail]) {
        let portfolio = engine.portfolio
        let liquid = try #require(portfolio.buckets.firstIndex { $0.wrapper == "flat.ordinary" })
        var simulator = engine.simulator(age: age)
        let recorder = PathRecorder()
        let (_, years) = simulator.tracedRun(nil, spending: 0, recorder: recorder)
        let classes = portfolio.classes
        let shares = recorder.years.map { year -> [AssetClass: Double] in
            let values = classes.indices.map { year.rebalancedClasses[liquid * classes.count + $0] }
            let total = values.reduce(0, +)
            var shares: [AssetClass: Double] = [:]
            for (c, value) in values.enumerated() where value > 1e-9 { shares[classes[c]] = value / total }
            return shares
        }
        return (shares, years)
    }

    static func matches(_ shares: [AssetClass: Double], _ expected: [AssetClass: Double]) -> Bool {
        Set(shares.keys).union(expected.keys).allSatisfy { abs((shares[$0] ?? 0) - (expected[$0] ?? 0)) < 1e-9 }
    }

    // MARK: Rebalancing to the mix in force

    @Test func eachYearIsRebalancedToTheMixInForceAtItsAge() async throws {
        let plan = Self.plan(target: [.equity: d("0.8"), .bonds: d("0.2")], steps: [
            TargetMixStep(fromAge: .age(58), mix: [.equity: d("0.5"), .bonds: d("0.5")]),
            TargetMixStep(fromAge: .age(60), mix: [.equity: d("0.3"), .bonds: d("0.6"), .cash: d("0.1")]),
        ])
        let (engine, model) = try await Self.engine(plan, Self.library())
        let (shares, years) = try Self.shares(engine, age: model.currentAge)
        #expect(years.map(\.age) == [56, 57, 58, 59, 60, 61, 62])
        for (year, share) in zip(years, shares) {
            let expected: [AssetClass: Double] = switch year.age {
            case ..<58: [.equity: 0.8, .bonds: 0.2]
            case ..<60: [.equity: 0.5, .bonds: 0.5]
            default: [.equity: 0.3, .bonds: 0.6, .cash: 0.1]
            }
            #expect(Self.matches(share, expected), "\(year.age): \(share)")
        }
        // The schedule says which step is in force each year.
        #expect(engine.schedules[model.currentAge]!.targetSteps == [-1, -1, 0, 0, 1, 1, 1])
        // Without tax and with equity at 5%, the value compounds the mix's return.
        let growth = [1.04, 1.04, 1.025, 1.025, 1.015, 1.015, 1.015].reduce(100_000, *)
        #expect(close(years.last?.endAssets, growth, 1e-6))
    }

    @Test func withoutATargetMixTheAccountsKeepTheirOwnMixUntilTheFirstStep() async throws {
        let plan = Self.plan(steps: [TargetMixStep(fromAge: .age(59), mix: [.bonds: 1])])
        let (engine, model) = try await Self.engine(plan, Self.library(mix: [.equity: d("0.7"), .cash: d("0.3")]))
        let (shares, years) = try Self.shares(engine, age: model.currentAge)
        for (year, share) in zip(years, shares) {
            #expect(Self.matches(share, year.age < 59 ? [.equity: 0.7, .cash: 0.3] : [.bonds: 1]), "\(year.age)")
        }
    }

    /// The year of the switch sells what the new mix doesn't want, and the
    /// sale's gain is taxed like any other; with no returns, no other year sells.
    @Test func theSwitchYearSellsAndIsTaxed() async throws {
        var system = FlatTaxSystem()
        system.gainsRate = 0.25
        let plan = Self.plan(equityReturn: "0", gainShare: "0.5",
                             steps: [TargetMixStep(fromAge: .age(58), mix: [.equity: d("0.6"), .bonds: d("0.4")])])
        let result = try await Planner.run(plan: plan, library: Self.library(), registry: Sample.registry(system),
                                           options: PlannerOptions(maxRetirementAge: 56,
                                                                   solveSustainableSpending: false))
        let years = result.expectedPath.years
        // Sell x of equity (half of it gain, taxed at 25%) so that what's left
        // is 60% of the bucket after the tax: 100,000 − x = 0.6 (100,000 − 0.125 x).
        let sold = 40_000 / 0.925
        for year in years {
            let tax = year.taxes.first { $0.id == "flat.gains" }?.amount ?? 0
            if year.age == 58 {
                #expect(close(tax, 0.125 * sold, 1e-3), "\(tax)")
            } else {
                #expect(abs(tax) < 1e-6, "\(year.age): \(tax)")
            }
        }
        #expect(close(result.expectedValue(in: 2028), 100_000 - 0.125 * sold, 1e-3))
        #expect(close(result.expectedValue(in: 2032), 100_000 - 0.125 * sold, 1e-3))
    }

    // MARK: Retirement steps

    /// A `retirement` step starts in the year of each candidate retirement
    /// age: for retiring today (55, already passed in 2026) from the first year.
    @Test func retirementStepsFollowEachCandidateAge() async throws {
        let plan = Self.plan(retire: .earliest, target: [.equity: 1], steps: [
            TargetMixStep(fromAge: .retirement, mix: [.equity: d("0.5"), .bonds: d("0.5")]),
            TargetMixStep(fromAge: .age(61), mix: [.bonds: 1]),
        ])
        let (engine, _) = try await Self.engine(plan, Self.library(), ages: [55, 58, 60, 61])
        #expect(engine.schedules[55]!.targetSteps == [0, 0, 0, 0, 0, 1, 1])
        #expect(engine.schedules[58]!.targetSteps == [-1, -1, 0, 0, 0, 1, 1])
        #expect(engine.schedules[60]!.targetSteps == [-1, -1, -1, -1, 0, 1, 1])
        // Retiring at 61, the later step starts as well and wins: the retirement step never applies.
        #expect(engine.schedules[61]!.targetSteps == [-1, -1, -1, -1, -1, 1, 1])
        let (shares, years) = try Self.shares(engine, age: 58)
        for (year, share) in zip(years, shares) {
            let expected: [AssetClass: Double] = year.age < 58 ? [.equity: 1]
                : year.age < 61 ? [.equity: 0.5, .bonds: 0.5] : [.bonds: 1]
            #expect(Self.matches(share, expected), "\(year.age): \(share)")
        }
    }

    // MARK: Assets needed to retire today

    /// The extra money of "assets needed to retire today" is split by the
    /// mix in force in the first year of retiring today.
    @Test func extraMoneyFollowsTheMixInForceToday() async throws {
        func added(_ steps: [TargetMixStep]) async throws -> [AssetClass: Double] {
            let (engine, _) = try await Self.engine(Self.plan(target: [.equity: 1], steps: steps), Self.library())
            let start = engine.startPortfolio(extra: 50_000)
            var added: [AssetClass: Double] = [:]
            for (index, lot) in start.lots.enumerated() where lot.value - engine.portfolio.lots[index].value > 1e-9 {
                added[start.classes[lot.classIndex], default: 0] += lot.value - engine.portfolio.lots[index].value
            }
            return added
        }
        // A later step doesn't apply yet; one already passed or starting at
        // retirement (today, in this scenario) does.
        #expect(Self.matches(try await added([TargetMixStep(fromAge: .age(60), mix: [.bonds: 1])]), [.equity: 50_000]))
        #expect(Self.matches(try await added([TargetMixStep(fromAge: .age(50), mix: [.bonds: 1])]), [.bonds: 50_000]))
        #expect(Self.matches(try await added([TargetMixStep(fromAge: .retirement, mix: [.bonds: 1])]),
                             [.bonds: 50_000]))
    }

    @Test func theSearchForTheAssetsNeededUsesTheMixInForceToday() async throws {
        // Retiring today on 10,000 a year, equity at 5% and bonds at 0%: with
        // all-equity until 58 the money lasts longer than with bonds from
        // retirement (today), so the second needs more.
        let library = Self.library()
        func needed(_ steps: [TargetMixStep]) async throws -> Double {
            var plan = Self.plan(target: [.equity: 1], steps: steps)
            plan.spending.retired = d("20000")
            let result = try await Planner.run(plan: plan, library: library, registry: Sample.registry(),
                                               options: PlannerOptions(maxRetirementAge: 56,
                                                                       solveSustainableSpending: false))
            return try #require(result.answer.assetsNeeded?.amount)
        }
        let equity = try await needed([])
        let bonds = try await needed([TargetMixStep(fromAge: .retirement, mix: [.bonds: 1])])
        // Seven years of 20,000 from bonds at 0% need 140,000; all-equity at 5% needs less.
        #expect(abs(bonds - 140_000) / 140_000 < 0.011, "\(bonds)")
        #expect(equity < bonds * 0.95, "\(equity) \(bonds)")
    }

    // MARK: Validation

    @Test func validationNamesTheStepsThatCantWork() throws {
        let library = Self.library()
        func issues(_ steps: [TargetMixStep]) -> [PlanIssue] {
            Planner.validate(plan: Self.plan(target: [.equity: 1], steps: steps), library: library,
                             registry: Sample.registry()).filter { $0.code.hasPrefix("planner.targetMix") }
        }
        let backwards = issues([TargetMixStep(fromAge: .age(60), mix: [.bonds: 1]),
                                TargetMixStep(fromAge: .age(58), mix: [.cash: 1])])
        #expect(backwards.map(\.code) == ["planner.targetMixAges"])
        #expect(backwards.first?.isError == true && backwards.first?.index == 1)
        #expect(backwards.first?.message == "The target mix's ages must go up: 58 comes after 60.")

        let late = issues([TargetMixStep(fromAge: .age(70), mix: [.bonds: 1])])
        #expect(late.map(\.message) == ["The target mix from 70 starts after the plan's end at 62; it never applies."])
        #expect(late.first?.isError == false && late.first?.option == "targetMixByAge")

        let total = issues([TargetMixStep(fromAge: .retirement, mix: [.bonds: d("0.5"), .equity: d("0.4")])])
        #expect(total.map(\.message) == ["The target mix from retirement adds up to 90%, not 100%; the plan scales it."])
        #expect(total.first?.index == 0)

        let empty = issues([TargetMixStep(fromAge: .age(58), mix: [:])])
        #expect(empty.map(\.code) == ["planner.targetMixEmpty"] && empty.first?.isError == true)

        let twice = issues([TargetMixStep(fromAge: .retirement, mix: [.bonds: 1]),
                            TargetMixStep(fromAge: .retirement, mix: [.cash: 1])])
        #expect(twice.map(\.code) == ["planner.targetMixRepeated"] && twice.first?.index == 0)

        // A step before today's age applies from the start: nothing to say.
        #expect(issues([TargetMixStep(fromAge: .age(40), mix: [.bonds: 1])]).isEmpty)
        let base = Planner.validate(plan: Self.plan(target: [.equity: d("0.5")]), library: library,
                                    registry: Sample.registry())
        #expect(base.map(\.message).contains("The target mix adds up to 50%, not 100%; the plan scales it."))
        // An empty target mix (every share cleared) keeps each account's own mix, and says so.
        let cleared = Planner.validate(plan: Self.plan(target: AssetMix()), library: library, registry: Sample.registry())
        #expect(cleared.filter { $0.code == "planner.targetMixEmpty" }.map(\.message)
            == ["The target mix has no asset class with a share; each ordinary account keeps its own mix."])
    }

    // MARK: Today's mix and a mix's growth

    @Test func theStartingMixSplitsOrdinaryAccountsFromTheRest() throws {
        let library = Sample.library(birth: "1970-01-01", on: "2025-12-31", [
            SampleAccount(id: "broker", mix: [.equity: d("0.75"), .cash: d("0.25")], balance: 80_000),
            SampleAccount(id: "fund", kind: .pensionFund, wrapper: "flat.pension", mix: [.bonds: 1], balance: 20_000),
            SampleAccount(id: "home", kind: .property, mix: [.realEstate: 1], balance: 300_000, includeInPlan: false),
        ])
        let mix = Planner.startingMix(plan: Self.plan(), library: library, registry: Sample.registry())
        #expect(mix.date == "2025-12-31" && mix.currency == .eur)
        #expect(mix.taxable == [.equity: 60_000, .cash: 20_000])
        #expect(mix.all == [.equity: 60_000, .cash: 20_000, .bonds: 20_000])
        #expect(mix.taxableTotal == 80_000 && mix.allTotal == 100_000)
        #expect(mix.taxableShares == [.equity: 0.75, .cash: 0.25])
        #expect(mix.allShares == [.equity: 0.6, .cash: 0.2, .bonds: 0.2])
        #expect(mix.classes == [.equity, .bonds, .cash])
    }

    @Test func aMixsGrowthIsItsReturnLessHalfItsVariance() {
        let assumptions = PlanAssumptions(returns: [
            .equity: ReturnAssumption(real: d("0.05"), volatility: d("0.2")),
            .bonds: ReturnAssumption(real: d("0.01"), volatility: 0),
        ])
        let growth = Planner.growth(of: [.equity: 0.5, .bonds: 0.5], assumptions: assumptions)
        #expect(abs(growth.expectedReturn - 0.03) < 1e-12)
        #expect(abs(growth.volatility - 0.1) < 1e-12)
        #expect(abs(growth.medianReturn - (1.03 / (1 + 0.01 / (1.03 * 1.03)).squareRoot() - 1)) < 1e-12)
        // Scaled to sum to 1; nothing grows nothing.
        #expect(Planner.growth(of: [.equity: 2, .bonds: 2], assumptions: assumptions) == growth)
        #expect(Planner.growth(of: [:], assumptions: assumptions).medianReturn == 0)
    }
}
