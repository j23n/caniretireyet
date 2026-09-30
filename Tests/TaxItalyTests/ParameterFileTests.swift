@testable import TaxItaly
import TaxKit
import Testing

/// The bundled parameter files: they load, every value cites a source, and
/// the values docs/tax/IT.md marks *verify* are flagged.
struct ParameterFileTests {
    @Test func bundledFilesLoad() throws {
        let store = ItalyTaxSystem.bundledParameters
        #expect(store.system == "it")
        #expect(store.years == [2026])
        for year in store.years {
            let set = try store.parameters(for: year)
            #expect(set.year == year)
            #expect(set.value(at: "year")?.intValue == year)
            _ = try ItalyParameters(set)
        }
        #expect(try store.parameters(for: 2045).year == 2026)
    }

    @Test func everyValueHasASource() throws {
        for year in Italy.system.parameters.years {
            let values = try Italy.system.parameters.parameters(for: year).values
            #expect(ParameterAudit.unsourcedPaths(in: values) == [], "\(year).json has values without a source")
        }
    }

    @Test func valuesToVerifyAreFlagged() throws {
        let values = try Italy.parameters().values
        #expect(ParameterAudit.pathsToVerify(in: values) == [
            "cuneo.countsExemptImpatriatiIncome",
            "forfettario.employmentIncomeLimit",
            "impatriati2024.forfettarioOnArrival",
            "inpsPension.foreignPensionCountsTowardMinimums",
            "investments.physicalGold",
            "pensionFund.newPayoutOptions",
            "wealthTax.blacklist",
        ])
    }

    @Test func readsTheLawsValues() throws {
        let p = try ItalyParameters(Italy.parameters())
        #expect(p.irpef.brackets.map(\.rate) == [0.23, 0.33, 0.43])
        #expect(p.irpef.thresholds == [28_000, 50_000])
        #expect(p.forfettario.revenueLimit == 85_000 && p.forfettario.immediateExitLimit == 100_000)
        #expect(p.forfettario.employmentIncomeLimit.value(in: 2026) == 35_000)
        #expect(p.forfettario.employmentIncomeLimit.value(in: 2027) == 30_000)
        #expect(p.pensionFund.deductionLimit == 5_300)
        #expect(p.pensionFund.payoutTaxRate(membershipYears: 10) == 0.15)
        #expect(abs(p.pensionFund.payoutTaxRate(membershipYears: 25) - 0.12) < 1e-12)
        #expect(p.pensionFund.payoutTaxRate(membershipYears: 40) == 0.09)
        #expect(p.investments.rate(for: .crypto) == 0.33 && p.investments.rate(for: .stablecoin) == 0.26)
        #expect(p.investments.rate(for: .governmentBond) == 0.125 && p.investments.rate(for: .etc) == 0.26)
        #expect(p.investments.gainRate(for: .cash) == 0)
        #expect(p.wealthTax.blacklist.contains("PA") && !p.wealthTax.blacklist.contains("IE"))
        #expect(p.inheritance.keys.sorted() == ["lineal", "other", "relative", "sibling", "spouse"])
        #expect(p.pension.coefficient(ageInMonths: 67 * 12) == 0.05608)
        #expect(abs(p.pension.coefficient(ageInMonths: 64 * 12 + 6) - (0.05088 + 0.05250) / 2) < 1e-12)
        #expect(p.pension.coefficient(ageInMonths: 75 * 12) == 0.06510)
        #expect(p.pension.coefficient(ageInMonths: 50 * 12) == 0.04204)
    }

    @Test func planOverridesChangeTheResult() throws {
        let year = Italy.workYear(.employee, regime: ItalyRegime.employee, gross: 35_000)
        let base = try Italy.prepare(year).fixedAssessment.total("it.irpef")
        let bundled = try #require(Italy.system.parameters as? JSONParameterStore)
        let store = bundled.applying(overrides: ["it.irpef.rates": ["0.23", "0.35", "0.43"]])
        let overridden = ItalyYearCalculator.prepare(system: Italy.system, year: year, state: .empty,
                                                     parameters: try store.parameters(for: 2026))
        // 2 more points on the 3,783.50 of taxable income above 28,000.
        #expect(abs(overridden.fixedAssessment.total("it.irpef") - base - 0.02 * 3_783.5) < 1e-6)
    }

    @Test func thresholdsIndexOrDrift() throws {
        var indexed = Italy.workYear(.employee, regime: ItalyRegime.employee, gross: 40_000, year: 2035)
        indexed.inflationFactor = 1.2
        var fixed = indexed
        fixed.indexThresholds = false
        let today = try Italy.prepare(Italy.workYear(.employee, regime: ItalyRegime.employee, gross: 40_000))
        let withIndexing = try Italy.prepare(indexed)
        let withoutIndexing = try Italy.prepare(fixed)
        // Indexed thresholds keep their value in today's euros, so the tax matches 2026's.
        #expect(abs(withIndexing.fixedAssessment.totalTax - today.fixedAssessment.totalTax) < 1e-6)
        // Fixed thresholds shrink in today's euros: fiscal drag.
        #expect(withoutIndexing.fixedAssessment.totalTax > withIndexing.fixedAssessment.totalTax + 100)
        // INPS amounts are indexed by law either way.
        #expect(withoutIndexing.fixedAssessment.contributions == withIndexing.fixedAssessment.contributions)
    }
}
