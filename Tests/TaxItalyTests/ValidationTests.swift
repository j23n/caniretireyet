@testable import TaxItaly
import TaxKit
import Testing

/// Plan validation: regime scope and years, exclusions, missing options,
/// unknown IDs, and forfettario's eligibility over a plan's years.
struct ValidationTests {
    let system = Italy.system

    private func codes(_ plan: TaxPlan) -> [String] {
        system.validate(plan, parameters: system.parameters).map(\.code).sorted()
    }

    /// The example library's base plan, as the planner would pass it.
    private var examplePlan: TaxPlan {
        TaxPlan(
            residence: [.init(from: 2026, system: "it", options: Italy.addizionali)],
            overlays: [RegimeChoice(regime: ItalyRegime.impatriati2024, options: ["movedIn": 2025, "minorChild": false])],
            overrides: ["it.irpef.rates": ["0.23", "0.35", "0.43"]],
            work: [
                .init(id: "work-0", kind: .employee, regime: ItalyRegime.employee, options: ["tfr": "pensionFund"],
                      fromYear: 2026, untilYear: 2028),
                .init(id: "work-1", kind: .selfEmployed, regime: ItalyRegime.forfettario,
                      options: ["coefficient": "0.67", "startedIn": 2029], fromYear: 2029, untilYear: nil),
            ],
            pensions: [.init(id: "pension-0", scheme: "it.inps",
                             options: ["montante": "92000", "contributionYears": "8", "foreignContributionYears": "6"]),
                       .init(id: "pension-1", scheme: "fixed")],
            birthYear: 1988)
    }

    @Test func theExamplePlan() {
        let issues = system.validate(examplePlan, parameters: system.parameters)
        #expect(issues.map(\.code) == ["it.impatriati.forfettario", "it.forfettario.startupEnds"])
        #expect(issues[0].message == "Impatriati doesn't apply to forfettario income: you lose the 2029 exemption.")
        #expect(issues[0].severity == .warning && issues[0].year == 2029)
        #expect(issues[1].message == "The 5% start-up rate ends after 2033; from 2034 the rate is 15%.")
    }

