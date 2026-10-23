import Foundation
import Model
import Testing
@testable import CanIRetireYet

/// The answer the Overview, Progress and the widgets show (`PlanStore.mainAnswer`):
/// the main plan's results, unless they're out of date with the library and
/// a check-in they didn't see recorded its answer, as the other device does
/// (UI.md, "Results are kept on the device").
@MainActor
struct LatestAnswerWiringTests {
    @Test func aCheckInTheResultsDidntSeeWinsUntilTheyRunAgain() async throws {
        let model = AppModel.preview(planEngine: PreviewPlanEngine(delay: .zero), defaults: "latest-answer-tests")
        let plans = model.plans
        let main = try #require(model.library.settings.mainPlan)
        let last = try #require(plans.recordedHeadlines(for: main).last)
        #expect(last.date == "2026-09-30")

        // Calculated from the 30 Sep check-in, whose answer is recorded.
        let first = try #require(await plans.run(main))
        #expect(first.latestCheckIn == "2026-09-30")
        #expect(plans.mainAnswer?.results == first)

        // An edit at a check-in the results saw makes them out of date,
        // but the answer recorded there isn't newer.
        try model.library.update {
            $0.upsert(Valuation(account: "conto-fineco", date: "2026-09-30", balance: 4_300))
        }
        #expect(plans.staleReasons(of: main).contains(.library))
        #expect(plans.mainAnswer?.results == first)

        // The other device saves a later check-in and records its answer.
        let later: CalendarDate = "2026-10-15"
        try model.library.update {
            $0.upsert(Valuation(account: "conto-fineco", date: later, balance: 4_500))
        }
        try model.library.record(Headline(date: later, confidence: 0.9, earliestAge: 53, engine: "other",
                                          planHash: "x", readiness: 0.3), for: main)
        #expect(plans.mainAnswer?.recorded?.date == later)
        #expect(plans.mainAnswer?.results == nil)
        #expect(plans.latestResults(of: main) == nil)

        // Calculated again, the results saw it.
        let second = try #require(await plans.run(main))
        #expect(second.latestCheckIn == later)
        #expect(plans.mainAnswer?.results == second)
        #expect(plans.mainAnswer?.recorded == nil)
    }
}
