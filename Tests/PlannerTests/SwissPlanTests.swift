import Foundation
import Model
@testable import Planner
import TaxGeneric
import TaxItaly
import TaxKit
import TaxSwitzerland
import Testing

/// Plans with the Swiss system (`ch`) end to end: the pension-fund transfer
/// to vested benefits that early retirement ages trigger, the plan's 3a
/// payout years, and Swiss pensions taxed by Switzerland while living
/// abroad (G8). Made-up people and amounts, zero volatility; the library is
/// in euros at 1 CHF per EUR.
struct SwissPlanTests {
    func library(birth: CalendarDate, _ accounts: [SampleAccount]) -> Library {
        var library = Sample.library(birth: birth, on: "2025-12-31", accounts)
        library.upsert(FXRecord(base: .eur, quote: .chf, date: "2025-12-31", rate: 1))
        return library
    }

    func zurich(_ extra: [String: JSONValue] = [:]) -> [String: JSONValue] {
        var options: [String: JSONValue] = ["canton": "ZH", "commune": "Zurich"]
        for (key, value) in extra { options[key] = value }
        return options
    }

    func run(_ plan: PlanDocument, _ library: Library, _ systems: [any TaxSystem] = [SwissTaxSystem()],
             maxAge: Int = 62) async throws -> PlanResult {
        try await Planner.run(plan: plan, library: library, registry: TaxRegistry(systems),
                              options: PlannerOptions(maxRetirementAge: maxAge, solveSustainableSpending: false))
    }

    @Test func aBVGPensionDoesntWarnAboutVestedBenefits() async throws {
        // Born 1976 and employed in Zurich, with a BVG pension and no vested-benefits
        // account: candidate retirement ages before 58 move the BVG assets into
        // vested benefits, which needs a bucket but no warning.
        let library = library(birth: "1976-01-01", [
            SampleAccount(id: "broker", wrapper: "ch.ordinary", mix: [.cash: 1], balance: 500_000),
        ])
        var plan = Sample.plan(retire: .age(52), endAge: 62, working: "60000", retired: "40000", equityReturn: "0",
                               work: [Sample.employee(from: "2026-01-01", gross: "100000")], runs: 10)
        plan.tax.residence = [PlanResidence(from: 2020, system: "ch", options: zurich())]
        plan.pensions = [PlanPension(scheme: "ch.bvg", claim: .earliest, options: ["startingBalance": "200000"])]
        let result = try await run(plan, library)
        #expect(!result.issues.contains { $0.code == "planner.newWrapper" })
        #expect(result.start.buckets.contains { $0.wrapper == "ch.vestedBenefits" })
        // At 52 the assets moved there, untaxed.
        let transfer = try #require(result.expectedPath.years.first { $0.year == 2028 })
        #expect(!transfer.taxes.contains { $0.id.hasPrefix("ch.capitalBenefits") })
        #expect(!transfer.income.contains { $0.kind == .pension })
    }

    @Test func thePlanChoosesThe3aPayoutYears() async throws {
        // Born 1966, retired at 60 (2026), with 30,000 in pillar 3a, and cash
        // for the AHV contributions without work until 65.
        let library = library(birth: "1966-01-01", [
            SampleAccount(id: "broker", wrapper: "ch.ordinary", mix: [.cash: 1], balance: 50_000),
            SampleAccount(id: "pillar", kind: .pensionFund, wrapper: "ch.pillar3a", mix: [.cash: 1], balance: 30_000),
        ])
        var plan = Sample.plan(retire: .age(60), endAge: 66, retired: "0", equityReturn: "0", runs: 10)
        func payouts(_ result: PlanResult) -> [Int: Double] {
            result.expectedPath.years.reduce(into: [:]) { years, year in
                if let payout = year.income.first(where: { $0.kind == .payout && $0.id == "ch.pillar3a" }) {
                    years[year.year] = payout.amount
                }
            }
        }
        // By default over 5 years: 6,000 a year from 60.
        plan.tax.residence = [PlanResidence(from: 2020, system: "ch", options: zurich())]
        let byDefault = payouts(try await run(plan, library))
        #expect(byDefault.keys.sorted() == [2026, 2027, 2028, 2029, 2030])
        #expect(byDefault.values.allSatisfy { close($0, 6_000) })
        // Two accounts: 15,000 at 60 and at 61.
        plan.tax.residence[0].options = zurich(["pillar3aPayoutYears": 2])
        let two = payouts(try await run(plan, library))
        #expect(two.keys.sorted() == [2026, 2027] && two.values.allSatisfy { close($0, 15_000) })
        // 0: only as needed, and nothing is needed until it must be paid out at 65.
        plan.tax.residence[0].options = zurich(["pillar3aPayoutYears": 0])
        let asNeeded = payouts(try await run(plan, library))
        #expect(asNeeded.keys.sorted() == [2031] && close(asNeeded[2031], 30_000))
    }

    /// Born 1956, living in Zurich until 2025 and elsewhere from 2026, with a
    /// Swiss occupational pension of 12,000 a year that the plan says
    /// Switzerland taxes.
    func abroadPlan(livingIn system: TaxSystemID) -> PlanDocument {
        var plan = Sample.plan(retire: .age(65), endAge: 73, retired: "10000", equityReturn: "0", runs: 10)
        plan.tax.residence = [PlanResidence(from: 2020, system: "ch", options: zurich()),
                              PlanResidence(from: 2026, system: system)]
        plan.pensions = [PlanPension(scheme: "fixed", name: "Pension fund", fromAge: 65, perYear: 12_000,
                                     taxedIn: .source, sourceCountry: "CH", kind: .occupational)]
        return plan
    }

    @Test func switzerlandTaxesItsPensionsPaidAbroad() async throws {
        let library = library(birth: "1956-01-01", [SampleAccount(id: "broker", wrapper: "taxable", balance: 200_000)])
        let result = try await run(abroadPlan(livingIn: "generic"), library,
                                   [SwissTaxSystem(), GenericTaxSystem()], maxAge: 70)
        let taxes = try #require(result.expectedPath.years.first { $0.year == 2026 }?.taxes)
        // 1% federal and Zurich's 6%.
        #expect(close(taxes.first { $0.id == "ch.nonResident.federal" }?.amount, 120))
        let cantonal = try #require(taxes.first { $0.id == "ch.nonResident.cantonal" })
        #expect(cantonal.label == "Switzerland: Source tax (cantonal and communal, Zurich)" && close(cantonal.amount, 720))
        #expect(!result.issues.contains { $0.code == "planner.taxedAtSource" })
        #expect(result.issues.contains { $0.code == "ch.nonResident.noTreaty" })
    }

    @Test func noSwissTaxIsCountedWhereTheTreatyRefundsIt() async throws {
        let library = library(birth: "1956-01-01", [SampleAccount(id: "broker", wrapper: "it.ordinary", balance: 200_000)])
        let result = try await run(abroadPlan(livingIn: "it"), library, [SwissTaxSystem(), ItalyTaxSystem()], maxAge: 70)
        let taxes = try #require(result.expectedPath.years.first { $0.year == 2026 }?.taxes)
        #expect(!taxes.contains { $0.id.hasPrefix("ch.") })
        // Italy taxes it at 5% whatever taxedIn says.
        #expect(close(taxes.first { $0.id == "it.swissPensionTax" }?.amount, 600))
        #expect(!result.issues.contains { $0.code == "planner.taxedAtSource" })
        #expect(result.issues.contains { $0.code == "ch.nonResident.treaty" })
    }
}
