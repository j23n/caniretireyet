import Foundation
import Model
@testable import Planner
import TaxItaly
import TaxKit
import Testing

extension Sample {
    /// The interpreted plan, or a failed expectation with its issues.
    static func model(_ plan: PlanDocument, _ library: Library, system: FlatTaxSystem = FlatTaxSystem())
        throws -> PlanModel {
        let (model, issues) = PlanInterpreter.interpret(plan: plan, library: library, registry: registry(system),
                                                        options: PlannerOptions())
        return try #require(model, "\(issues.filter(\.isError))")
    }

    /// What the tax system is asked to prepare in each year of the
    /// deterministic run, retiring at `age`.
    static func fixedYears(_ plan: PlanDocument, _ library: Library, system: FlatTaxSystem = FlatTaxSystem(),
                           age: Int) throws -> [FixedYear] {
        let model = try model(plan, library, system: system)
        return AgeSchedule(model: model, age: age, neededMasks: model.frames.map { _ in [] },
                           expectedMask: model.expectedEvents).fixedYears
    }
}

/// A plan in another currency than the library's, a tax system with its own
/// currency, and the person's facts the systems see. Made-up people and rates.
struct CurrencyAndPersonTests {
    /// Born 1976, working in 2026–2027 for 60,000 a year, spending all of it.
    func library(fx: [FXRecord] = []) -> Library {
        var library = Sample.library(birth: "1976-01-01", on: "2025-12-31", [SampleAccount(id: "broker", balance: 100_000)])
        for record in fx { library.upsert(record) }
        return library
    }

    var plan: PlanDocument {
        Sample.plan(retire: .age(52), endAge: 54, working: "60000", retired: "0", equityReturn: "0",
                    work: [Sample.employee(from: "2026-01-01", gross: "60000")], runs: 10)
    }

    /// A system that computes in CHF: 10% on work income above CHF 10,000.
    var swissLike: FlatTaxSystem {
        var system = FlatTaxSystem()
        system.currency = "CHF"
        system.incomeAllowance = 10_000
        system.incomeRate = 0.1
        return system
    }

    func incomeTax(_ result: PlanResult, in year: Int) -> Double? {
        result.expectedPath.years.first { $0.year == year }?.taxes.first { $0.id == "flat.income" }?.amount
    }

    @Test func aSystemWithItsOwnCurrencyConvertsAtTheStartDatesRate() async throws {
        // 1 EUR = 0.9 CHF on the start date; a later rate doesn't count.
        let library = library(fx: [FXRecord(base: .eur, quote: .chf, date: "2025-12-31", rate: d("0.9")),
                                   FXRecord(base: .eur, quote: .chf, date: "2026-06-30", rate: d("1.1"))])
        let result = try await Sample.run(plan, library, system: swissLike)
        // 60,000 EUR is 54,000 CHF; 44,000 CHF are taxed at 10%: 4,400 CHF, or 4,888.89 EUR.
        #expect(close(incomeTax(result, in: 2026), 4_400 / 0.9))
        #expect(close(incomeTax(result, in: 2027), 4_400 / 0.9))
        let years = try Sample.fixedYears(plan, library, system: swissLike, age: 52)
        #expect(years.allSatisfy { $0.currencyRate == 0.9 })
        #expect(!result.issues.contains { $0.code.hasPrefix("planner.") && $0.code.contains("xchange") })
        // A system without a currency of its own gets 1.
        #expect(try Sample.fixedYears(plan, library, age: 52).allSatisfy { $0.currencyRate == 1 })
    }

    @Test func withoutARateOnTheStartDateItWarns() async throws {
        // Only a later rate: it's used, with a warning.
        let later = library(fx: [FXRecord(base: .chf, quote: .eur, date: "2026-03-31", rate: d("1.25"))])
        let usingLater = try await Sample.run(plan, later, system: swissLike)
        #expect(usingLater.issues.contains { $0.code == "planner.exchangeRateAfterStart" })
        #expect(close(incomeTax(usingLater, in: 2026), (60_000 * 0.8 - 10_000) * 0.1 / 0.8))

        // No rate at all: 1 to 1, with a warning.
        let none = try await Sample.run(plan, library(), system: swissLike)
        #expect(none.issues.contains { $0.code == "planner.noExchangeRate" && $0.severity == .warning })
        #expect(close(incomeTax(none, in: 2026), 5_000))
    }

    @Test func aPlanInAnotherCurrencyValuesThePortfolioInIt() async throws {
        // The library is in EUR: 100,000 EUR in the broker and 11,000 USD in a
        // US account. The plan runs in CHF: 1 EUR = 0.95 CHF, 1 EUR = 1.1 USD.
        var library = library(fx: [FXRecord(base: .eur, quote: .chf, date: "2025-12-31", rate: d("0.95")),
                                   FXRecord(base: .eur, quote: .usd, date: "2025-12-31", rate: d("1.1"))])
        library.accounts["us"] = Account(id: "us", name: "US", kind: .brokerage, currency: .usd, opened: "2020-01-01",
                                         valuation: .balance, assetClasses: [.equity: 1],
                                         tax: AccountTax(wrapper: "flat.ordinary"))
        library.upsert(Valuation(account: "us", date: "2025-12-31", balance: 11_000))
        var plan = Sample.plan(retire: .age(50), endAge: 52, retired: "10000", equityReturn: "0", runs: 10)
        plan.currency = .chf
        let result = try await Sample.run(plan, library)

        #expect(result.currency == .chf)
        #expect(result.start.planAssets == d("104500"))
        #expect(close(result.start.buckets.first { $0.wrapper == "flat.ordinary" }?.value, 104_500))
        // Spending is in CHF too.
        #expect(close(result.expectedValue(in: 2026), 94_500))

        // Without a currency, the plan is in the base currency.
        plan.currency = nil
        let inEuros = try await Sample.run(plan, library)
        #expect(inEuros.currency == .eur && inEuros.start.planAssets == d("110000"))
    }

