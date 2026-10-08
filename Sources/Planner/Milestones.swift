import Foundation
import Model
import Tracker

/// A point on the way to retiring (PROGRESS.md, "Milestones"): an amount
/// of plan assets, in the base currency and today's money, and what it means.
public struct Milestone: Hashable, Sendable, Identifiable {
    /// What a milestone means.
    public enum Kind: Hashable, Sendable {
        /// A round amount: 1, 1.5, 2, 2.5, 3, 4, 5, 6 or 7.5 times a power of ten.
        case roundAmount
        /// Enough for this many years of the plan's retirement spending.
        case yearsOfSpending(Int)
        /// This share of what retiring today needs: `numerator / denominator`.
        case shareOfNeeded(numerator: Int, denominator: Int)
        /// Where a typical year's growth matches a year's saving.
        case crossover
        /// Saving nothing more, retiring when the first pension starts
        /// reaches the confidence level: the recorded coast age is at most
        /// that age (PLANNER.md, "Ages without").
        case coastPoint(age: Int)
    }

    public var kind: Kind
    /// The plan assets that reach it. For a share of what retiring today
    /// needs: that share of what it needs now, or, once a check-in reached
    /// it, the plan assets at that check-in; for the coast point, the plan
    /// assets at the check-in that reached it.
    public var amount: Decimal

    public init(kind: Kind, amount: Decimal) {
        self.kind = kind
        self.amount = amount
    }

    /// The same at every check-in: "round-300000", "years-10", "share-1-2", "crossover".
    public var id: String {
        switch kind {
        case .roundAmount: "round-\(amount)"
        case .yearsOfSpending(let years): "years-\(years)"
        case .shareOfNeeded(let numerator, let denominator): "share-\(numerator)-\(denominator)"
        case .crossover: "crossover"
        case .coastPoint: "coast"
        }
    }

    /// The share of what retiring today needs, for ``Kind/shareOfNeeded(numerator:denominator:)``.
    public var share: Decimal? {
        guard case .shareOfNeeded(let numerator, let denominator) = kind, denominator > 0 else { return nil }
        return Decimal(numerator) / Decimal(denominator)
    }

    /// The order of kinds with the same amount: round amounts first.
    var kindOrder: Int {
        switch kind {
        case .roundAmount: 0
        case .yearsOfSpending: 1
        case .shareOfNeeded: 2
        case .crossover: 3
        case .coastPoint: 4
        }
    }
}

/// A milestone your plan assets reached.
public struct ReachedMilestone: Hashable, Sendable, Identifiable {
    public var milestone: Milestone
    /// The day that reached it: a check-in, or the end of a month without
    /// one, valued from what you held and its prices.
    public var date: CalendarDate

    public init(milestone: Milestone, date: CalendarDate) {
        self.milestone = milestone
        self.date = date
    }

    public var id: String { milestone.id }
}

/// A milestone ahead: when the plan's median future reaches it.
public struct ProjectedMilestone: Hashable, Sendable, Identifiable {
    public var milestone: Milestone
    /// When the median first reaches its amount, by days between the
    /// year-ends around it.
    public var date: CalendarDate

    public init(milestone: Milestone, date: CalendarDate) {
        self.milestone = milestone
        self.date = date
    }

    public var id: String { milestone.id }
}

/// The nearest milestone ahead, and how far there.
public struct NextMilestone: Hashable, Sendable {
    public var milestone: Milestone
    /// From 0 to 1: today's plan assets as a share of its amount, or, for a
    /// share of what retiring today needs, today's readiness as a share of it.
    public var progress: Double

    public init(milestone: Milestone, progress: Double) {
        self.milestone = milestone
        self.progress = progress
    }
}

