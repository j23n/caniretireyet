import Foundation
import Model
@testable import Planner
import TaxGeneric
import TaxKit
import Testing

/// What retiring today would need (PLANNER.md, "Assets needed to retire
/// today"): the plan assets that make retiring at today's age reach the
/// confidence level, found by scaling the starting portfolio, and readiness,
/// today's plan assets over that. On the generic flat-rate system.
struct AssetsNeededTests {
    static let registry = TaxRegistry([GenericTaxSystem()])

    /// Born 1986-01-01, 39 on the start date: the simulation runs 2026
    /// (40) to 2046 (60), 21 whole years.
    func library(_ balance: Decimal, kind: AccountKind = .brokerage, mix: AssetMix? = [.equity: 1],
                 wrapper: WrapperID = "taxable") -> Library {
        Sample.library(birth: "1986-01-01", on: "2025-12-31",
                       [SampleAccount(id: "broker", kind: kind, wrapper: wrapper, mix: mix, balance: balance)])
    }

    /// Retiring today on 30,000 a year to 60, with generic flat taxes.
    func plan(retired: String = "30000", equityReturn: String = "0.03", volatility: String = "0.15",
              pensions: [PlanPension] = [], capitalGainsRate: String = "0.25", wealthTaxRate: String = "0.001",
              runs: Int = 200) -> PlanDocument {
        var plan = Sample.plan(retire: .earliest, endAge: 60, retired: retired, equityReturn: equityReturn,
                               volatility: volatility, pensions: pensions, inflation: "0", unrealizedGainShare: "0.3",
                               runs: runs)
        plan.tax = PlanTax(residence: [PlanResidence(from: 2026, system: "generic", options: [
            "incomeTaxRate": "0.2", "capitalGainsRate": .string(capitalGainsRate), "wealthTaxRate": .string(wealthTaxRate),
        ])])
        return plan
    }

    let options = PlannerOptions(maxRetirementAge: 45, solveSustainableSpending: false)

    func run(_ plan: PlanDocument, _ library: Library, options: PlannerOptions? = nil) async throws -> PlanResult {
        try await Planner.run(plan: plan, library: library, registry: Self.registry, options: options ?? self.options)
    }

    // MARK: Closed form

    @Test func withoutVolatilityItIsTheMoneyTheYearsTake() async throws {
        // Cash earning nothing, no tax on it: retiring today takes 21 × 30,000.
        let library = library(150_000, kind: .cash, mix: nil)
        let result = try await run(plan(volatility: "0", capitalGainsRate: "0", wealthTaxRate: "0"), library)
        let needed = try #require(result.answer.assetsNeeded)

        #expect(needed.outcome == .found)
        #expect(needed.age == 39)
        let amount = try #require(result.answer.assetsNeededToday)
        #expect(amount >= 630_000 - 1 && amount <= 630_000 * (1 + AssetsNeeded.tolerance), "\(amount)")
        #expect(close(needed.scale, amount / 150_000))
        #expect(close(result.answer.readiness, 150_000 / amount))
        #expect(needed.success == 1)
        #expect(!result.answer.canRetireNow && result.answer.successIfRetiringNow == 0)
        // The old rule of thumb thought this was 20% of the way (30,000 / 4% = 750,000).
        #expect(close(result.answer.fiProgress, 0.2))
    }

    // MARK: The search

    @Test func moreMoneyNeverLowersTheChance() async throws {
        let library = library(400_000)
        let plan = plan()
        let (interpreted, _) = PlanInterpreter.interpret(plan: plan, library: library, registry: Self.registry,
                                                         options: options)
        let model = try #require(interpreted)
        let age = model.currentAge
        let engine = try await Engine.make(model: model, ages: [age], maxAge: age)
        var rates: [Double] = []
        for scale in [0.25, 0.5, 0.8, 1, 1.25, 1.6, 2, 3, 5] {
            var simulator = engine.simulator(age: age, start: engine.portfolio.scaled(by: scale))
            let successes = (0..<model.runs).filter { simulator.run($0, spending: model.spending.retired).failure == nil }
            rates.append(Double(successes.count) / Double(model.runs))
        }
        #expect(rates == rates.sorted(), "\(rates)")
        #expect(rates.first! < 0.9 && rates.last! >= 0.9)

        // Scale 1 is the scan's own result for today.
        let result = try await run(plan, library)
        #expect(result.answer.successIfRetiringNow == rates[3])
    }

