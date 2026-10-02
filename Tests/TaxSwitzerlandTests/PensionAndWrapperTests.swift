import Foundation
@testable import TaxSwitzerland
import TaxKit
import Testing

struct RegistryTests {
    @Test func registeredWithOtherSystems() {
        let registry = TaxRegistry([SwissTaxSystem()])
        #expect(registry.system("ch")?.currency == "CHF")
        #expect(registry.pensionScheme("ch.ahv")?.name == "AHV (state pension)")
        #expect(registry.pensionScheme("ch.bvg")?.seedWrapper == "ch.bvg")
        #expect(registry.pensionScheme("fixed") != nil)
        #expect(registry.regime("ch.lumpSum")?.regime.scope == .overlay)
        #expect(registry.wrapper("ch.pillar3a")?.category == .taxDeferred)
        let system = SwissTaxSystem()
        #expect(system.defaultRegime(for: .employee) == SwissRegime.employee)
        #expect(system.defaultRegime(for: .selfEmployed) == SwissRegime.selfEmployed)
        #expect(system.defaultRegime(for: .net) == nil)
        #expect(system.wrappers.map(\.id) == ["ch.ordinary", "ch.pillar3a", "ch.vestedBenefits", "ch.bvg"])
        let canton = system.options.first { $0.key == "canton" }
        if case .choice(let choices) = canton?.kind {
            #expect(choices.map(\.value) == ["TI", "ZH"])
        } else {
            Issue.record("canton isn't a choice")
        }
    }
}

struct AHVTests {
    let scheme = AHVPensionScheme()
    let store = Swiss.system.parameters

    @Test func theRecordDriftsAgainstTheLimits() throws {
        var record = scheme.startingRecord(options: ["contributionYears": 10, "averageIncome": "50000",
                                                     "foreignContributionYears": 3],
                                           year: 2026, parameters: store, currencyRate: 0.9)
        #expect(record.montante == 450_000 && record.contributionMonths == 120 && record.foreignContributionMonths == 36)
        let options: OptionValues = ["realWageGrowth": 0.02, "inflation": 0.01]
        let credits = [Accrual(target: .pensionScheme("ch.ahv"), amount: 100_000, contributionMonths: 12, source: "job"),
                       Accrual(target: .pensionScheme("ch.ahv"), amount: 10_000, contributionMonths: 6),
                       Accrual(target: .pensionScheme("ch.bvg"), amount: 5_000, source: "job")]
        scheme.accrue(credits, in: 2026, to: &record, options: options, parameters: try Swiss.parameters(),
                      currencyRate: 0.9)
        // The first year doesn't drift; its credits count in full; at most 12 months a year.
        #expect(abs(record.montante - (450_000 + 99_000)) < 1e-6 && record.contributionMonths == 132)
        scheme.accrue(credits, in: 2027, to: &record, options: options, parameters: try Swiss.parameters(),
                      currencyRate: 0.9)
        // Then the sum loses inflation and half of real wage growth, and new credits are divided by the limits' growth.
        #expect(abs(record.montante - (549_000 / (1.01 * 1.01) + 99_000 / 1.01)) < 1e-6)
    }

    @Test func claimOptionsNeedAYearOfContributions() {
        let context = ClaimContext(year: 2026, birthDate: BirthDate(year: 1962, month: 3, day: 1),
                                   options: ["realWageGrowth": 0, "inflation": 0])
        let none = PensionRecord(scheme: "ch.ahv", montante: 0, contributionMonths: 0, foreignContributionMonths: 120)
        #expect(scheme.claimOptions(for: none, context: context, parameters: store).isEmpty)
        let short = PensionRecord(scheme: "ch.ahv", montante: 3_000, contributionMonths: 6)
        #expect(scheme.claimOptions(for: short, context: context, parameters: store).isEmpty)
        // Six months in Switzerland and six abroad make the year.
        let enough = PensionRecord(scheme: "ch.ahv", montante: 0, contributionMonths: 6, foreignContributionMonths: 6)
        let options = scheme.claimOptions(for: enough, context: context, parameters: store)
        #expect(options.map(\.age) == [64, 65, 66, 67, 68, 69, 70])
        #expect(options.map(\.route) == ["ch.ahv.early", "ch.ahv.reference"] + Array(repeating: "ch.ahv.deferred", count: 5))
        // The minimum pension × 0.5/44, at the reference age: 1,260 × 13 / 88.
        #expect(abs((options[1].fullYearAmount ?? 0) - 1_260 * 13 * 0.5 / 44) < 1e-6)
        #expect(scheme.oldAgePensionAge(in: 2030, options: [:], parameters: store) == 65)
        #expect(scheme.oldAgePensionAgeInMonths(in: 2030, options: [:], parameters: store) == 780)
        #expect(scheme.pensionKind(options: [:]) == .statutory && scheme.seedWrapper == nil)
    }

