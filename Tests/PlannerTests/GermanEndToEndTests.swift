import Foundation
import Model
@testable import Planner
import TaxGeneric
import TaxGermany
import TaxItaly
import TaxKit
import TaxSwitzerland
import Testing

/// The German system in the engine, with the registry the app and the CLI
/// use: Germany as the paying country of a pension taxed at source (G8), and
/// as the residence that exempts or credits what the paying country taxes.
/// Each amount is checked against the systems called directly with what the
/// planner passed them. Made-up people and amounts.
struct GermanEndToEndTests {
    static let registry = TaxRegistry([ItalyTaxSystem(), GenericTaxSystem(), GermanTaxSystem(), SwissTaxSystem()])
    let germany = GermanTaxSystem()
    let italy = ItalyTaxSystem()

    /// A DRV pension from 40 points, claimed at 67 (2028).
    let drv = PlanPension(scheme: "de.drv", name: "DRV", claim: .age(67), taxedIn: .source,
                          options: ["points": 40, "contributionYears": 40])
    /// An INPS pension from a montante of 300,000, claimed at 67 (2028).
    let inps = PlanPension(scheme: "it.inps", name: "INPS", claim: .age(67), taxedIn: .source,
                           options: ["montante": 300_000, "contributionYears": 25])
    /// A year with both pensions paid in full, the exempt amounts fixed.
    let year = 2031

    /// Born 1961, retired, with 500,000 in cash in an ordinary account.
    func library(wrapper: WrapperID, citizenships: [CountryCode]) -> Library {
        var library = Sample.library(birth: "1961-01-01", on: "2025-12-31",
                                     [SampleAccount(id: "bank", wrapper: wrapper, mix: [.cash: 1], balance: 500_000)])
        library.settings.person?.citizenships = citizenships
        return library
    }

    func plan(_ residence: [PlanResidence], _ pensions: [PlanPension]) -> PlanDocument {
        var plan = Sample.plan(retire: .age(60), endAge: 75, retired: "30000", equityReturn: "0", runs: 10)
        plan.tax.residence = residence
        plan.pensions = pensions
        return plan
    }

    static let italianResidence = [PlanResidence(from: 2020, system: "it")]
    static let germanResidence = [PlanResidence(from: 2020, system: "de",
                                                options: ["retirementHealthInsurance": "kvdr"])]

    func run(_ plan: PlanDocument, _ library: Library) async throws -> PlanResult {
        try await Planner.run(plan: plan, library: library, registry: Self.registry,
                              options: PlannerOptions(maxRetirementAge: 62, solveSustainableSpending: false))
    }

    /// What the planner prepared for a year.
    struct Prepared {
        /// The year the residence system saw.
        var year: FixedYear
        /// The tax state it was prepared with.
        var state: TaxState
        /// The year's taxes that don't depend on the markets: the residence
        /// system's and the paying countries'.
        var taxes: [AmountItem]
    }

    func prepared(_ plan: PlanDocument, _ library: Library, in year: Int) throws -> Prepared {
        let (model, issues) = PlanInterpreter.interpret(plan: plan, library: library, registry: Self.registry,
                                                        options: PlannerOptions())
        let interpreted = try #require(model, "\(issues.filter(\.isError))")
        let schedule = AgeSchedule(model: interpreted, age: 60, neededMasks: interpreted.frames.map { _ in [] },
                                   expectedMask: interpreted.expectedEvents)
        let index = try #require(schedule.years.firstIndex { $0.year == year })
        let scheduled = schedule.years[index]
        return Prepared(year: schedule.fixedYears[index], state: scheduled.taxState,
                        taxes: scheduled.variants[scheduled.expectedVariant].taxes)
    }

    /// The paying country's side, as the planner asks for it: only the
    /// pensions it taxes at source, without what they were charged.
    func nonResident(_ system: any TaxSystem, _ fixed: FixedYear, state: TaxState) throws -> TaxAssessment {
        var year = fixed
        year.systemOptions = [:]
        year.overlays = []
        year.work = []
        year.wrapperContributions = []
        year.windfalls = []
        year.pensions = fixed.pensions.filter { $0.taxedIn == .source && $0.sourceCountry == system.country }
            .map { var pension = $0; pension.sourceTax = nil; return pension }
        let parameters = try system.parameters.parameters(for: fixed.year)
        return try #require(system.prepareNonResident(year, state: state, parameters: parameters)).fixedAssessment
    }

    func residence(_ system: any TaxSystem, _ fixed: FixedYear, state: TaxState) throws -> TaxAssessment {
        system.prepare(fixed, state: state, parameters: try system.parameters.parameters(for: fixed.year))
            .fixedAssessment
    }

