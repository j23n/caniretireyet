import Foundation
import Glance
import Model
import Planner
import Testing
@testable import CanIRetireYet

/// Today's tiles (UI.md, "Tiles"), on the example library
/// (``PreviewLibrary``): which state the milestone tile shows, and the
/// values of the net worth tile's line.
struct TodayTilesTests {
    private let latest = PreviewLibrary.latestCheckIn

    private func milestones(reached: [ReachedMilestone] = []) throws -> PlanMilestones {
        let library = PreviewLibrary.library
        let plan = try #require(library.plans["base"])
        return PlanMilestones(plan: plan, library: library, valuator: PreviewLibrary.valuator, asOf: latest,
                              results: nil, reached: reached)
    }

    @Test func aMilestonePassedAtTheLatestCheckInComesBeforeTheNext() throws {
        let reached = [
            ReachedMilestone(milestone: Milestone(kind: .roundAmount, amount: 250_000), date: "2026-08-31"),
            ReachedMilestone(milestone: Milestone(kind: .roundAmount, amount: 300_000), date: "2026-09-30"),
        ]
        let milestones = try milestones(reached: reached)
        // Both since the check-in on 31 July: the newest leads, the other follows.
        let content = MilestoneTileContent(milestones, hasResults: false, latestCheckIn: latest,
                                           previousCheckIn: "2026-07-31", assetsBefore: nil)
        guard case .passed(let newest, let also, _) = content else {
            Issue.record("Expected the milestones passed, got \(content)")
            return
        }
        #expect(newest.id == "round-300000")
        #expect(also.map(\.id) == ["round-250000"])
        // At the check-in after, none is passed since: the tile shows what's next.
        let later = MilestoneTileContent(milestones, hasResults: false, latestCheckIn: "2026-10-31",
                                         previousCheckIn: latest, assetsBefore: nil)
        if case .passed = later {
            Issue.record("Expected the next milestone, got \(later)")
        }
    }

    @Test func theFaintBarShowsOnlyWhenItWasFurtherBefore() throws {
        let milestones = try milestones()
        let next = try #require(milestones.next)
        let amount = next.milestone.amount
        func before(_ assets: Decimal) -> (progress: Double, date: CalendarDate)? {
            let content = MilestoneTileContent(milestones, hasResults: false, latestCheckIn: latest,
                                               previousCheckIn: "2026-08-31", assetsBefore: assets)
            guard case .next(_, _, _, _, let before) = content else {
                Issue.record("Expected the next milestone, got \(content)")
                return nil
            }
            return before
        }
        // Behind where it is now, or within half a point of it: no faint bar.
        #expect(before(0) == nil)
        #expect(before(amount * Decimal(next.progress + 0.004)) == nil)
        // All the way there before (markets fell back since): the faint bar is full.
        if PlanMilestones.progress(toward: next.milestone, assets: amount) != nil, next.progress < 0.995 {
            let further = before(amount)
            #expect(further?.progress == 1)
            #expect(further?.date == "2026-08-31")
        } else {
            #expect(before(amount) == nil)
        }
    }

    @Test func theNetWorthLineEndsToday() {
        let history = [GlancePoint(date: "2026-08-31", value: 100), GlancePoint(date: "2026-09-30", value: 110)]
        var netWorth = NetWorthGlance(date: "2026-09-30", total: 110, isComplete: true, sinceLastCheckIn: nil,
                                      thisYear: nil, history: history)
        #expect(NetWorthTile.values(netWorth) == [100, 110])
        // Weeks after the last month end, today's value closes the line.
        netWorth.date = "2026-10-24"
        netWorth.total = 115
        #expect(NetWorthTile.values(netWorth) == [100, 110, 115])
    }
}
