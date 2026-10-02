import Foundation
import Model
@testable import Planner
import TaxGeneric
import TaxItaly
import TaxKit
import Testing

/// G8: a pension taxed in the paying country (`taxedIn: source`) is taxed
/// by that country's system when one is registered
/// (`TaxSystem.prepareNonResident`), while the person lives elsewhere. The
/// residence is `generic` or a flat test system; the paying country is a
/// made-up "XA" whose system taxes non-residents' pensions. Made-up people,
/// countries and rates.
struct NonResidentTaxTests {
    /// Born 1956, retired, with 200,000 in a taxable account.
    let library = Sample.library(birth: "1956-01-01", on: "2025-12-31",
                                 [SampleAccount(id: "broker", wrapper: "taxable", balance: 200_000)])

    /// Living under `generic` (20% on pensions it taxes), spending 20,000 a
    /// year, with a pension of 12,000 from XA taxed there.
    var plan: PlanDocument {
        var plan = Sample.plan(retire: .age(60), endAge: 73, retired: "20000", equityReturn: "0", runs: 10)
        plan.tax.residence = [PlanResidence(from: 2020, system: "generic", options: ["incomeTaxRate": "0.2"])]
        plan.pensions = [PlanPension(scheme: "fixed", name: "Pension from XA", fromAge: 65, perYear: 12_000,
                                     taxedIn: .source, sourceCountry: "xa")]
        return plan
    }

    /// XA's system: 15% on pensions paid to non-residents.
    var payer: FlatTaxSystem {
        var payer = FlatTaxSystem()
        payer.id = "payer"
        payer.name = "Payer"
        payer.country = "XA"
        payer.nonResidentRate = 0.15
        return payer
    }

    func run(_ plan: PlanDocument, _ systems: [any TaxSystem], library: Library? = nil) async throws -> PlanResult {
        try await Planner.run(plan: plan, library: library ?? self.library, registry: TaxRegistry(systems),
                              options: PlannerOptions(maxRetirementAge: 62, solveSustainableSpending: false))
    }

    func schedule(_ plan: PlanDocument, _ systems: [any TaxSystem]) throws -> AgeSchedule {
        let (model, issues) = PlanInterpreter.interpret(plan: plan, library: library, registry: TaxRegistry(systems),
                                                        options: PlannerOptions())
        let interpreted = try #require(model, "\(issues.filter(\.isError))")
        return AgeSchedule(model: interpreted, age: 60, neededMasks: interpreted.frames.map { _ in [] },
                           expectedMask: interpreted.expectedEvents)
    }

    func taxes(_ result: PlanResult, in year: Int) -> [AmountItem] {
        result.expectedPath.years.first { $0.year == year }?.taxes ?? []
    }

    @Test func thePayingCountryTaxesAPensionTaxedAtSource() async throws {
        let result = try await run(plan, [GenericTaxSystem(), payer])
        #expect(!result.issues.contains { $0.code == "planner.taxedAtSource" })
        let line = try #require(taxes(result, in: 2026).first { $0.id == "payer.nonResident" })
        #expect(line.label == "Payer: Non-resident tax" && close(line.amount, 1_800))
        // The residence doesn't tax it: generic follows taxedIn.
        #expect(!taxes(result, in: 2026).contains { $0.id == "generic.pensionTax" })
        // 200,000 + 12,000 − 1,800 − 20,000.
        #expect(close(result.expectedValue(in: 2026), 190_200, 1e-9))
        // The FI number counts the pension net of the paying country's tax: (20,000 − 10,200) / 4%.
        #expect(close(result.answer.fiNumber, 245_000, 1e-9))

        // The residence system still sees the pension, with the tax charged on it.
        let years = try schedule(plan, [GenericTaxSystem(), payer]).fixedYears
        let pension = try #require(years.first?.pensions.first)
        #expect(pension.taxedIn == .source && pension.sourceCountry == "XA" && close(pension.sourceTax, 1_800))
    }

    @Test func thePayingSystemComputesInItsOwnCurrency() async throws {
        // 1 EUR = 0.9 CHF. XA's system computes in CHF: the first CHF 5,000 of a
        // pension isn't taxed, and a CHF 90 fee is charged on top.
        var library = library
        library.upsert(FXRecord(base: .eur, quote: .chf, date: "2025-12-31", rate: d("0.9")))
        var payer = payer
        payer.currency = "CHF"
        payer.nonResidentAllowance = 5_000
        payer.nonResidentFee = 90
        let result = try await run(plan, [GenericTaxSystem(), payer], library: library)
        // 12,000 EUR is CHF 10,800; 15% of CHF 5,800 is CHF 870, or 966.67 EUR; the fee is 100 EUR.
        #expect(close(taxes(result, in: 2026).first { $0.id == "payer.nonResident" }?.amount, 870 / 0.9))
        #expect(close(taxes(result, in: 2026).first { $0.id == "payer.nonResidentFee" }?.amount, 100))
        #expect(!result.issues.contains { $0.code.contains("xchange") })
    }

