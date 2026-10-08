import Foundation
import Model
@testable import Planner
import Testing
import TestSupport

/// A target mix that changes with age (PLANNER.md, "Target mix"): each year
/// the money you can draw is rebalanced, saved into and drawn from toward
/// the mix in force at that year's age, and a `retirement` step follows each
/// candidate retirement age. With no volatility, so every number is exact.
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

    static func engine(_ plan: PlanDocument, _ library: Library, ages: [Int]? = nil) async throws
        -> (Engine, PlanModel) {
        let (interpreted, issues) = PlanInterpreter.interpret(
            plan: plan, library: library,
            options: PlannerOptions(maxRetirementAge: 62, solveSustainableSpending: false))
        let model = try #require(interpreted, "\(issues)")
        let ages = ages ?? [model.currentAge]
        let engine = try await Engine.make(model: model, ages: ages, maxAge: ages.max()!)
        return (engine, model)
    }

    /// The target mix of the money you can draw in each year when retiring
    /// at `age`, by class.
    static func mixes(_ engine: Engine, age: Int) -> [[AssetClass: Double]] {
        let classes = engine.portfolio.classes
        return engine.schedules[age]!.accessibleMix.map { shares in
            var mix: [AssetClass: Double] = [:]
            for (c, share) in shares.enumerated() where share > 1e-12 { mix[classes[c]] = share }
            return mix
        }
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
        let years = model.frames.map(\.age)
        #expect(years == [56, 57, 58, 59, 60, 61, 62])
        for (age, mix) in zip(years, Self.mixes(engine, age: model.currentAge)) {
            let expected: [AssetClass: Double] = switch age {
            case ..<58: [.equity: 0.8, .bonds: 0.2]
            case ..<60: [.equity: 0.5, .bonds: 0.5]
            default: [.equity: 0.3, .bonds: 0.6, .cash: 0.1]
            }
            #expect(Self.matches(mix, expected), "\(age): \(mix)")
        }
        // With equity at 5% and the rest at 0%, the value compounds each year's mix's return.
        let result = try await Sample.run(plan, Self.library(),
                                          options: PlannerOptions(maxRetirementAge: 56, solveSustainableSpending: false))
        let growth = [1.04, 1.04, 1.025, 1.025, 1.015, 1.015, 1.015].reduce(100_000, *)
        #expect(close(result.expectedPath.years.last?.endAssets, growth, 1e-9))
    }

    @Test func withoutATargetMixTheAccountsKeepTheirOwnMixUntilTheFirstStep() async throws {
        let plan = Self.plan(steps: [TargetMixStep(fromAge: .age(59), mix: [.bonds: 1])])
        let (engine, model) = try await Self.engine(plan, Self.library(mix: [.equity: d("0.7"), .cash: d("0.3")]))
        for (age, mix) in zip(model.frames.map(\.age), Self.mixes(engine, age: model.currentAge)) {
            #expect(Self.matches(mix, age < 59 ? [.equity: 0.7, .cash: 0.3] : [.bonds: 1]), "\(age)")
        }
    }

    /// Switching the mix isn't taxed: what was paid is tracked for the money
    /// you can draw as a whole, so its share of gain doesn't change.
    @Test func theSwitchIsNotTaxed() async throws {
        var plan = Self.plan(equityReturn: "0", gainShare: "0.5",
                             steps: [TargetMixStep(fromAge: .age(58), mix: [.equity: d("0.6"), .bonds: d("0.4")])])
        plan.tax.investmentRate = d("0.25")
        let result = try await Sample.run(plan, Self.library(),
                                          options: PlannerOptions(maxRetirementAge: 56, solveSustainableSpending: false))
        #expect(result.expectedPath.years.allSatisfy { $0.taxes.isEmpty })
        #expect(close(result.expectedValue(in: 2032), 100_000))
    }

    // MARK: Retirement steps

    /// A `retirement` step starts in the year of each candidate retirement
    /// age: for retiring today (55, already passed in 2026) from the first year.
    @Test func retirementStepsFollowEachCandidateAge() async throws {
        let plan = Self.plan(retire: .earliest, target: [.equity: 1], steps: [
            TargetMixStep(fromAge: .retirement, mix: [.equity: d("0.5"), .bonds: d("0.5")]),
            TargetMixStep(fromAge: .age(61), mix: [.bonds: 1]),
        ])
        let (engine, model) = try await Self.engine(plan, Self.library(), ages: [55, 58, 60, 61])
        let ages = model.frames.map(\.age)
        func expected(retiring: Int) -> [[AssetClass: Double]] {
            ages.map { age in
                age >= 61 ? [.bonds: 1] : age >= max(retiring, 56) && retiring < 61 ? [.equity: 0.5, .bonds: 0.5]
                    : [.equity: 1]
            }
        }
        for retiring in [55, 58, 60, 61] {
            let mixes = Self.mixes(engine, age: retiring)
            #expect(zip(mixes, expected(retiring: retiring)).allSatisfy { Self.matches($0, $1) },
                    "retiring at \(retiring): \(mixes)")
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
            for (c, value) in start.buckets[0].values.enumerated()
            where value - engine.portfolio.buckets[0].values[c] > 1e-9 {
                added[start.classes[c]] = value - engine.portfolio.buckets[0].values[c]
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
            let result = try await Planner.run(plan: plan, library: library,
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
            Planner.validate(plan: Self.plan(target: [.equity: 1], steps: steps), library: library)
                .filter { $0.code.hasPrefix("planner.targetMix") }
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
        let base = Planner.validate(plan: Self.plan(target: [.equity: d("0.5")]), library: library)
        #expect(base.map(\.message).contains("The target mix adds up to 50%, not 100%; the plan scales it."))
        // An empty target mix (every share cleared) keeps the money's own mix, and says so.
        let cleared = Planner.validate(plan: Self.plan(target: AssetMix()), library: library)
        #expect(cleared.filter { $0.code == "planner.targetMixEmpty" }.map(\.message)
            == ["The target mix has no asset class with a share; the money you can draw keeps its own mix."])
    }

    // MARK: Today's mix and a mix's growth

    @Test func theStartingMixSplitsTheMoneyYouCanDrawFromTheRest() throws {
        let library = Sample.library(birth: "1970-01-01", on: "2025-12-31", [
            SampleAccount(id: "broker", mix: [.equity: d("0.75"), .cash: d("0.25")], balance: 80_000),
            SampleAccount(id: "fund", kind: .pensionFund, mix: [.bonds: 1], balance: 20_000, availableFromAge: 60),
            SampleAccount(id: "home", kind: .property, mix: [.realEstate: 1], balance: 300_000, includeInPlan: false),
        ])
        let mix = Planner.startingMix(plan: Self.plan(), library: library)
        #expect(mix.date == "2025-12-31" && mix.currency == .eur)
        #expect(mix.accessible == [.equity: 60_000, .cash: 20_000])
        #expect(mix.all == [.equity: 60_000, .cash: 20_000, .bonds: 20_000])
        #expect(mix.accessibleTotal == 80_000 && mix.allTotal == 100_000)
        #expect(mix.accessibleShares == [.equity: 0.75, .cash: 0.25])
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
