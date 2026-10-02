import Foundation
import TaxKit
import Testing

/// A made-up paying country, "XA": it taxes non-residents 10% of each
/// pension it pays (a line per pension) plus a fixed 50 shared by all of
/// them, and keeps a count of such years in the state. Not a real rule set.
private struct PayingSystem: TaxSystem {
    let base = try! FakeTaxSystem()
    var id: String { "paying" }
    var name: String { "Paying" }
    var country: String? { "XA" }
    var options: [OptionField] { base.options }
    var regimes: [RegimeDescriptor] { [] }
    var wrappers: [WrapperRule] { [] }
    var pensionSchemes: [any PensionScheme] { [] }
    var parameters: any ParameterStore { base.parameters }

    func defaultRegime(for kind: EarnedIncomeKind) -> String? { nil }

    func validate(_ plan: TaxPlan, parameters: any ParameterStore) -> [TaxIssue] { [] }

    func prepare(_ year: FixedYear, state: TaxState, parameters: ParameterSet) -> any PreparedTaxYear {
        base.prepare(year, state: state, parameters: parameters)
    }

    func prepareNonResident(_ year: FixedYear, state: TaxState, parameters: ParameterSet) -> (any PreparedTaxYear)? {
        var lines = year.pensions.map {
            TaxLine(id: "paying.pension", label: "Non-resident tax", amount: 0.1 * $0.amount, base: $0.amount,
                    subject: $0.id)
        }
        lines.append(TaxLine(id: "paying.fee", label: "Fee", amount: 50))
        var next = state
        next["paying.years"] = (state["paying.years"] ?? 0) + 1
        return FakePreparedYear(fixed: TaxAssessment(lines: lines, nextState: next), gainsRate: 0)
    }
}

/// G8: the paying country's tax on pensions taxed at source.
struct NonResidentContractTests {
    @Test func existingSystemsBelongToNoCountryAndTaxNoNonResidents() throws {
        let system = try FakeTaxSystem()
        #expect(system.country == nil)
        let year = FixedYear(year: 2026, age: 70, pensions: [.init(id: "p", scheme: "fixed", amount: 1_000,
                                                                   taxedIn: .source)])
        #expect(system.prepareNonResident(year, state: .empty, parameters: try system.parameters.parameters(for: 2026))
            == nil)
        #expect(FixedYear.Pension(id: "p", scheme: "fixed", amount: 1).sourceTax == nil)
    }

    @Test func aPayingSystemIsFoundAndCalledThroughTheProtocol() throws {
        let registry = TaxRegistry([try FakeTaxSystem(), PayingSystem()])
        let paying = try #require(registry.system(forCountry: "xa"))
        #expect(paying.id == "paying")
        #expect(registry.system(forCountry: "XB") == nil)
        let year = FixedYear(year: 2026, age: 70, pensions: [
            .init(id: "a", scheme: "fixed", amount: 3_000, taxedIn: .source, sourceCountry: "XA"),
            .init(id: "b", scheme: "fixed", amount: 1_000, taxedIn: .source, sourceCountry: "XA"),
        ])
        let prepared = try #require(paying.prepareNonResident(year, state: ["other": 1],
                                                              parameters: try paying.parameters.parameters(for: 2026)))
        let assessment = prepared.fixedAssessment
        #expect(assessment.totalTax == 450)
        #expect(assessment.nextState == ["other": 1, "paying.years": 1])
        // Each pension's tax: its own line, and the fee shared 3 to 1.
        let byPension = assessment.taxByPension(year.pensions)
        #expect(byPension == ["a": 337.5, "b": 112.5])

        var residence = year
        residence.pensions[0].sourceTax = byPension["a"]
        #expect(residence.pensions[0].sourceTax == 337.5 && residence.pensions[1].sourceTax == nil)
    }

    @Test func taxByPensionSharesWhatBelongsToNoPension() {
        let pensions: [FixedYear.Pension] = [
            .init(id: "a", scheme: "fixed", amount: 2_000), .init(id: "b", scheme: "fixed", amount: 0),
        ]
        let assessment = TaxAssessment(lines: [
            TaxLine(id: "x", label: "X", amount: 100, subject: "b"),
            TaxLine(id: "y", label: "Y", amount: 40),
            TaxLine(id: "z", label: "Z", amount: 10, subject: "work-0"),
        ], contributions: [TaxLine(id: "c", label: "C", amount: 999, subject: "a")])
        #expect(assessment.taxByPension(pensions) == ["a": 50, "b": 100])
        // Without amounts, shared lines are split evenly.
        let zero = pensions.map { var pension = $0; pension.amount = 0; return pension }
        #expect(assessment.taxByPension(zero) == ["a": 25, "b": 125])
        #expect(TaxAssessment().taxByPension(pensions) == ["a": 0, "b": 0])
    }
}
