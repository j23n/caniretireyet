import Foundation
import Model

/// The deterministic run of a plan at one retirement age, with what it
/// starts from, unrounded: what a second implementation needs to work the
/// years out again and compare (`tools/oracle`). `retire plan debug --json`
/// prints it.
public struct DeterministicRun: Hashable, Sendable {
    public var plan: PlanID
    /// ``Planner/engineVersion``.
    public var engine: String
    /// The currency of every amount: the library's base currency.
    public var currency: CurrencyCode
    public var birthDate: CalendarDate
    /// The check-in the plan starts from; the first year starts the day after.
    public var startDate: CalendarDate
    /// The age work stops at in this run.
    public var retirementAge: Int
    /// The accounts by when they can be drawn, as the run starts with them:
    /// after the debts the plan counts are paid off.
    public var groups: [BucketSummary]
    /// The tax on the gains realised paying off debts at the start, due
    /// with the first year's taxes.
    public var debtGainsTax: Double
    /// The tax paying off debts took from pre-tax accounts at the start.
    public var debtWithdrawalTax: Double
    /// The years, and where the run failed if it did.
    public var path: PathDetail
}

extension Planner {
    /// The deterministic run of `plan` retiring at `retirementAge`: the
    /// plan's age without one, or today's age when the plan asks for the
    /// earliest. It runs no Monte Carlo simulation, so it's quick.
    ///
    /// Throws ``PlannerError/invalidPlan(_:)`` when the plan has errors.
    public static func deterministicRun(plan: PlanDocument, library: Library, retirementAge: Int? = nil,
                                        today: CalendarDate? = nil) throws -> DeterministicRun {
        let options = PlannerOptions(mode: .fast(runs: 1), today: today)
        let (interpreted, issues) = PlanInterpreter.interpret(plan: plan, library: library, options: options)
        guard let model = interpreted else { throw PlannerError.invalidPlan(issues) }
        let age = min(max(retirementAge ?? model.planAge ?? model.currentAge, model.currentAge), model.endAge - 1)
        let scenarios = MarketScenarios(model: model.returns, fractions: model.frames.map(\.fraction), runs: 1,
                                        seed: model.seed, eventProbabilities: model.uncertainEventProbabilities)
        var simulator = PathSimulator(model: model, schedule: AgeSchedule(model: model, age: age),
                                      scenarios: scenarios, start: model.portfolio)
        let (outcome, years) = simulator.detailedRun(nil, spending: model.spending.retired)
        return DeterministicRun(
            plan: plan.id, engine: engineVersion, currency: model.currency, birthDate: model.birthDate,
            startDate: model.startDate, retirementAge: age, groups: bucketSummaries(model.portfolio),
            debtGainsTax: model.portfolio.debtGainsTax, debtWithdrawalTax: model.portfolio.debtWithdrawalTax,
            path: PathDetail(failure: outcome.failure, years: years))
    }
}
