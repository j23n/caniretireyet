@testable import TaxGermany
import TaxKit
import Testing

/// Living in Germany with a foreign pension the plan says the paying country
/// taxes: Germany taxes it when the treaty gives it Germany, or when no
/// treaty is known, and credits the paying country's tax (`sourceTax`, which
/// the planner sets from that country's system) up to the German tax on it
/// (§34c Abs. 1). Made-up people and amounts.
struct ForeignTaxCreditTests {
    /// Private cover with a negligible premium, so no contributions are deducted.
    static let privateCover: OptionValues = ["healthInsurance": "pkv", "retirementHealthInsurance": "pkv",
                                             "pkvPremium": "0.0001"]
    let drv = FixedYear.Pension(id: "drv", scheme: "de.drv", amount: 20_409.6, startYear: 2030)

    private func inps(_ sourceTax: Double?, amount: Double = 12_000) -> FixedYear.Pension {
        FixedYear.Pension(id: "inps", scheme: "it.inps", amount: amount, taxedIn: .source, startYear: 2030,
                          sourceTax: sourceTax)
    }

    private func abroad(_ id: String, _ amount: Double, country: String? = "XA", taxedIn: FixedYear.TaxedIn = .source,
                        sourceTax: Double? = nil) -> FixedYear.Pension {
        FixedYear.Pension(id: id, scheme: "fixed", amount: amount, taxedIn: taxedIn, kind: .statutory, startYear: 2030,
                          sourceCountry: country, sourceTax: sourceTax)
    }

    private func assess(_ pensions: [FixedYear.Pension], citizenships: [String] = ["DE"], options: OptionValues? = nil,
                        currencyRate: Double = 1, state: TaxState = .empty) throws -> TaxAssessment {
        try Germany.prepare(FixedYear(year: 2031, age: 68, systemOptions: options ?? Self.privateCover,
                                      pensions: pensions, currencyRate: currencyRate, citizenships: citizenships),
                            state: state).fixedAssessment
    }

    private func credits(_ assessment: TaxAssessment) -> [String: Double] {
        assessment.lines.filter { $0.id == GermanLine.foreignTaxCredit }
            .reduce(into: [:]) { $0[$1.subject ?? "", default: 0] += $1.amount }
    }

    @Test func aTreatyPensionTaxedAtSourceIsCreditedUpToTheGermanTaxOnIt() throws {
        // A German national: the treaty gives Germany the INPS pension (Art. 19(4)).
        let none = try assess([drv, inps(nil)])
        #expect(credits(none).isEmpty)
        let tax = none.total(GermanLine.incomeTax)
        // The INPS pension's share of the income: its taxable part less its share of the €102.
        let taxed = 0.86 * 20_409.6 + 0.86 * 12_000
        let share = 0.86 * 12_000 * (taxed - 102) / taxed / (taxed - 102)
        let cap = tax * share
        for paid in [300.0, 5_000] {
            let result = try assess([drv, inps(paid)])
            #expect(abs(result.total(GermanLine.incomeTax) - tax) < 1e-6)
            #expect(abs(credits(result)["inps"]! + min(paid, cap)) < 1e-6)
            #expect(abs(result.totalTax - (tax - min(paid, cap))) < 1e-6)
            #expect(result.issues.map(\.code) == ["de.treaty.taxedInResidence"])
        }
    }

    @Test func theCreditIsInThePlansCurrency() throws {
        // A plan in francs: 1 CHF = 1.05 EUR (the negligible PKV premium is in francs too).
        let euros = try assess([drv, inps(300)])
        let rate = 1.05
        let francs = try assess([
            FixedYear.Pension(id: "drv", scheme: "de.drv", amount: 20_409.6 / rate, startYear: 2030),
            inps(300 / rate, amount: 12_000 / rate),
        ], currencyRate: rate)
        #expect(abs(credits(francs)["inps"]! - credits(euros)["inps"]! / rate) < 1e-6)
        #expect(abs(francs.totalTax - euros.totalTax / rate) < 1e-4)
    }

    @Test func aPensionTheTreatyLeavesToThePayingCountryGetsNoCredit() throws {
        // An Italian national: Italy taxes the INPS pension; Germany exempts it
        // with the progression clause, whatever Italy charged.
        let without = try assess([drv, inps(nil)], citizenships: ["IT"])
        let with = try assess([drv, inps(1_500)], citizenships: ["IT"])
        #expect(credits(with).isEmpty && with == without)
    }