    @Test func workAndYearsWithoutWorkAreCredited() throws {
        let employee = try Swiss.prepare(Swiss.workYear(.employee, gross: 90_000, fraction: 0.5)).fixedAssessment
        // Half a year of work, the other half without work: 12 months in all.
        #expect(employee.accruals.filter { $0.target == .pensionScheme("ch.ahv") }.map(\.contributionMonths) == [6, 6])
        #expect(abs(employee.accrued("ch.ahv") - (90_000 + 530 * 0.81 / 0.087 / 2)) < 1e-6)
        let retired = try Swiss.prepare(Swiss.pensionYear(20_000, age: 66)).fixedAssessment
        #expect(retired.accruals.isEmpty)
        let young = try Swiss.prepare(FixedYear(year: 2026, age: 20, systemOptions: Swiss.place("Zurich"))).fixedAssessment
        #expect(young.accruals.isEmpty)
        // Accruals are in the plan's currency.
        var abroad = Swiss.workYear(.employee, gross: 100_000)
        abroad.currencyRate = 0.9
        #expect(abs(try Swiss.prepare(abroad).fixedAssessment.accrued("ch.ahv") - 100_000) < 1e-6)
    }
}

struct BVGTests {
    let scheme = BVGPensionScheme()
    let store = Swiss.system.parameters

    @Test func recordAndCredits() throws {
        #expect(scheme.seedWrapper == "ch.bvg" && scheme.pensionKind(options: [:]) == .occupational)
        #expect(scheme.options.first { $0.key == "conversionRate" }?.defaultValue == .number(0.054))
        var record = scheme.startingRecord(options: ["startingBalance": "200000"], year: 2026, parameters: store,
                                           currencyRate: 0.9)
        #expect(record.montante == 180_000)
        scheme.accrue([Accrual(target: .pensionScheme("ch.bvg"), amount: 10_000, source: "job"),
                       Accrual(target: .pensionScheme("ch.ahv"), amount: 90_000)],
                      in: 2026, to: &record, options: ["realInterest": 0.01], parameters: try Swiss.parameters(),
                      currencyRate: 0.9)
        #expect(abs(record.montante - (180_000 * 1.01 + 9_000)) < 1e-9)
    }

    @Test func ageCreditsFromWork() throws {
        let year = Swiss.workYear(.employee, gross: 120_000,
                                  options: ["bvgCoordinationDeduction": "0", "bvgInsuredSalaryCap": "150000",
                                            "bvgEmployerShare": 0.6], age: 50)
        let assessment = try Swiss.prepare(year).fixedAssessment
        // No coordination deduction: 15% × 120,000, 40% of it from the employee.
        #expect(abs(assessment.accrued("ch.bvg") - 18_000) < 1e-9)
        #expect(abs(assessment.contribution(SwissLine.bvgEmployee) - 7_200) < 1e-9)
        let below = try Swiss.prepare(Swiss.workYear(.employee, gross: 20_000)).fixedAssessment
        #expect(below.accrued("ch.bvg") == 0 && below.contribution(SwissLine.bvgEmployee) == 0)
        let none = try Swiss.prepare(Swiss.workYear(.employee, gross: 80_000, options: ["bvgPlan": "none"])).fixedAssessment
        #expect(none.accrued("ch.bvg") == 0)
        // Part of a year: the thresholds apply to the yearly salary.
        let half = try Swiss.prepare(Swiss.workYear(.employee, gross: 40_000, fraction: 0.5)).fixedAssessment
        #expect(abs(half.accrued("ch.bvg") - (80_000 - 26_460) * 0.10 * 0.5) < 1e-9)
        // Self-employed voluntary savings.
        let own = try Swiss.prepare(Swiss.workYear(.selfEmployed, gross: 100_000, options: ["bvgSavingsRate": 0.1]))
            .fixedAssessment
        #expect(own.accrued("ch.bvg") == 10_000 && own.contribution(SwissLine.bvgSelfEmployed) == 10_000)
    }

