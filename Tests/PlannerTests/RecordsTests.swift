import Foundation
import Model
@testable import Planner
import Testing

/// Headlines and baselines made from a result, and the plan hash.
struct RecordsTests {
    let library = Sample.library(birth: "1966-01-01", on: "2025-12-31", [
        SampleAccount(id: "broker", balance: d("100000.5")),
        SampleAccount(id: "home", kind: .property, mix: nil, balance: 300_000, includeInPlan: false),
    ])
    /// Retires on 1 January 2031, with nothing to save before then.
    let plan = Sample.plan(retire: .age(65), endAge: 70, retired: "8000", volatility: "0.15", runs: 100)

    @Test func thePlanHashIsStableAndChangesWithThePlan() {
        let hash = Planner.planHash(plan)
        #expect(hash.count == 16 && hash.allSatisfy(\.isHexDigit))
        #expect(Planner.planHash(plan) == hash)
        var changed = plan
        changed.spending.retired = d("8001")
        #expect(Planner.planHash(changed) != hash)
        // Decimals are hashed as written: 8000 and 8000.0 are the same input.
        var same = plan
        same.spending.retired = d("8000.0")
        #expect(Planner.planHash(same) == hash)
    }

    @Test func aHeadlineRecordsTheAnswerAndItsProvenance() async throws {
        let result = try await Sample.run(plan, library)
        let headline = result.headline()

        #expect(headline.date == "2025-12-31")
        #expect(headline.engine == Planner.engineVersion)
        #expect(headline.planHash == Planner.planHash(plan))
        #expect(headline.confidence == d("0.9"))
        #expect(headline.earliestAge == result.answer.earliestAge)
        let success = try #require(result.answer.successAtTarget)
        #expect(headline.successAtTarget == Decimal.rounded(success, scale: 3))
        #expect(headline.taxParameters.isEmpty && headline.fiProgress == nil)
        // Readiness is rounded down, so a recorded 1 means retiring today works.
        let readiness = try #require(result.answer.readiness)
        #expect(headline.readiness == Decimal.roundedDown(readiness, scale: 2))
        #expect(headline.readiness! <= Decimal(readiness))
        #expect(result.headline(date: "2026-01-31").date == "2026-01-31")
    }

    @Test func readinessIsRoundedDown() {
        #expect(Decimal.roundedDown(0.58, scale: 2) == d("0.58"))
        #expect(Decimal.roundedDown(0.9999, scale: 2) == d("0.99"))
        #expect(Decimal.roundedDown(1, scale: 2) == 1)
        #expect(Decimal.roundedDown(1.0049, scale: 2) == d("1"))
        #expect(Decimal.roundedDown(0.072345, scale: 2) == d("0.07"))
    }

    @Test func aBaselineStoresTheProjection() async throws {
        let result = try await Sample.run(plan, library)
        let baseline = result.baseline(created: "2026-01-05", kind: .yearly, label: "Start of 2026")

        #expect(baseline.created == "2026-01-05" && baseline.kind == .yearly && baseline.label == "Start of 2026")
        #expect(baseline.accounts == ["broker"])
        #expect(baseline.start == BaselineStart(date: "2025-12-31", value: d("100000.5")))
        #expect(baseline.years.map(\.year) == Array(2026...2036))
        #expect(baseline.years[0].expected == Decimal.rounded(result.fan[0].expected, scale: 0))
        #expect(baseline.years.allSatisfy { $0.p10 <= $0.p50 && $0.p50 <= $0.p90 })
        #expect(baseline.headline == result.headlineSummary)
        #expect(baseline.taxParameters.isEmpty)
        #expect(try baseline.planDocument() == plan)
        // Working years record what the plan expected to save; retired years what it drew.
        #expect(baseline.years.first { $0.year == 2030 }?.savings == nil)
        #expect(baseline.years.first { $0.year == 2031 }?.savings == d("-8000"))

        // It survives the file format.
        let data = try JSONEncoder().encode(baseline)
        #expect(try JSONDecoder().decode(Baseline.self, from: data) == baseline)
    }
}
