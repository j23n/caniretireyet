import Foundation
@testable import TaxItaly
import TaxKit
import Testing

/// Pensions from Switzerland and Germany received in Italy, and Italian
/// pensions of someone living abroad (`prepareNonResident`). The amounts
/// are checked by hand in the reference cases; these check the rules
/// around them. Made-up people and amounts.
struct ForeignPensionTests {
    private func pension(_ id: String, _ amount: Double, from country: String?, kind: PensionKind? = nil,
                         scheme: String = "fixed", taxedIn: FixedYear.TaxedIn = .residence, startYear: Int? = nil,
                         sourceTax: Double? = nil, form: VariableYear.PayoutForm = .annuity) -> FixedYear.Pension {
        FixedYear.Pension(id: id, scheme: scheme, amount: amount, taxedIn: taxedIn, kind: kind, startYear: startYear,
                          sourceCountry: country, form: form, sourceTax: sourceTax)
    }

    private func year(_ pensions: [FixedYear.Pension], citizenships: [String] = ["IT"],
                      residence: [TaxPlan.Residence] = []) -> FixedYear {
        FixedYear(year: 2026, age: 68, systemOptions: Italy.addizionali, pensions: pensions,
                  citizenships: citizenships, residence: residence)
    }

    @Test func aPensionsCountry() {
        let country = ItalyPensionTreatment.country
        #expect(country(pension("a", 1, from: nil, scheme: "ch.bvg")) == "CH")
        #expect(country(pension("a", 1, from: nil, scheme: "it.inps")) == "IT")
        #expect(country(pension("a", 1, from: nil)) == nil)
        #expect(country(pension("a", 1, from: nil, scheme: "generic.x")) == nil)
        #expect(country(pension("a", 1, from: "de", scheme: "ch.bvg")) == "DE")
    }

    @Test func theGermanTaxableShareByStartYear() throws {
        let rules = try ItalyParameters(Italy.parameters()).foreignPensions
        let share = { (year: Int) in rules.germanStatutoryShare(startYear: year) }
        #expect(share(1990) == 0.5 && share(2005) == 0.5)
        #expect(abs(share(2013) - 0.66) < 1e-12 && abs(share(2021) - 0.81) < 1e-12)
        #expect(abs(share(2023) - 0.825) < 1e-12 && abs(share(2026) - 0.84) < 1e-12)
        #expect(abs(share(2040) - 0.91) < 1e-12)
        #expect(share(2058) == 1 && share(2070) == 1)
        #expect(rules.swissFlatRate == 0.05)
    }

    @Test func swissPensionsPayTheFlatTaxOutsideIrpef() throws {
        let calculator = try Italy.calculate(year([
            pension("ahv", 30_000, from: "CH", kind: .statutory),
            pension("bvg", 20_000, from: nil, kind: nil, scheme: "ch.bvg"),
        ]))
        // Nothing in IRPEF: no total income, no pension detrazione, no addizionali.
        #expect(calculator.irpef.totalIncome == 0 && calculator.irpef.pensionDetrazione == 0)
        let assessment = try Italy.prepare(year([
            pension("ahv", 30_000, from: "CH", kind: .statutory),
            pension("bvg", 20_000, from: nil, kind: nil, scheme: "ch.bvg"),
        ])).fixedAssessment
        #expect(assessment.lines.map(\.id) == ["it.swissPensionTax", "it.swissPensionTax"])
        #expect(abs(assessment.totalTax - 2_500) < 1e-9)
        #expect(assessment.lines.first?.label == "Imposta sostitutiva on Swiss pensions (5%)")
        #expect(assessment.issues.isEmpty)
    }

    @Test func swissPensionsInAnotherCurrency() throws {
        // 1 franc is 1.05 euros: a flat tax is the same share in any currency, and the credit converts too.
        var francs = year([pension("ahv", 20_000, from: "CH", kind: .statutory, taxedIn: .source, sourceTax: 300)])
        francs.currencyRate = 1.05
        let assessment = try Italy.prepare(francs).fixedAssessment
        #expect(abs(assessment.total("it.swissPensionTax") - 1_000) < 1e-9)
        #expect(abs(assessment.total("it.foreignTaxCredit") + 300) < 1e-9)
    }

    @Test func aGermanPensionTaxedInItalyCreditsTheGermanTax() throws {
        // An Italian citizen's DRV pension that the plan says Germany taxes: Italy taxes it and
        // credits the German tax, up to the IRPEF on it (all of IRPEF here).
        let drv = { (tax: Double) in
            self.pension("drv", 15_000, from: "DE", kind: .statutory, taxedIn: .source, startYear: 2026, sourceTax: tax)
        }
        let small = try Italy.prepare(year([drv(300)])).fixedAssessment
        #expect(abs(small.total("it.foreignTaxCredit") + 300) < 1e-9)
        #expect(small.issues.map(\.code) == ["it.treaty.taxedIn"])
        let large = try Italy.prepare(year([drv(5_000)])).fixedAssessment
        #expect(abs(large.total("it.foreignTaxCredit") + large.total("it.irpef")) < 1e-9)
        // With another income, only the pension's share of IRPEF is credited (TUIR art. 165).
        let shared = try Italy.prepare(year([drv(5_000), pension("inps", 12_600, from: "IT", scheme: "it.inps")]))
            .fixedAssessment
        #expect(abs(shared.total("it.foreignTaxCredit") + shared.total("it.irpef") / 2) < 1e-9)
    }

