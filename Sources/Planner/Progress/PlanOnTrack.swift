import Foundation
import Model
import Tracker

/// Whether you're on track (UI.md, "On track?"), as the Overview shows it:
/// where the latest check-in stands against its year's baseline, as
/// Progress's latest year has it
/// (``PlanProgressYear/latestPosition(for:library:valuator:asOf:)``), and
/// the coast age while you're past the coast point.
public struct PlanOnTrack: Hashable, Sendable {
    /// Where the latest check-in stands; `nil` without a baseline to
    /// measure it against.
    public var position: PlanBaselineComparison.Position?
    /// The baseline the latest check-in's year is measured against
    /// (``PlanProgressYear/latestBaseline(for:library:valuator:asOf:)``),
    /// and that check-in; `nil` without one.
    public var baseline: PlanBaselineEntry?
    public var checkIn: CalendarDate?
    /// The coast age (PLANNER.md, "Ages without") while it's at or under
    /// the age the first pension starts, as Progress's Milestones card has
    /// it (``MilestoneLadder/isPastCoastPoint(_:plan:)``); `nil` otherwise,
    /// and when you could retire today.
    public var coastAge: Int?

    /// - Parameter results: the plan's latest results, for the coast age;
    ///   without them, the one the latest check-in recorded.
    public init(plan: PlanDocument, library: Library, valuator: Valuator, asOf: CalendarDate, results: PlanResults?,
                canRetireNow: Bool) {
        if let latest = PlanProgressYear.latestBaseline(for: plan.id, library: library, valuator: valuator,
                                                        asOf: asOf) {
            baseline = latest.entry
            checkIn = latest.checkIn
            position = PlanProgressYear.latestPosition(for: plan.id, library: library, valuator: valuator, asOf: asOf)
        }
        let recorded = PlanMilestones.latestRecord(of: plan.id, library: library, asOf: asOf)
        let coast = PlanMilestones.currentCoastAge(results: results, recorded: recorded).age
        if !canRetireNow, MilestoneLadder.isPastCoastPoint(coast, plan: plan) {
            coastAge = coast
        }
    }
}
