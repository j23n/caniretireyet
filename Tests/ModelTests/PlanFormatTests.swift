import Foundation
import Model
import Testing
import TestSupport

/// The plan's pieces in the file format (PLANNER.md): tax rates, net work
/// phases, pensions, contributions into accounts, income yields, and an
/// account's `availableFromAge`. All made up.
struct PlanFormatTests {
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(T.self, from: Data(json.utf8))
    }

    /// The value written back as JSON, with sorted keys.
    private func json<T: Encodable>(_ value: T) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return String(decoding: try encoder.encode(value), as: UTF8.self)
    }

    private func roundTrips<T: Codable & Hashable>(_ type: T.Type, _ text: String) throws {
        let value = try decode(T.self, text)
        #expect(try decode(T.self, try json(value)) == value)
        #expect(try decode(JSONValue.self, try json(value)) == decode(JSONValue.self, text), "\(text)")
    }

    @Test func taxesAreTwoRatesAndAnAllowance() throws {
        try roundTrips(PlanTax.self, #"{ "investmentRate": "0.26", "wealthRate": "0.002", "wealthAllowance": "50000" }"#)
        let tax = try decode(PlanTax.self, #"{ "investmentRate": "0.26" }"#)
        #expect(tax.investmentRate == d("0.26") && tax.wealthRate == nil)
        #expect(tax.effectiveWealthRate == 0 && tax.effectiveWealthAllowance == 0)
        #expect(PlanTax().isEmpty && !tax.isEmpty)
        let plan = PlanDocument(id: "p", name: "P", retirement: PlanRetirement(age: .age(60)),
                                spending: PlanSpending(working: 1, retired: 1))
        #expect(!(try json(plan)).contains("tax"))
    }

    @Test func workPhasesAreEnteredAfterTax() throws {
        let text = #"{ "name": "Employee", "from": "2026-01-01", "until": "retirement", "netIncome": "40000", "realGrowth": "0.01" }"#
        try roundTrips(WorkPhase.self, text)
        let phase = try decode(WorkPhase.self, text)
        #expect(phase == WorkPhase(name: "Employee", from: "2026-01-01", until: .retirement, netIncome: 40_000,
                                   realGrowth: d("0.01")))
        #expect(try decode(WorkPhase.self, #"{ "from": "2026-01-01", "until": "2030-06-30" }"#).netIncome == nil)
    }

    @Test func pensionsAreAnAmountFromAnAge() throws {
        try roundTrips(PlanPension.self, #"{ "name": "State pension", "fromAge": 67, "perYear": "14000" }"#)
        #expect(try decode(PlanPension.self, #"{ "fromAge": 67, "perYear": "14000" }"#)
            == PlanPension(fromAge: 67, perYear: 14_000))
        #expect(try decode(PlanPension.self, #"{ "name": "Not known yet" }"#) == PlanPension(name: "Not known yet",
                                                                                         fromAge: nil, perYear: nil))
    }

    @Test func otherIncomeStartsAtAnAgeOrAtRetirement() throws {
        let rent = #"{ "name": "Rent", "from": 45, "untilAge": 85, "perYear": "9600" }"#
        let partTime = #"{ "name": "Part-time", "from": "retirement", "untilAge": 60, "perYear": "18000" }"#
        for text in [rent, partTime] { try roundTrips(PlanIncome.self, text) }
        #expect(try decode(PlanIncome.self, rent) == PlanIncome(name: "Rent", from: .age(45), untilAge: 85,
                                                                perYear: 9_600))
        #expect(try decode(PlanIncome.self, partTime).from == .retirement)
        #expect(try decode(PlanIncome.self, #"{ "from": 50, "perYear": "1" }"#).untilAge == nil)
        #expect(throws: DecodingError.self) { try decode(PlanIncome.self, #"{ "from": "soon" }"#) }
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

    @Test func returnAssumptionsMayGiveAnIncomeYield() throws {
        try roundTrips(ReturnAssumption.self, #"{ "real": "0.045", "volatility": "0.17", "incomeYield": "0.02" }"#)
        #expect(try decode(ReturnAssumption.self, #"{ "real": "0.01", "volatility": "0.06" }"#).incomeYield == nil)
        #expect(PlanAssumptions.defaultReturns.values.allSatisfy { $0.incomeYield == nil })
    }

    @Test func accountsSayFromWhatAgeTheyCanBeDrawn() throws {
        let text = #"{ "id": "fund", "name": "Fund", "kind": "pensionFund", "currency": "EUR", "opened": "2022-01-01", "availableFromAge": 67 }"#
        try roundTrips(Account.self, text)
        #expect(try decode(Account.self, text).availableFromAge == 67)
    }
}
