import TaxKit
@testable import TaxSwitzerland
import Testing

/// Pensions across the border (G8): as the residence system, which
/// foreign pensions entered as taxed at source Switzerland taxes anyway,
/// crediting the paying country's tax; as the paying country, the source
/// tax on Swiss pensions paid abroad, and when a treaty refunds it.
/// Made-up people and amounts.
struct TreatyTests {
    let system = Swiss.system

    /// A retired year in Zurich with one foreign pension taxed at source.
    func year(_ pension: FixedYear.Pension, citizenships: [String], commune: String = "Zurich") -> FixedYear {
        FixedYear(year: 2026, age: 68, systemOptions: Swiss.place(commune), pensions: [pension],
                  citizenships: citizenships)
    }

    func foreign(_ country: String, kind: PensionKind?, amount: Double = 30_000, sourceTax: Double? = 500,
                 form: VariableYear.PayoutForm = .annuity) -> FixedYear.Pension {
        FixedYear.Pension(id: "pension-0", scheme: "fixed", amount: amount, taxedIn: .source, kind: kind,
                          sourceCountry: country, form: form, sourceTax: sourceTax)
    }

    func codes(_ assessment: TaxAssessment) -> [String] {
        assessment.issues.map(\.code).sorted()
    }

    // MARK: - Living in Switzerland

    @Test func aTreatyPensionIsTaxedWhateverTaxedInSays() throws {
        let resident = FixedYear.Pension(id: "pension-0", scheme: "fixed", amount: 30_000, kind: .statutory,
                                         sourceCountry: "IT")
        let plain = try Swiss.prepare(year(resident, citizenships: ["CH"])).fixedAssessment
        let atSource = try Swiss.prepare(year(foreign("IT", kind: .statutory), citizenships: ["CH"])).fixedAssessment
        // The same tax as with taxedIn: residence, less the Italian tax credited.
        #expect(abs(atSource.total(SwissLine.foreignTaxCredit) + 500) < 1e-9)
        #expect(abs(atSource.totalTax - (plain.totalTax - 500)) < 1e-9)
        #expect(codes(atSource) == ["ch.treaty.taxedIn"] && plain.issues.isEmpty)
        #expect(atSource.lines.first { $0.id == SwissLine.foreignTaxCredit }?.subject == "pension-0")

        // Without a tax computed abroad, nothing is credited.
        let noTax = try Swiss.prepare(year(foreign("IT", kind: .statutory, sourceTax: nil), citizenships: ["CH"]))
        #expect(abs(noTax.fixedAssessment.totalTax - plain.totalTax) < 1e-9)
        // The credit is at most the Swiss tax on the pension.
        let large = try Swiss.prepare(year(foreign("IT", kind: .statutory, sourceTax: 50_000), citizenships: ["CH"]))
            .fixedAssessment
        #expect(abs(large.total(SwissLine.foreignTaxCredit) + plain.totalTax - plain.total(SwissLine.personalTax)) < 1e-9)
        #expect(abs(large.totalTax - plain.total(SwissLine.personalTax)) < 1e-9)
    }

    @Test func citizenshipDecidesForAPensionThatMayBeFromPublicService() throws {
        // An Italian citizen (dual too): Italy's (art. 19), counted for the rate only.
        for citizenships in [["IT"], ["IT", "CH"]] {
            let italian = try Swiss.prepare(year(foreign("IT", kind: .statutory), citizenships: citizenships))
                .fixedAssessment
            #expect(italian.total(SwissLine.federal) == 0 && italian.total(SwissLine.foreignTaxCredit) == 0)
            #expect(italian.issues.isEmpty)
        }
        // Unknown citizenship: Switzerland taxes it, with a warning.
        let unknown = try Swiss.prepare(year(foreign("IT", kind: nil), citizenships: [])).fixedAssessment
        #expect(codes(unknown) == ["ch.treaty.citizenship"] && unknown.total(SwissLine.federal) > 0)
        #expect(unknown.total(SwissLine.foreignTaxCredit) == -500)
        // A private annuity is never a public-service pension.
        let annuity = try Swiss.prepare(year(foreign("IT", kind: .privateAnnuity), citizenships: ["IT"])).fixedAssessment
        #expect(codes(annuity) == ["ch.treaty.taxedIn"] && annuity.total(SwissLine.federal) > 0)
    }

    @Test func aGermanStatePensionIsAlwaysSwitzerlands() throws {
        // The DRV pension of a German citizen: art. 18, not a public-service pension.
        let drv = try Swiss.prepare(year(foreign("DE", kind: .statutory), citizenships: ["DE"])).fixedAssessment
        #expect(codes(drv) == ["ch.treaty.taxedIn"] && drv.total(SwissLine.federal) > 0)
        let unknownKind = try Swiss.prepare(year(foreign("DE", kind: nil), citizenships: [])).fixedAssessment
        #expect(codes(unknownKind) == ["ch.treaty.taxedIn"])
        // An occupational pension of a German citizen may be a Beamtenpension: Germany's.
        let civil = try Swiss.prepare(year(foreign("DE", kind: .occupational), citizenships: ["DE"])).fixedAssessment
        #expect(civil.issues.isEmpty && civil.total(SwissLine.federal) == 0)
        // The message names the treaty.
        #expect(drv.issues.first?.message.contains("Germany–Switzerland treaty art. 18") == true)
    }

