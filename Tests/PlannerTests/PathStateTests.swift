import Foundation
import Model
@testable import Planner
import TaxGeneric
import TaxKit
import Testing

/// A made-up system for the tests of the state carried along a path: each
/// final assessment of a year adds one to `<id>.years`, and the smallest
/// gain a sale realised is kept as `<id>.minGain`. Gains are taxed at
/// `gainsRate` with no gross-up of its own, so the engine sizes every sale
/// by assessing the year with and without it, many times a year. Not a
/// real rule set.
struct PathTestSystem: TaxSystem {
    var id = "path"
    var name = "Path"
    var gainsRate = 0.0
    let parameters: any ParameterStore = try! JSONParameterStore(
        system: "path", files: [2025: Data(#"{ "source": "made up" }"#.utf8)])

    var options: [OptionField] { [] }
    var regimes: [RegimeDescriptor] { [] }
    var wrappers: [WrapperRule] {
        [WrapperRule(id: "path.ordinary", name: "Ordinary", category: .taxable) { _ in .accessible(route: nil) }]
    }
    var pensionSchemes: [any PensionScheme] { [FixedPensionScheme()] }

    func defaultRegime(for kind: EarnedIncomeKind) -> String? { nil }

    func validate(_ plan: TaxPlan, parameters: any ParameterStore) -> [TaxIssue] { [] }

    func prepare(_ year: FixedYear, state: TaxState, parameters: ParameterSet) -> any PreparedTaxYear {
        PathTestYear(id: id, gainsRate: gainsRate)
    }
}

struct PathTestYear: PreparedTaxYear {
    let id: String
    let gainsRate: Double

    var fixedAssessment: TaxAssessment { TaxAssessment() }

    func assess(_ variable: VariableYear) -> TaxAssessment {
        var next = variable.pathState
        next["\(id).years"] = (variable.pathState["\(id).years"] ?? 0) + 1
        var smallest = variable.pathState["\(id).minGain"]
        for sale in variable.sales {
            if let gain = sale.gain { smallest = min(smallest ?? gain, gain) }
        }
        next["\(id).minGain"] = smallest
        let gains = variable.sales.reduce(0) { $0 + max(0, $1.gain ?? $1.proceeds) }
        let lines = gains > 0 && gainsRate > 0
            ? [TaxLine(id: "\(id).gains", label: "Gains tax", amount: gainsRate * gains)] : []
        return TaxAssessment(lines: lines, nextPathState: next)
    }

    func grossUp(net: Double, from bucket: BucketSnapshot) -> Double? { nil }

    func carriedForward(in state: TaxState) -> [TaxLine] {
        state["\(id).years"].map { [TaxLine(id: "\(id).years", label: "Years assessed", amount: $0)] } ?? []
    }
}

struct PathStateTests {
    /// Born 1966, 60 in 2026 and retired: `balance` in equity, half of it
    /// gain, drawn for spending every year, to 70 (2026–2036).
    func makeSimulator(_ systems: [PathTestSystem], residence: [PlanResidence]? = nil, retired: String = "8000",
                       equityReturn: String = "0.05", volatility: String = "0.2", inflation: String = "0.02",
                       gainShare: String = "0.5", balance: Decimal = 200_000) async throws
        -> (PathSimulator, PlanModel) {
        let library = Sample.library(birth: "1966-01-01", on: "2025-12-31", [
            SampleAccount(id: "broker", wrapper: "path.ordinary", balance: balance),
        ])
        var plan = Sample.plan(retire: .age(59), endAge: 70, retired: retired, equityReturn: equityReturn,
                               volatility: volatility, inflation: inflation, unrealizedGainShare: gainShare, runs: 20)
        plan.tax = PlanTax(residence: residence ?? [PlanResidence(from: 2020, system: TaxSystemID(systems[0].id))])
        plan.withdrawals.cashBuffer = 0
        let (interpreted, issues) = PlanInterpreter.interpret(
            plan: plan, library: library, registry: TaxRegistry(systems),
            options: PlannerOptions(maxRetirementAge: 61, solveSustainableSpending: false))
        let model = try #require(interpreted, "\(issues.map(\.message))")
        let engine = try await Engine.make(model: model, ages: [model.currentAge], maxAge: model.currentAge)
        return (engine.simulator(age: model.currentAge), model)
    }

    @Test func theStateFlowsFromYearToYearAndStartsAfreshOnEveryPath() async throws {
        var system = PathTestSystem()
        system.gainsRate = 0.25
        let (made, model) = try await makeSimulator([system])
        var simulator = made
        let recorder = PathRecorder()
        _ = simulator.tracedRun(0, spending: model.spending.retired, recorder: recorder)
        // Each year's final assessment counts once: 1 after 2026, … 11 after 2036,
        // though the engine assessed many times a year to size the sales.
        #expect(recorder.years.map { $0.carriedForward.first?.amount ?? 0 } == (1...11).map(Double.init))
        #expect(recorder.years.allSatisfy { !$0.withdrawalSales.isEmpty })
        #expect(recorder.years.contains { $0.assessment?.lines.contains { $0.id == "path.gains" } == true })
        #expect(simulator.pathState["path.years"] == 11)
        // The next path, and the deterministic one, start empty again.
        _ = simulator.run(1, spending: model.spending.retired)
        #expect(simulator.pathState["path.years"] == 11)
        _ = simulator.run(nil, spending: model.spending.retired)
        #expect(simulator.pathState["path.years"] == 11)
    }

    @Test func sizingSalesAndPayoutsNeverCommitsTheState() async throws {
        // With a gains tax and no gross-up of the system's own, every sale is
        // sized by assessing the year twice per round; the count still only
        // follows the years.
        var system = PathTestSystem()
        system.gainsRate = 0.5
        let (made, model) = try await makeSimulator([system], retired: "30000")
        var simulator = made
        for run in 0..<5 {
            let outcome = simulator.run(run, spending: model.spending.retired)
            let years = outcome.failedYear ?? (model.frames.count - 1)
            // A failing run stops before its last year's assessment.
            #expect(simulator.pathState["path.years"] == Double(outcome.failedYear == nil ? years + 1 : years))
        }
    }

    @Test func aNewResidenceSystemStartsWithAnEmptyState() async throws {
        let (made, model) = try await makeSimulator(
            [PathTestSystem(id: "path"), PathTestSystem(id: "next", name: "Next")],
            residence: [PlanResidence(from: 2020, system: "path"), PlanResidence(from: 2030, system: "next")])
        var simulator = made
        let recorder = PathRecorder()
        _ = simulator.tracedRun(3, spending: model.spending.retired, recorder: recorder)
        let years = recorder.years.map { model.frames[$0.index].year }
        #expect(years.first == 2026)
        for year in recorder.years {
            let state = try #require(year.assessment?.nextPathState)
            if model.frames[year.index].year < 2030 {
                #expect(state["path.years"] == Double(year.index + 1) && state["next.years"] == nil)
            } else {
                // Carry-forwards don't follow the person to another country.
                #expect(state["path.years"] == nil && state["next.years"] == Double(year.index - 3))
            }
        }
    }

    @Test func lossesReachTheSystemAsNegativeGainsAndTheCostBasisFallsWithTheSale() async throws {
        // Equity loses 10% a year, bought at its value: every sale after the
        // first is at a loss.
        let (made, model) = try await makeSimulator([PathTestSystem()], retired: "10000", equityReturn: "-0.1",
                                                    volatility: "0", inflation: "0", gainShare: "0",
                                                    balance: 100_000)
        var simulator = made
        let recorder = PathRecorder()
        _ = simulator.tracedRun(nil, spending: model.spending.retired, recorder: recorder)
        // 2026: 10,000 sold at cost, then −10%: 81,000 costing 90,000.
        let first = try #require(recorder.years.first?.withdrawalSales.first)
        #expect(abs(first.proceeds - 10_000) < 1e-6 && abs((first.gain ?? 1) - 0) < 1e-6)
        #expect(abs(recorder.years[0].endBasis[0] - 90_000) < 1e-6)
        // 2027: 10,000 of 81,000 sold, with its share of the cost: a loss.
        let second = try #require(recorder.years[1].withdrawalSales.first)
        let share = 10_000 / 81_000.0
        #expect(abs((second.costBasis ?? 0) - 90_000 * share) < 1e-6)
        #expect(abs((second.gain ?? 0) - (10_000 - 90_000 * share)) < 1e-6)
        #expect(abs(recorder.years[1].endBasis[0] - 90_000 * (1 - share)) < 1e-6)
        let smallest = try #require(simulator.pathState["path.minGain"])
        #expect(smallest < -1_000)
    }

    /// The debugger shows what the tax system carries along each traced path.
    @Test func theDebuggerShowsLossesCarriedForward() async throws {
        let library = Sample.library(birth: "1966-01-01", on: "2025-12-31", [
            SampleAccount(id: "broker", wrapper: "taxable", mix: [.equity: 0.6, .crypto: 0.4], balance: 600_000),
        ])
        var plan = Sample.plan(retire: .age(59), endAge: 80, retired: "20000", volatility: "0.2",
                               unrealizedGainShare: "0.3", runs: 60)
        plan.tax = PlanTax(residence: [PlanResidence(from: 2020, system: "generic",
                                                     options: ["capitalGainsRate": "0.3"])])
        plan.assumptions.returns[.crypto] = ReturnAssumption(real: 0, volatility: d("0.7"))
        let report = try await Planner.debugReport(
            for: plan, library: library, registry: TaxRegistry([GenericTaxSystem()]),
            options: PlanDebugOptions(planner: PlannerOptions(maxRetirementAge: 61), retirementAge: .today,
                                      startScale: .actual, paths: .automatic(count: 3), runDate: "2026-01-02"))
        let carried = report.paths.flatMap(\.years).compactMap(\.carriedForward).flatMap { $0 }
        #expect(!carried.isEmpty)
        #expect(carried.allSatisfy { $0.id == "generic.losses" && $0.amount > 0 })
        for path in report.paths { #expect(path.matchesMainRun, "\(path.label)") }
        let markdown = report.markdown()
        #expect(markdown.contains("Carried forward"))
        let json = try report.json()
        #expect(json.contains("\"carriedForward\""))
        #expect(try PlanDebugReport.decode(json: json) == report)
        let anonymized = report.anonymized(PlanDebugAnonymization(rounding: .hundreds))
        let rounded = anonymized.paths.flatMap(\.years).compactMap(\.carriedForward).flatMap { $0 }
        #expect(rounded.allSatisfy { $0.amount.truncatingRemainder(dividingBy: 100) == 0 })
    }
}
