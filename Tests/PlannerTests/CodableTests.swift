import Foundation
import Model
import Planner
import Testing

/// The parts of a result an app keeps between launches read back as they
/// were written.
struct CodableTests {
    private func roundTrip<Value: Codable & Equatable>(_ value: Value) throws -> Value {
        try JSONDecoder().decode(Value.self, from: JSONEncoder().encode(value))
    }

    @Test func issuesReadBackAsTheyWere() throws {
        let issue = PlanIssue(.warning, code: "contributionAfterRetirement", message: "Ends after retirement.",
                              section: .contributions, index: 1, year: 2040, option: "end", account: "etf-world")
        #expect(try roundTrip(issue) == issue)
        let text = try #require(String(data: try JSONEncoder().encode(issue), encoding: .utf8))
        // A section is its name; a severity its word.
        #expect(text.contains(#""section":"contributions""#))
        #expect(text.contains(#""severity":"warning""#))
        #expect(try roundTrip(PlanIssue(.error, code: "noBirthDate", message: "No birth date.", section: .person))
            .isError)
    }

    @Test func assetsNeededReadsBackAsItWas() throws {
        let found = AssetsNeeded(age: 38, outcome: .found, scale: 2.5, amount: 750_000, success: 0.91,
                                 readiness: 0.4, extra: 450_000, accessible: 300_000)
        #expect(try roundTrip(found) == found)
        for outcome in [AssetsNeeded.Outcome.atMost, .moreThanMaximum, .noPlanAssets] {
            let needed = AssetsNeeded(age: 38, outcome: outcome)
            #expect(try roundTrip(needed) == needed)
        }
    }

    @Test func flexibleSpendingReadsBackAsItWas() throws {
        let summary = FlexibleSpendingSummary(
            cut: 0.1, floor: 0.8, upperGuardrail: 0.8, lowerGuardrail: 1.2, planSpending: 36_000, age: 55,
            runs: 2_000, retirementYears: 35, shareWithCut: 0.42, failureRate: 0.05, medianLowestLevel: 0.9,
            p10LowestLevel: nil, medianShareBelow: 0.1, medianYearsBelow: 3, p90YearsBelow: 12)
        #expect(try roundTrip(summary) == summary)
    }
}
