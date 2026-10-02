@testable import TaxSwitzerland
import TaxKit
import Testing

/// Plan validation: the canton and commune, the tariff, the permit, the
/// overlays' conditions, treaty notes, and the checks that need each
/// year's amounts.
struct ValidationTests {
    let system = Swiss.system

    private func codes(_ plan: TaxPlan) -> [String] {
        system.validate(plan, parameters: system.parameters).map(\.code).sorted()
    }

    /// A Zurich employee who retires to Lugano, as the planner would pass it.
    private var examplePlan: TaxPlan {
        TaxPlan(
            residence: [.init(from: 2026, system: "ch", options: Swiss.place("Zurich")),
                        .init(from: 2040, system: "ch", options: Swiss.place("Lugano"))],
            work: [.init(id: "work-0", kind: .employee, regime: SwissRegime.employee,
                         options: ["bvgPlan": "minimum", "bvgCreditRate45": 0.16], fromYear: 2026, untilYear: 2039)],
            pensions: [.init(id: "pension-0", scheme: "ch.ahv", options: ["contributionYears": 20, "averageIncome": "90000"]),
                       .init(id: "pension-1", scheme: "ch.bvg", options: ["lumpSumShare": "0.5"]),
                       .init(id: "pension-2", scheme: "fixed")],
            birthYear: 1980, citizenships: ["CH"])
    }

    @Test func theExamplePlanIsValid() {
        #expect(codes(examplePlan).isEmpty)
    }

    @Test func unsupportedCantonsAndCommunes() throws {
        var plan = examplePlan
        plan.residence = [.init(from: 2026, system: "ch", options: ["canton": "GE"])]
        let issues = system.validate(plan, parameters: system.parameters)
        #expect(issues.map(\.code) == ["ch.canton.unsupported"])
        #expect(issues[0].message == "The canton GE isn't supported: the Swiss system covers Ticino (TI) and Zurich (ZH).")
        #expect(issues[0].severity == .error && issues[0].option == "canton")

        plan.residence = [.init(from: 2026, system: "ch", options: ["canton": "ZH", "commune": "Lugano"])]
        #expect(codes(plan) == ["ch.commune.unknown"])
        plan.residence = [.init(from: 2026, system: "ch", options: ["canton": "ZH", "commune": "custom"])]
        #expect(codes(plan) == ["ch.commune.multiplierMissing"])
        plan.residence = [.init(from: 2026, system: "ch",
                                options: ["canton": "ZH", "commune": "custom", "communeMultiplier": 1.05])]
        #expect(codes(plan).isEmpty)
        plan.residence = [.init(from: 2026, system: "ch", options: ["canton": "TI"])]
        #expect(codes(plan).isEmpty)
        plan.residence = [.init(from: 2026, system: "ch", options: [:])]
        #expect(codes(plan) == ["ch.options.missing"])

        // In prepare, an unknown canton fails the year with the same message.
        var year = Swiss.workYear(.employee, gross: 80_000)
        year.systemOptions = ["canton": "VD"]
        let failed = try Swiss.prepare(year).fixedAssessment
        #expect(failed.issues.map(\.code) == ["ch.canton.unsupported"] && failed.lines.isEmpty)
    }

    @Test func payoutYearsAreCheckedLikeOtherOptions() {
        var plan = examplePlan
        plan.residence[0].options = Swiss.place("Zurich", ["pillar3aPayoutYears": 3, "vestedBenefitsPayoutYears": 1])
        #expect(codes(plan).isEmpty)
        // At most one year per vested-benefits account (two), and whole years.
        plan.residence[0].options = Swiss.place("Zurich", ["vestedBenefitsPayoutYears": 3])
        #expect(codes(plan) == ["ch.options.outOfRange"])
        plan.residence[0].options = Swiss.place("Zurich", ["pillar3aPayoutYears": 2.5])
        #expect(codes(plan) == ["ch.options.wrongType"])
        let field = system.options.first { $0.key == "pillar3aPayoutYears" }
        #expect(field?.defaultValue == .number(5) && field?.kind == .int)
        #expect(system.options.first { $0.key == "vestedBenefitsPayoutYears" }?.defaultValue == .number(2))
    }

    @Test func theMarriedTariffIsRefused() {
        var plan = examplePlan
        plan.residence[0].options["tariff"] = "married"
        let issues = system.validate(plan, parameters: system.parameters)
        #expect(issues.map(\.code) == ["ch.tariff.married"] && issues[0].severity == .error)
    }

    @Test func permits() {
        var plan = examplePlan
        plan.citizenships = ["IT"]
        #expect(codes(plan) == ["ch.permit.missing", "ch.permit.missing"])
        plan.residence[0].options["permit"] = "B"
        plan.residence[1].options["permit"] = "C"
        let issues = system.validate(plan, parameters: system.parameters)
        #expect(issues.map(\.code) == ["ch.permit.sourceTax"] && issues[0].severity == .warning)
        #expect(issues[0].message.contains("CHF 120,000"))
        // Unknown citizenship: nothing to say about permits.
        plan.citizenships = []
        plan.residence[0].options["permit"] = nil
        #expect(codes(plan) == [])
    }

