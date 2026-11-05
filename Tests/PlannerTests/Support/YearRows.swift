import Foundation
import Model
@testable import Planner
import Testing

/// One year of a path as the money it moved (PLANNER.md, "The yearly step").
///
/// A year adds up in two ways:
/// - **Its cash**: income from work, pensions and other income, windfalls
///   and what was sold come in; spending, one-off expenses and the taxes
///   paid from the year's money go out; what's left went into accounts:
///   contributions, and the rest invested in the money you can draw. The
///   tax on what paying off debts took from pre-tax money is in the first
///   year's tax on withdrawals, but it was paid at the start, from those
///   accounts, so it isn't paid from the year's money.
/// - **Its value**: the plan assets at the start of the year (the end of the
///   year before; the plan assets on the start date in the first year),
///   plus what went in, less what was sold, grow by the year's returns to
///   the end. Rebalancing moves money between classes without tax, so it
///   changes nothing here.
///
/// Every amount is for the part of the year simulated, so a part first year
/// adds up the same way.
struct YearRow {
    let detail: YearDetail

    /// Income from work, pensions and other income.
    var income: Double { sum([.work, .pension, .other]) }
    var windfalls: Double { sum([.windfall]) }
    /// What was sold, before the taxes on it.
    var sold: Double { sum([.withdrawal]) }
    /// The taxes paid from the year's money.
    var taxesPaid: Double {
        detail.investmentTax + detail.wealthTax + detail.withdrawalTax - detail.debtWithdrawalTax
    }
    /// What went into accounts: contributions, and the rest of the cash
    /// invested in the money you can draw.
    var putIn: Double { detail.savings + sold }
    /// Money in less money out less what went into accounts: 0 when the
    /// year's cash adds up.
    var unexplainedCash: Double {
        income + windfalls + sold - detail.spending - detail.expenses - taxesPaid - putIn
    }

    private func sum(_ kinds: Set<IncomeKind>) -> Double {
        detail.income.filter { kinds.contains($0.kind) }.reduce(0) { $0 + $1.amount }
    }
}

/// How a year's returns are known, for ``expectYearsAddUp(_:start:growth:_:sourceLocation:)``.
enum YearGrowth {
    /// Exactly: the plan assets after the year's money moved grow by this
    /// factor in year `t` (every class and every account alike).
    case exactly((Int) -> Double)
    /// Between the lowest and the highest factor of the classes held in year `t`.
    case between((Int) -> ClosedRange<Double>)
}

/// Checks that every year of `path` adds up (``YearRow``): its cash, to
/// within the 1 unit a run may leave unpaid (`PathSimulator.tolerance`);
/// each year starting from the end of the one before, from `start` in the
/// first; and its end value as what was there after the year's money moved
/// times the year's `growth`. The year a run fails isn't checked: the run
/// stops before its money moves.
func expectYearsAddUp(_ path: PathDetail, start: Double, growth: YearGrowth, _ label: String,
                      sourceLocation: SourceLocation = #_sourceLocation) {
    let years = path.failure == nil ? path.years : Array(path.years.dropLast())
    #expect(!years.isEmpty, "\(label): no years", sourceLocation: sourceLocation)
    var before = start
    for (t, detail) in years.enumerated() {
        let row = YearRow(detail: detail)
        let scale = max(1, before, abs(row.income) + abs(row.sold) + abs(detail.spending))
        #expect(abs(row.unexplainedCash) <= PathSimulator.tolerance + 1e-9 * scale,
                "\(label), \(detail.year): the cash is off by \(row.unexplainedCash)", sourceLocation: sourceLocation)
        #expect(row.sold >= 0 && row.putIn >= -1e-9 * scale,
                "\(label), \(detail.year): sold \(row.sold), put in \(row.putIn)", sourceLocation: sourceLocation)
        #expect(t == 0 || detail.debtWithdrawalTax == 0, sourceLocation: sourceLocation)
        #expect(detail.debtWithdrawalTax <= detail.withdrawalTax + 1e-9, sourceLocation: sourceLocation)
        let invested = before + detail.savings
        switch growth {
        case .exactly(let factor):
            let expected = invested * factor(t)
            #expect(abs(detail.endAssets - expected) <= 1e-9 * scale,
                    "\(label), \(detail.year): ends at \(detail.endAssets), not \(expected)",
                    sourceLocation: sourceLocation)
        case .between(let range):
            let factors = range(t)
            let low = invested * factors.lowerBound - 1e-9 * scale
            let high = invested * factors.upperBound + 1e-9 * scale
            #expect(detail.endAssets >= low && detail.endAssets <= high,
                    "\(label), \(detail.year): ends at \(detail.endAssets), outside \(low)…\(high)",
                    sourceLocation: sourceLocation)
        }
        before = detail.endAssets
    }
}

/// The deterministic growth of the classes `held` in a year simulated for
/// `fraction` of it: each class's median, compounded over the part.
func medianGrowth(of held: [AssetClass], assumptions: PlanAssumptions, fraction: Double) -> ClosedRange<Double> {
    let factors = held.map { assetClass in
        pow(1 + (assumptions.returnAssumption(for: assetClass)?.medianReturn ?? 0), fraction)
    }
    return (factors.min() ?? 1)...(factors.max() ?? 1)
}

/// The engine's random futures for `plan` run with `options`, as
/// `MarketScenarios` draws them for every run: for checking that a path is
/// one run's draws.
func scenarios(of plan: PlanDocument, library: Library, options: PlannerOptions) throws
    -> (model: PlanModel, scenarios: MarketScenarios) {
    let model = try #require(PlanInterpreter.interpret(plan: plan, library: library, options: options).0)
    let scenarios = MarketScenarios(model: model.returns, fractions: model.frames.map(\.fraction), runs: model.runs,
                                    seed: model.seed, eventProbabilities: model.uncertainEventProbabilities)
    return (model, scenarios)
}
