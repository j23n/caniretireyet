import Foundation
import Model

/// What a plan's starting portfolio holds by asset class, as the planner
/// reads the library (PLANNER.md, "The portfolio"): the money you can draw now,
/// which the plan's target mix applies to, and every account the plan
/// counts. The editors show it next to the target mix
/// (``Planner/startingMix(plan:library:today:)``).
public struct StartingMix: Hashable, Sendable {
    /// The day the plan starts from.
    public var date: CalendarDate
    /// The currency of the values: the library's base currency.
    public var currency: CurrencyCode
    /// Value per class of the money you can draw now.
    public var accessible: [AssetClass: Double]
    /// Value per class of every account the plan counts, those available
    /// from a later age (which keep their own mix) included.
    public var all: [AssetClass: Double]

    /// The value of the money you can draw now.
    public var accessibleTotal: Double { Self.total(accessible) }
    /// Every counted account's value.
    public var allTotal: Double { Self.total(all) }

    /// The mix of the money you can draw now, as shares summing to 1; empty without any.
    public var accessibleShares: [AssetClass: Double] { Self.shares(accessible) }
    /// Every counted account's mix, as shares summing to 1; empty without money.
    public var allShares: [AssetClass: Double] { Self.shares(all) }

    /// The classes held, in the canonical order (every known class, then others by name).
    public var classes: [AssetClass] {
        let held = Set(all.filter { $0.value > 0 }.keys).union(accessible.filter { $0.value > 0 }.keys)
        return AssetClass.knownValues.filter(held.contains) + held.subtracting(AssetClass.knownValues).sorted()
    }

    /// Summed in the classes' order, so the total is the same in every process.
    private static func total(_ values: [AssetClass: Double]) -> Double {
        values.sorted { $0.key < $1.key }.reduce(0) { $0 + max(0, $1.value) }
    }

    private static func shares(_ values: [AssetClass: Double]) -> [AssetClass: Double] {
        let total = total(values)
        guard total > 0 else { return [:] }
        return values.filter { $0.value > 0 }.mapValues { $0 / total }
    }
}

/// A mix rebalanced every year: its expected (mean) yearly real return,
/// its volatility, and its median (typical) yearly real return, as a
/// log-normal approximation from the classes' assumptions and correlations
/// (``Planner/growth(of:assumptions:)``).
public struct MixGrowth: Hashable, Sendable {
    public var expectedReturn: Double
    public var volatility: Double
    public var medianReturn: Double
}

extension Planner {
    /// What the plan's starting portfolio holds by asset class: the
    /// accounts it counts on its start date (the latest check-in, or the
    /// plan's date), valued in the base currency and grouped as a run groups
    /// them. Without a check-in it starts `today` with nothing.
    public static func startingMix(plan: PlanDocument, library: Library, today: CalendarDate? = nil) -> StartingMix {
        let date: CalendarDate = switch plan.portfolio.effectiveStart {
        case .date(let date): date
        case .latestCheckIn: library.latestCheckInDate ?? today ?? .today()
        }
        let currentAge = library.settings.person?.birthDate.map { $0.wholeYears(to: date) } ?? 0
        var issues: [PlanIssue] = []
        let portfolio = Portfolio.build(library: library, date: date, plan: plan, currentAge: currentAge,
                                        extraClasses: [], issues: &issues)
        var accessible: [AssetClass: Double] = [:]
        var all: [AssetClass: Double] = [:]
        for (b, bucket) in portfolio.buckets.enumerated() {
            for (c, assetClass) in portfolio.classes.enumerated() where bucket.values[c] > 0 {
                all[assetClass, default: 0] += bucket.values[c]
                if b == 0 { accessible[assetClass, default: 0] += bucket.values[c] }
            }
        }
        return StartingMix(date: date, currency: library.settings.baseCurrency, accessible: accessible, all: all)
    }

    /// How `mix` (shares by class; they're scaled to sum to 1) grows when
    /// it's rebalanced every year, under the plan's return assumptions and
    /// correlations. A class without an assumption counts as 0% with no
    /// volatility.
    public static func growth(of mix: [AssetClass: Double], assumptions: PlanAssumptions) -> MixGrowth {
        let classes = mix.filter { $0.value > 0 }.keys.sorted()
        let total = classes.reduce(0) { $0 + mix[$1]! }
        guard total > 0 else { return MixGrowth(expectedReturn: 0, volatility: 0, medianReturn: 0) }
        var issues: [PlanIssue] = []
        let model = ReturnModel(assumptions: assumptions, heldClasses: classes, issues: &issues)
        let correlations = model.drawIndex.map { i in
            model.drawIndex.map { j in zip(model.cholesky[i], model.cholesky[j]).reduce(0) { $0 + $1.0 * $1.1 } }
        }
        let weights = classes.map { mix[$0]! / total }
        var mean = 0.0
        var variance = 0.0
        for i in weights.indices {
            mean += weights[i] * model.expected[i]
            for j in weights.indices {
                variance += weights[i] * weights[j] * model.volatility[i] * model.volatility[j] * correlations[i][j]
            }
        }
        variance = max(0, variance)
        return MixGrowth(expectedReturn: mean, volatility: variance.squareRoot(),
                         medianReturn: median(expected: mean, variance: variance))
    }

    /// The median of a log-normal yearly return with this expected (mean)
    /// return and variance: (1 + μ) / √(1 + σ² / (1 + μ)²) − 1.
    static func median(expected: Double, variance: Double) -> Double {
        let mean = 1 + expected
        guard mean > 0 else { return -1 }
        return mean / (1 + variance / (mean * mean)).squareRoot() - 1
    }
}