    @Test func lumpSumTaxation() {
        let overlay = RegimeChoice(regime: SwissRegime.lumpSum,
                                   options: ["livingExpenses": "300000", "annualRent": "48000", "firstYear": 2026])
        let lugano = Swiss.place("Lugano", ["permit": "B"])
        var plan = TaxPlan(residence: [.init(from: 2026, system: "ch", options: lugano)],
                           overlays: [overlay], citizenships: ["IT"])
        #expect(codes(plan) == [])
        plan.residence = [.init(from: 2026, system: "ch", options: Swiss.place("Zurich", ["permit": "B"]))]
        let zurich = system.validate(plan, parameters: system.parameters)
        #expect(zurich.map(\.code) == ["ch.lumpSum.canton"])
        #expect(zurich[0].message == "Zurich has abolished lump-sum taxation; of the cantons offered, only Ticino has it.")
        plan.residence = [.init(from: 2026, system: "ch", options: lugano)]
        plan.citizenships = ["IT", "CH"]
        #expect(codes(plan) == ["ch.lumpSum.citizenship"])
        plan.citizenships = []
        #expect(codes(plan) == ["ch.lumpSum.citizenship"])
        plan.citizenships = ["DE"]
        plan.work = [.init(id: "w", kind: .selfEmployed, fromYear: 2027, untilYear: 2028)]
        #expect(codes(plan) == ["ch.lumpSum.earnedIncome"])
        plan.work = []
        plan.residence = [.init(from: 2024, system: "ch", options: lugano)]
        #expect(codes(plan) == ["ch.lumpSum.firstYear"])
        // Missing options are reported by the shared checks.
        plan.residence = [.init(from: 2026, system: "ch", options: lugano)]
        plan.overlays = [RegimeChoice(regime: SwissRegime.lumpSum, options: ["firstYear": 2026])]
        #expect(codes(plan) == ["ch.options.missing", "ch.options.missing"])
    }

    @Test func lumpSumTaxationInPrepare() throws {
        let overlay = RegimeChoice(regime: SwissRegime.lumpSum,
                                   options: ["livingExpenses": "300000", "annualRent": "48000", "firstYear": 2026])
        var year = FixedYear(year: 2026, age: 62, systemOptions: Swiss.place("Zurich"), overlays: [overlay])
        let zurich = try Swiss.prepare(year).fixedAssessment
        #expect(zurich.issues.map(\.code) == ["ch.lumpSum.canton"] && zurich.total(SwissLine.federal) == 0)
        year.systemOptions = Swiss.place("Lugano")
        #expect(try Swiss.prepare(year).fixedAssessment.total(SwissLine.federal) > 40_000)
        year.work = [.init(phaseID: "w", kind: .employee, gross: 50_000)]
        let working = try Swiss.prepare(year).fixedAssessment
        #expect(working.issues.map(\.code) == ["ch.lumpSum.earnedIncome"] && working.total(SwissLine.federal) < 1_000)
        // Before its first year it doesn't apply.
        year.work = []
        year.year = 2025
        #expect(try Swiss.prepare(year).fixedAssessment.total(SwissLine.federal) == 0)
    }

    @Test func expatriates() throws {
        var plan = examplePlan
        plan.overlays = [RegimeChoice(regime: SwissRegime.expatriate, options: ["assignmentStart": 2026])]
        #expect(codes(plan).isEmpty)
        plan.work = [.init(id: "w", kind: .selfEmployed, fromYear: 2026, untilYear: 2035)]
        #expect(codes(plan) == ["ch.expatriate.noEmployment"])
        // The deduction lasts 5 years from the start.
        let overlay = [RegimeChoice(regime: SwissRegime.expatriate, options: ["assignmentStart": 2022])]
        let within = try Swiss.prepare(Swiss.workYear(.employee, gross: 150_000, overlays: overlay)).fixedAssessment
        let after = try Swiss.prepare(Swiss.workYear(.employee, gross: 150_000, year: 2027, overlays: overlay))
            .fixedAssessment
        #expect(within.totalTax < after.totalTax - 4_000)
        let actual = [RegimeChoice(regime: SwissRegime.expatriate,
                                   options: ["assignmentStart": 2026, "deduction": "actual", "actualAmount": "30000"])]
        let more = try Swiss.prepare(Swiss.workYear(.employee, gross: 150_000, overlays: actual)).fixedAssessment
        #expect(more.totalTax < within.totalTax)
    }