    func taxes(_ result: PlanResult, in year: Int) -> [AmountItem] {
        result.expectedPath.years.first { $0.year == year }?.taxes ?? []
    }

    func amount(_ items: [AmountItem], _ id: String) -> Double {
        items.filter { $0.id == id }.reduce(0) { $0 + $1.amount }
    }

    @Test func aGermanLivingInItalyPaysGermanTaxOnTheDRVPension() async throws {
        let library = library(wrapper: "it.ordinary", citizenships: ["DE"])
        let plan = plan(Self.italianResidence, [drv])
        let result = try await run(plan, library)
        let prepared = try prepared(plan, library, in: year)

        // Germany taxes it (Art. 19(4)), as a resident (§1 Abs. 3): it's given
        // only this pension.
        let german = try nonResident(germany, prepared.year, state: prepared.state)
        let pension = try #require(prepared.year.pensions.first)
        #expect(pension.sourceCountry == "DE" && pension.taxedIn == .source && pension.kind == .statutory)
        #expect(german.lines.allSatisfy { $0.subject == pension.id } && german.totalTax > 0)
        #expect(close(pension.sourceTax, german.totalTax))
        #expect(close(amount(prepared.taxes, GermanLine.nonResidentIncomeTax), german.totalTax))
        let line = try #require(taxes(result, in: year).first { $0.id == GermanLine.nonResidentIncomeTax })
        #expect(line.label == "Germany: Income tax (non-resident)" && close(line.amount, german.totalTax))
        #expect(result.issues.contains { $0.code == "de.nonResident.taxedAsResident" })
        #expect(!result.issues.contains { $0.code == "planner.taxedAtSource" || $0.code.hasPrefix("it.treaty") })

        // The exempt amount was fixed in 2029, the year after the claim, from
        // that year's pension (the 2028 cohort's 85% taxable), in nominal euros,
        // and carried in the state since.
        let exempt = try #require(prepared.state["de.pension.pension-0.exemptAmount"])
        let fixing = try self.prepared(plan, library, in: 2029).year
        let first = try #require(fixing.pensions.first)
        #expect(first.startYear == 2028 && close(exempt, 0.15 * first.amount * fixing.inflationFactor))

        // Italy exempts it: no IRPEF on it, nothing to credit; its fixed taxes
        // are the year's apart from Germany's.
        let italian = try residence(italy, prepared.year, state: prepared.state)
        #expect(italian.totalTax == 0 && !italian.lines.contains { $0.subject == pension.id })
        #expect(prepared.taxes.allSatisfy { $0.id.hasPrefix("de.nonResident.") })
    }

    @Test func anItalianLivingInGermanyPaysItalianTaxOnTheINPSPension() async throws {
        // A DRV pension Germany taxes as the residence, and an INPS pension Italy
        // taxes (Art. 19(4)): Germany counts it only for the rate.
        let library = library(wrapper: "de.ordinary", citizenships: ["IT"])
        var residencePension = drv
        residencePension.taxedIn = nil
        let plan = plan(Self.germanResidence, [residencePension, inps])
        let result = try await run(plan, library)
        let prepared = try prepared(plan, library, in: year)

        let pension = try #require(prepared.year.pensions.first { $0.scheme == "it.inps" })
        #expect(pension.sourceCountry == "IT" && pension.taxedIn == .source)
        let italian = try nonResident(italy, prepared.year, state: prepared.state)
        #expect(italian.totalTax > 0 && close(pension.sourceTax, italian.totalTax))
        for line in italian.lines {
            let reported = try #require(taxes(result, in: year).first { $0.id == line.id })
            #expect(reported.label == "Italy: \(line.label)" && close(reported.amount, line.amount))
        }

        // Germany: the progression clause, no credit.
        let german = try residence(germany, prepared.year, state: prepared.state)
        #expect(!german.lines.contains { $0.id == GermanLine.foreignTaxCredit })
        #expect(close(amount(prepared.taxes, GermanLine.incomeTax), german.sum(GermanLine.incomeTax)))
        var withoutINPS = prepared.year
        withoutINPS.pensions.removeAll { $0.id == pension.id }
        let alone = try residence(germany, withoutINPS, state: prepared.state)
        #expect(german.sum(GermanLine.incomeTax) > alone.sum(GermanLine.incomeTax))
        // The INPS pension doesn't change the taxable income (its contributions
        // aren't deducted either), only the rate on it.
        #expect(close(german.lines.first { $0.id == GermanLine.incomeTax }?.base,
                      try #require(alone.lines.first { $0.id == GermanLine.incomeTax }?.base)))
        #expect(!result.issues.contains { $0.code.hasPrefix("de.treaty") || $0.code == "it.nonResident.treaty" })
    }

