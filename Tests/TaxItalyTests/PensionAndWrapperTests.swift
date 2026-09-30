import Foundation
@testable import TaxItaly
import TaxKit
import Testing

struct INPSTests {
    let scheme = INPSPensionScheme()
    let store = Italy.system.parameters

    @Test func registeredWithTheSystem() {
        let registry = TaxRegistry([ItalyTaxSystem()])
        #expect(registry.pensionScheme("it.inps")?.name == "INPS (contributory system)")
        #expect(registry.pensionScheme("fixed") != nil)
        #expect(registry.regime("it.forfettario")?.regime.name == "Regime forfettario")
        #expect(registry.wrapper("it.tfr")?.category == .taxDeferred)
    }

    @Test func montanteGrowsAndCollectsCredits() throws {
        var record = scheme.startingRecord(options: ["montante": "92000", "contributionYears": "8",
                                                     "foreignContributionYears": 6], year: 2026, parameters: store)
        #expect(record.montante == 92_000 && record.contributionMonths == 96 && record.foreignContributionMonths == 72)
        #expect(record.totalContributionYears == 14)
        let credits = [Accrual(target: .pensionScheme("it.inps"), amount: 21_450, contributionMonths: 12, source: "job"),
                       Accrual(target: .pensionScheme("it.inps"), amount: 3_000, contributionMonths: 6, source: "gig"),
                       Accrual(target: .wrapper("it.tfr"), amount: 4_491.5, source: "job")]
        scheme.accrue(credits, in: 2026, to: &record, options: [:], parameters: try Italy.parameters())
        #expect(abs(record.montante - (92_000 * 1.005 + 24_450)) < 1e-9)
        #expect(record.contributionMonths == 108)
        scheme.accrue([], in: 2027, to: &record, options: ["realRevaluation": "0.01"], parameters: try Italy.parameters())
        #expect(abs(record.montante - (92_000 * 1.005 + 24_450) * 1.01) < 1e-9)
    }