    @Test func otherCountriesAndItalyFollowTaxedIn() throws {
        let plain = try Italy.prepare(Italy.pensionYear(20_000)).fixedAssessment
        for country in ["IT", "FR", "US"] {
            let mixed = try Italy.prepare(year([
                pension("inps", 20_000, from: country, scheme: "it.inps"),
                pension("other", 9_000, from: country, taxedIn: .source, sourceTax: 2_000),
            ])).fixedAssessment
            #expect(abs(mixed.totalTax - plain.totalTax) < 1e-9, "\(country)")
            #expect(mixed.issues.isEmpty)
        }
    }

    @Test func treatyWarningsAreGivenOnce() throws {
        // A German citizen's DRV pension with taxedIn residence, and the same warning in later years.
        let drv = pension("drv", 15_000, from: "DE", kind: .statutory, startYear: 2024)
        let assessment = try Italy.prepare(year([drv], citizenships: ["DE"])).fixedAssessment
        #expect(assessment.issues.count == 1 && assessment.issues[0].year == nil)
        let years = (2026...2028).map { y -> FixedYear in var year = year([drv], citizenships: ["DE"]); year.year = y; return year }
        let issues = Italy.system.validate(TaxPlan(residence: [.init(from: 2026, system: "it")]), years: years,
                                           parameters: Italy.system.parameters)
        #expect(issues.filter { $0.code == "it.treaty.taxedIn" }.count == 1)
    }

    @Test func italyIsTheCountryOfItalianPensionsPaidAbroad() throws {
        #expect(Italy.system.country == "IT")
        let registry = TaxRegistry([ItalyTaxSystem()])
        #expect(registry.system(forCountry: "it")?.id == "it")
    }

    @Test func nonResidentsPayIrpefInThePlansCurrency() throws {
        var abroad = year([pension("inps", 24_000, from: "IT", scheme: "it.inps", taxedIn: .source)],
                          residence: [.init(from: 2026, system: "generic")])
        let euros = try #require(Italy.system.prepareNonResident(abroad, state: ["x": 1],
                                                                 parameters: try Italy.parameters())).fixedAssessment
        #expect(euros.nextState == ["x": 1] && euros.issues.isEmpty && euros.contributions.isEmpty)
        #expect(Set(euros.lines.map(\.id)) == ["it.nonResident.irpef", "it.nonResident.addizionaleRegionale",
                                               "it.nonResident.addizionaleComunale"])
        #expect(euros.lines.allSatisfy { $0.subject == "inps" })
        // The same pension stated as 19,200 units, each worth 1.25 euros.
        abroad.pensions[0].amount = 19_200
        abroad.currencyRate = 1.25
        let units = try #require(Italy.system.prepareNonResident(abroad, state: .empty,
                                                                 parameters: try Italy.parameters())).fixedAssessment
        #expect(abs(units.totalTax * 1.25 - euros.totalTax) < 1e-9)
        // Every path's assessment is the fixed one.
        let prepared = try #require(Italy.system.prepareNonResident(abroad, state: .empty,
                                                                    parameters: try Italy.parameters()))
        #expect(prepared.assess(VariableYear(sales: [.init(wrapper: "it.ordinary", category: .fund, proceeds: 100,
                                                           costBasis: 0)])) == units)
    }

    @Test func nonResidentTreatyWarnings() throws {
        let inps = pension("inps", 24_000, from: "IT", scheme: "it.inps", taxedIn: .source)
        let fund = pension("fund", 6_000, from: "IT", kind: .occupational, taxedIn: .source)
        func codes(_ citizenships: [String], _ system: String, _ pensions: [FixedYear.Pension]) throws -> [String] {
            let year = year(pensions, citizenships: citizenships, residence: [.init(from: 2020, system: system)])
            return try #require(Italy.system.prepareNonResident(year, state: .empty, parameters: try Italy.parameters()))
                .fixedAssessment.issues.map(\.code)
        }
        #expect(try codes(["IT"], "de", [inps]).isEmpty)
        #expect(try codes(["IT", "DE"], "de", [inps]) == ["it.nonResident.treaty"])
        #expect(try codes([], "de", [inps]) == ["it.nonResident.treaty"])
        #expect(try codes(["IT"], "de", [fund]) == ["it.nonResident.treaty"])
        #expect(try codes(["IT"], "ch", [inps, fund]) == ["it.nonResident.treaty"])
        #expect(try codes(["IT"], "generic", [inps, fund]).isEmpty)
    }

    @Test func swissPensionWrappersOwnNoWealthTaxAndGrossUpExactly() throws {
        let prepared = try Italy.prepare(FixedYear(year: 2026, age: 66, systemOptions: Italy.addizionali))
        let held = prepared.assess(VariableYear(balances: [
            .init(wrapper: "ch.vestedBenefits", category: .fund, country: "CH", value: 100_000),
            .init(wrapper: "ch.pillar3a", category: .fund, country: "CH", value: 50_000),
        ]))
        #expect(held.lines.isEmpty && held.issues.isEmpty)
        let bucket = BucketSnapshot(wrapper: "ch.vestedBenefits", value: 100_000, costBasis: 80_000,
                                    categoryShares: [.fund: 1])
        #expect(prepared.grossUp(net: 9_500, from: bucket) == 10_000)
        var pillar = bucket
        pillar.wrapper = "ch.pillar3a"
        #expect(prepared.grossUp(net: 9_500, from: pillar) == nil)
        // A pillar 3a annuity is IRPEF at the marginal rate, without the warnings for unknown wrappers.
        let annuity = prepared.assess(VariableYear(payouts: [.init(wrapper: "ch.pillar3a", amount: 3_000, form: .annuity)]))
        #expect(annuity.lines.map(\.id) == ["it.taxDeferredPayout"] && annuity.issues.isEmpty)
    }
}
