import Foundation
@testable import TaxGermany
import TaxKit
import Testing

/// The bundled parameter file: it loads, every value cites a source, the
/// values docs/tax/DE.md marks *verify* are flagged, and each group of
/// amounts follows prices by its `indexed` rule.
struct ParameterFileTests {
    @Test func bundledFilesLoad() throws {
        let store = GermanTaxSystem.bundledParameters
        #expect(store.system == "de")
        #expect(store.years == [2026])
        for year in store.years {
            let set = try store.parameters(for: year)
            #expect(set.year == year && set.value(at: "year")?.intValue == year)
            _ = try GermanParameters(set)
            _ = try DRVParameters(set)
        }
        #expect(try store.parameters(for: 2045).year == 2026)
    }

    @Test func everyValueHasASource() throws {
        for year in Germany.system.parameters.years {
            let values = try Germany.system.parameters.parameters(for: year).values
            #expect(ParameterAudit.unsourcedPaths(in: values) == [], "\(year).json has values without a source")
        }
    }

    @Test func valuesToVerifyAreFlagged() throws {
        let values = try Germany.parameters().values
        #expect(ParameterAudit.pathsToVerify(in: values) == [
            "aktivrente.selfEmployedExtension", "allowances.next",
            "drv.foreignPeriods.residenceBasedPeriodsTowardFortyFiveYears", "drv.proposals", "exitTax.instalments",
            "exitTax.returnWithinYears", "investments.otherIncome",
            "pensionHealthInsurance.voluntary.capitalIncomeExpenseAllowance",
            "pensionHealthInsurance.voluntary.partialExemptionApplies", "pensionTaxation.ageRelief",
            "pensionTaxation.foreignOccupational", "socialInsurance.next", "treaties.CH.bvgLumpSumOneFifthRule",
            "treaties.CH.extendedTaxationAfterMove", "treaties.CH.pillar3aInGermany", "treaties.IT.privatePensions",
            "treaties.IT.tfr", "wrappers.altersvorsorgedepot", "wrappers.foreign",
        ])
    }

    @Test func readsTheLawsValues() throws {
        let p = try GermanParameters(Germany.parameters())
        // The published 2026 table: €4,217 at €30,000 and €10,548 at €50,000.
        #expect(abs(p.tariff.tax(on: 30_000) - 4_217.13) < 0.01)
        #expect(abs(p.tariff.tax(on: 50_000) - 10_548.33) < 0.01)
        #expect(p.tariff.tax(on: 12_348) == 0 && p.tariff.tax(on: 12_349) > 0)
        #expect(abs(p.tariff.tax(on: 300_000) - (0.45 * 300_000 - 19_470.38)) < 1e-6)
        #expect(p.tariff.limits == [12_348, 17_799, 69_878, 277_825])
        #expect(p.soli.amount(onIncomeTax: 20_350) == 0)
        #expect(abs(p.soli.amount(onIncomeTax: 30_000) - 0.119 * 9_650) < 1e-9)
        #expect(abs(p.soli.amount(onIncomeTax: 50_000) - 0.055 * 50_000) < 1e-9)
        #expect(p.churchRate(in: "BY") == 0.08 && p.churchRate(in: "bw") == 0.08 && p.churchRate(in: "NW") == 0.09)
        #expect(p.churchRate(in: nil) == 0.09)
        for (year, share) in [(2004, 0.5), (2005, 0.5), (2020, 0.8), (2022, 0.82), (2023, 0.825), (2025, 0.835),
                              (2026, 0.84), (2030, 0.86), (2040, 0.91), (2058, 1.0), (2070, 1.0)] {
            #expect(abs(p.taxableShare.share(startedIn: year) - share) < 1e-12, "share for \(year)")
        }
        for (age, share) in [(1, 0.59), (50, 0.30), (62, 0.21), (65, 0.18), (66, 0.18), (67, 0.17), (80, 0.08), (99, 0.01)] {
            #expect(p.annuityShare(ageAtStart: age) == share, "Ertragsanteil at \(age)")
        }
        #expect(p.partialExemption(.equityFund) == 0.3 && p.partialExemption(.mixedFund) == 0.15)
        #expect(p.partialExemption(.realEstateFund) == 0.6 && p.partialExemption(.foreignRealEstateFund) == 0.8)
        #expect(p.partialExemption(.fund) == 0 && p.partialExemption(.stock) == 0)
        #expect(p.standardAgeMonths(bornIn: 1958) == 66 * 12 && p.standardAgeMonths(bornIn: 1960) == 66 * 12 + 4)
        #expect(p.standardAgeMonths(bornIn: 1964) == 67 * 12 && p.standardAgeMonths(bornIn: 1990) == 67 * 12)
        #expect(p.privateSaleCategories.contains(.etcWithDeliveryClaim) && !p.privateSaleCategories.contains(.etc))
        #expect(p.payingStateTaxesItsNationals == ["IT": true, "CH": false])
        #expect(p.kvdr.countries.contains("IT") && p.kvdr.countries.contains("CH") && !p.kvdr.countries.contains("US"))
        let drv = try DRVParameters(Germany.parameters())
        #expect(drv.averageEarnings == 51_944 && drv.pensionValue == 42.52)
        #expect(abs(drv.pensionValue(in: 2036, growth: 0.005) - 42.52 * pow(1.005, 10)) < 1e-9)
    }

    @Test func eachGroupFollowsItsIndexingRule() throws {
        let p = try GermanParameters(Germany.parameters())
        #expect(p.rule("incomeTax.tariff") == .plan && p.rule("soli") == .plan)
        #expect(p.rule("allowances.saverAllowance") == .fixed && p.rule("inheritance") == .fixed)
        #expect(p.rule("socialInsurance.health") == .wages && p.rule("provisions.retirementMaximum") == .wages)
        #expect(p.rule("wrappers.altersvorsorgedepot") == .fixed)

        // 2035, prices 20% above the plan's start, wages 1% a year above prices.
        let year = FixedYear(year: 2035, age: 50, inflationFactor: 1.2)
        let scales = IndexingScales(year: year, parameterYear: 2026, realWageGrowth: 0.01, indexFixedAllowances: false)
        let later = p.scaled(by: scales)
        #expect(later.tariff.tax(on: 50_000) == p.tariff.tax(on: 50_000))
        #expect(abs(later.saverAllowance - 1_000 / 1.2) < 1e-9)
        #expect(abs(later.health.ceiling - 69_750 * pow(1.01, 9)) < 1e-6)
        #expect(abs(later.inheritance.relationships["lineal"]!.allowance - 400_000 / 1.2) < 1e-6)

        var fixed = year
        fixed.indexThresholds = false
        let drifting = p.scaled(by: IndexingScales(year: fixed, parameterYear: 2026, realWageGrowth: 0.01,
                                                   indexFixedAllowances: false))
        #expect(abs(drifting.tariff.tax(on: 50_000 / 1.2) - p.tariff.tax(on: 50_000) / 1.2) < 1e-6)
        #expect(abs(drifting.health.ceiling - later.health.ceiling) < 1e-9)

        let indexed = p.scaled(by: IndexingScales(year: year, parameterYear: 2026, realWageGrowth: 0.01,
                                                  indexFixedAllowances: true))
        #expect(indexed.saverAllowance == 1_000 && indexed.employeeLumpSum == 1_230)
    }

    @Test func planOverridesChangeTheResult() throws {
        let year = Germany.workYear(.employee, regime: GermanRegime.employee, gross: 120_000)
        let base = try Germany.prepare(year).fixedAssessment
        let bundled = try #require(Germany.system.parameters as? JSONParameterStore)
        let store = bundled.applying(overrides: ["de.incomeTax.tariff.zones.3.rate": "0.44",
                                                 "de.soli.exemptionLimit": "40000"])
        let overridden = Germany.system.prepare(year, state: .empty, parameters: try store.parameters(for: 2026))
            .fixedAssessment
        let taxable = try #require(base.lines.first { $0.id == GermanLine.incomeTax }?.base)
        #expect(abs(overridden.total(GermanLine.incomeTax) - base.total(GermanLine.incomeTax) - 0.02 * taxable) < 1e-6)
        #expect(base.total(GermanLine.soli) > 0 && overridden.total(GermanLine.soli) == 0)

        let plan = TaxPlan(residence: [.init(from: 2026, system: "de")],
                           overrides: ["de.incomeTax.tarif.zones": "1", "de.incomeTax.tariff.zones.3.rate": "0.44"])
        #expect(Germany.system.validate(plan, parameters: store).map(\.code) == ["de.unknownOverride"])
    }

    @Test func fiscalDragAndWageGrowthOverTheYears() throws {
        // The same real salary ten years on, 2% inflation: the tariff keeps its
        // value, the lump sums shrink, and the health ceiling grows with wages.
        let today = try Germany.prepare(Germany.workYear(.employee, regime: GermanRegime.employee, gross: 80_000))
            .fixedAssessment
        var later = Germany.workYear(.employee, regime: GermanRegime.employee, gross: 80_000, year: 2036)
        later.inflationFactor = pow(1.02, 10)
        let then = try Germany.prepare(later).fixedAssessment
        #expect(then.contribution(GermanLine.health) > today.contribution(GermanLine.health))
        #expect(then.contribution(GermanLine.pension) == today.contribution(GermanLine.pension))
        // Fixed thresholds without indexing.
        later.indexThresholds = false
        let drift = try Germany.prepare(later).fixedAssessment
        #expect(drift.total(GermanLine.incomeTax) > then.total(GermanLine.incomeTax) + 500)
    }
}