    @Test func withoutAPayingSystemThePensionStaysUntaxed() async throws {
        var plan = plan
        plan.pensions[0].sourceCountry = "XB"
        let result = try await run(plan, [GenericTaxSystem(), payer])
        #expect(result.issues.contains { $0.code == "planner.taxedAtSource" })
        #expect(!taxes(result, in: 2026).contains { $0.id.hasPrefix("payer.") || $0.id == "generic.pensionTax" })
        #expect(close(result.expectedValue(in: 2026), 192_000, 1e-9))
        #expect(try schedule(plan, [GenericTaxSystem(), payer]).fixedYears.first?.pensions.first?.sourceTax == nil)
    }

    @Test func aPayingSystemThatDoesntTaxNonResidentsWarns() async throws {
        var payer = payer
        payer.nonResidentRate = nil
        let result = try await run(plan, [GenericTaxSystem(), payer])
        let issue = try #require(result.issues.first { $0.code == "planner.taxedAtSource" })
        #expect(issue.message.contains("Payer") && issue.index == 0)
        #expect(close(result.expectedValue(in: 2026), 192_000, 1e-9))
    }

    @Test func livingInThePayingCountryItIsTheResidencesToTax() async throws {
        // Moving to XA in 2028: from then on XA taxes the pension as the residence (10%).
        var payer = payer
        payer.incomeRate = 0.1
        var plan = plan
        plan.tax.residence.append(PlanResidence(from: 2028, system: "payer"))
        let result = try await run(plan, [GenericTaxSystem(), payer])
        #expect(close(taxes(result, in: 2027).first { $0.id == "payer.nonResident" }?.amount, 1_800))
        #expect(!taxes(result, in: 2028).contains { $0.id == "payer.nonResident" })
        #expect(close(taxes(result, in: 2028).first { $0.id == "flat.income" }?.amount, 1_200))
        #expect(!result.issues.contains { $0.code == "flat.nonResidentAtHome" || $0.code == "planner.taxedAtSource" })
        let years = try schedule(plan, [GenericTaxSystem(), payer]).fixedYears
        #expect(years.first { $0.year == 2028 }?.pensions.first?.taxedIn == .residence)
        #expect(years.first { $0.year == 2028 }?.pensions.first?.sourceTax == nil)
    }

    @Test func theResidenceSystemCanCreditTheForeignTax() async throws {
        // At home, 25% on the pension too, less what XA charged.
        var home = FlatTaxSystem()
        home.id = "home"
        home.name = "Home"
        home.incomeRate = 0.25
        home.taxesSourcePensionsWithCredit = true
        var plan = plan
        plan.tax.residence = [PlanResidence(from: 2020, system: "home")]
        let result = try await run(plan, [home, payer])
        let year = taxes(result, in: 2026)
        #expect(close(year.first { $0.id == "flat.income" }?.amount, 3_000))
        #expect(close(year.first { $0.id == "flat.foreignCredit" }?.amount, -1_800))
        #expect(close(year.first { $0.id == "payer.nonResident" }?.amount, 1_800))
        // 3,000 in all: 1,800 abroad and 1,200 at home.
        #expect(close(result.expectedValue(in: 2026), 200_000 + 12_000 - 3_000 - 20_000, 1e-9))
    }

    @Test func contributionsIssuesAndStateFromThePayingSystem() async throws {
        var payer = payer
        payer.nonResidentContributionRate = 0.05
        // A residence timeline that also names XA's system: its options go with the non-resident years.
        var plan = plan
        plan.tax.residence.append(PlanResidence(from: 2040, system: "payer", options: ["surcharge": "0.01"]))
        let result = try await run(plan, [GenericTaxSystem(), payer])
        let contribution = try #require(result.expectedPath.years.first { $0.year == 2026 }?.contributions
            .first { $0.id == "payer.nonResidentHealth" })
        #expect(contribution.label == "Payer: Health contributions" && close(contribution.amount, 600))
        #expect(close(result.expectedValue(in: 2026), 200_000 + 12_000 - 1_800 - 600 - 20_000, 1e-9))

