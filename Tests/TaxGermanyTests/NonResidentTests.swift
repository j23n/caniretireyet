@testable import TaxGermany
import TaxKit
import Testing

/// Germany as the paying country: the tax it charges a non-resident on
/// German pensions the plan says the paying country taxes (TaxKit's G8),
/// given what the planner passes: only those pensions. Made-up people.
struct NonResidentTests {
    let system = Germany.system
    /// A DRV pension as the planner passes it: paid from Germany, taxed there.
    let drv = FixedYear.Pension(id: "drv", scheme: "de.drv", amount: 20_409.6, taxedIn: .source, startYear: 2030,
                                sourceCountry: "DE")
    let italy = [TaxPlan.Residence(from: 2026, system: "it")]

    private func year(_ citizenships: [String], residence: [TaxPlan.Residence], pensions: [FixedYear.Pension],
                      in calendarYear: Int = 2031) -> FixedYear {
        FixedYear(year: calendarYear, age: 67, pensions: pensions, citizenships: citizenships, residence: residence)
    }

    private func assessment(_ year: FixedYear, state: TaxState = .empty) throws -> TaxAssessment? {
        system.prepareNonResident(year, state: state, parameters: try Germany.parameters(year.year))?.fixedAssessment
    }

    private func ruerup(_ amount: Double) -> FixedYear.Pension {
        FixedYear.Pension(id: "ruerup", scheme: "fixed", amount: amount, taxedIn: .source, kind: .basicPension,
                          startYear: 2030, sourceCountry: "DE")
    }

    private var tariff: ZoneTariff {
        get throws { try GermanParameters(Germany.parameters()).tariff }
    }

    /// The 2031 taxable part of the DRV pension: the exempt 14% fixed, less the €102 lump sum.
    private let drvIncome = 0.86 * 20_409.6 - 102

    @Test func isThePayingCountryOfGermanPensions() {
        #expect(system.country == "DE")
    }

    @Test func aGermanNationalLivingInItaly() throws {
        let result = try #require(try assessment(year(["DE"], residence: italy, pensions: [drv])))
        // All the income Germany sees is German: taxed as a resident (§1 Abs. 3),
        // with the basic allowance and the €36 lump sum, and a warning.
        #expect(abs(result.total(GermanLine.nonResidentIncomeTax) - (try tariff.tax(on: drvIncome - 36))) < 1e-6)
        #expect(result.total(GermanLine.nonResidentSoli) == 0 && result.total(GermanLine.incomeTax) == 0)
        #expect(result.lines.allSatisfy { $0.subject == "drv" && $0.label == "Income tax (non-resident)" })
        #expect(result.issues.map(\.code) == ["de.nonResident.taxedAsResident"] && result.issues[0].year == nil)
        #expect(abs(result.nextState["de.pension.drv.exemptAmount"]! - 0.14 * 20_409.6) < 1e-9)
        // The planner gives each pension the lines naming it.
        #expect(abs(result.taxByPension([drv])["drv"]! - result.totalTax) < 1e-9)
    }

    @Test func eachPensionGetsItsOwnTax() throws {
        let occupational = FixedYear.Pension(id: "bav", scheme: "fixed", amount: 6_000, taxedIn: .source,
                                             kind: .occupational, startYear: 2030, sourceCountry: "DE")
        // Living under generic (no treaty): Germany taxes both, the bAV in full.
        let living = [TaxPlan.Residence(from: 2026, system: "generic")]
        let result = try #require(try assessment(year(["DE"], residence: living, pensions: [drv, occupational])))
        let total = try tariff.tax(on: drvIncome + 102 + 6_000 - 102 - 36)
        #expect(abs(result.totalTax - total) < 1e-6)
        let byPension = result.taxByPension([drv, occupational])
        let drvShare = (drvIncome + 102) / (drvIncome + 102 + 6_000)
        #expect(abs(byPension["drv"]! - total * drvShare) < 1e-6)
        #expect(abs(byPension["bav"]! - total * (1 - drvShare)) < 1e-6)
    }

