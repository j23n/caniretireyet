import Foundation
import Model
@testable import Planner
import Testing

/// The full scan the Results screen needs: 2,000 runs × 58 years × 38
/// retirement ages (38 to 75), with taxes, pensions, contributions into an
/// account available later, and uncertain events.
///
/// The full scan takes about a minute in a debug build, so it runs only in
/// release builds, or when `PLANNER_PERF_TESTS=1` is set:
///
///     swift test -c release -Xswiftc -enable-testing --filter PerformanceTests
///     PLANNER_PERF_TESTS=1 swift test --filter PerformanceTests
///
/// A small scan of the same plan always runs.
struct PerformanceTests {
    /// Whether the full scan runs: in release builds, or with `PLANNER_PERF_TESTS=1`.
    static var fullScanEnabled: Bool {
        #if DEBUG
        ProcessInfo.processInfo.environment["PLANNER_PERF_TESTS"] == "1"
        #else
        true
        #endif
    }

    static let library = Sample.library(birth: "1988-04-12", on: "2026-09-30", [
        SampleAccount(id: "broker", mix: [.equity: d("0.8"), .bonds: d("0.2")], balance: 150_000),
        SampleAccount(id: "cash", kind: .cash, mix: nil, balance: 20_000),
        SampleAccount(id: "fund", kind: .pensionFund, balance: 20_000, availableFromAge: 67),
    ])

    static var plan: PlanDocument {
        var plan = Sample.plan(
            retire: .earliest, endAge: 95, working: "36000", retired: "36000", volatility: "0.17", equityYield: "0.02",
            work: [Sample.work(from: "2026-01-01", net: "45000", growth: "0.01")],
            pensions: [PlanPension(name: "State pension", fromAge: 67, perYear: d("14000")),
                       PlanPension(name: "Abroad", fromAge: 67, perYear: d("4800"))],
            contributions: [PlanContribution(account: "fund", perYear: d("5000"))],
            events: [PlanEvent(name: "Inheritance", timing: .age(62), amount: d("150000"), probability: d("0.8")),
                     PlanEvent(name: "New car", timing: .year(2031), amount: d("-25000"))],
            investmentRate: "0.26", wealthRate: "0.002", unrealizedGainShare: "0.2", runs: 2000, seed: 1)
        plan.spending.phases = [SpendingPhase(fromAge: 75, factor: d("0.9")), SpendingPhase(fromAge: 85, factor: d("0.8"))]
        plan.assumptions.returns[.bonds] = ReturnAssumption(real: d("0.01"), volatility: d("0.06"))
        plan.assumptions.returns[.cash] = ReturnAssumption(real: 0, volatility: d("0.01"))
        return plan
    }

    @Test func aSmallScanOfTheSamePlanRuns() async throws {
        let result = try await Planner.run(plan: Self.plan, library: Self.library,
                                           options: PlannerOptions(mode: .fast(runs: 40), maxRetirementAge: 45))
        #expect(result.successCurve.map(\.age) == Array(38...45))
        #expect(result.fan.count == 58)
        #expect(result.settings.runs == 40)
        #expect(result.answer.sustainableSpending != nil)
        for year in result.fan {
            #expect(year.p10 <= year.p50 && year.p50 <= year.p90)
        }
    }

    @Test(.enabled(if: fullScanEnabled, "The full scan runs in release builds, or with PLANNER_PERF_TESTS=1."))
    func theFullScanIsFast() async throws {
        let clock = ContinuousClock()
        var measured: PlanResult?
        let scan = try await clock.measure {
            measured = try await Planner.run(plan: Self.plan, library: Self.library,
                                           options: PlannerOptions(solveSustainableSpending: false))
        }
        let result = try #require(measured)
        #expect(result.successCurve.count == 38)
        #expect(result.fan.count == 58)
        #expect(result.settings.runs == 2000)

        let solve = try await clock.measure {
            _ = try await Planner.run(plan: Self.plan, library: Self.library,
                                      options: PlannerOptions(ageScan: .headline))
        }
        let fast = try await clock.measure {
            _ = try await Planner.run(plan: Self.plan, library: Self.library,
                                      options: .fast())
        }
        print("""
            Planner performance: full scan (2,000 runs × 58 years × 38 ages) \(scan); \
            headline scan with the spending solver \(solve); fast mode (250 runs, full scan) \(fast). \
            Earliest age \(result.answer.earliestAge.map(String.init) ?? "none").
            """)
        #expect(scan < .seconds(600))
    }
}