    @Test func withoutCitizenshipsNothingIsTaxedTwiceOrLeftUntaxed() async throws {
        // Living in Italy: Germany taxes the DRV pension as the plan says, and
        // Italy taxes it too, as its convention is, crediting Germany's tax.
        let inItaly = library(wrapper: "it.ordinary", citizenships: [])
        let italyPlan = plan(Self.italianResidence, [drv])
        let result = try await run(italyPlan, inItaly)
        let prepared = try prepared(italyPlan, inItaly, in: year)
        let german = try nonResident(germany, prepared.year, state: prepared.state)
        let italian = try residence(italy, prepared.year, state: prepared.state)
        let credit = italian.sum("it.foreignTaxCredit")
        let irpef = italian.sum("it.irpef")
        #expect(german.totalTax > 0 && irpef > 0)
        // Not twice: Italy's IRPEF on it is reduced by Germany's tax, up to all of it.
        #expect(close(-credit, min(german.totalTax, irpef)))
        let total = prepared.taxes.reduce(0) { $0 + $1.amount }
        #expect(close(total, german.totalTax + italian.totalTax))
        for code in ["de.treaty.citizenshipUnknown", "it.treaty.citizenship", "it.treaty.taxedIn"] {
            #expect(result.issues.contains { $0.code == code }, "\(code)")
        }

        // Living in Germany with an INPS pension: Italy taxes it as the plan says
        // and Germany exempts it (progression only), so it's taxed once.
        let inGermany = library(wrapper: "de.ordinary", citizenships: [])
        let germanPlan = plan(Self.germanResidence, [inps])
        let atHome = try await run(germanPlan, inGermany)
        let home = try self.prepared(germanPlan, inGermany, in: year)
        let italianAbroad = try nonResident(italy, home.year, state: home.state)
        let germanAtHome = try residence(germany, home.year, state: home.state)
        #expect(italianAbroad.totalTax > 0 && germanAtHome.totalTax == 0)
        #expect(close(home.taxes.reduce(0) { $0 + $1.amount }, italianAbroad.totalTax))
        for code in ["de.treaty.citizenshipUnknown", "it.nonResident.treaty"] {
            #expect(atHome.issues.contains { $0.code == code }, "\(code)")
        }
    }

    @Test func aPlanInFrancsWithGermanResidenceConverts() async throws {
        // The same plan in euros and in francs (1 EUR = 0.95 CHF): the DRV
        // pension, Germany's taxes and its contributions all scale by 0.95.
        var library = library(wrapper: "de.ordinary", citizenships: ["DE"])
        library.upsert(FXRecord(base: .eur, quote: .chf, date: "2025-12-31", rate: d("0.95")))
        var residencePension = drv
        residencePension.taxedIn = nil
        let inEuros = plan(Self.germanResidence, [residencePension])
        var inFrancs = inEuros
        inFrancs.currency = .chf
        inFrancs.spending = PlanSpending(working: 0, retired: d("28500"))
        let francs = try await run(inFrancs, library)
        #expect(francs.currency == .chf && !francs.issues.contains { $0.code.contains("xchange") })

        let euroYear = try prepared(inEuros, library, in: year)
        let francYear = try prepared(inFrancs, library, in: year)
        #expect(close(francYear.year.currencyRate, 1 / 0.95) && euroYear.year.currencyRate == 1)
        let pension = try #require(euroYear.year.pensions.first?.amount)
        #expect(close(francYear.year.pensions.first?.amount, pension * 0.95))
        #expect(!euroYear.taxes.isEmpty && amount(euroYear.taxes, GermanLine.incomeTax) > 0)
        for item in euroYear.taxes {
            #expect(close(amount(francYear.taxes, item.id), item.amount * 0.95), "\(item.id)")
        }
        // Health and care contributions (KVdR) too.
        let charged = try residence(germany, francYear.year, state: francYear.state).contributions
        let chargedInEuros = try residence(germany, euroYear.year, state: euroYear.state).contributions
        for id in [GermanLine.health, GermanLine.care] {
            let total = chargedInEuros.filter { $0.id == id }.reduce(0) { $0 + $1.amount }
            #expect(total > 0 && close(charged.filter { $0.id == id }.reduce(0) { $0 + $1.amount }, total * 0.95),
                    "\(id)")
        }
    }
}

private extension TaxAssessment {
    /// The sum of the tax lines with `id`.
    func sum(_ id: String) -> Double {
        lines.filter { $0.id == id }.reduce(0) { $0 + $1.amount }
    }
}