    @Test func workStoppingBeforeTheEarliestAgeMovesTheAssets() {
        let record = PensionRecord(scheme: "ch.bvg", montante: 300_000)
        let birth = BirthDate(year: 1976, month: 5, day: 1)
        let stopped = ClaimContext(year: 2028, birthDate: birth, options: ["lumpSumShare": "0.5"], currencyRate: 0.95,
                                   yearsSinceWorkStopped: 1)
        let options = scheme.claimOptions(for: record, context: stopped, parameters: store)
        // Without a route from the plan, the transfer is the only option.
        #expect(options.map(\.route) == ["ch.bvg.vestedBenefits"])
        #expect(options.allSatisfy { $0.age == 52 && $0.lumpSumWrapper == "ch.vestedBenefits" && $0.annualAmount == 0 })
        #expect(abs((options.first?.lumpSum ?? 0) - 300_000 / 0.95) < 1e-6)
        // With one, it's also listed under that route, so the plan's choice finds it.
        for route in ["ch.bvg.annuity", "ch.bvg.capital", "ch.bvg.partialCapital"] {
            var chosen = stopped
            chosen.claimRoute = route
            let listed = scheme.claimOptions(for: record, context: chosen, parameters: store)
            #expect(listed.map(\.route) == ["ch.bvg.vestedBenefits", route])
            #expect(listed.allSatisfy { $0.lumpSumWrapper == "ch.vestedBenefits" && $0.label == "Transfer to vested benefits" })
        }
        // A route the scheme doesn't have, or the transfer's own, adds nothing.
        for route in ["ch.bvg.vestedBenefits", "ch.ahv.reference"] {
            var chosen = stopped
            chosen.claimRoute = route
            #expect(scheme.claimOptions(for: record, context: chosen, parameters: store).map(\.route)
                    == ["ch.bvg.vestedBenefits"])
        }
        // Still working: the retirement options from 58, the partial route first.
        let working = ClaimContext(year: 2028, birthDate: birth, options: ["lumpSumShare": "0.5"])
        let later = scheme.claimOptions(for: record, context: working, parameters: store)
        #expect(later.first?.age == 58 && later.first?.route == "ch.bvg.partialCapital")
        #expect(later.last?.age == 70)
        // Stopping at 60 is a retirement, not a transfer.
        let retired = ClaimContext(year: 2036, birthDate: birth, yearsSinceWorkStopped: 0)
        #expect(scheme.claimOptions(for: record, context: retired, parameters: store).first?.route == "ch.bvg.annuity")
    }

    @Test func aLumpSumWithinThreeYearsOfABuyInFromVestedBenefits() throws {
        let year = FixedYear(year: 2026, age: 62, systemOptions: Swiss.place("Zurich"))
        let prepared = try Swiss.prepare(year, state: ["ch.bvg.buyIn.2025": 40_000])
        let payout = VariableYear(payouts: [.init(wrapper: "ch.vestedBenefits", amount: 100_000, form: .lumpSum)])
        let assessed = prepared.assess(payout)
        #expect(assessed.issues.map(\.code) == ["ch.bvg.buyInLock"])
        #expect(assessed.total(SwissLine.federal) > 0)
        // A 3a payout doesn't reverse it.
        let pillar = prepared.assess(VariableYear(payouts: [.init(wrapper: "ch.pillar3a", amount: 100_000,
                                                                  form: .lumpSum)]))
        #expect(pillar.issues.isEmpty && pillar.total(SwissLine.federal) == 0)
    }
}