    @Test func germanPensionsTheTreatyLeavesAbroadCountForTheResidentTest() throws {
        // A Rürup pension is Italy's (Art. 18), but counts as income not taxed in
        // Germany: 86% × 16,000 = 13,760 is more than 10% and the basic
        // allowance, so no resident treatment (§50 Abs. 1 Satz 2).
        let large = try #require(try assessment(year(["DE"], residence: italy, pensions: [drv, ruerup(16_000)])))
        #expect(abs(large.total(GermanLine.nonResidentIncomeTax) - (try tariff.tax(on: drvIncome + 12_348))) < 1e-6)
        #expect(large.issues.map(\.code) == ["de.nonResident.residenceTaxes"])
        #expect(large.lines.allSatisfy { $0.subject == "drv" })
        #expect(abs(large.nextState["de.pension.ruerup.exemptAmount"]! - 0.14 * 16_000) < 1e-9)
        // 86% × 10,000 = 8,600 is under the allowance: taxed as a resident, the
        // Rürup pension raising the rate (§32b Abs. 1 Nr. 5).
        let small = try #require(try assessment(year(["DE"], residence: italy, pensions: [drv, ruerup(10_000)])))
        let x = drvIncome - 36
        let progressive = x * (try tariff.tax(on: x + 8_600)) / (x + 8_600)
        #expect(abs(small.total(GermanLine.nonResidentIncomeTax) - progressive) < 1e-6)
        #expect(small.issues.map(\.code).sorted() == ["de.nonResident.residenceTaxes", "de.nonResident.taxedAsResident"])
    }

    @Test func onlyGermanPensionsAreGermanys() throws {
        // A direct caller passing more than the planner does: other pensions
        // and work aren't Germany's to tax and don't change the result.
        let inps = FixedYear.Pension(id: "inps", scheme: "it.inps", amount: 15_000, startYear: 2030)
        var more = year(["DE"], residence: italy, pensions: [drv, inps])
        more.work = [.init(phaseID: "work", kind: .employee, gross: 30_000)]
        let alone = try #require(try assessment(year(["DE"], residence: italy, pensions: [drv])))
        #expect(try assessment(more) == alone)
        #expect(try assessment(year(["DE"], residence: italy, pensions: [inps])) == nil)
    }

    @Test func theTreatyGivesSomePensionsToTheResidenceCountry() throws {
        // An Italian national (or a dual national): Italy taxes the DRV pension;
        // Germany still fixes its exempt amount in the state.
        for citizenships in [["IT"], ["IT", "DE"]] {
            let result = try #require(try assessment(year(citizenships, residence: italy, pensions: [drv])))
            #expect(result.lines.isEmpty && result.issues.map(\.code) == ["de.nonResident.residenceTaxes"])
            #expect(result.issues.allSatisfy { $0.year == nil })
            #expect(abs(result.nextState["de.pension.drv.exemptAmount"]! - 0.14 * 20_409.6) < 1e-9)
        }
        // Without citizenships, Germany taxes it as the plan says, with a warning.
        let unknown = try #require(try assessment(year([], residence: italy, pensions: [drv])))
        #expect(unknown.total(GermanLine.nonResidentIncomeTax) > 0)
        #expect(unknown.issues.map(\.code) == ["de.treaty.citizenshipUnknown", "de.nonResident.taxedAsResident"])
        // A Rürup pension: Italy taxes it (Art. 18).
        let privatePension = try #require(try assessment(year(["DE"], residence: italy, pensions: [ruerup(6_000)])))
        #expect(privatePension.lines.isEmpty)
    }

    @Test func movingToSwitzerland() throws {
        let living = [TaxPlan.Residence(from: 2010, system: "de"), TaxPlan.Residence(from: 2027, system: "ch")]
        // The year of the move and the 5 after: Germany taxes German income.
        let soon = try #require(try assessment(year(["DE"], residence: living, pensions: [drv], in: 2030)))
        #expect(soon.total(GermanLine.nonResidentIncomeTax) > 0)
        #expect(soon.issues.map(\.code) == ["de.treaty.CH.extendedTaxation", "de.nonResident.taxedAsResident"])
        // Later, Switzerland (Art. 18); and never for a Swiss national.
        let later = try #require(try assessment(year(["DE"], residence: living, pensions: [drv], in: 2033)))
        #expect(later.lines.isEmpty && later.issues.map(\.code) == ["de.nonResident.residenceTaxes"])
        let swiss = try #require(try assessment(year(["DE", "CH"], residence: living, pensions: [drv], in: 2030)))
        #expect(swiss.lines.isEmpty)
    }

