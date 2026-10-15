import Foundation
import Model
import Testing
import TestSupport

/// The plan's pieces in the file format (PLANNER.md): tax rates, net work
/// phases, pensions, contributions into accounts, income yields, and an
/// account's `availableFromAge`. All made up.
struct PlanFormatTests {
    private func roundTrips<T: Codable & Hashable>(_ type: T.Type, _ text: String) throws {
        let value = try decode(T.self, text)
        #expect(try decode(T.self, try json(value)) == value)
        #expect(try decode(JSONValue.self, try json(value)) == decode(JSONValue.self, text), "\(text)")
    }

    @Test func contributionsGoIntoAccountsYearlyOrOnce() throws {
        let yearly = #"{ "account": "pension-fund", "perYear": "5000", "until": "retirement" }"#
        let oneOff = #"{ "account": "pillar-3a", "amount": "7000", "year": 2027 }"#
        for text in [yearly, oneOff] { try roundTrips(PlanContribution.self, text) }
        #expect(try decode(PlanContribution.self, oneOff) == PlanContribution(account: "pillar-3a", amount: 7_000, year: 2027))
        #expect(try decode(PlanContribution.self, oneOff).isOneOff)
        #expect(!(try decode(PlanContribution.self, yearly)).isOneOff)
        // An account is required, and without a one-off amount a yearly one.
        #expect(throws: DecodingError.self) { try decode(PlanContribution.self, #"{ "perYear": "1" }"#) }
        #expect(throws: DecodingError.self) { try decode(PlanContribution.self, #"{ "account": "a" }"#) }
    }

}