    @Test func workCreditsTheMontante() throws {
        let employee = try Italy.prepare(Italy.workYear(.employee, regime: ItalyRegime.employee, gross: 65_000))
        #expect(employee.fixedAssessment.accruals.first == Accrual(target: .pensionScheme("it.inps"), amount: 21_450,
                                                                    contributionMonths: 12, source: "work"))
        // Below the Gestione Separata minimum base, fewer months count.
        let small = try Italy.prepare(Italy.workYear(.selfEmployed, regime: ItalyRegime.forfettario, gross: 14_000,
                                                     options: ["coefficient": "0.67"]))
        #expect(small.fixedAssessment.accruals.first?.contributionMonths == 5)
        // Above the maximum base, nothing more is charged or credited.
        let big = try Italy.prepare(Italy.workYear(.selfEmployed, regime: ItalyRegime.professional, gross: 200_000))
        #expect(big.fixedAssessment.contributions.first?.base == 122_295)
        #expect(abs((big.fixedAssessment.accruals.first?.amount ?? 0) - 0.25 * 122_295) < 1e-9)
    }

    @Test func oldAgePensionAge() {
        #expect(scheme.oldAgePensionAge(in: 2026, options: [:], parameters: store) == 67)
        #expect(scheme.oldAgePensionAge(in: 2028, options: [:], parameters: store) == 67)
        // 3 months by 2028, then a month a year: 67 years and 12 months in 2037.
        #expect(scheme.oldAgePensionAge(in: 2037, options: [:], parameters: store) == 68)
        #expect(scheme.oldAgePensionAge(in: 2037, options: ["ageIncreaseMonthsPerYear": 0], parameters: store) == 67)
    }

    private func claims(montante: Double, years: Int, foreign: Int = 0, born: Int, month: Int = 1,
                        options: OptionValues = ["coefficientDeclinePerYear": 0, "realRevaluation": 0,
                                                 "ageIncreaseMonthsPerYear": 0]) -> [ClaimOption] {
        let record = PensionRecord(scheme: "it.inps", montante: montante, contributionMonths: years * 12,
                                   foreignContributionMonths: foreign * 12)
        return scheme.claimOptions(for: record, context: ClaimContext(year: 2026, birthDate: BirthDate(year: born,
                                                                                                        month: month,
                                                                                                        day: 15),
                                                                      options: options),
                                   parameters: store)
    }

    @Test func anticipataIsCappedUntilTheVecchiaiaAge() throws {
        // 900,000 × 5.142% / 13 = 3,560 a month, above 5 × 611.85 = 3,059.25.
        let options: OptionValues = ["coefficientDeclinePerYear": 0, "realRevaluation": 0, "ageIncreaseMonthsPerYear": 0,
                                     "indexationInflation": 0]
        let first = try #require(claims(montante: 900_000, years: 30, born: 1962, options: options).first)
        #expect(first.route == "it.inps.anticipata" && first.age == 64)
        let cap = 5 * 611.85 * 13
        #expect(abs(first.annualAmount - cap * 8 / 12) < 1e-6)
        #expect(abs(first.annualAmount(atAge: 65) - cap) < 1e-6)
        // Vecchiaia at 67 years and 3 months (April 2029): uncapped from May 2029, 8 months of 12.
        let full = 900_000 * (0.05088 + (0.05250 - 0.05088) * 4 / 12)
        #expect(abs(first.annualAmount(atAge: 67) - (cap * 4 / 12 + full * 8 / 12)) < 1e-6)
        #expect(abs(first.annualAmount(atAge: 68) - full) < 1e-6)
        #expect(first.note?.contains("capped") == true)
    }

    @Test func partialIndexationErodesLargePensions() throws {
        // With 2% inflation, the part above 4× the minimum pension keeps only 90% or 75% of it.
        let options: OptionValues = ["coefficientDeclinePerYear": 0, "realRevaluation": 0, "ageIncreaseMonthsPerYear": 0]
        let large = try #require(claims(montante: 900_000, years: 30, born: 1959, options: options).first)
        #expect(large.annualAmount(atAge: 69) < large.annualAmount(atAge: 68))
        #expect(large.annualAmount(atAge: 90) < large.annualAmount(atAge: 70) * 0.99)
        // Below 4× the minimum it keeps its value in today's euros.
        let small = try #require(claims(montante: 150_000, years: 30, born: 1959, options: options).first)
        #expect(small.changes.count == 1)
        #expect(small.annualAmount(atAge: 90) == small.annualAmount(atAge: 68))
    }

    @Test func foreignYearsCountTowardTheMinimum() throws {
        // 15 years in Italy and 6 abroad: 21 years, enough for the vecchiaia at 67.
        let withForeign = claims(montante: 150_000, years: 15, foreign: 6, born: 1959)
        #expect(withForeign.first?.route == "it.inps.vecchiaia" && withForeign.first?.age == 67)
        let without = claims(montante: 150_000, years: 15, born: 1959)
        #expect(without.first?.route == "it.inps.vecchiaiaContributiva" && without.first?.age == 71)
    }

    @Test func mothersNeedLess() throws {
        // 400,000 × 5.142% / 13 = 1,582 a month: below 3× (1,638.72), above 2.8× (1,529.47).
        #expect(claims(montante: 400_000, years: 25, born: 1962).first?.age != 64)
        let mother = claims(montante: 400_000, years: 25, born: 1962,
                            options: ["motherOfChildren": 1, "ageIncreaseMonthsPerYear": 0])
        #expect(mother.first?.age == 64 && mother.first?.route == "it.inps.anticipata")
    }

    @Test func laterRetirementsUseLaterRules() throws {
        // Born October 1990: the ages rise by 3 months by 2028 and a month a year after that. In 2060 the
        // vecchiaia needs 67 years + 35 months, reached in September 2060; the pension starts in October, at 70.
        let options = claims(montante: 300_000, years: 30, born: 1990, month: 10,
                             options: ["coefficientDeclinePerYear": 0.004, "realRevaluation": 0])
        let vecchiaia = try #require(options.first)
        #expect(vecchiaia.route == "it.inps.vecchiaia" && vecchiaia.age == 70)
        #expect(vecchiaia.note == "Starts in October 2060, at 70 years.")
        // After the 2025-2026 table, the coefficients fall by 0.4% a year: 34 years to 2060.
        let expected = 300_000 * 0.06258 * pow(0.996, 34) * 3 / 12
        #expect(abs(vecchiaia.annualAmount - expected) < 1e-6)
        #expect(options.last?.age == 75)
    }

    @Test func noClaimWithoutEnoughContributions() {
        #expect(claims(montante: 50_000, years: 4, born: 1960).isEmpty)
    }
}

