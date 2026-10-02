import Foundation
import Model
@testable import Planner
import TaxGeneric
import TaxKit
import Testing

/// A made-up scheme, `echo.fund`, that pays 1,000 a year from 60 by
/// whatever route the plan picks (`ClaimContext.claimRoute`), or by
/// `echo.default` when it picks none. Not a real rule set.
private struct EchoScheme: PensionScheme {
    let id = "echo.fund"
    let name = "Echo"
    var options: [OptionField] { [] }

    func startingRecord(options: OptionValues, year: Int, parameters: any ParameterStore) -> PensionRecord {
        PensionRecord(scheme: id)
    }

    func accrue(_ accruals: [Accrual], in year: Int, to record: inout PensionRecord, options: OptionValues,
                parameters: ParameterSet) {}

    func claimOptions(for record: PensionRecord, context: ClaimContext, parameters: any ParameterStore)
        -> [ClaimOption] {
        [ClaimOption(route: context.claimRoute ?? "echo.default", label: "Echo", age: 60, annualAmount: 1_000)]
    }
}

/// The flat test system, plus a residence option `pillarYears` that sets how
/// many years `flat.pillar` spreads its payouts over (the rule's own value
/// when it isn't set; 0 for none), and the `echo.fund` scheme.
private struct ChoosingSystem: TaxSystem {
    var base: FlatTaxSystem
    var id: String { base.id }
    var name: String { base.name }
    var options: [OptionField] { base.options + [.int("pillarYears", "Pillar payout years", range: 0...10)] }
    var regimes: [RegimeDescriptor] { base.regimes }
    var wrappers: [WrapperRule] { base.wrappers }
    var pensionSchemes: [any PensionScheme] { base.pensionSchemes + [EchoScheme()] }
    var parameters: any ParameterStore { base.parameters }

    func defaultRegime(for kind: EarnedIncomeKind) -> String? { base.defaultRegime(for: kind) }

    func validate(_ plan: TaxPlan, parameters: any ParameterStore) -> [TaxIssue] {
        base.validate(plan, parameters: parameters)
    }

    func prepare(_ year: FixedYear, state: TaxState, parameters: ParameterSet) -> any PreparedTaxYear {
        base.prepare(year, state: state, parameters: parameters)
    }

    func preferredPayoutYears(for wrapper: String, options: OptionValues) -> Int? {
        guard wrapper == "flat.pillar", let years = options.int("pillarYears") else {
            return base.preferredPayoutYears(for: wrapper, options: options)
        }
        return years > 0 ? years : nil
    }
}

/// What a plan chooses that the tax system turns into the plan's flows: the
/// years a wrapper's payouts are spread over (from the residence options),
/// the claim route the scheme is told, and which new buckets get a warning.
/// Worked out by hand on the made-up flat system, with zero volatility.
struct PlanChoiceTests {
    /// Born 1966: the pillar, 30,000, opens at 60 (2026).
    let library = Sample.library(birth: "1966-01-01", on: "2025-12-31", [
        SampleAccount(id: "broker", mix: [.cash: 1], balance: 0),
        SampleAccount(id: "pillar", kind: .pensionFund, wrapper: "flat.pillar", mix: [.cash: 1], balance: 30_000),
    ])

    fileprivate var system: ChoosingSystem {
        var base = FlatTaxSystem()
        base.pillarPayoutYears = 3
        return ChoosingSystem(base: base)
    }

    func run(_ plan: PlanDocument, _ systems: [any TaxSystem], library: Library? = nil) async throws -> PlanResult {
        try await Planner.run(plan: plan, library: library ?? self.library, registry: TaxRegistry(systems),
                              options: PlannerOptions(maxRetirementAge: 62, solveSustainableSpending: false))
    }

    func payoutYears(_ result: PlanResult) -> [Int] {
        result.expectedPath.years.filter { $0.income.contains { $0.kind == .payout } }.map(\.year)
    }

    func payout(_ result: PlanResult, in year: Int) -> Double? {
        result.expectedPath.years.first { $0.year == year }?.income.first { $0.kind == .payout }?.amount
    }

