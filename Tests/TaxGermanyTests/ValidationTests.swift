@testable import TaxGermany
import TaxKit
import Testing

/// Plan validation: options, required ones, impossible combinations, and
/// what the residence timeline shows; checks that need amounts, year by year.
struct ValidationTests {
    let system = Germany.system

    private func codes(_ plan: TaxPlan) -> [String] {
        system.validate(plan, parameters: system.parameters).map(\.code).sorted()
    }

    /// A made-up Berlin employee who later freelances, with a DRV pension.
    private var plan: TaxPlan {
        TaxPlan(
            residence: [.init(from: 2026, system: "de", options: ["bundesland": "BE", "childBirthYears": [2016, 2019]])],
            work: [.init(id: "work-0", kind: .employee, regime: GermanRegime.employee, fromYear: 2026, untilYear: 2030),
                   .init(id: "work-1", kind: .selfEmployed, regime: GermanRegime.freelancer,
                         options: ["drv": "voluntary", "drvContribution": "3000"], fromYear: 2031, untilYear: nil)],
            pensions: [.init(id: "pension-0", scheme: "de.drv", options: ["points": "18.5", "contributionYears": 15])],
            birthYear: 1985, citizenships: ["DE"])
    }

    @Test func aGoodPlanHasNoIssues() {
        #expect(codes(plan).isEmpty)
    }