    @Test func withoutATreatyGermanyTaxesAndCredits() throws {
        // XA (made up) has no treaty in the parameters: Germany taxes its pension
        // as world income, as if the plan said residence, and warns once.
        let atHome = try assess([drv, abroad("xa", 10_000, taxedIn: .residence)])
        let atSource = try assess([drv, abroad("xa", 10_000)])
        #expect(abs(atSource.totalTax - atHome.totalTax) < 1e-9 && atHome.issues.isEmpty)
        #expect(atSource.issues.map(\.code) == ["de.treaty.none"] && atSource.issues[0].message.contains("XA"))
        let next = try assess([drv, abroad("xa", 10_000)], state: atSource.nextState)
        #expect(next.issues.isEmpty)
        // With XA's tax known, it's credited.
        let credited = try assess([drv, abroad("xa", 10_000, sourceTax: 400)])
        #expect(abs(credits(credited)["xa"]! + 400) < 1e-9)
        #expect(abs(credited.totalTax - (atHome.totalTax - 400)) < 1e-9)
        // A pension that names no country: taxed, nothing known to credit.
        let unnamed = try assess([drv, abroad("somewhere", 10_000, country: nil)])
        #expect(abs(unnamed.totalTax - atHome.totalTax) < 1e-9 && credits(unnamed).isEmpty)
        #expect(unnamed.issues.map(\.code) == ["de.treaty.none"])
        #expect(unnamed.issues[0].message.contains("names no paying country"))
    }

    @Test func theCapIsPerCountry() throws {
        // Two XA pensions, only one charged there: XA's cap covers both (§68a EStDV).
        let none = try assess([drv, abroad("a", 10_000), abroad("b", 10_000)])
        let tax = none.total(GermanLine.incomeTax)
        let taxed = 0.86 * (20_409.6 + 20_000)
        let cap = tax * 0.86 * 20_000 / taxed
        let result = try assess([drv, abroad("a", 10_000, sourceTax: 5_000), abroad("b", 10_000)])
        #expect(abs(credits(result)["a"]! + cap) < 1e-6 && credits(result)["b"] == nil)
        // More than the cap of the first pension alone.
        #expect(cap > tax * 0.86 * 10_000 / taxed)
    }

    @Test func theCreditComesBeforeSoliAndChurchTax() throws {
        let options: OptionValues = ["healthInsurance": "pkv", "retirementHealthInsurance": "pkv",
                                     "pkvPremium": "0.0001", "churchMember": true]
        let result = try assess([abroad("big", 90_000, taxedIn: .residence),
                                 abroad("xa", 40_000, sourceTax: 6_000)], options: options)
        let incomeTax = result.total(GermanLine.incomeTax) + result.total(GermanLine.foreignTaxCredit)
        let p = try GermanParameters(Germany.parameters())
        #expect(result.total(GermanLine.foreignTaxCredit) < 0)
        #expect(abs(result.total(GermanLine.soli) - p.soli.amount(onIncomeTax: incomeTax)) < 1e-6)
        #expect(abs(result.total(GermanLine.churchTax) - p.churchRate(in: nil) * incomeTax) < 1e-6)
        let soliLine = try #require(result.lines.first { $0.id == GermanLine.soli })
        #expect(abs(soliLine.base! - incomeTax) < 1e-9)
    }

    @Test func marketIncomeChangesTheCap() throws {
        // A bAV payout at the tariff raises the total income and the average
        // rate: the cap, the average rate on the pension's income, is
        // recomputed on the path's assessment and rises.
        let year = FixedYear(year: 2031, age: 68, systemOptions: Self.privateCover,
                             pensions: [drv, abroad("xa", 10_000, sourceTax: 5_000)], citizenships: ["DE"])
        let prepared = try Germany.prepare(year)
        let fixed = prepared.fixedAssessment
        let path = prepared.assess(VariableYear(payouts: [.init(wrapper: GermanWrapper.bav, amount: 20_000,
                                                                form: .annuity)]))
        #expect(credits(path)["xa"]! < credits(fixed)["xa"]!)
        #expect(path.total(GermanLine.incomeTax) > fixed.total(GermanLine.incomeTax))
    }
}
