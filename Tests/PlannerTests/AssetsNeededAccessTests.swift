import Foundation
import Model
@testable import Planner
import Testing

/// What retiring today would need when part of the money is locked away
/// (PLANNER.md, "Assets needed to retire today"): the search adds extra money
/// only to the buckets that can be drawn now, so a large locked pension fund
/// doesn't inflate what's needed. The pension fund here is available from 60.
struct AssetsNeededAccessTests {
    /// Born 1986-01-01, 39 on the start date; the plan runs to 60.
    static func library(broker: Decimal, fund: Decimal, mix: AssetMix = [.equity: 0.8, .cash: 0.2]) -> Library {
        Sample.library(birth: "1986-01-01", on: "2025-12-31", [
            SampleAccount(id: "broker", mix: mix, balance: broker),
            SampleAccount(id: "fund", kind: .pensionFund, mix: [.equity: 0.6, .bonds: 0.4], balance: fund,
                          availableFromAge: 60),
        ])
    }

    static func plan(retired: String = "30000", volatility: String = "0.15", pensions: [PlanPension] = [],
                     runs: Int = 200) -> PlanDocument {
        Sample.plan(retire: .earliest, endAge: 60, retired: retired, equityReturn: "0.03", volatility: volatility,
                    pensions: pensions, inflation: "0", investmentRate: "0.25", unrealizedGainShare: "0.3", runs: runs)
    }

    static let options = PlannerOptions(maxRetirementAge: 45, solveSustainableSpending: false)

    /// The engine for retiring today, and the age.
    static func engine(_ plan: PlanDocument, _ library: Library) async throws -> (Engine, PlanModel) {
        let (interpreted, _) = PlanInterpreter.interpret(plan: plan, library: library, options: options)
        let model = try #require(interpreted)
        let engine = try await Engine.make(model: model, ages: [model.currentAge], maxAge: model.currentAge)
        return (engine, model)
    }

    static func success(_ engine: Engine, _ model: PlanModel, start: Portfolio) -> Double {
        var simulator = engine.simulator(age: model.currentAge, start: start)
        let successes = (0..<model.runs).filter { simulator.run($0, spending: model.spending.retired).failure == nil }
        return Double(successes.count) / Double(model.runs)
    }

    // MARK: Where the extra money goes

    @Test func extraMoneyGoesOnlyIntoTheAccessibleBucketsAtTheirTargetMix() async throws {
        let (engine, _) = try await Self.engine(Self.plan(), Self.library(broker: 100_000, fund: 300_000))
        let portfolio = engine.portfolio
        #expect(portfolio.buckets.map(\.opensAtAge) == [nil, 60])
        #expect(abs(portfolio.accessibleValue - 100_000) < 1e-6)
        let equity = try #require(portfolio.classes.firstIndex(of: .equity))

        // The pension fund is untouched; the broker gets all 50,000 at its
        // target mix (its own 80/20), costing what it's worth.
        let more = engine.startPortfolio(extra: 50_000)
        #expect(more.buckets[1].values == portfolio.buckets[1].values)
        #expect(abs(more.buckets[0].value - 150_000) < 1e-6)
        #expect(abs(more.buckets[0].basis - portfolio.buckets[0].basis - 50_000) < 1e-6)
        #expect(abs(more.buckets[0].values[equity] - portfolio.buckets[0].values[equity] - 40_000) < 1e-6)

        // Less money comes out of the broker in proportion, never below zero.
        let less = engine.startPortfolio(extra: -25_000)
        #expect(abs(less.buckets[0].value - 75_000) < 1e-6)
        #expect(abs(less.buckets[0].basis - portfolio.buckets[0].basis * 0.75) < 1e-6)
        #expect(abs(less.buckets[1].value - 300_000) < 1e-6)
        let emptied = engine.startPortfolio(extra: -1_000_000)
        #expect(emptied.buckets.allSatisfy { $0.values.allSatisfy { $0 >= 0 } })
        #expect(emptied.buckets[0].value == 0 && abs(emptied.buckets[1].value - 300_000) < 1e-6)
        #expect(engine.startPortfolio(extra: 0).buckets.map(\.values) == portfolio.buckets.map(\.values))
    }

    // MARK: The search