struct WrapperTests {
    private func context(age: Int, stopped: Int?, year: Int = 2040) -> WrapperAccessContext {
        WrapperAccessContext(year: year, age: age, yearsSinceWorkStopped: stopped, oldAgePensionAge: 67,
                             contributionYears: 30, membershipYears: 10)
    }

    @Test func pillar3aAndVestedBenefits() throws {
        let system = Swiss.system
        let pillar = try #require(system.wrapper("ch.pillar3a"))
        let vested = try #require(system.wrapper("ch.vestedBenefits"))
        for rule in [pillar, vested] {
            // From 60, whatever another country's pension age; due at 65 once work stops, at 70 at the latest.
            #expect(!rule.access(in: context(age: 59, stopped: 5)).isAccessible)
            #expect(rule.access(in: context(age: 60, stopped: nil)).isAccessible)
            #expect(!rule.mustPayOut(in: context(age: 64, stopped: 3)))
            #expect(rule.mustPayOut(in: context(age: 65, stopped: 0)))
            #expect(!rule.mustPayOut(in: context(age: 66, stopped: nil)))
            #expect(rule.mustPayOut(in: context(age: 70, stopped: nil)))
        }
        #expect(pillar.preferredPayoutYears == 5 && vested.preferredPayoutYears == 2)
        if case .locked(let reason) = pillar.access(in: context(age: 50, stopped: 1)) {
            #expect(reason.hasPrefix("A pillar 3a account can be drawn from 60"))
        }
        // The plan chooses the years in its residence options; the rules hold the defaults.
        let place = Swiss.place("Zurich")
        #expect(system.preferredPayoutYears(for: "ch.pillar3a", options: place) == 5)
        #expect(system.preferredPayoutYears(for: "ch.vestedBenefits", options: [:]) == 2)
        #expect(system.preferredPayoutYears(for: "ch.pillar3a", options: Swiss.place("Zurich", ["pillar3aPayoutYears": 3]))
                == 3)
        #expect(system.preferredPayoutYears(for: "ch.vestedBenefits", options: ["vestedBenefitsPayoutYears": 1]) == 1)
        // 0: drawn only as needed until they must pay out.
        #expect(system.preferredPayoutYears(for: "ch.pillar3a", options: ["pillar3aPayoutYears": 0]) == nil)
        #expect(system.preferredPayoutYears(for: "ch.vestedBenefits", options: ["vestedBenefitsPayoutYears": 0]) == nil)
        #expect(system.preferredPayoutYears(for: "ch.bvg", options: ["pillar3aPayoutYears": 3]) == nil)
        #expect(system.preferredPayoutYears(for: "ch.ordinary", options: [:]) == nil)
        // Neither looks like severance pay to the planner (locked while working, open once work stops).
        for rule in system.wrappers {
            let working = rule.access(in: WrapperAccessContext(year: 2026, age: 0, yearsSinceWorkStopped: nil,
                                                               oldAgePensionAge: nil, contributionYears: 0,
                                                               membershipYears: 0))
            let stopped = rule.access(in: WrapperAccessContext(year: 2026, age: 0, yearsSinceWorkStopped: 0,
                                                               oldAgePensionAge: nil, contributionYears: 0,
                                                               membershipYears: 0))
            #expect(working.isAccessible || !stopped.isAccessible, "\(rule.id)")
        }
        let bvg = try #require(system.wrapper("ch.bvg"))
        #expect(!bvg.access(in: context(age: 58, stopped: nil)).isAccessible)
        #expect(bvg.access(in: context(age: 58, stopped: 0)).isAccessible)
    }

    @Test func otherWrappers() throws {
        let prepared = try Swiss.prepare(Swiss.pensionYear(30_000))
        let base = prepared.fixedAssessment.totalTax
        let year = VariableYear(
            sales: [.init(wrapper: "it.ordinary", category: .stock, proceeds: 10_000, costBasis: 1_000)],
            payouts: [.init(wrapper: "taxFree", amount: 5_000, form: .lumpSum),
                      .init(wrapper: "it.tfr", amount: 20_000, form: .lumpSum),
                      .init(wrapper: "xx.plan", amount: 10_000, form: .lumpSum)],
            capitalIncome: [.init(wrapper: "de.depot", category: .equityFund, kind: .dividend, amount: 1_000),
                            .init(wrapper: "it.pensionFund", category: .fund, kind: .reportedIncome, amount: 1_000)],
            balances: [.init(wrapper: "it.ordinary", category: .stock, value: 500_000),
                       .init(wrapper: "it.pensionFund", category: .fund, value: 500_000),
                       .init(wrapper: "xx.plan", category: .fund, value: 100_000)])
        let assessed = prepared.assess(year)
        #expect(Set(assessed.issues.map(\.code)) == ["ch.unknownWrapper", "ch.foreignWrapper.taxedAtSource"])
        // Wealth: the Italian account and the unknown one (600,000), not the pension fund.
        #expect(abs((assessed.lines.first { $0.id == SwissLine.wealthCantonal }?.base ?? 0) - 600_000) < 1e-9)
        // The unknown wrapper's payout is a capital benefit; the TFR and the tax-free payout aren't taxed.
        #expect(assessed.lines.filter { $0.id.hasPrefix("ch.capitalBenefits") }.allSatisfy { $0.subject == "xx.plan" })
        // The German dividend is income; the pension fund's isn't.
        let income = prepared.assess(VariableYear(capitalIncome: [
            .init(wrapper: "de.depot", category: .equityFund, kind: .dividend, amount: 1_000)]))
        #expect(income.totalTax > base)
        #expect(prepared.assess(VariableYear(capitalIncome: [
            .init(wrapper: "it.pensionFund", category: .fund, kind: .reportedIncome, amount: 1_000)])).totalTax == base)
    }
}

