import Foundation
import Model
@testable import Planner
import TaxKit
import Testing

/// A tax that isn't a number (a bug in a tax system, or input it can't
/// handle) makes runs fail. Comparing NaN is always false, so before, a NaN
/// shortfall looked like no shortfall and every run "succeeded".
struct NonFiniteTests {
    let library = Sample.library(birth: "1976-01-01", on: "2025-12-31", [SampleAccount(id: "broker", balance: 500_000)])

    @Test func aTaxThatIsntANumberFailsTheRun() async throws {
        let plan = Sample.plan(retire: .age(60), endAge: 80, working: "30000", retired: "30000",
                               work: [Sample.employee(from: "2026-01-01", gross: "60000")], runs: 20)
        var system = FlatTaxSystem()
        system.incomeRate = .nan
        let result = try await Sample.run(plan, library, system: system)
        // Every age that works in 2026 meets the NaN (retiring today doesn't).
        let working = result.successCurve.filter { $0.age > 50 }
        #expect(!working.isEmpty)
        #expect(working.allSatisfy { $0.success == 0 })
        #expect(result.focusAge == 60)
        let failure = try #require(result.expectedPath.failure)
        #expect(failure.year == 2026 && failure.reason == .depleted)
        #expect(result.expectedPath.years.allSatisfy { $0.endAssets.isFinite })
    }

    /// A tax on market income that isn't a number only shows in the year's
    /// final assessment, after the cash flow was funded.
    @Test func aMarketTaxThatIsntANumberFailsTheRun() async throws {
        let plan = Sample.plan(retire: .age(60), endAge: 80, retired: "30000", unrealizedGainShare: "0.5", runs: 20)
        var system = FlatTaxSystem()
        system.gainsRate = .nan
        system.exactGrossUp = false
        let result = try await Sample.run(plan, library, system: system)
        #expect(result.successCurve.allSatisfy { $0.success == 0 })
        let failure = try #require(result.expectedPath.failure)
        #expect(failure.reason == .depleted)
        #expect(result.fan.allSatisfy { [$0.p10, $0.p25, $0.p50, $0.p75, $0.p90, $0.expected].allSatisfy(\.isFinite) })

        // The same plan with a real rate succeeds: the failures are the NaN's.
        system.gainsRate = 0.2
        let finite = try await Sample.run(plan, library, system: system)
        #expect(finite.successCurve.contains { $0.success == 1 })
    }
}