    @Test func italyTaxesAPlanInFrancsInEuros() async throws {
        // Born 1960, living in Italy on a pension of CHF 20,000; 1 EUR = 0.95 CHF.
        var library = Sample.library(birth: "1960-01-01", on: "2025-12-31",
                                     [SampleAccount(id: "broker", wrapper: "it.ordinary", balance: 100_000)])
        library.upsert(FXRecord(base: .eur, quote: .chf, date: "2025-12-31", rate: d("0.95")))
        var plan = Sample.plan(retire: .age(60), endAge: 68, retired: "20000", equityReturn: "0", runs: 10)
        plan.currency = .chf
        plan.tax.residence = [PlanResidence(from: 2020, system: "it")]
        plan.pensions = [PlanPension(scheme: "fixed", name: "Pension", fromAge: 60, perYear: 20_000)]
        let italy = ItalyTaxSystem()
        let result = try await Planner.run(plan: plan, library: library, registry: TaxRegistry([italy]),
                                           options: PlannerOptions(maxRetirementAge: 62, solveSustainableSpending: false))
        #expect(!result.issues.contains { $0.code.contains("xchange") })

        // Italy sees €21,052.63 and taxes it in euros; the plan shows the tax in francs.
        let inEuros = italy.prepare(FixedYear(year: 2026, age: 66, pensions: [
            .init(id: "pension-0", scheme: "fixed", amount: 20_000 / 0.95),
        ]), state: .empty, parameters: try italy.parameters.parameters(for: 2026)).fixedAssessment
        let taxes = try #require(result.expectedPath.years.first { $0.year == 2026 }?.taxes)
        for id in ["it.irpef", "it.addizionaleRegionale", "it.addizionaleComunale"] {
            let euros = inEuros.lines.filter { $0.id == id }.reduce(0) { $0 + $1.amount }
            #expect(euros > 0)
            #expect(close(taxes.first { $0.id == id }?.amount, euros * 0.95), "\(id)")
        }
    }

    @Test func theSystemsSeeThePersonAndTheResidenceTimeline() throws {
        // Born 3 March 1960, citizen of Italy and Germany, with a statement pension
        // from Germany paid since 60 (2020), 40% from an occupational scheme's
        // mandatory part.
        var library = Sample.library(birth: "1960-03-03", on: "2025-12-31", [SampleAccount(id: "broker", balance: 100_000)])
        library.settings.person?.citizenships = ["IT", "de"]
        var plan = Sample.plan(retire: .age(65), endAge: 68, retired: "20000", runs: 10)
        plan.pensions = [PlanPension(scheme: "fixed", name: "German pension", fromAge: 60, perYear: 12_000,
                                     sourceCountry: "de", options: ["mandatoryShare": "0.4"], kind: .occupational)]
        plan.tax.residence.append(PlanResidence(from: 2027, system: "flat", options: ["surcharge": "0.01"]))

        let years = try Sample.fixedYears(plan, library, age: 65)
        let first = try #require(years.first)
        #expect(first.year == 2026 && first.citizenships == ["IT", "DE"] && first.isCitizen(of: "de"))
        #expect(first.birthDate == BirthDate(year: 1960, month: 3, day: 3))
        #expect(first.residence == [TaxPlan.Residence(from: 2020, system: "flat"),
                                    TaxPlan.Residence(from: 2027, system: "flat", options: ["surcharge": "0.01"])])
        let pension = try #require(first.pensions.first)
        #expect(pension.kind == .occupational && pension.sourceCountry == "DE" && pension.form == .annuity)
        #expect(pension.startYear == 2020 && pension.mandatoryShare == 0.4)
        #expect(years.last?.pensions.first?.startYear == 2020)

        let model = try Sample.model(plan, library)
        #expect(model.systems[0].taxPlan.citizenships == ["IT", "DE"])
        #expect(model.systems[0].taxPlan.pensions.first?.kind == .occupational)
        #expect(model.systems[0].taxPlan.pensions.first?.sourceCountry == "DE")
    }

    @Test func aSchemeSaysItsKindUnlessThePlanDoes() throws {
        let library = Sample.library(birth: "1966-01-01", on: "2025-12-31", [SampleAccount(id: "broker", balance: 0)])
        var plan = Sample.plan(retire: .age(60), endAge: 62, retired: "0", runs: 10)
        plan.pensions = [PlanPension(scheme: "flat.fund", claim: .age(60), options: ["startingBalance": "100000"])]
        let years = try Sample.fixedYears(plan, library, age: 60)
        #expect(years.first?.pensions.first?.kind == .occupational)
        #expect(years.first?.pensions.first?.startYear == 2026)
        plan.pensions[0].kind = .privateAnnuity
        #expect(try Sample.fixedYears(plan, library, age: 60).first?.pensions.first?.kind == .privateAnnuity)
    }
}