/// The milestones of a plan (PROGRESS.md, "Milestones"): round amounts,
/// years of its retirement spending, shares of what retiring today needs,
/// and the crossover.
public struct MilestoneLadder: Hashable, Sendable {
    /// The plan's retirement spending a year; without it, no years of spending.
    public var spending: Decimal?
    /// What retiring today needs now; without it (and without a readiness
    /// to work it out from), no shares of it ahead.
    public var neededToday: Decimal?
    /// Where a typical year's growth matches a year's saving; `nil` without
    /// saving or growth.
    public var crossover: Decimal?
    /// The age the coast point is for: when the first pension starts; `nil`
    /// without a pension.
    public var coastTarget: Int?

    public init(spending: Decimal? = nil, neededToday: Decimal? = nil, crossover: Decimal? = nil,
                coastTarget: Int? = nil) {
        self.spending = spending
        self.neededToday = neededToday
        self.crossover = crossover
        self.coastTarget = coastTarget
    }

    /// The round amounts' first digits, times ten: 1, 1.5, 2, 2.5, 3, 4, 5, 6 and 7.5.
    static let roundSteps: [Decimal] = [10, 15, 20, 25, 30, 40, 50, 60, 75]
    /// The years of spending that are milestones.
    public static let years = [1, 2, 3, 5, 10, 15, 20, 25, 30, 40, 50]
    /// The shares of what retiring today needs that are milestones.
    public static let shares: [(numerator: Int, denominator: Int)] = [(1, 4), (1, 3), (1, 2), (2, 3), (3, 4), (9, 10),
                                                                     (1, 1)]

    /// The round amounts in `range`, lowest first: 1, 1.5, 2, 2.5, 3, 4, 5, 6
    /// and 7.5 times a power of ten, from 1,000.
    public static func roundAmounts(in range: ClosedRange<Decimal>) -> [Decimal] {
        var amounts: [Decimal] = []
        var power: Decimal = 100
        while 10 * power <= range.upperBound {
            for step in roundSteps where range.contains(step * power) {
                amounts.append(step * power)
            }
            power *= 10
        }
        return amounts
    }

    /// Every milestone whose amount is in `range`, by amount (round amounts
    /// first where two meet).
    public func milestones(in range: ClosedRange<Decimal>) -> [Milestone] {
        var milestones = Self.roundAmounts(in: range).map { Milestone(kind: .roundAmount, amount: $0) }
        if let spending, spending > 0 {
            for years in Self.years where range.contains(spending * Decimal(years)) {
                milestones.append(Milestone(kind: .yearsOfSpending(years), amount: spending * Decimal(years)))
            }
        }
        if let neededToday, neededToday > 0 {
            for share in Self.shares {
                let amount = (neededToday * Decimal(share.numerator) / Decimal(share.denominator)).rounded(scale: 0)
                if range.contains(amount) {
                    milestones.append(Milestone(kind: .shareOfNeeded(numerator: share.numerator,
                                                                     denominator: share.denominator),
                                                amount: amount))
                }
            }
        }
        if let crossover, range.contains(crossover) {
            milestones.append(Milestone(kind: .crossover, amount: crossover))
        }
        return milestones.sorted { ($0.amount, $0.kindOrder) < ($1.amount, $1.kindOrder) }
    }

    // MARK: Reached