struct NonEmployedTests {
    private func contribution(_ year: FixedYear, wealth: Double, fraction: Double = 1) throws -> Double {
        let balances = [VariableYear.Balance(wrapper: "ch.ordinary", category: .equityFund, value: wealth)]
        return try Swiss.prepare(year).assess(VariableYear(balances: balances, fractionOfYear: fraction))
            .contribution(SwissLine.ahvNonEmployed)
    }

    @Test func dueWithoutWorkUntilTheReferenceAge() throws {
        let idle = FixedYear(year: 2026, age: 50, systemOptions: Swiss.place("Lugano"))
        #expect(abs(try contribution(idle, wealth: 1_000_000) - 2_014 * 1.05) < 1e-9)
        #expect(abs(try contribution(idle, wealth: 1_000_000, fraction: 0.25) - 2_014 * 1.05 * 0.25) < 1e-9)
        var cheaper = idle
        cheaper.systemOptions = Swiss.place("Lugano", ["nonEmployedAdminRate": 0.02])
        #expect(abs(try contribution(cheaper, wealth: 1_000_000) - 2_014 * 1.02) < 1e-9)
        // The home counts, less the mortgage; pensions count 20 times.
        var owner = idle
        owner.systemOptions = Swiss.place("Lugano", ["homeTaxValue": "700000", "mortgage": "400000"])
        owner.pensions = [.init(id: "bridge", scheme: "fixed", amount: 10_000)]
        #expect(abs(try contribution(owner, wealth: 400_000) - non(400_000 + 300_000 + 200_000) * 1.05) < 1e-9)
        // In the year of the reference age, until the birthday month; not after it, nor before 21.
        var sixtyFive = idle
        sixtyFive.age = 65
        sixtyFive.birthDate = BirthDate(year: 1961, month: 4, day: 10)
        #expect(abs(try contribution(sixtyFive, wealth: 1_000_000) - 2_014 * 1.05 * 4 / 12) < 1e-9)
        sixtyFive.birthDate = nil
        #expect(try contribution(sixtyFive, wealth: 1_000_000) == 0)
        var young = idle
        young.age = 20
        #expect(try contribution(young, wealth: 1_000_000) == 0)
    }

    private func non(_ base: Double) -> Double {
        base < 350_000 ? 530 : base < 1_750_000 ? 636 + 106 * ((base - 350_000) / 50_000).rounded(.down)
            : min(26_500, 3_604 + 159 * ((base - 1_750_000) / 50_000).rounded(.down))
    }