    @Test func withoutATreatyGermanyTaxes() throws {
        let living = [TaxPlan.Residence(from: 2026, system: "generic")]
        let result = try #require(try assessment(year(["DE"], residence: living, pensions: [drv])))
        #expect(abs(result.totalTax - (try tariff.tax(on: drvIncome - 36))) < 1e-6)
        #expect(result.issues.map(\.code) == ["de.nonResident.taxedAsResident"])
        // In another currency, converted: amounts in, lines out.
        var francs = year(["DE"], residence: living, pensions: [drv])
        francs.currencyRate = 1.05
        francs.pensions[0].amount /= 1.05
        let converted = try #require(try assessment(francs))
        #expect(abs(converted.totalTax - result.totalTax / 1.05) < 1e-6)
        #expect(abs(converted.nextState["de.pension.drv.exemptAmount"]! - 0.14 * 20_409.6) < 1e-9)
    }

    @Test func theStateCarriesOn() throws {
        let state: TaxState = ["de.pension.drv.exemptAmount": 2_000, "other.key": 1]
        let result = try #require(try assessment(year(["DE"], residence: italy, pensions: [drv]), state: state))
        #expect(result.nextState["de.pension.drv.exemptAmount"] == 2_000 && result.nextState["other.key"] == 1)
        let taxable = 20_409.6 - 2_000 - 102 - 36
        #expect(abs(result.totalTax - (try tariff.tax(on: taxable))) < 1e-6)
    }

    @Test func theExemptAmountIsTheSameWhereverThePersonLives() throws {
        // Living in Germany when the pension starts (2030) and is fixed (2031),
        // in Italy from 2032; and the other way round.
        let toItaly = [TaxPlan.Residence(from: 2020, system: "de"), TaxPlan.Residence(from: 2032, system: "it")]
        let fromItaly = [TaxPlan.Residence(from: 2020, system: "it"), TaxPlan.Residence(from: 2032, system: "de")]
        var pension = drv
        var start = year(["DE"], residence: toItaly, pensions: [pension], in: 2030)
        start.inflationFactor = 1
        var fixed = start
        fixed.year = 2031
        fixed.inflationFactor = 1.02
        pension.amount = 21_000
        var moved = start
        moved.year = 2032
        moved.inflationFactor = 1.0404
        moved.pensions = [pension]

        let atHome = try Germany.prepare(fixed, state: try Germany.prepare(start).fixedAssessment.nextState)
            .fixedAssessment.nextState
        var firstAbroad = start
        firstAbroad.residence = fromItaly
        let started = try #require(try assessment(firstAbroad)).nextState
        var abroad = fixed
        abroad.residence = fromItaly
        let fromAbroad = try #require(try assessment(abroad, state: started)).nextState
        let key = "de.pension.drv.exemptAmount"
        #expect(abs(atHome[key]! - 0.14 * 20_409.6 * 1.02) < 1e-9 && atHome[key] == fromAbroad[key])

        // In 2032 each side uses the amount the other fixed.
        let laterAbroad = try #require(try assessment(moved, state: atHome))
        var home = moved
        home.residence = fromItaly
        home.systemOptions = ["healthInsurance": "pkv", "retirementHealthInsurance": "pkv", "pkvPremium": "0.0001"]
        let laterAtHome = try Germany.prepare(home, state: fromAbroad).fixedAssessment
        let taxable = 21_000 - atHome[key]! / 1.0404
        #expect(laterAbroad.nextState[key] == atHome[key] && laterAtHome.nextState[key] == atHome[key])
        let p = try GermanParameters(Germany.parameters()).scaled(by: IndexingScales(
            year: moved, parameterYear: 2026, realWageGrowth: 0.01, indexFixedAllowances: false))
        #expect(abs(laterAbroad.totalTax - p.tariff.tax(on: taxable - p.pensionLumpSum - p.specialExpensesLumpSum))
            < 1e-6)
        #expect(abs(laterAtHome.total(GermanLine.incomeTax)
            - p.tariff.tax(on: taxable - p.pensionLumpSum - p.specialExpensesLumpSum)) < 0.01)
    }

    @Test func onlyTheModellingOptionsApplyAbroad() throws {
        // The options of the plan's German residence period: church membership
        // and the like don't follow the person abroad; how amounts follow
        // prices does.
        var later = year(["DE"], residence: italy, pensions: [drv], in: 2036)
        later.inflationFactor = 1.1
        let plain = try #require(try assessment(later))
        later.systemOptions = ["churchMember": true, "bundesland": "BY"]
        #expect(try assessment(later) == plain)
        later.systemOptions = ["indexFixedAllowances": true]
        let indexed = try #require(try assessment(later))
        // The €102 and €36 keep their value in today's euros: more is deducted, less is taxed.
        #expect(indexed.totalTax < plain.totalTax)
    }
}