    /// The milestones reached, oldest first: each at the first value of
    /// plan assets that reaches its amount, above every value before (so
    /// one passed before the first value, or passed again after a fall,
    /// isn't listed); the shares of what retiring today needs where the
    /// recorded readiness first reaches them, with the plan assets then as
    /// their amount.
    ///
    /// The coast point is reached at the first check-in whose recorded coast
    /// age is at most ``coastTarget``, after one above it.
    ///
    /// - Parameters:
    ///   - values: plan assets at each check-in and at the end of each
    ///     month without one, oldest first.
    ///   - readiness: the readiness recorded at check-ins, oldest first
    ///     (1 is all that retiring today needs).
    ///   - coastAges: the coast age recorded at check-ins, oldest first.
    public func reached(values: [SeriesPoint], readiness: [SeriesPoint] = [],
                        coastAges: [SeriesPoint] = []) -> [ReachedMilestone] {
        var reached: [ReachedMilestone] = []
        let amounts = MilestoneLadder(spending: spending, crossover: crossover)
        if var high = values.first?.value {
            for point in values.dropFirst() where point.value > high {
                for milestone in amounts.milestones(in: high...point.value) where milestone.amount > high {
                    reached.append(ReachedMilestone(milestone: milestone, date: point.date))
                }
                high = point.value
            }
        }
        if var high = readiness.first?.value {
            for point in readiness.dropFirst() where point.value > high {
                let assets = values.last { $0.date <= point.date }?.value ?? 0
                for share in Self.shares {
                    let fraction = Decimal(share.numerator) / Decimal(share.denominator)
                    guard fraction > high, fraction <= point.value else { continue }
                    let kind = Milestone.Kind.shareOfNeeded(numerator: share.numerator, denominator: share.denominator)
                    reached.append(ReachedMilestone(milestone: Milestone(kind: kind, amount: assets), date: point.date))
                }
                high = point.value
            }
        }
        if let target = coastTarget, var low = coastAges.first?.value {
            let age = Decimal(target)
            for point in coastAges.dropFirst() where point.value < low {
                if point.value <= age, low > age {
                    let assets = values.last { $0.date <= point.date }?.value ?? 0
                    reached.append(ReachedMilestone(milestone: Milestone(kind: .coastPoint(age: target), amount: assets),
                                                    date: point.date))
                }
                low = point.value
            }
        }
        return reached.sorted {
            ($0.date, $0.milestone.amount, $0.milestone.kindOrder) < ($1.date, $1.milestone.amount, $1.milestone.kindOrder)
        }
    }

    /// The milestones `plan` reached through `date`: plan assets on the line
    /// Progress draws, from the first record of one (a value, or a trade)
    /// through the latest check-in on or before `date`, at each check-in
    /// and the end of every month without one (PROGRESS.md, "Milestones");
    /// and the readiness and coast age recorded for the plan.
    public func reached(plan: PlanID, library: Library, valuator: Valuator,
                        through date: CalendarDate) -> [ReachedMilestone] {
        let checkIns = valuator.checkInDates(in: .planAssets, through: date)
        var values: [SeriesPoint] = []
        if let last = checkIns.last {
            let first = min(valuator.firstValuationDate(in: .planAssets) ?? last, last)
            values = DateGrid.checkInsAndMonthEnds(from: first, through: last, checkIns: checkIns).map { day in
                SeriesPoint(date: day, value: valuator.total(on: day, in: .planAssets).total)
            }
        }
        let headlines = library.headlines(for: plan)
            .filter { $0.date <= date }
            .sorted { $0.date < $1.date }
        let readiness = headlines.compactMap { headline in
            headline.readiness.map { SeriesPoint(date: headline.date, value: $0) }
        }
        let coastAges = headlines.compactMap { headline in
            headline.coastAge.map { SeriesPoint(date: headline.date, value: Decimal($0)) }
        }
        return reached(values: values, readiness: readiness, coastAges: coastAges)
    }

    // MARK: Ahead

    /// The milestones above `current` that the median future reaches,
    /// soonest first.
    ///
    /// - Parameters:
    ///   - current: today's plan assets.
    ///   - readiness: today's readiness. With it, the shares of what retiring
    ///     today needs are those above it, at the amounts it implies
    ///     (`current / readiness` is what retiring today needs).
    ///   - median: the median future's plan assets at the start and at each
    ///     year-end after it, oldest first.
    public func ahead(of current: Decimal, readiness: Decimal? = nil, median: [SeriesPoint]) -> [ProjectedMilestone] {
        guard let top = median.map(\.value).max(), top > current else { return [] }
        let ladder = matching(current: current, readiness: readiness)
        var projected: [ProjectedMilestone] = []
        for milestone in ladder.milestones(in: current...top)
        where Self.isAhead(milestone, of: current, readiness: readiness) {
            for (before, after) in zip(median, median.dropFirst())
            where before.value < milestone.amount && after.value >= milestone.amount {
                let share = ((milestone.amount - before.value) / (after.value - before.value)).doubleValue
                let days = Int((Double(before.date.days(to: after.date)) * share).rounded())
                projected.append(ProjectedMilestone(milestone: milestone, date: before.date.adding(days: days)))
                break
            }
        }
        return projected.sorted {
            ($0.date, $0.milestone.amount, $0.milestone.kindOrder) < ($1.date, $1.milestone.amount, $1.milestone.kindOrder)
        }
    }

