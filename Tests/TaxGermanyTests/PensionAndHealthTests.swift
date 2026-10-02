import Foundation
@testable import TaxGermany
import TaxKit
import Testing

/// The `de.drv` scheme: its record, credits, claim options and ages.
struct DRVTests {
    let scheme = DRVPensionScheme()
    let store = Germany.system.parameters

    @Test func pointsBuildUpFromInsuredEarnings() throws {
        var record = scheme.startingRecord(options: ["points": "20.5", "contributionYears": 18,
                                                     "foreignContributionYears": 4, "foreignYears45": 2],
                                           year: 2026, parameters: store)
        #expect(record.extra["points"] == 20.5 && record.contributionMonths == 216 && record.foreignContributionMonths == 48)
        #expect(record.extra["months45"] == 240)
        let credits = [Accrual(target: .pensionScheme("de.drv"), amount: 40_000, contributionMonths: 12, source: "job"),
                       Accrual(target: .pensionScheme("de.drv"), amount: 5_000, contributionMonths: 6, source: "gig"),
                       Accrual(target: .wrapper("de.bav"), amount: 450, source: "job")]
        scheme.accrue(credits, in: 2026, to: &record, options: [:], parameters: try Germany.parameters(),
                      currencyRate: 1)
        #expect(abs(record.extra["points"]! - (20.5 + 45_000 / 51_944)) < 1e-12)
        #expect(record.contributionMonths == 228 && record.extra["months45"] == 252)
        // Later years' average earnings grow with real wages (1% by default);
        // a plan in another currency is converted.
        let before = record.extra["points"]!
        scheme.accrue([Accrual(target: .pensionScheme("de.drv"), amount: 40_000 / 1.05, contributionMonths: 12)],
                      in: 2030, to: &record, options: [:], parameters: try Germany.parameters(2030), currencyRate: 1.05)
        #expect(abs(record.extra["points"]! - before - 40_000 / (51_944 * pow(1.01, 4))) < 1e-9)
    }