    @Test func workPaysEnoughOrWorksFullTime() throws {
        // Half a year's work on 80,000: 10.6% × 80,000 = 8,480, more than half of 13,939 (5M): nothing more.
        let part = Swiss.workYear(.employee, gross: 80_000, fraction: 0.5)
        #expect(try contribution(part, wealth: 5_000_000) == 0)
        // On 20,000 it's 2,120, less than half: the rest is due.
        let small = Swiss.workYear(.employee, gross: 20_000, fraction: 0.5)
        #expect(abs(try contribution(small, wealth: 5_000_000) - (13_939 - 2_120) * 1.05) < 1e-6)
        // Working most of the year is full-time work, whatever the wealth.
        let fullTime = Swiss.workYear(.employee, gross: 20_000, fraction: 0.8)
        #expect(try contribution(fullTime, wealth: 9_000_000) == 0)
    }
}

struct MarketTests {
    @Test func ticinosWealthTaxBrake() throws {
        let bundled = try #require(Swiss.system.parameters as? JSONParameterStore)
        let store = bundled.applying(overrides: ["ch.cantons.TI.wealth.brake.maximumShareOfIncome": "0.05"])
        let system = SwissTaxSystem(parameters: store)
        let prepared = try Swiss.prepare(Swiss.pensionYear(30_000, commune: "Lugano"), system: system)
        let balances = [VariableYear.Balance(wrapper: "ch.ordinary", category: .equityFund, value: 2_000_000)]
        let assessed = prepared.assess(VariableYear(balances: balances))
        let brake = assessed.total(SwissLine.wealthBrake)
        #expect(brake < 0)
        // Cantonal and communal tax on income and wealth together are cut to 5% of the income counted
        // (taxable income + 1% of wealth, the minimum yield).
        let taxes = try #require(prepared.context?.incomeTaxes)
        let counted = taxes.cantonalTaxable + 20_000
        let total = assessed.total(SwissLine.cantonal) + assessed.total(SwissLine.communal)
            + assessed.total(SwissLine.wealthCantonal) + assessed.total(SwissLine.wealthCommunal) + brake
        #expect(abs(total - 0.05 * counted) < 1e-6)
        // With the law's 60% it doesn't bind.
        let normal = try Swiss.prepare(Swiss.pensionYear(30_000, commune: "Lugano")).assess(VariableYear(balances: balances))
        #expect(normal.total(SwissLine.wealthBrake) == 0)
    }

    @Test func largeGainsGetAWarning() throws {
        let prepared = try Swiss.prepare(Swiss.pensionYear(20_000, commune: "Lugano"))
        let sale = VariableYear(sales: [.init(wrapper: "ch.ordinary", category: .stock, proceeds: 100_000, costBasis: 40_000)])
        let assessed = prepared.assess(sale)
        #expect(assessed.issues.map(\.code) == ["ch.securitiesTrader"])
        #expect(assessed.totalTax == prepared.fixedAssessment.totalTax)
        let small = VariableYear(sales: [.init(wrapper: "ch.ordinary", category: .stock, proceeds: 10_000, costBasis: 9_000)])
        #expect(prepared.assess(small).issues.isEmpty)
    }

    @Test func pensionsTaxedAbroadCountForTheRate() throws {
        // An Italian citizen's Italian pension entered as taxed in Italy: a
        // public-service pension, which the treaty leaves to Italy (art. 19).
        var year = Swiss.pensionYear(40_000, commune: "Lugano")
        year.citizenships = ["IT"]
        let alone = try Swiss.prepare(year).fixedAssessment
        year.pensions.append(.init(id: "italy", scheme: "fixed", amount: 40_000, taxedIn: .source, sourceCountry: "IT"))
        let withExempt = try Swiss.prepare(year).fixedAssessment
        #expect(withExempt.total(SwissLine.cantonal) > alone.total(SwissLine.cantonal))
        // The rate is that of the whole income; the tax only on the Swiss part.
        let taxes = try #require(try Swiss.prepare(year).context?.incomeTaxes)
        let schedule = try #require(try Swiss.prepare(year).context?.tariffs.schedule)
        let rateBase = taxes.cantonalTaxable + 40_000
        #expect(abs(taxes.simple - schedule.tax(on: rateBase) * taxes.cantonalTaxable / rateBase) < 1e-9)
    }
}
