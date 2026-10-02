import Foundation
import Model
import Testing

/// The optional keys plans, people and instruments gained for other tax
/// systems: the plan's currency, citizenships, a pension's kind and claim
/// route, contributions into pension schemes and one-off contributions, fund
/// income yields, and an instrument's fund type and delivery claim. All made up.
struct PlanAdditionsTests {
    private static func d(_ string: String) -> Decimal { Decimal(fileString: string)! }

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

    @Test func aPlanHasACurrencyDefaultingToTheBaseCurrency() throws {
        var plan = PlanDocument(id: "p", name: "P", retirement: PlanRetirement(age: .age(60)),
                                spending: PlanSpending(working: 1, retired: 1))
        #expect(plan.currency == nil)
        #expect(plan.effectiveCurrency(base: .eur) == .eur)
        #expect(!(try json(plan)).contains("currency"))
        plan.currency = .chf
        #expect(plan.effectiveCurrency(base: .eur) == .chf)
        try roundTrips(PlanDocument.self, try json(plan))
        #expect(try json(plan).contains(#""currency":"CHF""#))
    }

    @Test func aPersonListsCitizenships() throws {
        #expect(Person().citizenships.isEmpty)
        #expect(try json(Person(name: "Sam Sample")) == #"{"name":"Sam Sample"}"#)
        try roundTrips(Person.self, #"{ "birthDate": "1980-05-01", "citizenships": ["DE", "IT"] }"#)
        #expect(try decode(Person.self, #"{ "citizenships": ["DE", "IT"] }"#).citizenships == [.de, .it])
    }

    @Test func pensionsSayTheirKindAndClaimRoute() throws {
        let text = #"""
        { "scheme": "fixed", "fromAge": 65, "perYear": "6000", "kind": "occupational", "sourceCountry": "DE",
          "claimRoute": "fixed" }
        """#
        try roundTrips(PlanPension.self, text)
        let pension = try decode(PlanPension.self, text)
        #expect(pension.kind == .occupational && pension.claimRoute == "fixed")
        #expect(PlanPensionKind.knownValues == [.statutory, .occupational, .basicPension, .privateAnnuity])
        #expect(try decode(PlanPension.self, #"{ "scheme": "fixed", "kind": "lifeInsurance" }"#).kind?.isKnown == false)
    }

    @Test func contributionsGoIntoAccountsOrSchemesYearlyOrOnce() throws {
        let yearly = #"{ "account": "pension-fund", "perYear": "5000", "until": "retirement" }"#
        let buyIn = #"{ "pension": "ch.bvg", "amount": "20000", "year": 2030 }"#
        let oneOff = #"{ "account": "pillar-3a", "amount": "7000", "year": 2027 }"#
        let schemeYearly = #"{ "pension": "ch.bvg", "perYear": "3000" }"#
        for text in [yearly, buyIn, oneOff, schemeYearly] { try roundTrips(PlanContribution.self, text) }

        let decoded = try decode(PlanContribution.self, buyIn)
        #expect(decoded == PlanContribution(pension: "ch.bvg", amount: 20_000, year: 2030))
        #expect(decoded.isOneOff && decoded.account.rawValue.isEmpty && decoded.perYear == 0)
        #expect(try decode(PlanContribution.self, oneOff) == PlanContribution(account: "pillar-3a", amount: 7_000, year: 2027))
        #expect(try decode(PlanContribution.self, schemeYearly) == PlanContribution(pension: "ch.bvg", perYear: 3_000))
        #expect(!(try decode(PlanContribution.self, yearly)).isOneOff)

        // Without a scheme an account is still required, and without a one-off amount a yearly one.
        #expect(throws: DecodingError.self) { try decode(PlanContribution.self, #"{ "perYear": "1" }"#) }
        #expect(throws: DecodingError.self) { try decode(PlanContribution.self, #"{ "account": "a" }"#) }
    }

    @Test func returnAssumptionsMayGiveAnIncomeYield() throws {
        try roundTrips(ReturnAssumption.self, #"{ "real": "0.045", "volatility": "0.17", "incomeYield": "0.02" }"#)
        #expect(try decode(ReturnAssumption.self, #"{ "real": "0.01", "volatility": "0.06" }"#).incomeYield == nil)
        #expect(PlanAssumptions.defaultReturns.values.allSatisfy { $0.incomeYield == nil })
    }

    @Test func instrumentsMayStateTheirFundTypeAndDeliveryClaim() throws {
        let text = #"{ "fundType": "foreignRealEstate", "deliveryClaim": true, "govBondShare": "0.1", "note": "x" }"#
        try roundTrips(InstrumentTax.self, text)
        let tax = try decode(InstrumentTax.self, text)
        #expect(tax.fundType == .foreignRealEstate && tax.deliveryClaim == true)
        #expect(tax.govBondShare == Self.d("0.1") && tax.details == ["note": "x"])
        #expect(FundType.knownValues == [.equity, .mixed, .realEstate, .foreignRealEstate, .other])
        #expect(InstrumentTax().fundType == nil && InstrumentTax().deliveryClaim == nil)
    }
}
