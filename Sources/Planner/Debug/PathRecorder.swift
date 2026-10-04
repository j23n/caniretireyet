import Foundation
import TaxKit

/// Records what one simulated path does, step by step and year by year, for
/// the plan debugger (``Planner/debugReport(for:library:registry:options:)``).
///
/// ``PathSimulator/tracedRun(_:spending:recorder:)`` tells it about each
/// step of each year: the start, money arriving in wrappers, payouts the
/// rules require, the year's cash flow and withdrawals, rebalancing, and the
/// year-end after the returns and the assessment. It only reads the
/// simulator's state, so a traced run ends exactly as the same run untraced.
/// Normal runs never make one.
final class PathRecorder {
    /// One simulated year as the simulator went through it. Bucket values
    /// are per bucket; class values per bucket and class (`bucket *
    /// classCount + class`), in the plan's currency.
    struct Year {
        let index: Int
        let variant: Int
        /// The market-dependent taxes of the year before, paid this year.
        let carriedIn: Double
        /// Per class of the portfolio, the year's real return (factor − 1),
        /// over the part of the year simulated.
        var returns: [Double] = []
        var startTotal = 0.0
        var start: [Double] = []
        var startClasses: [Double] = []
        var afterCredits: [Double] = []
        var afterPayouts: [Double] = []
        var afterFlows: [Double] = []
        var flowClasses: [Double] = []
        var afterRebalancing: [Double] = []
        var rebalancedClasses: [Double] = []
        var end: [Double] = []
        var endClasses: [Double] = []
        /// Per bucket, its purchase cost at the end of the year.
        var endBasis: [Double] = []

        /// Severance pay and payouts the rules require, after their tax.
        var payoutsNet = 0.0
        var contributions = 0.0
        var spending = 0.0
        var expenses = 0.0
        /// The year's cash flow before withdrawals: positive is invested.
        var cash = 0.0
        /// What couldn't be raised (after spending forced down toward the
        /// floor, with flexible spending).
        var shortfall = 0.0
        /// The spending paid: ``spending``, or less when flexible spending
        /// forced it down because the money that could be drawn ran short.
        var paidSpending = 0.0
        /// What the flexible-spending rule did this year; `nil` without the
        /// rule, or in a year without retirement spending.
        var flexible: FlexibleStep?

        var requiredPayouts: [VariableYear.WrapperPayout] = []
        var withdrawalPayouts: [VariableYear.WrapperPayout] = []
        var withdrawalSales: [VariableYear.Sale] = []
        var rebalancingSales: [VariableYear.Sale] = []
        var withheldOnPayouts = 0.0
        var withheldOnWithdrawals = 0.0
        var withheldOnRebalancing = 0.0
        /// The year's full assessment (`nil` in a year that failed).
        var assessment: TaxAssessment?
        /// Market-dependent taxes left to pay next year.
        var carriedOut = 0.0
        /// What the tax system carries along the path into next year, such
        /// as losses carried forward (``TaxKit/PreparedTaxYear/carriedForward(in:)``).
        var carriedForward: [TaxLine] = []
        var endAssets = 0.0
        var failure: RunFailure?
    }

    private(set) var years: [Year] = []
    private var current: Year?
    private var payoutMark = 0
    private var saleMark = 0
    private var withheldMark = 0.0

    func begin(year t: Int, variant: Int, run: Int?, carriedIn: Double, _ simulator: PathSimulator) {
        var year = Year(index: t, variant: variant, carriedIn: carriedIn)
        let scenarios = simulator.scenarios
        year.returns = (0..<scenarios.classes).map { c in
            if let run { return scenarios.factors[(run * scenarios.years + t) * scenarios.classes + c] - 1 }
            return scenarios.expectedFactors[t * scenarios.classes + c] - 1
        }
        year.startTotal = simulator.total()
        year.start = Self.bucketValues(simulator)
        year.startClasses = Self.classValues(simulator)
        current = year
        payoutMark = 0
        saleMark = 0
        withheldMark = 0
    }

