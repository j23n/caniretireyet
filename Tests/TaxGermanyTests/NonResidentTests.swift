@testable import TaxGermany
import TaxKit
import Testing

/// Germany as the paying country: the tax it charges a non-resident on
/// German pensions the plan says the paying country taxes (TaxKit gap G8).
/// Made-up people.
struct NonResidentTests {
    let system = Germany.system
    let drv = FixedYear.Pension(id: "drv", scheme: "de.drv", amount: 20_409.6, taxedIn: .source, startYear: 2030)
    let italian = FixedYear.Pension(id: "inps", scheme: "it.inps", amount: 15_000, startYear: 2030)

    private func year(_ citizenships: [String], residence: [TaxPlan.Residence], pensions: [FixedYear.Pension],
                      in calendarYear: Int = 2031) -> FixedYear {
        FixedYear(year: calendarYear, age: 67, pensions: pensions, citizenships: citizenships, residence: residence)
    }

    private func assessment(_ year: FixedYear, state: TaxState = .empty) throws -> TaxAssessment? {
        system.prepareNonResident(year, state: state, parameters: try Germany.parameters(year.year))?.fixedAssessment
    }

    private var tariff: ZoneTariff {
        get throws { try GermanParameters(Germany.parameters()).tariff }
    }

    @Test func isThePayingCountryOfGermanPensions() {
        #expect(system.country == "DE")
    }

    @Test func aGermanNationalLivingInItaly() throws {
        let living = [TaxPlan.Residence(from: 2026, system: "it")]
        let result = try #require(try assessment(year(["DE"], residence: living, pensions: [drv, italian])))
        // 2031: the exempt 14% fixed from this year's amount; the €102 lump sum;
        // no basic allowance (the Italian pension is more than 10% of the
        // income and above the allowance): the tariff on taxable income + 12,348.
        let taxable = 0.86 * 20_409.6 - 102
        #expect(abs(result.total(GermanLine.incomeTax) - (try tariff.tax(on: taxable + 12_348))) < 1e-6)
        #expect(result.lines.allSatisfy { $0.subject == "drv" } && result.total(GermanLine.soli) == 0)
        #expect(result.issues.isEmpty)
        #expect(abs(result.nextState["de.pension.drv.exemptAmount"]! - 0.14 * 20_409.6) < 1e-9)

        // With only German income, taxed as a resident (§1 Abs. 3).
        let alone = try #require(try assessment(year(["DE"], residence: living, pensions: [drv])))
        #expect(abs(alone.total(GermanLine.incomeTax) - (try tariff.tax(on: taxable))) < 1e-6)
    }

    @Test func theTreatyGivesSomePensionsToTheResidenceCountry() throws {
        let living = [TaxPlan.Residence(from: 2026, system: "it")]
        // An Italian national (or a dual national): Italy taxes the DRV pension.
        for citizenships in [["IT"], ["IT", "DE"]] {
            let result = try #require(try assessment(year(citizenships, residence: living, pensions: [drv, italian])))
            #expect(result.lines.isEmpty && result.issues.map(\.code) == ["de.nonResident.residenceTaxes"])
        }
        // Without citizenships, Germany taxes it as the plan says, with a warning.
        let unknown = try #require(try assessment(year([], residence: living, pensions: [drv, italian])))
        #expect(unknown.total(GermanLine.incomeTax) > 0)
        #expect(unknown.issues.map(\.code) == ["de.treaty.citizenshipUnknown"])
        // A Rürup pension: Italy taxes it (Art. 18).
        let ruerup = FixedYear.Pension(id: "ruerup", scheme: "fixed", amount: 6_000, taxedIn: .source, kind: .basicPension,
                                       startYear: 2030, sourceCountry: "de")
        let privatePension = try #require(try assessment(year(["DE"], residence: living, pensions: [ruerup])))
        #expect(privatePension.lines.isEmpty)
        // No German pension: nothing to say.
        #expect(try assessment(year(["DE"], residence: living, pensions: [italian])) == nil)
    }

    @Test func movingToSwitzerland() throws {
        let living = [TaxPlan.Residence(from: 2010, system: "de"), TaxPlan.Residence(from: 2027, system: "ch")]
        // The year of the move and the 5 after: Germany taxes German income.
        let soon = try #require(try assessment(year(["DE"], residence: living, pensions: [drv, italian], in: 2030)))
        #expect(soon.total(GermanLine.incomeTax) > 0)
        #expect(soon.issues.map(\.code) == ["de.treaty.CH.extendedTaxation"])
        // Later, Switzerland (Art. 18); and never for a Swiss national.
        let later = try #require(try assessment(year(["DE"], residence: living, pensions: [drv, italian], in: 2033)))
        #expect(later.lines.isEmpty && later.issues.map(\.code) == ["de.nonResident.residenceTaxes"])
        let swiss = try #require(try assessment(year(["DE", "CH"], residence: living, pensions: [drv, italian],
                                                     in: 2030)))
        #expect(swiss.lines.isEmpty)
    }

    @Test func withoutATreatyGermanyTaxes() throws {
        let living = [TaxPlan.Residence(from: 2026, system: "generic")]
        let result = try #require(try assessment(year(["DE"], residence: living, pensions: [drv, italian])))
        #expect(result.total(GermanLine.incomeTax) > 0 && result.issues.isEmpty)
        // In another currency, converted.
        var francs = year(["DE"], residence: living, pensions: [drv, italian])
        francs.currencyRate = 1.05
        francs.pensions = francs.pensions.map { var pension = $0; pension.amount /= 1.05; return pension }
        let converted = try #require(try assessment(francs))
        #expect(abs(converted.total(GermanLine.incomeTax) - result.total(GermanLine.incomeTax) / 1.05) < 1e-6)
    }

    @Test func theStateCarriesOn() throws {
        let living = [TaxPlan.Residence(from: 2026, system: "it")]
        let state: TaxState = ["de.pension.drv.exemptAmount": 2_000, "other.key": 1]
        let result = try #require(try assessment(year(["DE"], residence: living, pensions: [drv, italian]), state: state))
        #expect(result.nextState["de.pension.drv.exemptAmount"] == 2_000 && result.nextState["other.key"] == 1)
        let taxable = 20_409.6 - 2_000 - 102
        #expect(abs(result.total(GermanLine.incomeTax) - (try tariff.tax(on: taxable + 12_348))) < 1e-6)
    }
}
