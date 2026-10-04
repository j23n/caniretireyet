import Foundation
import Model
@testable import Planner
import TaxKit
import Testing

/// What retiring today would need when part of the money is locked away
/// (PLANNER.md, "Assets needed to retire today"): the search adds extra money
/// only to the buckets that can be drawn now, so a large locked pension fund
/// doesn't inflate what's needed. On the flat test system, whose pension
/// fund is locked until 60.
struct AssetsNeededAccessTests {
    /// Born 1986-01-01, 39 on the start date; the plan runs to 60.
    static func library(broker: Decimal, fund: Decimal, mix: AssetMix = [.equity: 0.8, .cash: 0.2]) -> Library {
        Sample.library(birth: "1986-01-01", on: "2025-12-31", [
            SampleAccount(id: "broker", mix: mix, balance: broker),
            SampleAccount(id: "fund", kind: .pensionFund, wrapper: "flat.pension", mix: [.equity: 0.6, .bonds: 0.4],
                          balance: fund),
        ])
    }

    static let system: FlatTaxSystem = {
        var system = FlatTaxSystem()
        system.gainsRate = 0.25
        system.payoutRate = 0.1
        return system
    }()

    static func plan(retired: String = "30000", volatility: String = "0.15", pensions: [PlanPension] = [],
                     runs: Int = 200) -> PlanDocument {
        Sample.plan(retire: .earliest, endAge: 60, retired: retired, equityReturn: "0.03", volatility: volatility,
                    pensions: pensions, inflation: "0", unrealizedGainShare: "0.3", runs: runs)
    }

    static let options = PlannerOptions(maxRetirementAge: 45, solveSustainableSpending: false)

    /// The engine for retiring today, and the age.
    static func engine(_ plan: PlanDocument, _ library: Library) async throws -> (Engine, PlanModel) {
        let (interpreted, _) = PlanInterpreter.interpret(plan: plan, library: library,
                                                         registry: Sample.registry(system), options: options)
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
        let liquid = try #require(portfolio.buckets.firstIndex { $0.wrapper == "flat.ordinary" })
        let locked = try #require(portfolio.buckets.firstIndex { $0.wrapper == "flat.pension" })
        #expect(abs(portfolio.accessibleValue - 100_000) < 1e-6)

        let more = portfolio.withExtra(50_000)
        func total(_ p: Portfolio, _ b: Int, _ keyPath: KeyPath<Portfolio.Lot, Double>) -> Double {
            p.buckets[b].lots.reduce(0) { $0 + p.lots[$1][keyPath: keyPath] }
        }
        // The pension fund is untouched; the broker gets all 50,000, 80/20, with
        // a purchase cost equal to the amount (no embedded gain).
        #expect(more.lots[portfolio.buckets[locked].lots].map(\.value) == portfolio.lots[portfolio.buckets[locked].lots].map(\.value))
        #expect(abs(total(more, liquid, \.value) - 150_000) < 1e-6)
        #expect(abs(total(more, liquid, \.basis) - total(portfolio, liquid, \.basis) - 50_000) < 1e-6)
        let equity = try #require(portfolio.classes.firstIndex(of: .equity))
        let addedEquity = portfolio.buckets[liquid].lots.reduce(0.0) { sum, index in
            sum + (portfolio.lots[index].classIndex == equity ? more.lots[index].value - portfolio.lots[index].value : 0)
        }
        #expect(abs(addedEquity - 40_000) < 1e-6)

        // Less money comes out of the broker in proportion, never below zero.
        let less = portfolio.withExtra(-25_000)
        #expect(abs(total(less, liquid, \.value) - 75_000) < 1e-6)
        #expect(abs(total(less, liquid, \.basis) - total(portfolio, liquid, \.basis) * 0.75) < 1e-6)
        #expect(abs(total(less, locked, \.value) - 300_000) < 1e-6)
        let emptied = portfolio.withExtra(-1_000_000)
        #expect(emptied.lots.allSatisfy { $0.value >= 0 })
        #expect(total(emptied, liquid, \.value) == 0 && abs(total(emptied, locked, \.value) - 300_000) < 1e-6)
        #expect(portfolio.withExtra(0).lots.map(\.value) == portfolio.lots.map(\.value))
    }

    // MARK: The search

    @Test func aLargeLockedFundNeedsLessThanScalingEverything() async throws {
        let library = Self.library(broker: 100_000, fund: 300_000)
        let result = try await Planner.run(plan: Self.plan(), library: library, registry: Sample.registry(Self.system),
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
        let scaled = Self.success(engine, model, start: engine.portfolio.scaled(by: amount / 400_000))
        #expect(scaled < 0.9, "\(scaled)")
        // Extra money where it can be drawn reaches the confidence; 2% less doesn't.
        #expect(Self.success(engine, model, start: engine.portfolio.withExtra(extra)) >= 0.9)
        #expect(Self.success(engine, model, start: engine.portfolio.withExtra(amount / 1.02 - 400_000)) < 0.9)
    }

    @Test func moreExtraMoneyNeverLowersTheChance() async throws {
        let (engine, model) = try await Self.engine(Self.plan(), Self.library(broker: 100_000, fund: 300_000))
        let rates = [-100_000.0, -50_000, 0, 100_000, 200_000, 300_000, 450_000, 700_000].map {
            Self.success(engine, model, start: engine.portfolio.withExtra($0))
        }
        #expect(rates == rates.sorted(), "\(rates)")
        #expect(rates.first! < 0.9 && rates.last! >= 0.9)
    }

    @Test func pastOneHundredPercentMoneyCouldBeTakenOut() async throws {
        let result = try await Planner.run(plan: Self.plan(), library: Self.library(broker: 1_500_000, fund: 50_000),
                                           registry: Sample.registry(Self.system), options: Self.options)
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
        let pension = PlanPension(scheme: .fixed, name: "Paid already", fromAge: 30, perYear: d("50000"))
        let result = try await Planner.run(plan: Self.plan(pensions: [pension]),
                                           library: Self.library(broker: 100_000, fund: 60_000),
                                           registry: Sample.registry(Self.system), options: Self.options)
        let needed = try #require(result.answer.assetsNeeded)
        #expect(needed.outcome == .atMost && needed.leavesOnlyLockedMoney)
        #expect(abs(try #require(needed.amount) - 60_000) < 1e-6)
        #expect(abs(try #require(needed.extra) + 100_000) < 1e-6)
        #expect(abs(try #require(needed.readiness) - 160_000.0 / 60_000) < 1e-9)
    }

    @Test func theSearchStopsAtTwentyTimesTodaysPlanAssets() async throws {
        let result = try await Planner.run(plan: Self.plan(), library: Self.library(broker: 1_000, fund: 1_000),
                                           registry: Sample.registry(Self.system), options: Self.options)
        let needed = try #require(result.answer.assetsNeeded)
        #expect(needed.outcome == .moreThanMaximum)
        #expect(needed.scale == AssetsNeeded.maximumScale && needed.amount == nil && needed.readiness == nil)
        #expect(needed.extra == (AssetsNeeded.maximumScale - 1) * 2_000)
    }
}