    func afterCredits(_ simulator: PathSimulator) {
        current?.afterCredits = Self.bucketValues(simulator)
    }

    func afterPayouts(severancePay: Double, contributions: Double, spending: Double, expenses: Double, cash: Double,
                      _ simulator: PathSimulator) {
        current?.afterPayouts = Self.bucketValues(simulator)
        current?.requiredPayouts = simulator.variable.payouts
        payoutMark = simulator.variable.payouts.count
        current?.withheldOnPayouts = simulator.withheld
        withheldMark = simulator.withheld
        current?.payoutsNet = severancePay
        current?.contributions = contributions
        current?.spending = spending
        current?.expenses = expenses
        current?.cash = cash
    }

    func afterFlows(shortfall: Double, paidSpending: Double, flexible: FlexibleStep?, _ simulator: PathSimulator) {
        current?.afterFlows = Self.bucketValues(simulator)
        current?.flowClasses = Self.classValues(simulator)
        current?.withdrawalPayouts = Array(simulator.variable.payouts[payoutMark...])
        current?.withdrawalSales = simulator.variable.sales
        saleMark = simulator.variable.sales.count
        current?.withheldOnWithdrawals = simulator.withheld - withheldMark
        withheldMark = simulator.withheld
        current?.shortfall = shortfall
        current?.paidSpending = paidSpending
        current?.flexible = flexible
    }

    func failed(_ failure: RunFailure, _ simulator: PathSimulator) {
        guard var year = current else { return }
        year.failure = failure
        year.end = Self.bucketValues(simulator)
        year.endClasses = Self.classValues(simulator)
        year.endBasis = Self.bases(simulator)
        year.endAssets = simulator.total()
        years.append(year)
        current = nil
    }

    func afterRebalancing(_ simulator: PathSimulator) {
        current?.afterRebalancing = Self.bucketValues(simulator)
        current?.rebalancedClasses = Self.classValues(simulator)
        current?.rebalancingSales = Array(simulator.variable.sales[saleMark...])
        current?.withheldOnRebalancing = simulator.withheld - withheldMark
        withheldMark = simulator.withheld
    }

    func end(assessment: TaxAssessment, carriedOut: Double, endAssets: Double, carriedForward: [TaxLine],
             _ simulator: PathSimulator) {
        guard var year = current else { return }
        year.end = Self.bucketValues(simulator)
        year.endClasses = Self.classValues(simulator)
        year.endBasis = Self.bases(simulator)
        year.assessment = assessment
        year.carriedOut = carriedOut
        year.carriedForward = carriedForward
        year.endAssets = endAssets
        years.append(year)
        current = nil
    }

    // MARK: - Reading the simulator

    private static func bucketValues(_ simulator: PathSimulator) -> [Double] {
        simulator.bucketStart.indices.map { b in
            (simulator.bucketStart[b]..<simulator.bucketEnd[b]).reduce(0) { $0 + simulator.values[$1] }
        }
    }

    private static func classValues(_ simulator: PathSimulator) -> [Double] {
        let classes = simulator.classCount
        var result = [Double](repeating: 0, count: simulator.bucketStart.count * classes)
        for b in simulator.bucketStart.indices {
            for l in simulator.bucketStart[b]..<simulator.bucketEnd[b] {
                result[b * classes + simulator.lotClass[l]] += simulator.values[l]
            }
        }
        return result
    }

    /// Per bucket, its purchase cost: a liquid bucket's documented lots'
    /// (cash at its value), a tax-advantaged bucket's single one.
    private static func bases(_ simulator: PathSimulator) -> [Double] {
        simulator.bucketStart.indices.map { b in
            guard simulator.bucketLiquid[b] else { return simulator.wrapperBasis[b] }
            return (simulator.bucketStart[b]..<simulator.bucketEnd[b]).reduce(0) { total, l in
                total + (simulator.lotDocumented[l] ? simulator.bases[l] : 0)
            }
        }
    }
}