    @Test func workAndBuyInsCreditTheScheme() throws {
        let year = Germany.workYear(.employee, regime: GermanRegime.employee, gross: 120_000,
                                    contributions: [.init(wrapper: "de.drv", amount: 9_300, source: "contribution-0")])
        let assessment = try Germany.prepare(year).fixedAssessment
        #expect(assessment.accruals == [
            Accrual(target: .pensionScheme("de.drv"), amount: 101_400, contributionMonths: 12, source: "work"),
            Accrual(target: .pensionScheme("de.drv"), amount: 9_300 / 0.186, source: "contribution-0"),
        ])
        // The buy-in is deductible with the pension contributions, within 30,826.
        let without = try Germany.prepare(Germany.workYear(.employee, regime: GermanRegime.employee, gross: 120_000))
            .fixedAssessment
        #expect(without.total(GermanLine.incomeTax) - assessment.total(GermanLine.incomeTax) > 9_300 * 0.42 - 0.01)
    }

    @Test func standardAgeAndItsIncrease() {
        #expect(scheme.oldAgePensionAge(in: 2026, options: [:], parameters: store) == 67)
        #expect(scheme.oldAgePensionAgeInMonths(in: 2031, options: ["ageIncreaseMonthsPerYear": 2],
                                                parameters: store) == 804)
        #expect(scheme.oldAgePensionAgeInMonths(in: 2035, options: ["ageIncreaseMonthsPerYear": 2],
                                                parameters: store) == 812)
        #expect(scheme.pensionKind(options: [:]) == .statutory)
    }

    private func claims(points: Double = 40, years: Int, foreign: Int = 0, years45: Int? = nil, born: BirthDate,
                        options: OptionValues = ["realPensionValueGrowth": 0], currencyRate: Double = 1) -> [ClaimOption] {
        var values: OptionValues = ["points": .number(points), "contributionYears": .number(Double(years)),
                                    "foreignContributionYears": .number(Double(foreign))]
        if let years45 { values["years45"] = .number(Double(years45)) }
        let record = scheme.startingRecord(options: values, year: 2026, parameters: store)
        return scheme.claimOptions(for: record, context: ClaimContext(year: 2026, birthDate: born, options: options,
                                                                      currencyRate: currencyRate),
                                   parameters: store)
    }

    @Test func foreignYearsHelpReachTheWaitingTimes() throws {
        let born = BirthDate(year: 1966, month: 3, day: 10)
        // 30 German years: the standard pension only; with 5 abroad, from 63.
        #expect(claims(years: 30, born: born).first?.route == "de.drv.standard")
        let withForeign = claims(years: 30, foreign: 5, born: born)
        #expect(withForeign.first?.route == "de.drv.longInsured" && withForeign.first?.age == 63)
        // The years abroad add no points: the same amount at 67.
        let at67 = claims(years: 30, born: born).first { $0.age == 67 }
        #expect(withForeign.first { $0.age == 67 }?.annualAmount == at67?.annualAmount)
        // Less than a year in Germany: Germany pays nothing.
        #expect(claims(points: 0.5, years: 0, foreign: 30, born: born).isEmpty)
        // Under 5 years in all: no pension.
        #expect(claims(points: 3, years: 4, born: born).isEmpty)
    }

    @Test func severalRoutesInAYearBestFirst() throws {
        // Born in June with 45 years: in the year of 65, the 45-year pension from
        // July comes first, the 35-year one from January (9% less) second.
        let options = claims(points: 50, years: 45, born: BirthDate(year: 1964, month: 6, day: 15))
        let at65 = options.filter { $0.age == 65 }
        #expect(at65.map(\.route) == ["de.drv.veryLongInsured", "de.drv.longInsured"])
        #expect(at65[1].note?.contains("9% less") == true)
        // The standard age's year: the 45-year pension from January; the standard
        // one from July and the 35-year one from January (with a deduction) are
        // never better, so they aren't listed.
        #expect(options.filter { $0.age == 67 }.map(\.route) == ["de.drv.veryLongInsured"])
        #expect(options.last?.age == 70)
    }

    @Test func amountsInThePlansCurrencyAndGrowth() throws {
        let born = BirthDate(year: 1964, month: 1, day: 1)
        let euros = claims(years: 40, born: born)
        let francs = claims(years: 40, born: born, currencyRate: 0.95)
        #expect(abs(francs[0].annualAmount - euros[0].annualAmount / 0.95) < 1e-9)
        let growing = claims(years: 40, born: born, options: ["realPensionValueGrowth": 0.005])
        let standard = try #require(growing.first { $0.route == "de.drv.standard" })
        #expect(abs(standard.annualAmount - 40 * 42.52 * pow(1.005, 5) * 12) < 1e-6)
        #expect(standard.realGrowthPerYear == 0.005)
    }

    @Test func laterAgesWithTheProposedIncrease() throws {
        // Two months a year from 2032: born in July 1975, 67 would be reached in
        // July 2042, but by then the age is 67 + 22 months; reached in 2044, it's
        // 67 + 26 months: September 2044, paid from October, at 69.
        let options = claims(years: 30, born: BirthDate(year: 1975, month: 7, day: 2),
                             options: ["realPensionValueGrowth": 0, "ageIncreaseMonthsPerYear": 2])
        let standard = try #require(options.first { $0.route == "de.drv.standard" })
        #expect(standard.age == 69 && standard.note == "Starts in October 2044, at 69 years and 3 months.")
    }
}

/// Taxation of pensions by kind and cohort, and health insurance in retirement.
struct PensionAndHealthTests {
    /// PKV with a negligible premium, so no contributions change the taxable income.
    static let privateCover: OptionValues = ["healthInsurance": "pkv", "retirementHealthInsurance": "pkv",
                                             "pkvPremium": "0.0001"]

    @Test func theExemptAmountIsFixedInTheSecondYear() throws {
        let first = FixedYear(year: 2030, age: 66, pensions: [.init(id: "drv", scheme: "de.drv", amount: 10_000,
                                                                    startYear: 2030)])
        let start = try Germany.prepare(first).fixedAssessment
        #expect(start.nextState["de.pension.drv.exemptAmount"] == nil)
        var second = first
        second.year = 2031
        second.pensions[0].amount = 20_000
        second.inflationFactor = 1.1
        let fixed = try Germany.prepare(second, state: start.nextState).fixedAssessment
        #expect(abs(fixed.nextState["de.pension.drv.exemptAmount"]! - 0.14 * 20_000 * 1.1) < 1e-9)
        // Increases later are taxed in full: the exemption stays nominal.
        var third = second
        third.year = 2032
        third.pensions[0].amount = 21_000
        third.inflationFactor = 1.2
        let later = try Germany.prepare(third, state: fixed.nextState).fixedAssessment
        #expect(later.nextState["de.pension.drv.exemptAmount"] == fixed.nextState["de.pension.drv.exemptAmount"])
    }

