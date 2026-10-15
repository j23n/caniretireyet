import Foundation
import Model
import Tracker

/// A plan's milestones as the screens show them (UI.md, "Milestones";
/// PROGRESS.md, "Milestones"): those its plan assets reached, those its
/// median future reaches, and the next with how far there.
public struct PlanMilestones: Sendable {
    public let ladder: MilestoneLadder
    /// Oldest first; Progress sets those its ``PlanProgress`` worked out.
    public var reached: [ReachedMilestone]
    /// Soonest first; empty without results.
    public let ahead: [ProjectedMilestone]
    public let next: NextMilestone?
    /// The coast age now (PLANNER.md, "Ages without"): from the results
    /// shown, else the latest check-in's record; `nil` when no age works
    /// saving nothing more, or when it isn't known (``knowsCoastAge``).
    public let coastAge: Int?
    /// Whether ``coastAge`` is known: a run looked for it, or a check-in recorded one.
    public let knowsCoastAge: Bool

    /// - Parameters:
    ///   - results: the plan's results shown, for what retiring today needs
    ///     and the median future; without them, nothing is ahead.
    ///   - reached: those reached, as Progress works them out once
    ///     (``PlanProgress``); none where only what's ahead shows (the
    ///     Plan screen, the widget).
    public init(plan: PlanDocument, library: Library, valuator: Valuator, asOf: CalendarDate, results: PlanResults?,
                reached: [ReachedMilestone] = []) {
        let recorded = Self.latestRecord(of: plan.id, library: library, asOf: asOf)
        let readiness = results?.headline.readiness.map(Readiness.rounded) ?? recorded?.readiness
        // What retiring today needs; with a readiness, the ladder works it
        // out from today's plan assets instead.
        let needed = results?.details.assetsNeeded?.amount.map { Decimal(wholeNumber: $0) }
        let ladder = MilestoneLadder(plan: plan, library: library, valuator: valuator, on: asOf, neededToday: needed)
        self.ladder = ladder
        self.reached = reached
        let current: Decimal
        let median: [SeriesPoint]
        let portfolio = results?.portfolio ?? []
        if let start = portfolio.first {
            current = Decimal(wholeNumber: start.p50)
            median = portfolio.map {
                SeriesPoint(date: CalendarDate($0.date, in: .current), value: Decimal(wholeNumber: $0.p50))
            }
        } else {
            current = valuator.total(on: asOf, in: .planAssets).total
            median = []
        }
        ahead = ladder.ahead(of: current, readiness: readiness, median: median)
        next = ladder.next(after: current, readiness: readiness)
        let coast = Self.currentCoastAge(results: results, recorded: recorded)
        coastAge = coast.age
        knowsCoastAge = coast.isKnown
    }

    /// The answer the latest check-in on or before `asOf` recorded for `plan`.
    public static func latestRecord(of plan: PlanID, library: Library, asOf: CalendarDate) -> Headline? {
        library.headlines(for: plan).filter { $0.date <= asOf }.max { $0.date < $1.date }
    }

    /// The coast age now: from `results`, else from the answer `recorded`
    /// at the latest check-in (``coastAge``); and whether it's known.
    public static func currentCoastAge(results: PlanResults?, recorded: Headline?) -> (age: Int?, isKnown: Bool) {
        if let coast = results?.details.agesWithout.coast { return (coast.earliestAge, true) }
        if let age = recorded?.coastAge { return (age, true) }
        return (nil, false)
    }

    /// When the median future reaches the next milestone; `nil` without
    /// results, or when it never does.
    public var nextDate: CalendarDate? {
        guard let next else { return nil }
        return ahead.first { $0.id == next.milestone.id }?.date
    }

    /// The milestones `plan`'s assets reached by a check-in on `date`: on
    /// its day, and at the ends of the months since the check-in before
    /// (`previous`), which are valued from what you held and its prices.
    public static func reached(by plan: PlanDocument, library: Library, valuator: Valuator,
                               since previous: CalendarDate?, through date: CalendarDate) -> [ReachedMilestone] {
        MilestoneLadder(plan: plan, library: library, valuator: valuator, on: date)
            .reached(plan: plan.id, library: library, valuator: valuator, through: date)
            .filter { milestone in
                guard milestone.date <= date else { return false }
                guard let previous else { return milestone.date == date }
                return milestone.date > previous
            }
    }

    /// The coast point, when a check-in reached it; `nil` if none did.
    public var coastPointReached: ReachedMilestone? {
        reached.last { if case .coastPoint = $0.milestone.kind { true } else { false } }
    }

    /// The kinds the plan has, in the order *All Milestones* explains them:
    /// round amounts always, the others when the ladder has them or one of
    /// them is reached, ahead or next.
    public var kinds: [PlanMilestoneKind] {
        let listed = reached.map(\.milestone) + ahead.map(\.milestone) + (next.map { [$0.milestone] } ?? [])
        let seen = Set(listed.map { PlanMilestoneKind($0.kind) })
        return PlanMilestoneKind.allCases.filter { kind in
            switch kind {
            case .roundAmount: true
            case .yearsOfSpending: ladder.spending != nil || seen.contains(kind)
            case .shareOfNeeded: ladder.neededToday != nil || seen.contains(kind)
            case .crossover: ladder.crossover != nil || seen.contains(kind)
            case .coastPoint: ladder.coastTarget != nil || seen.contains(kind)
            }
        }
    }

    /// The latest milestone of `kind` reached; `nil` if none is.
    public func latestReached(_ kind: PlanMilestoneKind) -> ReachedMilestone? {
        reached.last { PlanMilestoneKind($0.milestone.kind) == kind }
    }

    /// The soonest milestone of `kind` ahead; `nil` if none is.
    public func soonestAhead(_ kind: PlanMilestoneKind) -> ProjectedMilestone? {
        ahead.first { PlanMilestoneKind($0.milestone.kind) == kind }
    }
}

/// A kind of milestone, without its amount, years, share or age, as the
/// *All Milestones* sheet explains them (UI.md, "Milestones"), in its order.
public enum PlanMilestoneKind: CaseIterable, Hashable, Sendable {
    case roundAmount
    case yearsOfSpending
    case shareOfNeeded
    case crossover
    case coastPoint

    public init(_ kind: Milestone.Kind) {
        switch kind {
        case .roundAmount: self = .roundAmount
        case .yearsOfSpending: self = .yearsOfSpending
        case .shareOfNeeded: self = .shareOfNeeded
        case .crossover: self = .crossover
        case .coastPoint: self = .coastPoint
        }
    }
}