    @Test func pensionsFromOtherCountriesFollowTaxedIn() throws {
        for pension in [foreign("FR", kind: .statutory),
                        FixedYear.Pension(id: "pension-0", scheme: "fixed", amount: 30_000, taxedIn: .source,
                                          sourceTax: 500)] {
            let assessment = try Swiss.prepare(year(pension, citizenships: ["CH"])).fixedAssessment
            #expect(assessment.issues.isEmpty && assessment.total(SwissLine.foreignTaxCredit) == 0)
            #expect(assessment.total(SwissLine.federal) == 0 && assessment.total(SwissLine.cantonal) == 0)
        }
        // A Swiss pension is Switzerland's.
        let swiss = FixedYear.Pension(id: "pension-0", scheme: "ch.bvg", amount: 30_000, taxedIn: .source)
        let assessment = try Swiss.prepare(year(swiss, citizenships: ["CH"])).fixedAssessment
        #expect(assessment.issues.isEmpty && assessment.total(SwissLine.federal) > 0)
    }

    @Test func aForeignLumpSumIsACapitalBenefitWithTheCredit() throws {
        let lumpSum = foreign("DE", kind: .occupational, amount: 100_000, sourceTax: 1_000, form: .lumpSum)
        let prepared = try Swiss.prepare(year(lumpSum, citizenships: ["CH"]))
        let fixed = prepared.fixedAssessment
        #expect(fixed.total(SwissLine.capitalBenefitsFederal) > 0 && fixed.total(SwissLine.foreignTaxCredit) == -1_000)
        // The year without markets is the prepared one; a 3a payout on top
        // raises the rate on both, and the credit stays (it's below the tax).
        #expect(prepared.assess(.empty) == fixed)
        let payout = VariableYear(payouts: [.init(wrapper: "ch.pillar3a", amount: 200_000, form: .lumpSum)])
        let assessed = prepared.assess(payout)
        #expect(assessed.total(SwissLine.foreignTaxCredit) == -1_000)
        let lines = assessed.lines.filter { $0.subject == "pension-0" && $0.id.hasPrefix("ch.capitalBenefits") }
        #expect(lines.reduce(0) { $0 + $1.amount } > fixed.total(SwissLine.capitalBenefitsFederal)
                + fixed.total(SwissLine.capitalBenefitsCantonal) + fixed.total(SwissLine.capitalBenefitsCommunal))
    }

    @Test func anAnnuitysCreditIsRecomputedWithInvestmentIncome() throws {
        // The Swiss tax on the pension is its share of the income taxes:
        // with investment income the taxes rise, and so does the cap.
        let pension = foreign("IT", kind: .statutory, sourceTax: 100_000)
        let prepared = try Swiss.prepare(year(pension, citizenships: ["CH"]))
        let fixed = prepared.fixedAssessment
        let incomeTax = [SwissLine.federal, SwissLine.cantonal, SwissLine.communal].reduce(0) { $0 + fixed.total($1) }
        #expect(abs(fixed.total(SwissLine.foreignTaxCredit) + incomeTax) < 1e-9)
        #expect(prepared.assess(.empty) == fixed)
        let income = VariableYear(capitalIncome: [.init(wrapper: "ch.ordinary", category: .bond, kind: .interest,
                                                        amount: 30_000)])
        let assessed = prepared.assess(income)
        let taxes = [SwissLine.federal, SwissLine.cantonal, SwissLine.communal].reduce(0) { $0 + assessed.total($1) }
        // Half the income is the pension, so half the income taxes are credited.
        #expect(abs(assessed.total(SwissLine.foreignTaxCredit) + taxes / 2) < 1e-9)
    }

    // MARK: - Paid abroad

    func abroad(_ pensions: [FixedYear.Pension], livingIn residence: String, options: OptionValues = Swiss.place("Zurich"),
                rate: Double = 1) throws -> TaxAssessment {
        let year = FixedYear(year: 2026, age: 66, systemOptions: options, pensions: pensions, currencyRate: rate,
                             residence: [.init(from: 2020, system: "ch", options: options),
                                         .init(from: 2026, system: residence)])
        let prepared = try #require(system.prepareNonResident(year, state: ["kept": 1],
                                                              parameters: try Swiss.parameters()))
        let fixed = prepared.fixedAssessment
        #expect(fixed.nextState == ["kept": 1])
        #expect(prepared.grossUp(net: 100, from: BucketSnapshot(wrapper: "ch.ordinary", value: 1, costBasis: 1,
                                                                 categoryShares: [:])) == nil)
        return fixed
    }

    func swiss(_ id: String, scheme: String = "ch.bvg", amount: Double, kind: PensionKind? = .occupational,
               form: VariableYear.PayoutForm = .annuity) -> FixedYear.Pension {
        FixedYear.Pension(id: id, scheme: scheme, amount: amount, taxedIn: .source, kind: kind, sourceCountry: "CH",
                          form: form)
    }

    @Test func switzerlandIsAPayingCountry() throws {
        #expect(system.country == "CH")
        let registry = TaxRegistry([system])
        #expect(registry.system(forCountry: "ch")?.id == "ch")
    }

    @Test func anAnnuityPaidAbroadPaysTheSourceTax() throws {
        let fixed = try abroad([swiss("pension-0", amount: 30_000)], livingIn: "generic")
        #expect(fixed.total(SwissLine.nonResidentFederal) == 300 && abs(fixed.total(SwissLine.nonResidentCantonal) - 1_800) < 1e-9)
        #expect(fixed.lines.allSatisfy { $0.subject == "pension-0" && $0.base == 30_000 })
        #expect(fixed.lines.first { $0.id == SwissLine.nonResidentCantonal }?.label
                == "Source tax (cantonal and communal, Zurich)")
        #expect(codes(fixed) == ["ch.nonResident.noTreaty"])
        // Ticino's rate, and a plan in another currency: amounts in, lines out, at the rate.
        let ticino = try abroad([swiss("pension-0", amount: 10_000)], livingIn: "generic",
                                options: Swiss.place("Lugano"), rate: 0.9)
        #expect(abs(ticino.total(SwissLine.nonResidentCantonal) - 900) < 1e-9)
        #expect(abs(ticino.total(SwissLine.nonResidentFederal) - 100) < 1e-9)
    }

    @Test func aTreatyCountryOfResidenceGetsNoSwissTax() throws {
        let pensions = [swiss("pension-0", amount: 30_000), swiss("pension-0.lumpSum", amount: 200_000, form: .lumpSum),
                        swiss("pension-1", scheme: "fixed", amount: 5_000, kind: .privateAnnuity)]
        for residence in ["it", "de"] {
            let fixed = try abroad(pensions, livingIn: residence)
            #expect(fixed.lines.isEmpty && fixed.totalTax == 0)
            // A warning per pension, that its taxedIn should be residence.
            #expect(codes(fixed) == Array(repeating: "ch.nonResident.treaty", count: 3))
            #expect(fixed.issues.allSatisfy { $0.year == nil })
            #expect(fixed.taxByPension(pensions) == ["pension-0": 0, "pension-0.lumpSum": 0, "pension-1": 0])
        }
        #expect(try abroad(pensions, livingIn: "de").issues.first?.message.contains("Germany–Switzerland treaty art. 18")
                == true)
    }

    @Test func theAHVPensionIsNotTaxedAtSource() throws {
        for pension in [swiss("pension-0", scheme: "ch.ahv", amount: 30_000, kind: nil),
                        swiss("pension-0", scheme: "fixed", amount: 30_000, kind: .statutory)] {
            let fixed = try abroad([pension], livingIn: "generic")
            #expect(fixed.lines.isEmpty && codes(fixed) == ["ch.nonResident.ahv"])
        }
    }

    @Test func lumpSumsAreTaxedTogetherAndSplit() throws {
        let fixed = try abroad([swiss("a.lumpSum", amount: 150_000, form: .lumpSum),
                                swiss("b.lumpSum", scheme: "fixed", amount: 100_000, kind: .privateAnnuity, form: .lumpSum)],
                               livingIn: "generic")
        // Together they're the 250,000 of the reference case: 3,900.688 federal, 10,700 in Zurich.
        #expect(abs(fixed.total(SwissLine.nonResidentFederal) - 3_900.688) < 1e-6)
        #expect(abs(fixed.total(SwissLine.nonResidentCantonal) - 10_700) < 1e-6)
        let byPension = fixed.taxByPension([swiss("a.lumpSum", amount: 150_000), swiss("b.lumpSum", amount: 100_000)])
        #expect(abs((byPension["a.lumpSum"] ?? 0) - 0.6 * 14_600.688) < 1e-6)
    }

    @Test func withoutACantonOnlyTheFederalTax() throws {
        let fixed = try abroad([swiss("pension-0", amount: 20_000)], livingIn: "generic", options: [:])
        #expect(fixed.total(SwissLine.nonResidentFederal) == 200 && fixed.total(SwissLine.nonResidentCantonal) == 0)
        #expect(codes(fixed) == ["ch.nonResident.canton", "ch.nonResident.noTreaty"])
    }
}