    @Test func theAmountFoundReachesTheConfidenceAndOnePerCentLessDoesNot() async throws {
        let start: Decimal = 400_000
        let result = try await run(plan(), library(start))
        let needed = try #require(result.answer.assetsNeeded)
        #expect(needed.outcome == .found)
        let scale = try #require(needed.scale)
        #expect(scale > 1)
        #expect(try #require(needed.success) >= 0.9)
        let readiness = try #require(result.answer.readiness)
        #expect(readiness < 1 && !result.answer.canRetireNow)

        // Starting with that much, retiring today reaches the confidence level;
        // starting with 2% less (beyond the 1% tolerance), it doesn't.
        let enough = try await run(plan(), library(start * Decimal(scale)))
        #expect(enough.answer.successIfRetiringNow >= 0.9)
        #expect(enough.answer.canRetireNow)
        let short = try await run(plan(), library(start * Decimal(scale / 1.02)))
        #expect(short.answer.successIfRetiringNow < 0.9)
    }

    @Test func pastOneHundredPercentYouCanRetireToday() async throws {
        let result = try await run(plan(), library(3_000_000))
        let needed = try #require(result.answer.assetsNeeded)
        #expect(result.answer.canRetireNow)
        #expect(needed.outcome == .found)
        #expect(try #require(needed.scale) <= 1)
        #expect(try #require(result.answer.readiness) >= 1)
        #expect(try #require(result.answer.assetsNeededToday) <= 3_000_000)
        #expect(try #require(needed.success) >= 0.9)
        // A recorded 1 or more means retiring today works.
        #expect(try #require(result.headline().readiness) >= 1)
    }

    @Test func readinessReachesOneExactlyWhenRetiringTodayDoes() async throws {
        for balance: Decimal in [200_000, 600_000, 900_000, 1_200_000] {
            let result = try await run(plan(runs: 100), library(balance))
            let readiness = try #require(result.answer.readiness)
            #expect((readiness >= 1) == result.answer.canRetireNow, "\(balance): \(readiness)")
            let recorded = try #require(result.headline().readiness)
            #expect((recorded >= 1) == result.answer.canRetireNow, "\(balance): recorded \(recorded)")
        }
    }

    // MARK: The limits

    @Test func moreThanTheMaximumHasNoAmount() async throws {
        // 1,000 for 21 years of 30,000: hundreds of times what there is.
        let result = try await run(plan(), library(1_000))
        let needed = try #require(result.answer.assetsNeeded)
        #expect(needed.outcome == .moreThanMaximum)
        #expect(needed.scale == AssetsNeeded.maximumScale)
        #expect(needed.amount == nil && result.answer.readiness == nil)
        #expect(result.headline().readiness == nil)
    }

    @Test func aPensionThatCoversEverythingNeedsAlmostNothing() async throws {
        // A pension already paid covers the spending after its tax.
        let pension = PlanPension(scheme: .fixed, name: "Paid already", fromAge: 30, perYear: d("50000"))
        let result = try await run(plan(pensions: [pension]), library(100_000))
        let needed = try #require(result.answer.assetsNeeded)
        #expect(result.answer.canRetireNow)
        #expect(needed.outcome == .atMost)
        #expect(needed.scale == 1 / AssetsNeeded.maximumScale)
        #expect(close(needed.amount, 100_000 / AssetsNeeded.maximumScale))
        #expect(needed.readiness == AssetsNeeded.maximumScale)
    }

    @Test func withoutPlanAssetsThereIsNothingToScale() async throws {
        let result = try await run(plan(), library(0))
        let needed = try #require(result.answer.assetsNeeded)
        #expect(needed.outcome == .noPlanAssets)
        #expect(needed.readiness == 0 && needed.amount == nil)
        #expect(!result.answer.canRetireNow)
    }

    @Test func theSearchCanBeTurnedOff() async throws {
        var off = options
        off.solveAssetsNeeded = false
        let result = try await run(plan(), library(400_000), options: off)
        #expect(result.answer.assetsNeeded == nil)
        #expect(result.answer.readiness == nil && result.answer.assetsNeededToday == nil)
        #expect(result.headline().readiness == nil)
        // The old numbers are still there.
        #expect(result.answer.fiNumber != nil && result.answer.fiProgress != nil)
    }

    @Test func logBisectionStepsGetWithinTheTolerance() {
        #expect(Engine.logBisectionSteps(low: 1, high: 1.005) == 0)
        #expect(Engine.logBisectionSteps(low: 1, high: 2) == 7)
        var ratio = 64.0
        for _ in 0..<Engine.logBisectionSteps(low: 1, high: 64) { ratio = ratio.squareRoot() }
        #expect(ratio <= 1 + AssetsNeeded.tolerance)
    }
}
