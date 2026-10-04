import Foundation
import Model
import TaxKit

/// What a plan's starting portfolio holds by asset class, as the planner
/// reads the library (PLANNER.md, "Buckets"): the ordinary (taxable)
/// accounts the plan's target mix applies to, and every account the plan
/// counts. The editors show it next to the target mix
/// (``Planner/startingMix(plan:library:registry:today:)``).
public struct StartingMix: Hashable, Sendable {
    /// The day the plan starts from.
    public var date: CalendarDate
    /// The currency of the values: the plan's.
    public var currency: CurrencyCode
    /// Value per class of the ordinary (taxable) accounts.
    public var taxable: [AssetClass: Double]
    /// Value per class of every account the plan counts, tax-advantaged ones
    /// (a pension fund, which keeps its own mix) included.
    public var all: [AssetClass: Double]

    public init(date: CalendarDate, currency: CurrencyCode, taxable: [AssetClass: Double],
                all: [AssetClass: Double]) {
        self.date = date
        self.currency = currency
        self.taxable = taxable
        self.all = all
    }

    /// The ordinary accounts' value.
    public var taxableTotal: Double { Self.total(taxable) }
    /// Every counted account's value.
    public var allTotal: Double { Self.total(all) }

    /// The ordinary accounts' mix, as shares summing to 1; empty without money in them.
    public var taxableShares: [AssetClass: Double] { Self.shares(taxable) }
    /// Every counted account's mix, as shares summing to 1; empty without money.
    public var allShares: [AssetClass: Double] { Self.shares(all) }

    /// The classes held, in the canonical order (every known class, then others by name).
    public var classes: [AssetClass] {
        let held = Set(all.filter { $0.value > 0 }.keys).union(taxable.filter { $0.value > 0 }.keys)
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

    public init(expectedReturn: Double, volatility: Double, medianReturn: Double) {
        self.expectedReturn = expectedReturn
        self.volatility = volatility
        self.medianReturn = medianReturn
    }
}

extension Planner {
    /// What the plan's starting portfolio holds by asset class: the
    /// accounts it counts on its start date (the latest check-in, or the
    /// plan's date), valued in its currency and grouped as a run groups
    /// them. Ordinary (taxable) accounts are what the target mix applies
    /// to; accounts that start a pension scheme aren't money to draw on and
    /// aren't counted. Without a check-in it starts `today` with nothing.
    public static func startingMix(plan: PlanDocument, library: Library, registry: TaxRegistry,
                                   today: CalendarDate? = nil) -> StartingMix {
        let date: CalendarDate = switch plan.portfolio.effectiveStart {
        case .date(let date): date
        case .latestCheckIn: library.latestCheckInDate ?? today ?? .today()
        }
        let residence = plan.tax.residence.min { $0.from < $1.from }.flatMap { registry.system($0.system.rawValue) }
            ?? defaultTaxSystem(for: library.settings, registry: registry)
        var seedWrappers: [String: String] = [:]
        for pension in plan.pensions where pension.scheme != .fixed {
            guard let scheme = registry.pensionScheme(pension.scheme.rawValue), let wrapper = scheme.seedWrapper,
                  seedWrappers[wrapper] == nil else { continue }
            seedWrappers[wrapper] = pension.scheme.rawValue
        }
        let currency = plan.effectiveCurrency(base: library.settings.baseCurrency)
        var issues: [PlanIssue] = []
        let portfolio = PortfolioBuilder(library: library, date: date, plan: plan, registry: registry,
                                         residence: residence, currency: currency, seedWrappers: seedWrappers,
                                         issues: &issues)
        var taxable: [AssetClass: Double] = [:]
        var all: [AssetClass: Double] = [:]
        for bucket in portfolio.buckets {
            for holding in bucket.holdings where holding.value > 0 {
                all[holding.assetClass, default: 0] += holding.value
                if bucket.category == .taxable { taxable[holding.assetClass, default: 0] += holding.value }
            }
        }
        return StartingMix(date: date, currency: currency, taxable: taxable, all: all)
    }

    /// How `mix` (shares by class; they're scaled to sum to 1) grows when
    /// it's rebalanced every year, under the plan's return assumptions and
    /// correlations: the same arithmetic as the plan debugger's assumptions
    /// table. A class without an assumption counts as 0% with no volatility.
    public static func growth(of mix: [AssetClass: Double], assumptions: PlanAssumptions) -> MixGrowth {
        let classes = mix.filter { $0.value > 0 }.keys.sorted()
        let total = classes.reduce(0) { $0 + mix[$1]! }
        guard total > 0 else { return MixGrowth(expectedReturn: 0, volatility: 0, medianReturn: 0) }
        var issues: [PlanIssue] = []
        let model = ReturnModel(assumptions: assumptions, heldClasses: classes, issues: &issues)
        let correlations = model.drawIndex.map { i in
            model.drawIndex.map { j in zip(model.cholesky[i], model.cholesky[j]).reduce(0) { $0 + $1.0 * $1.1 } }
        }
        let growth = PlanDebugMath.growth(weights: classes.map { mix[$0]! / total }, expected: model.expected,
                                          volatility: model.volatility, correlations: correlations)
        return MixGrowth(expectedReturn: growth.expectedReturn, volatility: growth.volatility,
                         medianReturn: growth.medianReturn)
    }
}