        let schedule = try schedule(plan, [GenericTaxSystem(), payer])
        #expect(schedule.years[0].taxState["payer.nonResidentYears"] == nil)
        #expect(schedule.years[1].taxState["payer.nonResidentYears"] == 1)
        #expect(schedule.years[2].taxState["payer.nonResidentYears"] == 2)
        #expect(NonResidentTaxes.options(of: "payer", in: 2026, residence: [
            TaxPlan.Residence(from: 2020, system: "generic"),
            TaxPlan.Residence(from: 2040, system: "payer", options: ["surcharge": "0.01"]),
        ]) == ["surcharge": "0.01"])
    }

    @Test func italyTaxesAnINPSPensionPaidAbroad() async throws {
        // An Italian citizen living under generic, with an INPS pension of 25,000 taxed in Italy.
        var library = library
        library.settings.person?.citizenships = ["IT"]
        var plan = plan
        plan.pensions = [PlanPension(scheme: "fixed", name: "INPS", fromAge: 65, perYear: 25_000, taxedIn: .source,
                                     sourceCountry: "IT", kind: .statutory)]
        let italy = ItalyTaxSystem()
        let result = try await run(plan, [GenericTaxSystem(), italy], library: library)
        #expect(!result.issues.contains { $0.code == "planner.taxedAtSource" || $0.code.hasPrefix("it.") })
        let year = FixedYear(year: 2026, age: 70, pensions: [
            .init(id: "pension-0", scheme: "fixed", amount: 25_000, taxedIn: .source, kind: .statutory,
                  startYear: 2021, sourceCountry: "IT"),
        ], citizenships: ["IT"], residence: [TaxPlan.Residence(from: 2020, system: "generic")])
        let expected = try #require(italy.prepareNonResident(year, state: .empty,
                                                             parameters: try italy.parameters.parameters(for: 2026)))
            .fixedAssessment
        let taxes = taxes(result, in: 2026)
        for line in expected.lines {
            let reported = try #require(taxes.first { $0.id == line.id })
            #expect(reported.label == "Italy: \(line.label)" && close(reported.amount, line.amount))
        }
        #expect(close(result.expectedValue(in: 2026), 200_000 + 25_000 - expected.totalTax - 20_000, 1e-9))
    }

    @Test func livingInItalyAnItalianPensionTaxedAtSourceIsResidenceIncome() async throws {
        var plan = plan
        plan.tax.residence = [PlanResidence(from: 2020, system: "it")]
        plan.pensions = [PlanPension(scheme: "fixed", name: "Italian pension", fromAge: 65, perYear: 28_000,
                                     taxedIn: .source, sourceCountry: "IT")]
        var library = library
        library.accounts["broker"]?.tax = AccountTax(wrapper: "it.ordinary")
        let result = try await run(plan, [ItalyTaxSystem()], library: library)
        // IRPEF as for any pension taxed in Italy (the reference case pension-28000).
        #expect(close(taxes(result, in: 2026).first { $0.id == "it.irpef" }?.amount, 5_690))
        #expect(!taxes(result, in: 2026).contains { $0.id.hasPrefix("it.nonResident") })
        #expect(!result.issues.contains { $0.code == "planner.taxedAtSource" })
    }

    @Test func italyCreditsTheTaxOfAPensionItTaxesAnyway() async throws {
        // Living in Italy with a Swiss AHV pension that the plan says Switzerland taxes, through a
        // made-up Swiss-like system: Italy taxes it at 5% anyway, crediting the other country's tax.
        var swiss = payer
        swiss.country = "CH"
        swiss.nonResidentRate = 0.02
        var plan = plan
        plan.tax.residence = [PlanResidence(from: 2020, system: "it")]
        plan.pensions = [PlanPension(scheme: "fixed", name: "AHV", fromAge: 65, perYear: 20_000, taxedIn: .source,
                                     sourceCountry: "CH", kind: .statutory)]
        var library = library
        library.accounts["broker"]?.tax = AccountTax(wrapper: "it.ordinary")
        let result = try await run(plan, [ItalyTaxSystem(), swiss], library: library)
        let year = taxes(result, in: 2026)
        #expect(close(year.first { $0.id == "payer.nonResident" }?.amount, 400))
        #expect(close(year.first { $0.id == "it.swissPensionTax" }?.amount, 1_000))
        #expect(close(year.first { $0.id == "it.foreignTaxCredit" }?.amount, -400))
        #expect(result.issues.contains { $0.code == "it.treaty.taxedIn" })
    }

    @Test func aSchemesPensionsComeFromItsSystemsCountry() throws {
        // A scheme of XA's system, with no sourceCountry in the plan, is paid from XA.
        var plan = plan
        plan.pensions = [PlanPension(scheme: "flat.fund", claim: .age(70), taxedIn: .source,
                                     options: ["startingBalance": "100000"])]
        let years = try schedule(plan, [GenericTaxSystem(), payer]).fixedYears
        let pension = try #require(years.first?.pensions.first)
        #expect(pension.sourceCountry == "XA" && close(pension.sourceTax, 5_000 * 0.15))
    }
}