    @Test func pensionsAreTaxedByKind() throws {
        func incomeTax(_ pension: FixedYear.Pension) throws -> Double {
            try Germany.prepare(FixedYear(year: 2030, age: 67, systemOptions: Self.privateCover, pensions: [pension]))
                .fixedAssessment.total(GermanLine.incomeTax)
        }
        let p = try GermanParameters(Germany.parameters())
        func tariff(_ taxable: Double) -> Double { p.tariff.tax(on: taxable - 102 - 36) }
        let amount = 40_000.0
        // Statutory and Rürup: the 2030 cohort's 86%.
        #expect(abs(try incomeTax(.init(id: "a", scheme: "fixed", amount: amount, kind: .statutory, startYear: 2030))
            - tariff(0.86 * amount)) < 0.01)
        #expect(abs(try incomeTax(.init(id: "b", scheme: "fixed", amount: amount, kind: .basicPension, startYear: 2030))
            - tariff(0.86 * amount)) < 0.01)
        // A German occupational pension: in full.
        #expect(abs(try incomeTax(.init(id: "c", scheme: "fixed", amount: amount, kind: .occupational, startYear: 2030,
                                        sourceCountry: "DE")) - tariff(amount)) < 0.01)
        // A private annuity and a foreign occupational pension: the Ertragsanteil for 67, 17%.
        #expect(abs(try incomeTax(.init(id: "d", scheme: "fixed", amount: amount, kind: .privateAnnuity,
                                        startYear: 2030)) - tariff(0.17 * amount)) < 0.01)
        #expect(abs(try incomeTax(.init(id: "e", scheme: "fixed", amount: amount, kind: .occupational, startYear: 2030,
                                        sourceCountry: "GB")) - tariff(0.17 * amount)) < 0.01)
        // A Swiss pension-fund pension, 70% mandatory.
        #expect(abs(try incomeTax(.init(id: "f", scheme: "fixed", amount: amount, kind: .occupational, startYear: 2030,
                                        sourceCountry: "CH", mandatoryShare: 0.7))
            - tariff(0.86 * 0.7 * amount + 0.17 * 0.3 * amount)) < 0.01)
        // A DRV pension the plan says is taxed at source is still German.
        #expect(abs(try incomeTax(.init(id: "g", scheme: "de.drv", amount: amount, taxedIn: .source, startYear: 2030))
            - tariff(0.86 * amount)) < 0.01)
    }

    @Test func lumpSums() throws {
        let year = FixedYear(year: 2030, age: 67, systemOptions: Self.privateCover, pensions: [
                                 .init(id: "bvg.lumpSum", scheme: "ch.bvg", amount: 100_000, startYear: 2030,
                                       form: .lumpSum, mandatoryShare: 0.6),
                                 .init(id: "life.lumpSum", scheme: "fixed", amount: 50_000, kind: .privateAnnuity,
                                       startYear: 2030, form: .lumpSum),
                             ])
        let assessment = try Germany.prepare(year).fixedAssessment
        #expect(assessment.issues.map(\.code) == ["de.pension.swissLumpSum", "de.pension.lumpSumNotTaxed"])
        let p = try GermanParameters(Germany.parameters())
        #expect(abs(assessment.total(GermanLine.incomeTax) - p.tariff.tax(on: 86_000 - 102 - 36)) < 0.01)
    }

    @Test func healthInsuranceFromTheFirstPension() throws {
        let amount = 20_000.0
        func contributions(_ options: OptionValues, interest: Double = 0, year: FixedYear? = nil) throws -> Double {
            let fixed = year ?? FixedYear(year: 2031, age: 67, systemOptions: options,
                                          pensions: [.init(id: "drv", scheme: "de.drv", amount: amount, startYear: 2030)])
            let assessed = try Germany.prepare(fixed).assess(VariableYear(capitalIncome: [
                .init(wrapper: GermanWrapper.ordinary, category: .cash, kind: .interest, amount: interest),
            ]))
            return assessed.totalContributions
        }
        let kvdr = 0.0875 * amount + 0.042 * amount
        // auto passes the 9/10 test by default: KVdR, nothing on interest.
        #expect(abs(try contributions([:], interest: 10_000) - kvdr) < 1e-6)
        // Voluntary: interest too.
        #expect(abs(try contributions(["retirementHealthInsurance": "voluntary"], interest: 10_000)
            - kvdr - 0.211 * 10_000) < 1e-6)
        // Children add 3 years each: two children turn a failing record into KVdR.
        let born = BirthDate(year: 1964, month: 1, day: 1)
        let residence = [TaxPlan.Residence(from: 2005, system: "generic"),
                         TaxPlan.Residence(from: 2026, system: "de")]
        func year(_ options: OptionValues) -> FixedYear {
            FixedYear(year: 2031, age: 67, systemOptions: options,
                      pensions: [.init(id: "drv", scheme: "de.drv", amount: amount, startYear: 2031)],
                      birthDate: born, residence: residence)
        }
        // 1984–2031: second half 2007.5–2031 (23.5 years), 9/10 is 21.15; insured
        // 2026–2030 only (5 years): fails.
        #expect(try contributions([:], interest: 10_000, year: year([:])) > kvdr + 1)
        // With work from 2000 (second half 2015.5–2031, 15.5 years, 13.95 needed),
        // the 5 years and 9 for 3 children pass.
        let passing = year(["workStartYear": 2000, "children": 3])
        #expect(abs(try contributions([:], interest: 10_000, year: passing) - 0.0875 * amount
            - (0.036) * amount) < 1e-6)
        // Choosing KVdR on a failing record warns.
        let warned = try Germany.prepare(year(["retirementHealthInsurance": "kvdr"])).fixedAssessment
        #expect(warned.issues.map(\.code) == ["de.kvdr.mayBeRefused"])
    }

    @Test func privateHealthInsuranceInRetirement() throws {
        let year = FixedYear(year: 2031, age: 67,
                             systemOptions: ["healthInsurance": "pkv", "pkvPremium": "800", "pkvBasicShare": "0.75"],
                             pensions: [.init(id: "drv", scheme: "de.drv", amount: 24_000, startYear: 2030)])
        let assessment = try Germany.prepare(year, state: ["de.pkv.years": 5]).fixedAssessment
        let premium = 800.0 * 12 * pow(1.01, 5)
        let subsidy = min(0.5 * 0.175 * 24_000, 0.5 * premium)
        #expect(abs(assessment.contribution(GermanLine.privateHealth) - (premium - subsidy)) < 1e-6)
        #expect(assessment.contribution(GermanLine.health) == 0)
        #expect(assessment.nextState["de.pkv.years"] == 6)
        // No contributions on capital income in PKV.
        let assessed = try Germany.prepare(year).assess(VariableYear(capitalIncome: [
            .init(wrapper: GermanWrapper.ordinary, category: .cash, kind: .interest, amount: 50_000),
        ]))
        #expect(assessed.contributions.count == 1)
    }

    @Test func workingPastTheStandardAgeWithAPension() throws {
        // At 68 with a DRV pension: no pension contribution of the employee's own,
        // health at the reduced rate, and contributions on the pension too.
        var year = Germany.workYear(.employee, regime: GermanRegime.employee, gross: 30_000, age: 68)
        year.pensions = [.init(id: "drv", scheme: "de.drv", amount: 18_000, startYear: 2024)]
        let assessment = try Germany.prepare(year).fixedAssessment
        #expect(assessment.contribution(GermanLine.pension) == 0 && assessment.contribution(GermanLine.unemployment) == 0)
        #expect(abs(assessment.contribution(GermanLine.health) - (0.0845 * 30_000 + 0.0875 * 18_000)) < 1e-6)
        #expect(abs(assessment.contribution(GermanLine.care) - (0.024 * 30_000 + 0.042 * 18_000)) < 1e-6)
        #expect(assessment.accruals.isEmpty)
    }

    @Test func theAktivrenteStartsTheMonthAfterTheStandardAge() throws {
        // Born 10 April 1959: 66 and 2 months, reached in June 2025; from July. Born
        // 15 May 1960: 66 and 4 months, reached in September 2026; tax-free from October.
        func taxFree(_ born: BirthDate) throws -> Double {
            var year = Germany.workYear(.employee, regime: GermanRegime.employee, gross: 60_000)
            year.age = 2026 - born.year
            year.birthDate = born
            let with = try Germany.prepare(year).fixedAssessment.total(GermanLine.incomeTax)
            year.birthDate = BirthDate(year: 1970, month: 1, day: 1)
            year.age = 56
            let without = try Germany.prepare(year).fixedAssessment.total(GermanLine.incomeTax)
            return without - with
        }
        let early = try taxFree(BirthDate(year: 1959, month: 4, day: 10))
        let late = try taxFree(BirthDate(year: 1960, month: 5, day: 15))
        #expect(early > late && late > 0)
        #expect(try taxFree(BirthDate(year: 1961, month: 5, day: 15)) < 1e-9)
    }
}
