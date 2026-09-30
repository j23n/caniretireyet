import Foundation
import Model
@testable import Planner
import TaxKit
import Testing

/// The full scan the Results screen needs: 2,000 runs × 58 years × 38
/// retirement ages (38 to 75), with taxes, pensions, contributions, credits
/// into wrappers and uncertain events.
///
/// The bound is generous so the test also passes in debug builds; for the
/// real figure, run it in a release build:
///
///     swift test -c release -Xswiftc -enable-testing --filter PerformanceTests
struct PerformanceTests {
    static let library = Sample.library(birth: "1988-04-12", on: "2026-09-30", [
        SampleAccount(id: "broker", mix: [.equity: d("0.8"), .bonds: d("0.2")], balance: 150_000),
        SampleAccount(id: "cash", kind: .cash, mix: nil, balance: 20_000),
        SampleAccount(id: "fund", kind: .pensionFund, wrapper: "flat.pension", balance: 20_000),
    ])

    static var system: FlatTaxSystem {
        var system = FlatTaxSystem()
        system.incomeRate = 0.3
        system.contributionRate = 0.09
        system.gainsRate = 0.26
        system.interestRate = 0.26
        system.wealthRate = 0.002
        system.payoutRate = 0.15
        system.pensionCreditRate = 0.33
        system.tfrRate = 0.069
        system.growthTaxRate = 0.2
        return system
    }

    static var plan: PlanDocument {
        var plan = Sample.plan(
            retire: .earliest, endAge: 95, working: "36000", retired: "36000", volatility: "0.17",
            work: [Sample.employee(from: "2026-01-01", gross: "65000", growth: "0.01")],
            pensions: [PlanPension(scheme: "flat.state", options: ["montante": "92000", "contributionYears": "14"]),
                       PlanPension(scheme: .fixed, name: "Abroad", fromAge: 67, perYear: d("4800"))],
            contributions: [PlanContribution(account: "fund", perYear: d("5000"))],
            events: [PlanEvent(name: "Inheritance", timing: .age(62), amount: d("150000"), probability: d("0.8")),
                     PlanEvent(name: "New car", timing: .year(2031), amount: d("-25000"))],
            cashBuffer: "10000", unrealizedGainShare: "0.2", runs: 2000, seed: 1)
        plan.spending.phases = [SpendingPhase(fromAge: 75, factor: d("0.9")), SpendingPhase(fromAge: 85, factor: d("0.8"))]
        plan.assumptions.returns[.bonds] = ReturnAssumption(real: d("0.01"), volatility: d("0.06"))
        plan.assumptions.returns[.cash] = ReturnAssumption(real: 0, volatility: d("0.01"))
        return plan
    }

    @Test func theFullScanIsFast() async throws {
        let clock = ContinuousClock()
        var measured: PlanResult?
        let scan = try await clock.measure {
            measured = try await Planner.run(plan: Self.plan, library: Self.library, registry: Sample.registry(Self.system),
                                           options: PlannerOptions(solveSustainableSpending: false))
        }
        let result = try #require(measured)
        #expect(result.successCurve.count == 38)
        #expect(result.fan.count == 58)
        #expect(result.settings.runs == 2000)

        let solve = try await clock.measure {
            _ = try await Planner.run(plan: Self.plan, library: Self.library, registry: Sample.registry(Self.system),
                                      options: PlannerOptions(ageScan: .headline))
        }
        let fast = try await clock.measure {
            _ = try await Planner.run(plan: Self.plan, library: Self.library, registry: Sample.registry(Self.system),
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
