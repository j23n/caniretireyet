import Foundation
import Model
import Planner
import Testing
@testable import CanIRetireYet

/// Stepping through the milestones reached on *Your way to retirement*
/// (UI.md, "Your way to retirement").
struct ReachedMilestonePagerTests {
    private let english = Locale(identifier: "en_US")

    /// Three milestones reached, oldest first.
    private let reached = [
        ReachedMilestone(milestone: Milestone(kind: .roundAmount, amount: 100_000), date: "2024-03-31"),
        ReachedMilestone(milestone: Milestone(kind: .yearsOfSpending(5), amount: 150_000), date: "2025-06-30"),
        ReachedMilestone(milestone: Milestone(kind: .shareOfNeeded(numerator: 1, denominator: 2), amount: 180_000),
                         date: "2026-08-31"),
    ]

    @Test func opensOnTheNewest() {
        let pager = ReachedMilestonePager(reached: reached)
        #expect(pager.shown?.id == "share-1-2")
        #expect(pager.showsNewest)
        #expect(pager.canStepOlder)
        #expect(!pager.canStepNewer)
        #expect(pager.label(relativeTo: "2026-10-22", locale: english) == "Last reached · August")
    }

    @Test func stepsOlderAndStopsAtTheOldest() {
        var pager = ReachedMilestonePager(reached: reached)
        pager.step(by: -1)
        #expect(pager.shown?.id == "years-5")
        #expect(!pager.showsNewest)
        #expect(pager.label(relativeTo: "2026-10-22", locale: english) == "Reached · June 2025")
        pager.step(by: -1)
        #expect(pager.shown?.id == "round-100000")
        #expect(!pager.canStepOlder)
        pager.step(by: -1)
        #expect(pager.shown?.id == "round-100000")
        #expect(pager.canStepNewer)
    }

    @Test func stepsNewerAndStopsAtTheNewest() {
        var pager = ReachedMilestonePager(reached: reached)
        pager.show(0)
        pager.step(by: 1)
        #expect(pager.shown?.id == "years-5")
        pager.step(by: 1)
        #expect(pager.shown?.id == "share-1-2")
        #expect(pager.shownID == nil)
        pager.step(by: 1)
        #expect(pager.shown?.id == "share-1-2")
        #expect(!pager.canStepNewer)
    }

    @Test func showsTheNewestOnceTheOneShownIsGone() {
        let pager = ReachedMilestonePager(reached: reached, shownID: "crossover")
        #expect(pager.shown?.id == "share-1-2")
        let none = ReachedMilestonePager(reached: [])
        #expect(none.shown == nil)
        #expect(!none.canStepOlder)
        #expect(!none.canStepNewer)
        #expect(none.label(relativeTo: "2026-10-22", locale: english) == nil)
    }
}