    @Test func optionsAreChecked() {
        var plan = plan
        plan.residence = [.init(from: 2026, system: "de", options: [
            "bundesland": "XX", "churchMember": "yes", "zusatzbeitrag": "0.5", "childBirthYears": "2016",
            "healthInsurance": "pkv",
        ])]
        plan.work[1].options = ["drv": "sometimes"]
        plan.pensions[0].options = ["points": "-1"]
        #expect(codes(plan) == ["de.options.invalidChoice", "de.options.invalidChoice", "de.options.outOfRange",
                                "de.options.outOfRange", "de.options.wrongType", "de.options.wrongType",
                                "de.pkv.premiumMissing"])
    }

    @Test func requiredOptionsAndScope() {
        var plan = plan
        plan.work = [
            .init(id: "a", kind: .selfEmployed, regime: GermanRegime.trader, fromYear: 2026, untilYear: 2027),
            .init(id: "b", kind: .selfEmployed, regime: GermanRegime.trader, options: ["hebesatz": "1.5"],
                  fromYear: 2026, untilYear: 2027),
            .init(id: "c", kind: .employee, regime: GermanRegime.freelancer, fromYear: 2026, untilYear: 2027),
            .init(id: "d", kind: .employee, regime: "de.beamter", fromYear: 2026, untilYear: 2027),
            .init(id: "e", kind: .employee, regime: "it.employee", fromYear: 2026, untilYear: 2027),
        ]
        plan.pensions = [.init(id: "p", scheme: "de.knappschaft")]
        #expect(codes(plan) == ["de.foreignRegime", "de.options.missing", "de.options.outOfRange", "de.regimeScope",
                                "de.unknownPensionScheme", "de.unknownRegime"])
    }

    @Test func privateHealthInsuranceNeedsItsPremium() {
        var plan = plan
        plan.residence = [.init(from: 2026, system: "de", options: ["retirementHealthInsurance": "pkv"])]
        #expect(codes(plan) == ["de.pkv.premiumMissing"])
        plan.residence = [.init(from: 2026, system: "de", options: ["healthInsurance": "pkv", "pkvPremium": "650",
                                                                    "retirementHealthInsurance": "kvdr"])]
        #expect(codes(plan) == ["de.kvdr.afterPKV"])
    }

    @Test func fixedPensionsNeedAKind() {
        var plan = plan
        plan.pensions.append(.init(id: "pension-1", scheme: "fixed"))
        plan.pensions.append(.init(id: "pension-2", scheme: "fixed", kind: .occupational, sourceCountry: "CH"))
        #expect(codes(plan) == ["de.pension.kindUnknown"])
    }

    @Test func leavingGermany() {
        var plan = plan
        plan.residence = [.init(from: 2020, system: "de"), .init(from: 2032, system: "ch")]
        let issues = system.validate(plan, parameters: system.parameters)
        #expect(issues.map(\.code) == ["de.exitTax", "de.treaty.CH.extendedTaxation"])
        #expect(issues.allSatisfy { $0.year == 2032 && $0.severity == .warning })
        // Not after fewer than 7 of the last 12 years; not for a Swiss national.
        plan.residence = [.init(from: 2027, system: "de"), .init(from: 2032, system: "ch")]
        plan.citizenships = ["DE", "CH"]
        #expect(codes(plan).isEmpty)
        plan.residence = [.init(from: 2020, system: "de"), .init(from: 2032, system: "it")]
        #expect(codes(plan) == ["de.exitTax"])
    }

    @Test func onlyChecksWhileResidentInGermany() {
        let plan = TaxPlan(residence: [.init(from: 2026, system: "it")],
                           work: [.init(id: "w", kind: .selfEmployed, regime: GermanRegime.trader, fromYear: 2026,
                                        untilYear: nil)])
        #expect(codes(plan).isEmpty)
    }

    @Test func yearByYearChecks() throws {
        let plan = TaxPlan(residence: [.init(from: 2026, system: "de", options: ["healthInsurance": "pkv",
                                                                                 "pkvPremium": "500"])],
                           work: [.init(id: "w", kind: .employee, fromYear: 2026, untilYear: 2027)])
        let years = [60_000.0, 90_000].enumerated().map { index, gross in
            FixedYear(year: 2026 + index, age: 40, systemOptions: ["healthInsurance": "pkv", "pkvPremium": "500"],
                      work: [.init(phaseID: "w", kind: .employee, gross: gross)],
                      wrapperContributions: [.init(wrapper: GermanWrapper.altersvorsorgedepot, amount: 1_000)])
        }
        let issues = system.validate(plan, years: years, parameters: system.parameters)
        #expect(issues.map(\.code) == ["de.pkv.belowCompulsoryLimit", "de.altersvorsorgedepot.beforeStart"])
        #expect(issues.map(\.year) == [2026, 2026])
    }

    @Test func contributionsBeyondTheirLimits() throws {
        let freelancer = Germany.workYear(.selfEmployed, regime: GermanRegime.freelancer, gross: 60_000,
                                          options: ["drv": "voluntary", "drvContribution": "50"],
                                          contributions: [.init(wrapper: GermanWrapper.riester, amount: 2_000),
                                                          .init(wrapper: GermanWrapper.ruerup, amount: 40_000)])
        let assessment = try Germany.prepare(freelancer).fixedAssessment
        #expect(assessment.issues.map(\.code) == ["de.drv.contributionLimits", "de.riester.notEligible",
                                                  "de.ruerup.aboveMaximum"])
        // Voluntary DRV contributions are raised to the minimum.
        #expect(abs(assessment.contribution(GermanLine.pension) - 112.16 * 12) < 1e-9)

        let employee = Germany.workYear(.employee, regime: GermanRegime.employee, gross: 50_000,
                                        contributions: [.init(wrapper: GermanWrapper.riester, amount: 2_500),
                                                        .init(wrapper: GermanWrapper.bav, amount: 9_000)])
        #expect(try Germany.prepare(employee).fixedAssessment.issues.map(\.code) == ["de.bav.aboveLimit",
                                                                                      "de.riester.aboveMaximum"])
        let retiree = FixedYear(year: 2026, age: 60,
                                wrapperContributions: [.init(wrapper: GermanWrapper.bav, amount: 1_000)])
        #expect(try Germany.prepare(retiree).fixedAssessment.issues.map(\.code) == ["de.bav.noSalary"])
    }

    @Test func aRegimeOfAnotherKindFallsBackWithAWarning() throws {
        let year = Germany.workYear(.employee, regime: GermanRegime.trader, gross: 30_000)
        let assessment = try Germany.prepare(year).fixedAssessment
        #expect(assessment.issues.map(\.code) == ["de.regimeScope"])
        #expect(assessment.contributions.map(\.id) == ["de.rv", "de.av", "de.kv", "de.pv"])
        let missing = try Germany.prepare(Germany.workYear(.selfEmployed, regime: GermanRegime.trader, gross: 60_000))
            .fixedAssessment
        #expect(missing.issues.map(\.code) == ["de.trader.hebesatz"])
        #expect(missing.total(GermanLine.tradeTax) > 0)
    }
}
