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
                              section: .contributions, index: 1, option: "end", account: "etf-world")
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

    @Test func agesWithoutAndFailuresByAgeReadBackAsTheyWere() throws {
        let ages = [AgeWithout(change: .saving, earliestAge: 67),
                    AgeWithout(change: .windfall(index: 2), earliestAge: nil),
                    AgeWithout(change: .pace, earliestAge: 59)]
        #expect(try roundTrip(ages) == ages)
        let failures = [AgeCount(age: 81, count: 12), AgeCount(age: 90, count: 40)]
        #expect(try roundTrip(failures) == failures)
    }
}