    // MARK: Next

    /// The milestone with the lowest amount above `current`, and how far
    /// there; `nil` without one.
    ///
    /// - Parameters:
    ///   - current: today's plan assets.
    ///   - readiness: today's readiness, for the shares of what retiring
    ///     today needs (as in ``ahead(of:readiness:median:)``).
    public func next(after current: Decimal, readiness: Decimal? = nil) -> NextMilestone? {
        let ladder = matching(current: current, readiness: readiness)
        let upper = max(current, 0) * 2 + 1_000
        guard let milestone = ladder.milestones(in: current...upper)
            .first(where: { Self.isAhead($0, of: current, readiness: readiness) }) else {
            return nil
        }
        let progress: Double
        if let share = milestone.share, let readiness, share > 0 {
            progress = (readiness / share).doubleValue
        } else {
            progress = milestone.amount > 0 ? (max(current, 0) / milestone.amount).doubleValue : 0
        }
        return NextMilestone(milestone: milestone, progress: min(1, max(0, progress)))
    }

    /// Whether `milestone` is ahead of today: a share of what retiring today
    /// needs while today's readiness is below it, as ``reached(values:readiness:coastAges:)``
    /// counts them (its amount, worked out from a readiness that meets it
    /// exactly, can round to above `current`); any other while its amount is
    /// above `current`.
    private static func isAhead(_ milestone: Milestone, of current: Decimal, readiness: Decimal?) -> Bool {
        if let share = milestone.share, let readiness, readiness > 0, current > 0 {
            return share > readiness
        }
        return milestone.amount > current
    }

    /// The ladder with what retiring today needs worked out from today's
    /// readiness, when there is one, so its shares agree with it.
    private func matching(current: Decimal, readiness: Decimal?) -> MilestoneLadder {
        guard let readiness, readiness > 0, current > 0 else { return self }
        var ladder = self
        ladder.neededToday = (current / readiness).rounded(scale: 0)
        return ladder
    }
}

extension MilestoneLadder {
    /// A plan's ladder: its retirement spending; what retiring today needs
    /// when known (from the plan's results); and the crossover
    /// (``crossover(plan:library:on:)``).
    public init(plan: PlanDocument, library: Library, on date: CalendarDate, neededToday: Decimal? = nil) {
        self.init(spending: plan.spending.retired > 0 ? plan.spending.retired : nil, neededToday: neededToday,
                  crossover: Self.crossover(plan: plan, library: library, on: date),
                  coastTarget: plan.pensions.compactMap(\.fromAge).min())
    }

    /// Where a typical year's growth matches a year's saving, in whole
    /// units: the saving of the work phase in force on `date` (its
    /// take-home pay less spending while working) divided by the median
    /// yearly growth of the plan's target mix, else of the money you can
    /// draw today. `nil` without saving or growth.
    public static func crossover(plan: PlanDocument, library: Library, on date: CalendarDate) -> Decimal? {
        let working = plan.work.last { phase in
            phase.from <= date && (phase.until.date.map { $0 >= date } ?? true)
        }
        guard let income = working?.netIncome else { return nil }
        let saving = income - plan.spending.working
        guard saving > 0 else { return nil }
        let mix: [AssetClass: Double]
        if let target = plan.portfolio.targetMix, !target.shares.isEmpty {
            mix = target.shares.mapValues(\.doubleValue)
        } else {
            mix = Planner.startingMix(plan: plan, library: library, today: date).accessibleShares
        }
        let growth = Planner.growth(of: mix, assumptions: plan.assumptions).medianReturn
        guard growth >= 0.001 else { return nil }
        return .rounded(saving.doubleValue / growth, scale: 0)
    }
}