struct WrapperTests {
    let system = Italy.system

    private func context(age: Int, stopped: Int?, contributionYears: Double = 25, membership: Int = 10,
                         oldAge: Int? = 67) -> WrapperAccessContext {
        WrapperAccessContext(year: 2040, age: age, yearsSinceWorkStopped: stopped, oldAgePensionAge: oldAge,
                             contributionYears: contributionYears, membershipYears: membership)
    }

    @Test func describesItsWrappers() throws {
        #expect(system.wrappers.map(\.id) == ["it.ordinary", "it.pensionFund", "it.tfr"])
        let fund = try #require(system.wrapper("it.pensionFund"))
        #expect(fund.category == .taxDeferred && fund.growthTaxRate == 0.2 && fund.revaluation == nil)
        let tfr = try #require(system.wrapper("it.tfr"))
        #expect(tfr.growthTaxRate == 0.17)
        #expect(tfr.revaluation == WrapperRevaluation(fixedRate: 0.015, inflationShare: 0.75))
        #expect(system.wrapper("it.ordinary")?.access(in: context(age: 30, stopped: nil)).isAccessible == true)
    }

    @Test func pensionFundAccessAndRITA() throws {
        let fund = try #require(system.wrapper("it.pensionFund"))
        #expect(fund.access(in: context(age: 67, stopped: nil)) == .accessible(route: nil))
        #expect(!fund.access(in: context(age: 67, stopped: 1, membership: 4)).isAccessible)
        // RITA within 5 years, after stopping work, with 20 years of contributions.
        #expect(fund.access(in: context(age: 62, stopped: 0)) == .accessible(route: "it.rita"))
        #expect(!fund.access(in: context(age: 62, stopped: 0, contributionYears: 19)).isAccessible)
        #expect(!fund.access(in: context(age: 62, stopped: nil)).isAccessible)
        // RITA within 10 years, after 2 years without work.
        #expect(fund.access(in: context(age: 57, stopped: 2, contributionYears: 10)) == .accessible(route: "it.rita"))
        #expect(!fund.access(in: context(age: 57, stopped: 1)).isAccessible)
        #expect(!fund.access(in: context(age: 56, stopped: 5)).isAccessible)
        // The planner's pension age wins; without one, the file's rules apply (68 by 2040).
        #expect(fund.access(in: context(age: 60, stopped: 3, oldAge: 70)) == .accessible(route: "it.rita"))
        #expect(!fund.access(in: context(age: 67, stopped: nil, oldAge: nil)).isAccessible)
        #expect(fund.access(in: context(age: 68, stopped: nil, oldAge: nil)).isAccessible)
        if case .locked(let reason) = fund.access(in: context(age: 50, stopped: 3)) {
            #expect(reason.contains("RITA"))
        } else {
            Issue.record("expected locked")
        }
    }

    @Test func tfrIsPaidWhenTheJobEnds() throws {
        let tfr = try #require(system.wrapper("it.tfr"))
        #expect(!tfr.access(in: context(age: 50, stopped: nil)).isAccessible)
        #expect(tfr.access(in: context(age: 50, stopped: 0)).isAccessible)
    }

