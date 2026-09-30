import Foundation
import Model
@testable import Planner
import TaxGeneric
import TaxItaly
import TaxKit
import Testing
import TestSupport

/// Plans run end to end with the real tax systems, registered as the app
/// and the CLI register them. These check that runs complete and that the
/// numbers are plausible; exact tax amounts belong to each system's
/// reference cases, and the engine's arithmetic to its hand-checked tests.
struct EndToEndTests {
    static let registry = TaxRegistry([ItalyTaxSystem(), GenericTaxSystem()])
    let library: Library
    let base: PlanDocument

    init() throws {
        library = try Fixtures.exampleLibrary()
        base = try #require(library.plans["base"])
    }

    /// The errors among `issues`.
    func errors(_ issues: [PlanIssue]) -> [String] {
        issues.filter(\.isError).map { "\($0.code): \($0.message)" }
    }

    /// Checks every result should pass: no errors, a fan whose percentiles
    /// are in order every year, success rates between 0 and 1.
    func expectPlausible(_ result: PlanResult) {
        #expect(errors(result.issues).isEmpty)
        #expect(result.fan.count == result.expectedPath.years.count || result.expectedPath.failure != nil)
        for year in result.fan {
            #expect(year.p10 <= year.p25 && year.p25 <= year.p50 && year.p50 <= year.p75 && year.p75 <= year.p90,
                    "\(year.year)")
        }
        for point in result.successCurve {
            #expect((0...1).contains(point.success), "at \(point.age)")
        }
    }

    @Test func theBasePlanRunsWithTheItalianSystem() async throws {
        #expect(errors(Planner.validate(plan: base, library: library, registry: Self.registry)).isEmpty)
        let result = try await Planner.run(plan: base, library: library, registry: Self.registry, options: .fast())
        expectPlausible(result)
        #expect(result.settings.runs == PlannerOptions.defaultFastRuns)
        #expect(result.taxParameters == ["it": 2026])
        #expect(result.focusAge == 55)

        // The answer.
        let earliest = try #require(result.answer.earliestAge)
        #expect((45...75).contains(earliest))
        #expect(result.success(atAge: earliest)! >= result.settings.confidence)
        let atTarget = try #require(result.answer.successAtTarget)
        #expect(atTarget > 0 && (earliest > 55 ? atTarget < result.settings.confidence : atTarget <= 1))
        let spending = try #require(result.answer.sustainableSpending)
        #expect(spending.age == 55 && spending.perYear > 10_000 && spending.perYear < 60_000)
        #expect(spending.success >= result.settings.confidence)
        #expect((spending.perYear < 36_000) == (atTarget < result.settings.confidence))
        let fi = try #require(result.answer.fiNumber)
        #expect(fi > 100_000 && fi < 1_500_000)

        // INPS, from its own claim options: the anticipata at 64 at the
        // earliest, the vecchiaia contributiva at 71 (plus the rising ages) at
        // the latest.
        let inps = try #require(result.markers.first { $0.kind == .pensionStart && $0.label == "INPS (contributory system)" })
        #expect((64...76).contains(inps.age))
        let inpsAmount = try #require(inps.amount)
        #expect(inpsAmount > 3_000 && inpsAmount < 40_000)
        // The marker shows a whole year, not the months paid in the first one.
        let firstFullYear = try #require(result.expectedPath.years.first { $0.age == inps.age + 1 })
        let paidNextYear = try #require(firstFullYear.income.first { $0.id == "pension-0" }?.amount)
        #expect(abs(inpsAmount - paidNextYear) < 0.01 * paidNextYear, "\(inpsAmount) against \(paidNextYear)")
        #expect(result.successCurve.first { $0.age == 55 }?.pensionStartAges["pension-0"] == inps.age)
        let fixed = try #require(result.markers.first { $0.kind == .pensionStart && $0.label.hasPrefix("State pension") })
        #expect(fixed.age == 67 && fixed.amount == 4_800)

        // Italian taxes on work, and later on the pensions.
        let years = result.expectedPath.years
        #expect(years.reduce(0) { $0 + $1.totalTax } > 0)
        let employed = try #require(years.first { $0.year == 2027 })
        #expect(employed.taxes.contains { $0.id == "it.irpef" && $0.amount > 0 })
        #expect(employed.contributions.contains { $0.id == "it.inps.employee" && $0.amount > 0 })
        let forfettario = try #require(years.first { $0.year == 2030 })
        #expect(forfettario.taxes.contains { $0.id == "it.forfettario" && $0.amount > 0 })
        let pensioner = try #require(years.first { $0.age == inps.age + 1 })
        #expect(pensioner.taxes.contains { $0.id == "it.irpef" && $0.amount > 0 })

        // The TFR held at the start is paid, and taxed, when the job ends at the end of 2028.
        let jobEnds = try #require(years.first { $0.year == 2028 })
        let tfr = try #require(jobEnds.income.first { $0.kind == .payout && $0.id == "it.tfr" })
        #expect(tfr.amount > 5_000)
        #expect(jobEnds.taxes.contains { $0.id == "it.tfr.payoutTax" && $0.amount > 0 })
        #expect(years.first { $0.year == 2029 }?.income.contains { $0.id == "it.tfr" } == false)
        #expect(!result.markers.contains { $0.kind == .accessible && $0.label == "TFR" })

        // The pension fund opens by RITA or at the vecchiaia age from INPS.
        let fund = try #require(result.markers.first { $0.kind == .accessible && $0.label == "Pension fund" })
        #expect((57...72).contains(fund.age))

        print("""
            End to end, base.json (Italy, fast mode, \(result.settings.runs) runs): earliest age \(earliest), \
            success at \(result.focusAge) \(atTarget), INPS from \(inps.age) at \(Int(inpsAmount)) a year \
            (\(result.successCurve.first { $0.age == 55 }.map { "\($0.pensionStartAges)" } ?? "")), \
            pension fund from \(fund.age), TFR paid in 2028: \(Int(tfr.amount)), sustainable spending \
            \(Int(spending.perYear)) (success \(spending.success)), FI number \(Int(fi)).
            """)
    }

    /// IRPEF and the addizionali on a pension have no subject, since they're
    /// charged on total income: the FI number takes the tax a pension adds.
    @Test func theFINumberCountsTheTaxOnPensions() async throws {
        let library = Sample.library(birth: "1986-01-01", on: "2025-12-31",
                                     [SampleAccount(id: "cash", kind: .cash, wrapper: "it.ordinary", mix: nil,
                                                    balance: 150_000)])
        var plan = Sample.plan(retire: .age(51), endAge: 90, retired: "30000",
                               pensions: [PlanPension(scheme: .fixed, fromAge: 67, perYear: d("20000"))])
        plan.tax = PlanTax(residence: [PlanResidence(from: 2026, system: "it")])
        let result = try await Planner.run(plan: plan, library: library, registry: Self.registry,
                                           options: PlannerOptions(mode: .fast(runs: 1), ageScan: .headline,
                                                                   maxRetirementAge: 0, solveSustainableSpending: false))
        // IRPEF on 20,000: 23% = 4,600 less the pension detrazione
        // 700 + 1,255 × 8,000 / 19,500 = 1,214.87; addizionali 1.73% + 0.8%
        // of 20,000 = 506. Net pension 16,108.87; (30,000 − 16,108.87) / 4%.
        let tax = 4_600 - (700 + 1_255 * 8_000 / 19_500.0) + 506
        #expect(close(result.answer.fiNumber, (30_000 - (20_000 - tax)) / 0.04, 1e-9))
        #expect(close(result.answer.fiProgress, 150_000 / ((30_000 - (20_000 - tax)) / 0.04), 1e-9))
    }

    @Test func aPlanOnGenericFlatRatesMatchesTheClosedForm() async throws {
        // Born 1986, 100,000 in a taxable account half of which is gain; works
        // 2026–2030 on 60,000 and retires at 45; a pension of 12,000 from 47.
        let library = Sample.library(birth: "1986-01-01", on: "2025-12-31",
                                     [SampleAccount(id: "broker", wrapper: "taxable", balance: 100_000)])
        var plan = Sample.plan(
            retire: .age(45), endAge: 50, working: "30000", retired: "30000",
            work: [Sample.employee(from: "2026-01-01", gross: "60000")],
            pensions: [PlanPension(scheme: .fixed, name: "Earlier job", fromAge: 47, perYear: d("12000"))],
            inflation: "0", unrealizedGainShare: "0.5", runs: 50)
        plan.tax = PlanTax(residence: [PlanResidence(from: 2026, system: "generic", options: [
            "incomeTaxRate": "0.2", "socialContributionRate": "0.1", "capitalGainsRate": "0.25",
            "pensionTaxRate": "0.1",
        ])])
        let result = try await Planner.run(plan: plan, library: library, registry: Self.registry,
                                           options: PlannerOptions(maxRetirementAge: 46, solveSustainableSpending: false))
        expectPlausible(result)

        // Working: 60,000 less 10% contributions and 20% income tax leaves
        // 42,000; 12,000 is saved at the start of each year, and grows 5%.
        let first = try #require(result.expectedPath.years.first)
        #expect(first.taxes == [AmountItem(id: "generic.incomeTax", label: "Income tax", amount: 12_000)])
        #expect(first.contributions == [AmountItem(id: "generic.social", label: "Social contributions", amount: 6_000)])
        var value = 100_000.0
        var cost = 50_000.0
        for year in 2026...2030 {
            value = (value + 12_000) * 1.05
            cost += 12_000
            #expect(close(result.expectedValue(in: year), value), "\(year)")
        }
        // Retired: what the pension (net of 10%) doesn't cover is sold, grossed
        // up for 25% tax on the gain share of the sale.
        for year in 2031...2036 {
            let need = 30_000 - (year >= 2033 ? 12_000 * 0.9 : 0)
            let gainShare = 1 - cost / value
            let sale = need / (1 - 0.25 * gainShare)
            let detail = try #require(result.expectedPath.years.first { $0.year == year })
            #expect(close(detail.taxes.first { $0.id == "generic.capitalGainsTax" }?.amount, 0.25 * gainShare * sale),
                    "\(year)")
            cost *= 1 - sale / value
            value = (value - sale) * 1.05
            #expect(close(result.expectedValue(in: year), value), "\(year)")
        }
        let pensionYear = try #require(result.expectedPath.years.first { $0.year == 2033 })
        #expect(pensionYear.taxes.contains(AmountItem(id: "generic.pensionTax", label: "Tax on pensions", amount: 1_200)))

        // Zero volatility: every run is the deterministic one.
        for year in result.fan {
            #expect(year.p10 == year.expected && year.p90 == year.expected)
        }
    }

    @Test func movingFromItalyToAGenericCountrySwitchesTheTaxes() async throws {
        var plan = base
        plan.tax.residence.append(PlanResidence(from: 2045, system: "generic", options: [
            "incomeTaxRate": "0.2", "pensionTaxRate": "0.15", "capitalGainsRate": "0.26",
        ]))
        #expect(errors(Planner.validate(plan: plan, library: library, registry: Self.registry)).isEmpty)
        let result = try await Planner.run(plan: plan, library: library, registry: Self.registry,
                                           options: PlannerOptions(mode: .fast(runs: 100), ageScan: .headline,
                                                                   solveSustainableSpending: false))
        expectPlausible(result)
        #expect(result.taxParameters == ["it": 2026, "generic": 2026])

        // Italian taxes up to 2044, the generic system's from 2045.
        let years = result.expectedPath.years
        for year in years where !year.taxes.isEmpty {
            let systems = Set(year.taxes.map { $0.id.split(separator: ".").first.map(String.init) ?? "" })
            #expect(systems == [year.year < 2045 ? "it" : "generic"], "\(year.year): \(systems)")
        }
        #expect(years.contains { $0.year < 2045 && $0.taxes.contains { $0.id == "it.irpef" } })
        // INPS keeps paying abroad, taxed where you live.
        let inps = try #require(result.markers.first { $0.kind == .pensionStart && $0.label == "INPS (contributory system)" })
        let pensioner = try #require(years.first { $0.age == inps.age + 1 })
        #expect(pensioner.taxes.contains { $0.id == "generic.pensionTax" && $0.amount > 0 })
        #expect(pensioner.income.contains { $0.kind == .pension && $0.id == "pension-0" })
    }
}