    @Test func theResidenceOptionsChooseThePayoutYears() async throws {
        var plan = Sample.plan(retire: .age(60), endAge: 66, retired: "0", equityReturn: "0", runs: 10)
        // Not set: the rule's 3 years, 10,000 a year.
        let byRule = try await run(plan, [system])
        #expect(payoutYears(byRule) == [2026, 2027, 2028])
        #expect(close(payout(byRule, in: 2027), 10_000))

        // Two years: half, then the rest.
        plan.tax.residence = [PlanResidence(from: 2020, system: "flat", options: ["pillarYears": 2])]
        let two = try await run(plan, [system])
        #expect(payoutYears(two) == [2026, 2027])
        #expect(close(payout(two, in: 2026), 15_000) && close(payout(two, in: 2027), 15_000))

        // One: all at once. None: drawn only as needed, and nothing is needed.
        plan.tax.residence[0].options = ["pillarYears": 1]
        let once = try await run(plan, [system])
        #expect(payoutYears(once) == [2026] && close(payout(once, in: 2026), 30_000))
        plan.tax.residence[0].options = ["pillarYears": 0]
        #expect(payoutYears(try await run(plan, [system])).isEmpty)
    }

    @Test func theOptionsComeFromTheWrappersOwnSystem() async throws {
        // Living under generic until 2028 and then under flat, whose period
        // (the first after the pillar opens) says two years.
        var plan = Sample.plan(retire: .age(60), endAge: 66, retired: "0", equityReturn: "0", runs: 10)
        plan.tax.residence = [PlanResidence(from: 2020, system: "generic"),
                              PlanResidence(from: 2028, system: "flat", options: ["pillarYears": 2])]
        let later = try await run(plan, [GenericTaxSystem(), system])
        #expect(payoutYears(later) == [2026, 2027])
        // Never living under flat: its default, the rule's 3 years.
        plan.tax.residence = [PlanResidence(from: 2020, system: "generic")]
        let never = try await run(plan, [GenericTaxSystem(), system])
        #expect(payoutYears(never) == [2026, 2027, 2028])
    }

    @Test func theSchemeIsToldTheClaimRoute() async throws {
        var plan = Sample.plan(retire: .age(60), endAge: 62, retired: "0", equityReturn: "0", runs: 10)
        plan.pensions = [PlanPension(scheme: "echo.fund", claim: .age(60), claimRoute: "echo.chosen")]
        let (model, issues) = PlanInterpreter.interpret(plan: plan, library: library, registry: TaxRegistry([system]),
                                                        options: PlannerOptions())
        let interpreted = try #require(model, "\(issues.filter(\.isError))")
        let schedule = AgeSchedule(model: interpreted, age: 60, neededMasks: interpreted.frames.map { _ in [] },
                                   expectedMask: interpreted.expectedEvents)
        #expect(schedule.claims.first??.option.route == "echo.chosen")
        // Without a route, the scheme is told none.
        plan.pensions[0].claimRoute = nil
        let result = try await run(plan, [system])
        #expect(!result.issues.contains { $0.code == "planner.claimRoute" })
        #expect(result.expectedPath.years.first?.income.contains { $0.kind == .pension && $0.amount == 1_000 } == true)
    }

    @Test func aWrapperOnlyALumpSumMovesIntoGetsNoWarning() async throws {
        // Born 1976, stopping work at 52 (2028), before the fund pays at 60:
        // its 100,000 move into `flat.vested`, which no account uses. That's
        // expected, so there's no warning; severance credited to `flat.tfr`,
        // which no account uses either, still gets one.
        let library = Sample.library(birth: "1976-01-01", on: "2025-12-31", [SampleAccount(id: "broker", balance: 0)])
        var plan = Sample.plan(retire: .age(52), endAge: 54, working: "50000", retired: "0", equityReturn: "0",
                               work: [Sample.employee(from: "2026-01-01", gross: "50000")], runs: 10)
        plan.pensions = [PlanPension(scheme: "flat.fund", claim: .earliest, options: ["startingBalance": "100000"])]
        let transferOnly = try await Sample.run(plan, library)
        #expect(transferOnly.start.buckets.contains { $0.wrapper == "flat.vested" })
        #expect(!transferOnly.issues.contains { $0.code == "planner.newWrapper" })

        var withSeverance = FlatTaxSystem()
        withSeverance.tfrRate = 0.1
        let both = try await Sample.run(plan, library, system: withSeverance)
        let warnings = both.issues.filter { $0.code == "planner.newWrapper" }
        #expect(warnings.count == 1 && warnings.first?.message.contains("Severance") == true)
    }
}