    @Test func pensionFundContributionsAreDeductedAndTracked() throws {
        let year = Italy.workYear(.employee, regime: ItalyRegime.employee, gross: 50_000, options: ["tfr": "pensionFund"],
                                  contributions: [.init(wrapper: ItalyWrapper.pensionFund, amount: 6_000)])
        let calculator = try Italy.calculate(year)
        #expect(calculator.irpef.pensionFundDeduction == 5_300)
        let assessment = try Italy.prepare(year, state: ["it.pensionFund.deducted": 1_000]).fixedAssessment
        #expect(assessment.nextState["it.pensionFund.deducted"] == 6_300)
        #expect(assessment.nextState["it.pensionFund.nonDeducted"] == 700)
        #expect(abs((assessment.nextState["it.pensionFund.tfr"] ?? 0) - 0.0691 * 50_000) < 1e-9)
        #expect(assessment.nextState["it.pensionFund.years"] == 1)
        #expect(assessment.accruals.contains { $0.target == .wrapper("it.pensionFund") })
        // The deduction lowers IRPEF at the marginal rate (33%, plus the addizionali).
        let without = try Italy.prepare(Italy.workYear(.employee, regime: ItalyRegime.employee, gross: 50_000))
        let saved = without.fixedAssessment.totalTax - (try Italy.prepare(year)).fixedAssessment.totalTax
        #expect(saved > 5_300 * 0.33)

        // Forfettario income alone: nothing to deduct from, so the contributions are tax-free at payout.
        let forfettario = Italy.workYear(.selfEmployed, regime: ItalyRegime.forfettario, gross: 60_000,
                                         options: ["coefficient": "0.67"],
                                         contributions: [.init(wrapper: ItalyWrapper.pensionFund, amount: 3_000)])
        let state = try Italy.prepare(forfettario).fixedAssessment.nextState
        #expect(state["it.pensionFund.deducted"] == 0 && state["it.pensionFund.nonDeducted"] == 3_000)
    }

    @Test func lumpSumsAboveHalfTheFundGetAWarning() throws {
        let prepared = try Italy.prepare(Italy.pensionYear(20_000, year: 2026))
        let year = VariableYear(
            payouts: [.init(wrapper: ItalyWrapper.pensionFund, amount: 60_000, form: .lumpSum, costBasis: 40_000,
                            membershipYears: 30)],
            balances: [.init(wrapper: ItalyWrapper.pensionFund, category: .fund, value: 40_000)])
        #expect(prepared.assess(year).issues.map(\.code) == ["it.pensionFund.lumpSumLimit"])
        // A small fund can be taken whole: 70% of 6,000 as an annuity is far below half the assegno sociale.
        let small = VariableYear(payouts: [.init(wrapper: ItalyWrapper.pensionFund, amount: 6_000, form: .lumpSum)],
                                 balances: [.init(wrapper: ItalyWrapper.pensionFund, category: .fund, value: 0)])
        #expect(prepared.assess(small).issues.isEmpty)
    }

    @Test func foreignAndUnknownWrappers() throws {
        let prepared = try Italy.prepare(Italy.pensionYear(30_000))
        let assessment = prepared.assess(VariableYear(
            sales: [.init(wrapper: "pt.ppr", category: .fund, proceeds: 1_000, costBasis: 500)],
            payouts: [.init(wrapper: "taxDeferred", amount: 1_000, form: .annuity),
                      .init(wrapper: "taxFree", amount: 1_000, form: .lumpSum)]))
        #expect(Set(assessment.issues.map(\.code)) == ["it.unknownWrapper", "it.taxDeferredPayout"])
        #expect(abs(assessment.total("it.capitalGains") - 130) < 1e-9)
        // Payouts at the marginal rate: 33% plus the addizionali.
        #expect(abs(assessment.total("it.taxDeferredPayout") - 1_000 * (0.33 + 0.0173 + 0.008)) < 1e-9)
    }

    @Test func inheritanceRelationships() throws {
        var year = Italy.pensionYear(20_000)
        year.windfalls = [.init(name: "Spouse", kind: "inheritance.spouse", amount: 1_200_000),
                          .init(name: "Uncle", kind: "inheritance.cousin", amount: 10_000)]
        let assessment = try Italy.prepare(year).fixedAssessment
        #expect(abs(assessment.total("it.inheritanceTax") - (0.04 * 200_000 + 0)) < 1e-9)
        #expect(assessment.issues.map(\.code) == ["it.inheritance.relationship"])
    }
}
