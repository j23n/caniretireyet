import Foundation
import Model
@testable import Planner
import Testing
import TestSupport

/// The example library's plans, run as the app and the CLI run them.
struct ExampleLibraryTests {
    let library: Library
    let plan: PlanDocument

    init() throws {
        library = try Fixtures.exampleLibrary()
        plan = try #require(library.plans["base"])
    }

    /// A past baseline (PROGRESS.md, "Past baselines"): the plan started on
    /// an earlier day reads the library as it was that day.
    @Test func aPastBaselineStartsFromItsDay() async throws {
        var past = plan
        past.portfolio.start = .date("2025-12-31")
        let result = try await Sample.run(past, library,
                                          options: PlannerOptions(mode: .fast(runs: 50), maxRetirementAge: 60,
                                                                  solveSustainableSpending: false))
        #expect(result.issues.filter(\.isError).isEmpty)
        #expect(result.start.date == "2025-12-31")
        // Not the latest check-in's 161,505.49.
        #expect(result.start.planAssets > 0 && result.start.planAssets.rounded(2) != d("161505.49"))
        let baseline = result.baseline(created: "2026-10-06", kind: .past, label: "What I planned in 2025")
        #expect(baseline.kind == .past && baseline.created == "2026-10-06")
        #expect(baseline.start.date == "2025-12-31" && baseline.start.value == result.start.planAssets)
        #expect(baseline.years.first?.year == 2026)
        let data = try JSONEncoder().encode(baseline)
        #expect(try JSONDecoder().decode(Baseline.self, from: data).kind == .past)
    }

    @Test func theStartingPortfolioComesFromTheLatestCheckIn() async throws {
        let result = try await Sample.run(plan, library,
                                          options: PlannerOptions(mode: .fast(runs: 100), maxRetirementAge: 60,
                                                                  solveSustainableSpending: false))
        #expect(result.issues.filter(\.isError).isEmpty)
        #expect(result.start.date == "2026-09-30" && result.start.age == 38)
        // The plan leaves out the home and the mortgage (PROGRESS.md: 161,505.49).
        #expect(result.start.planAssets.rounded(2) == d("161505.49"))
        #expect(result.start.accounts
            == ["conto-deposito", "conto-fineco", "directa", "fondo-pensione", "gold-coins", "ledger-wallet", "tfr"])
        #expect(close(result.start.buckets.reduce(0) { $0 + $1.value }, result.start.planAssets.doubleValue, 1e-12))

        // The pension fund is available from 67; everything else can be drawn now.
        #expect(result.start.buckets.map(\.availableFromAge) == [nil, 67])
        let drawable = result.start.buckets[0]
        let fund = result.start.buckets[1]
        #expect(fund.accounts == ["fondo-pensione"] && fund.name == "Fondo pensione")
        #expect(close(fund.mix[.bonds], 0.4) && close(fund.mix[.equity], 0.6))
        #expect(fund.costBasis == fund.value)
        #expect(drawable.accounts == ["conto-deposito", "conto-fineco", "directa", "gold-coins", "ledger-wallet", "tfr"])
        // Recorded purchase costs are used (the ETF's 48,200 and the gold's 8,236.03); the
        // bitcoin has none, so the plan's 20% gain estimate applies; cash (the TFR, which has
        // no asset mix, counts as cash) has no gain.
        let cash = drawable.value * (drawable.mix[.cash] ?? 0)
        #expect(close(drawable.costBasis, 48_200 + 8_236.03 + cash + 0.8 * 44_128.004913, 1e-9))
        #expect(result.issues.contains { $0.code == "planner.noAssetMix" && $0.account == "tfr" })

        // The first year runs from October: a quarter of the year.
        #expect(close(result.expectedPath.years.first?.fraction, 92.0 / 365))
        #expect(result.fan.last?.year == 1988 + 95)
        #expect(result.focusAge == 55)
        #expect(result.markers.contains { $0.kind == .windfall && $0.label == "Inheritance" && $0.probability == 0.8 })
        #expect(result.markers.contains { $0.kind == .accessible && $0.age == 67 && $0.label == "Fondo pensione" })
        #expect(result.markers.filter { $0.kind == .pensionStart }.map(\.age) == [67, 67])
    }

    @Test func thePartTimePlanRuns() async throws {
        let plan = try #require(library.plans["part-time-from-50"])
        let result = try await Sample.run(plan, library,
                                          options: PlannerOptions(mode: .fast(runs: 50), maxRetirementAge: 60,
                                                                  solveSustainableSpending: false))
        #expect(result.issues.filter(\.isError).isEmpty)
        #expect(result.start.date == "2026-06-30")
        #expect(!result.start.accounts.contains("gold-coins"))
        let year = try #require(result.expectedYear(2030))
        #expect(year.income.contains { $0.kind == .work && $0.label == "Work 1" })
    }

    @Test func aPlanCanStartFromAnEarlierCheckInAndExcludeAccounts() async throws {
        var plan = plan
        plan.portfolio = PlanPortfolio(start: .date("2026-06-30"), unrealizedGainShare: d("0.2"), exclude: ["gold-coins"],
                                       targetMix: [.equity: d("0.7"), .bonds: d("0.3")])
        let result = try await Sample.run(plan, library,
                                          options: PlannerOptions(mode: .fast(runs: 50), maxRetirementAge: 56,
                                                                  solveSustainableSpending: false))
        #expect(result.start.date == "2026-06-30")
        #expect(!result.start.accounts.contains("gold-coins"))
        #expect(!result.issues.contains { $0.code == "planner.unknownCostBasis" })
    }
}