    @Test func aLargeLockedFundNeedsLessThanScalingEverything() async throws {
        let library = Self.library(broker: 100_000, fund: 300_000)
        let result = try await Planner.run(plan: Self.plan(), library: library,
                                           options: Self.options)
        let needed = try #require(result.answer.assetsNeeded)
        #expect(needed.outcome == .found && !result.answer.canRetireNow)
        let amount = try #require(needed.amount)
        let extra = try #require(needed.extra)
        #expect(abs(amount - (400_000 + extra)) < 1e-6)
        #expect(abs(try #require(needed.accessible) - 100_000) < 1e-6)
        #expect(abs(try #require(needed.readiness) - 400_000 / amount) < 1e-12)
        #expect(try #require(needed.success) >= 0.9)

        // With the same total in every holding alike, as the search used to
        // add it, most of the money would be locked until 60: far short.
        let (engine, model) = try await Self.engine(Self.plan(), library)
        var scaledPortfolio = engine.portfolio
        for b in scaledPortfolio.buckets.indices {
            scaledPortfolio.buckets[b].values = scaledPortfolio.buckets[b].values.map { $0 * amount / 400_000 }
            scaledPortfolio.buckets[b].basis *= amount / 400_000
        }
        let scaled = Self.success(engine, model, start: scaledPortfolio)
        #expect(scaled < 0.9, "\(scaled)")
        // Extra money where it can be drawn reaches the confidence; 2% less doesn't.
        #expect(Self.success(engine, model, start: engine.startPortfolio(extra: extra)) >= 0.9)
        #expect(Self.success(engine, model, start: engine.startPortfolio(extra: amount / 1.02 - 400_000)) < 0.9)
    }

    @Test func moreExtraMoneyNeverLowersTheChance() async throws {
        let (engine, model) = try await Self.engine(Self.plan(), Self.library(broker: 100_000, fund: 300_000))
        let rates = [-100_000.0, -50_000, 0, 100_000, 200_000, 300_000, 450_000, 700_000].map {
            Self.success(engine, model, start: engine.startPortfolio(extra: $0))
        }
        #expect(rates == rates.sorted(), "\(rates)")
        #expect(rates.first! < 0.9 && rates.last! >= 0.9)
    }

    @Test func pastOneHundredPercentMoneyCouldBeTakenOut() async throws {
        let result = try await Planner.run(plan: Self.plan(), library: Self.library(broker: 1_500_000, fund: 50_000),
                                           options: Self.options)
        let needed = try #require(result.answer.assetsNeeded)
        #expect(result.answer.canRetireNow && needed.outcome == .found)
        let extra = try #require(needed.extra)
        #expect(extra < 0 && extra > -1_500_000)
        #expect(abs(try #require(needed.amount) - (1_550_000 + extra)) < 1e-6)
        #expect(try #require(result.answer.readiness) > 1)
    }

    @Test func whenThePensionsCoverEverythingOnlyTheLockedMoneyIsLeft() async throws {
        // A pension already paid covers the spending: even with the broker
        // emptied, retiring today works, so what's needed is at most what's locked.
        let pension = PlanPension(name: "Paid already", fromAge: 30, perYear: d("50000"))
        let result = try await Planner.run(plan: Self.plan(pensions: [pension]),
                                           library: Self.library(broker: 100_000, fund: 60_000),
                                           options: Self.options)
        let needed = try #require(result.answer.assetsNeeded)
        #expect(needed.outcome == .atMost && needed.leavesOnlyLockedMoney)
        #expect(abs(try #require(needed.amount) - 60_000) < 1e-6)
        #expect(abs(try #require(needed.extra) + 100_000) < 1e-6)
        #expect(abs(try #require(needed.readiness) - 160_000.0 / 60_000) < 1e-9)
    }

    @Test func theSearchStopsAtTwentyTimesTodaysPlanAssets() async throws {
        let result = try await Planner.run(plan: Self.plan(), library: Self.library(broker: 1_000, fund: 1_000),
                                           options: Self.options)
        let needed = try #require(result.answer.assetsNeeded)
        #expect(needed.outcome == .moreThanMaximum)
        #expect(needed.scale == AssetsNeeded.maximumScale && needed.amount == nil && needed.readiness == nil)
        #expect(needed.extra == (AssetsNeeded.maximumScale - 1) * 2_000)
    }
}