    @Test func unknownIDsAndScope() {
        var plan = examplePlan
        plan.work = [
            .init(id: "a", kind: .employee, regime: "it.freelance", fromYear: 2026, untilYear: 2027),
            .init(id: "b", kind: .employee, regime: ItalyRegime.forfettario, options: ["coefficient": "0.67"],
                  fromYear: 2026, untilYear: 2027),
            .init(id: "c", kind: .selfEmployed, regime: ItalyRegime.impatriati2015, fromYear: 2026, untilYear: 2027),
            .init(id: "d", kind: .selfEmployed, regime: ItalyRegime.forfettario, fromYear: 2026, untilYear: 2027),
            .init(id: "e", kind: .employee, regime: "generic.employee", fromYear: 2026, untilYear: 2027),
        ]
        plan.overlays = [RegimeChoice(regime: "it.impatriati-2030", options: [:]),
                         RegimeChoice(regime: ItalyRegime.forfettario, options: [:])]
        plan.pensions = [.init(id: "p", scheme: "it.inpgi")]
        plan.overrides = ["it.irpef.brakets": "1"]
        #expect(codes(plan) == [
            "it.foreignRegime", "it.options.missing", "it.regimeScope", "it.regimeScope", "it.regimeScope",
            "it.unknownOverlay", "it.unknownOverride", "it.unknownPensionScheme", "it.unknownRegime",
        ])
    }

    @Test func optionsAreChecked() {
        var plan = examplePlan
        plan.residence = [.init(from: 2026, system: "it", options: ["addizionaleRegionale": "1.73", "otherTaxCredits": "x"])]
        plan.overlays = [RegimeChoice(regime: ItalyRegime.impatriati2024, options: ["minorChild": "yes"])]
        plan.work = [.init(id: "w", kind: .employee, regime: ItalyRegime.employee, options: ["tfr": "bank"],
                           fromYear: 2026, untilYear: 2030)]
        #expect(codes(plan) == ["it.options.invalidChoice", "it.options.missing", "it.options.outOfRange",
                                "it.options.wrongType", "it.options.wrongType"])
    }

    @Test func impatriatiRules() {
        var plan = examplePlan
        plan.work = []
        plan.overlays = [RegimeChoice(regime: ItalyRegime.impatriati2024, options: ["movedIn": 2023]),
                         RegimeChoice(regime: ItalyRegime.impatriati2015, options: ["movedIn": 2024])]
        #expect(codes(plan) == ["it.impatriati.both", "it.impatriati.movedIn", "it.impatriati.movedIn"])

        plan.overlays = [RegimeChoice(regime: ItalyRegime.impatriati2015,
                                      options: ["movedIn": 2018, "extension": "home"])]
        #expect(codes(plan) == ["it.impatriati.extension", "it.impatriati.noYears"])

        plan.overlays = [RegimeChoice(regime: ItalyRegime.impatriati2024, options: ["movedIn": 2026])]
        plan.residence.append(.init(from: 2028, system: "generic"))
        #expect(codes(plan) == ["it.impatriati.minimumStay"])
    }

    @Test func forfettarioOnArrival() {
        var plan = examplePlan
        plan.overlays = [RegimeChoice(regime: ItalyRegime.impatriati2024, options: ["movedIn": 2026])]
        plan.work = [.init(id: "f", kind: .selfEmployed, regime: ItalyRegime.forfettario,
                           options: ["coefficient": "0.67"], fromYear: 2026, untilYear: 2027)]
        let issues = system.validate(plan, parameters: system.parameters)
        #expect(issues.map(\.code) == ["it.impatriati.forfettario", "it.impatriati.forfettarioOnArrival"])
        #expect(issues[0].message.hasSuffix("you lose the 2026–2027 exemptions."))
        #expect(issues[1].message.contains("no ruling on the 2024 regime"))

        plan.overlays = [RegimeChoice(regime: ItalyRegime.impatriati2015, options: ["movedIn": 2023])]
        plan.work = [.init(id: "f", kind: .selfEmployed, regime: ItalyRegime.forfettario,
                           options: ["coefficient": "0.67"], fromYear: 2023, untilYear: 2026)]
        let old = system.validate(plan, parameters: system.parameters)
        #expect(old.map(\.code) == ["it.impatriati.forfettario", "it.impatriati.forfettarioOnArrival"])
        #expect(old[1].message.hasSuffix("rules out Impatriati (2015 regime) in later years."))
    }

    @Test func onlyChecksWhileResidentInItaly() {
        let plan = TaxPlan(residence: [.init(from: 2026, system: "generic")],
                           work: [.init(id: "w", kind: .selfEmployed, regime: ItalyRegime.forfettario, fromYear: 2026,
                                        untilYear: nil)])
        #expect(codes(plan).isEmpty)
    }

    @Test func forfettarioEligibilityOverThePlansYears() {
        let plan = TaxPlan(residence: [.init(from: 2026, system: "it")],
                           work: [.init(id: "f", kind: .selfEmployed, regime: ItalyRegime.forfettario,
                                        options: ["coefficient": "0.78"], fromYear: 2026, untilYear: 2030)])
        let revenues: [Int: Double] = [2026: 80_000, 2027: 90_000, 2028: 60_000, 2029: 70_000, 2030: 110_000]
        let years = revenues.keys.sorted().map { year in
            FixedYear(year: year, age: 40, work: [.init(phaseID: "f", kind: .selfEmployed,
                                                        regime: ItalyRegime.forfettario,
                                                        options: ["coefficient": "0.78"], gross: revenues[year]!)])
        }
        let issues = system.validate(plan, years: years, parameters: system.parameters)
        #expect(issues.map(\.code) == ["it.forfettario.revenueLimitNextYear", "it.forfettario.revenueLimit",
                                       "it.forfettario.immediateExit"])
        #expect(issues.map(\.year) == [2027, 2028, 2030])
    }

    @Test func forfettarioSwitchesToOrdinario() throws {
        let year = Italy.workYear(.selfEmployed, regime: ItalyRegime.forfettario, gross: 70_000, costs: 3_000,
                                  options: ["coefficient": "0.67"])
        let eligible = try Italy.prepare(year, state: ["it.prior.selfEmployedRevenue": 85_000])
        #expect(eligible.fixedAssessment.total("it.forfettario") > 0)
        #expect(eligible.fixedAssessment.issues.isEmpty)

        let over = try Italy.prepare(year, state: ["it.prior.selfEmployedRevenue": 85_001])
        #expect(over.fixedAssessment.total("it.forfettario") == 0)
        #expect(over.fixedAssessment.total("it.irpef") > 0)
        #expect(over.fixedAssessment.issues.map(\.code) == ["it.forfettario.revenueLimit"])
        // The same as choosing the regime ordinario.
        let ordinario = try Italy.prepare(Italy.workYear(.selfEmployed, regime: ItalyRegime.professional, gross: 70_000,
                                                         costs: 3_000))
        #expect(abs(over.fixedAssessment.totalTax - ordinario.fixedAssessment.totalTax) < 1e-9)

        // Employment income over 35,000 last year counts only while the job goes on.
        let ended = try Italy.prepare(year, state: ["it.prior.employmentIncome": 50_000])
        #expect(ended.fixedAssessment.issues.isEmpty)
        var both = year
        both.work.append(.init(phaseID: "job", kind: .employee, regime: ItalyRegime.employee, gross: 20_000))
        let ongoing = try Italy.prepare(both, state: ["it.prior.employmentIncome": 50_000])
        #expect(ongoing.fixedAssessment.issues.map(\.code) == ["it.forfettario.employmentIncomeLimit"])
        let pensioner = try Italy.prepare(year, state: ["it.prior.pensionIncome": 36_000])
        #expect(pensioner.fixedAssessment.issues.map(\.code) == ["it.forfettario.employmentIncomeLimit"])
    }

    @Test func regimeOfAnotherKindFallsBackWithAWarning() throws {
        let year = Italy.workYear(.employee, regime: ItalyRegime.forfettario, gross: 30_000)
        let assessment = try Italy.prepare(year).fixedAssessment
        #expect(assessment.issues.map(\.code) == ["it.regimeScope"])
        #expect(assessment.contributions.map(\.id) == ["it.inps.employee"])
    }
}