    @Test func homeOptionsEndAfter2028() throws {
        var plan = examplePlan
        plan.residence[1].options["imputedRentalValue"] = "20000"
        #expect(codes(plan) == ["ch.property.imputedRentEnds"])
        let options: OptionValues = ["imputedRentalValue": "20000", "mortgageInterest": "5000"]
        var year = Swiss.pensionYear(40_000)
        year.systemOptions = Swiss.place("Zurich", options)
        let before = try Swiss.prepare(year).fixedAssessment.totalTax
        year.year = 2029
        let after = try Swiss.prepare(year).fixedAssessment.totalTax
        let plain = try Swiss.prepare(Swiss.pensionYear(40_000, year: 2029)).fixedAssessment.totalTax
        #expect(before > after && abs(after - plain) < 1e-9)
    }

    @Test func italianPublicServicePensions() {
        var plan = examplePlan
        plan.pensions.append(.init(id: "pension-3", scheme: "it.inps", sourceCountry: "IT"))
        #expect(codes(plan).isEmpty)
        plan.citizenships = ["CH", "IT"]
        let issues = system.validate(plan, parameters: system.parameters)
        #expect(issues.map(\.code) == ["ch.foreignPension.italianPublicService"])
        #expect(issues[0].message.contains("taxedIn: source"))
    }

    @Test func sharedChecks() {
        var plan = examplePlan
        plan.work = [
            .init(id: "a", kind: .employee, regime: "ch.freelance", fromYear: 2026, untilYear: 2027),
            .init(id: "b", kind: .employee, regime: SwissRegime.selfEmployed, fromYear: 2026, untilYear: 2027),
            .init(id: "c", kind: .employee, regime: SwissRegime.employee, options: ["bvgPlan": "maximum"],
                  fromYear: 2026, untilYear: 2027),
            .init(id: "d", kind: .employee, regime: "it.employee", fromYear: 2026, untilYear: 2027),
        ]
        plan.overlays = [RegimeChoice(regime: "ch.holding"), RegimeChoice(regime: SwissRegime.employee)]
        plan.pensions = [.init(id: "p", scheme: "ch.pillar1")]
        #expect(codes(plan) == ["ch.foreignRegime", "ch.options.invalidChoice", "ch.regimeScope", "ch.regimeScope",
                                "ch.unknownOverlay", "ch.unknownPensionScheme", "ch.unknownRegime"])
    }

    @Test func checksThatNeedTheAmounts() throws {
        // 3a without earned income, a buy-in without a pension fund, a regime of another kind.
        let retired = FixedYear(year: 2026, age: 50, systemOptions: Swiss.place("Zurich"),
                                wrapperContributions: [.init(wrapper: "ch.pillar3a", amount: 7_258),
                                                       .init(wrapper: "ch.bvg", amount: 10_000)])
        let assessment = try Swiss.prepare(retired).fixedAssessment
        #expect(assessment.issues.map(\.code) == ["ch.pillar3a.noEarnedIncome", "ch.bvg.buyInNotInsured"])
        #expect(assessment.accrued("ch.bvg") == 10_000)
        var wrongRegime = Swiss.workYear(.employee, gross: 60_000)
        wrongRegime.work[0].regime = SwissRegime.selfEmployed
        let fallback = try Swiss.prepare(wrongRegime).fixedAssessment
        #expect(fallback.issues.map(\.code) == ["ch.regimeScope"])
        #expect(fallback.contributions.map(\.id).contains(SwissLine.ahvEmployee))

        // Arriving from abroad: buy-ins limited to 20% of the insured salary for 5 years.
        var arrived = Swiss.workYear(.employee, gross: 100_000, contributions: [.init(wrapper: "ch.bvg", amount: 20_000)])
        arrived.residence = [.init(from: 2020, system: "it"), .init(from: 2024, system: "ch")]
        #expect(try Swiss.prepare(arrived).fixedAssessment.issues.map(\.code) == ["ch.bvg.buyInArrival"])
        arrived.residence = [.init(from: 2020, system: "it"), .init(from: 2021, system: "ch")]
        #expect(try Swiss.prepare(arrived).fixedAssessment.issues.isEmpty)

        // Over a plan's years: the 3a limit (20% of net income without a pension fund), every year it's exceeded.
        let plan = TaxPlan(residence: [.init(from: 2026, system: "ch", options: Swiss.place("Lugano"))],
                           work: [.init(id: "work", kind: .selfEmployed, fromYear: 2026, untilYear: 2028)],
                           citizenships: ["CH"])
        let years = [30_000.0, 100_000, 200_000].enumerated().map { index, income in
            Swiss.workYear(.selfEmployed, gross: income, commune: "Lugano", year: 2026 + index,
                           contributions: [.init(wrapper: "ch.pillar3a", amount: 20_000)])
        }
        let issues = system.validate(plan, years: years, parameters: system.parameters)
        #expect(issues.map(\.code) == ["ch.pillar3a.limit", "ch.pillar3a.limit"])
        #expect(issues.map(\.year) == [2026, 2027])
    }
}
