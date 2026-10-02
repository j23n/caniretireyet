@testable import TaxSwitzerland
import TaxKit
import Testing

/// The bundled parameter files: they load, every value cites a source, the
/// values docs/tax/CH.md marks *verify* are flagged, and amounts follow
/// prices as their `indexed` rule says.
struct ParameterFileTests {
    @Test func bundledFilesLoad() throws {
        let store = SwissTaxSystem.bundledParameters
        #expect(store.system == "ch")
        #expect(store.years == [2026])
        for year in store.years {
            let set = try store.parameters(for: year)
            #expect(set.year == year && set.value(at: "year")?.intValue == year)
            _ = try SwissParameters(set)
        }
        #expect(try store.parameters(for: 2045).year == 2026)
        #expect(Swiss.system.currency == "CHF" && Swiss.system.id == TaxSwitzerland.systemID)
    }

    @Test func everyValueHasASource() throws {
        for year in Swiss.system.parameters.years {
            let values = try Swiss.system.parameters.parameters(for: year).values
            #expect(ParameterAudit.unsourcedPaths(in: values) == [], "\(year).json has values without a source")
        }
    }

    @Test func valuesToVerifyAreFlagged() throws {
        let flagged = ParameterAudit.pathsToVerify(in: try Swiss.parameters().values)
        #expect(flagged.filter { !$0.hasPrefix("cantonsNotOffered") } == [
            "ahvPension.adjustment2027", "ahvPension.earlyWithdrawal", "ahvPension.revaluationFactor",
            "bvgSchemeDefaults", "cantons.TI.capitalBenefits", "cantons.TI.deductions.children",
            "cantons.TI.deductions.indexed", "cantons.TI.deductions.insurancePremiums",
            "cantons.TI.deductions.professionalExpenses", "cantons.TI.deductions.singlePersonDeduction",
            "cantons.TI.income.indexed", "cantons.TI.income.married", "cantons.TI.income.maximumCategoryRate",
            "cantons.TI.inheritance", "cantons.TI.lumpSumTaxation", "cantons.TI.multipliers.church",
            "cantons.TI.nonResident", "cantons.TI.personalTax", "cantons.TI.wealth.brake", "cantons.TI.wealth.single",
            "cantons.ZH.deductions.insurancePremiums", "cantons.ZH.inheritance", "cantons.ZH.multipliers.church",
            "cantons.ZH.nonResident", "cantons.ZH.personalTax", "expatriates", "federal.deductions.commutingMaximum",
            "federal.dividends", "federal.lumpSumTaxation", "federal.tariff.single", "foreign.nonResident",
            "foreign.pensions.treaties.DE", "foreign.wrappers", "investments.professionalTrader",
            "lumpSumTaxationAbolishedIn", "pillar3a.nextYear", "property.imputedRentalValue",
            "socialSecurity.nonEmployed.incomeCredit", "socialSecurity.selfEmployed",
        ])
    }

    @Test func readsTheLawsValues() throws {
        let p = try SwissParameters(Swiss.parameters())
        #expect(p.federal.tariff.thresholds.first == 15_200 && p.federal.tariff.thresholds.last == 185_100)
        #expect(abs(p.federal.tariff.tax(on: 185_100) - 10_936.64) < 0.005)
        #expect(p.federal.maximumAverageRate == 0.115 && p.federal.minimumTax == 25)
        #expect(p.federal.capitalBenefitShare == 0.2)
        #expect(p.employee.ahvRate == 0.053 && p.employee.alvCap == 148_200 && p.employee.alvSolidarityRate == 0)
        #expect(p.bvg.coordinationDeduction == 26_460 && p.bvg.creditRate(age: 40) == 0.10 && p.bvg.creditRate(age: 24) == 0)
        #expect(p.pillar3a.maximumWithPensionFund == 7_258 && p.pillar3a.maximumWithoutPensionFund == 36_288)
        #expect(p.nonEmployed.contribution(onBase: 1_000_000) == 2_014)
        #expect(p.nonEmployed.contribution(onBase: 9_000_000) == 26_500)
        #expect(p.nonEmployed.contribution(onBase: 349_999) == 530 && p.nonEmployed.contribution(onBase: 350_000) == 636)
        #expect(p.ahv.earliestAge == 63 && p.ahv.latestAge == 70 && p.ahv.referenceAge == 65)
        #expect(p.ahv.fullMonthlyPension(averageIncome: 0) == 1_260)
        #expect(p.ahv.fullMonthlyPension(averageIncome: 200_000) == 2_520)
        #expect(Set(p.cantons.keys) == ["ZH", "TI"])
        let zh = try #require(p.cantons["ZH"])
        let ti = try #require(p.cantons["TI"])
        #expect(zh.name == "Zurich" && zh.capital == "Zurich" && zh.cantonMultiplier == 0.95 && zh.communes["Zurich"] == 1.19)
        #expect(ti.name == "Ticino" && ti.capital == "Bellinzona" && ti.communes["Lugano"] == 0.80)
        #expect(!zh.lumpSumAvailable && ti.lumpSumAvailable)
        #expect(abs(zh.incomeSchedule(in: 2026).tax(on: 100_000) - 6_170) < 1e-9)
        // Ticino's categories are capped by the year's maximum rate, which falls to 12% by 2030.
        #expect(ti.incomeSchedule(in: 2026).brackets.last?.rate == 0.14)
        #expect(ti.incomeSchedule(in: 2030).brackets.map(\.rate).max() == 0.12)
        #expect(ti.wealthSimpleTax(on: 199_999) == 0 && ti.wealthSimpleTax(on: 200_000) == 200)
        #expect(ti.singlePerson?.amount(netIncome: 23_999) == 8_000 && ti.singlePerson?.amount(netIncome: 24_000) == 7_000)
        #expect(ti.singlePerson?.amount(netIncome: 45_000) == 0)
        #expect(ti.conversionFactor(table: "male") == 0.05077 && zh.conversionFactor(table: "male") == 0)
        #expect(p.foreignWrappers["it.pensionFund"] == .taxDeferred && p.foreignWrappers["it.tfr"] == .taxedAtSource)
        #expect(p.foreignWrappers["de.depot"] == .taxable)
        // Treaties and the source tax on pensions paid abroad.
        #expect(Set(p.treaties.keys) == ["IT", "DE"])
        #expect(p.treaties["IT"]?.system == "it" && p.treaties["DE"]?.system == "de" && p.treaties["DE"]?.name == "Germany")
        #expect(p.treaties["IT"]?.mayBePublicService(nil) == true && p.treaties["IT"]?.mayBePublicService(.statutory) == true)
        #expect(p.treaties["DE"]?.mayBePublicService(.statutory) == false
                && p.treaties["DE"]?.mayBePublicService(.occupational) == true)
        #expect(p.treaties["IT"]?.mayBePublicService(.privateAnnuity) == false)
        #expect(p.nonResidentFederalAnnuityRate == 0.01)
        #expect(zh.nonResidentAnnuityRate == 0.06 && ti.nonResidentAnnuityRate == 0.09)
    }

    @Test func indexingRulesFollowTheLaw() throws {
        let p = try SwissParameters(Swiss.parameters())
        #expect(p.rules["federal.tariff"] == .law && p.rules["federal.deductions"] == .law)
        #expect(p.rules["federal.tariff.minimumTax"] == .fixed)
        #expect(p.rules["socialSecurity"] == .law && p.rules["bvg"] == .law && p.rules["pillar3a"] == .law)
        #expect(p.rules["cantons.ZH.income"] == .law && p.rules["cantons.ZH.wealth"] == .law)
        #expect(p.rules["cantons.TI.income"] == .law && p.rules["cantons.TI.deductions"] == .law)
        #expect(p.rules["cantons.TI.wealth"] == .plan)
        #expect(p.rules["cantons.ZH.personalTax"] == .fixed && p.rules["expatriates"] == .fixed)
    }

    @Test func amountsIndexedByLawKeepTheirValue() throws {
        let today = try Swiss.prepare(Swiss.workYear(.employee, gross: 100_000)).fixedAssessment
        var later = Swiss.workYear(.employee, gross: 100_000, year: 2035)
        later.inflationFactor = 1.2
        later.indexThresholds = false
        let drifted = try Swiss.prepare(later).fixedAssessment
        // Tariffs, deductions and contributions are indexed by law, whatever the plan says.
        for id in [SwissLine.federal, SwissLine.cantonal, SwissLine.communal] {
            #expect(abs(drifted.total(id) - today.total(id)) < 1e-9, "\(id)")
        }
        #expect(drifted.contributions == today.contributions)
        // The personal tax is fixed in nominal francs, so it shrinks in today's money.
        #expect(abs(drifted.total(SwissLine.personalTax) - 24 / 1.2) < 1e-9)

        // Ticino's wealth tariff follows the plan: without indexing its limits shrink, so the tax rises.
        let wealth = VariableYear(balances: [.init(wrapper: "ch.ordinary", category: .equityFund, value: 600_000)])
        var retired = Swiss.pensionYear(30_000, commune: "Lugano", year: 2035)
        retired.inflationFactor = 1.2
        let indexed = try Swiss.prepare(retired).assess(wealth).total(SwissLine.wealthCantonal)
        retired.indexThresholds = false
        let fixed = try Swiss.prepare(retired).assess(wealth).total(SwissLine.wealthCantonal)
        #expect(fixed > indexed + 50)
    }

    @Test func planOverridesChangeTheResult() throws {
        let year = Swiss.workYear(.employee, gross: 100_000)
        let base = try Swiss.prepare(year).fixedAssessment
        let bundled = try #require(Swiss.system.parameters as? JSONParameterStore)
        let store = bundled.applying(overrides: ["ch.cantons.ZH.multipliers.canton": "0.98"])
        let system = SwissTaxSystem(parameters: store)
        let overridden = try Swiss.prepare(year, system: system).fixedAssessment
        #expect(abs(overridden.total(SwissLine.cantonal) - base.total(SwissLine.cantonal) * 0.98 / 0.95) < 1e-6)
        #expect(overridden.total(SwissLine.communal) == base.total(SwissLine.communal))
        // An unknown override is reported.
        let plan = TaxPlan(residence: [.init(from: 2026, system: "ch", options: Swiss.place("Zurich"))],
                           overrides: ["ch.cantons.ZH.multipliers.cantonn": "1"], citizenships: ["CH"])
        #expect(Swiss.system.validate(plan, parameters: Swiss.system.parameters).map(\.code) == ["ch.unknownOverride"])
    }
}
