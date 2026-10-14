import Foundation
import Testing
@testable import CanIRetireYet

/// Trends' *Year by year* (UI.md, "Trends"; PROGRESS.md, "Trends"): what
/// you saved and spent against the year's baseline, as planned within 5%,
/// and what markets did, by the rule Progress's year words use.
struct PlanYearGradeTests {
    private func grade(putIn: Decimal = 0, plannedSaving: Decimal? = nil, spent: Decimal? = nil,
                       plannedSpending: Decimal? = nil, hasBaseline: Bool = true,
                       marketYear: MarketYear? = .average) -> PlanYearGrade {
        PlanYearGrade(year: 2025, isSoFar: false, hasBaseline: hasBaseline, putIn: putIn,
                      plannedSaving: plannedSaving, spentPerYear: spent, plannedSpending: plannedSpending,
                      markets: 0, start: 100_000, marketYear: marketYear)
    }

    // MARK: As planned within 5%

    @Test func withinFivePercentEitherWayIsAsPlanned() {
        #expect(PlanComparison(10_000, planned: 10_000) == .asPlanned)
        #expect(PlanComparison(10_500, planned: 10_000) == .asPlanned)
        #expect(PlanComparison(9_500, planned: 10_000) == .asPlanned)
    }

    @Test func pastFivePercentIsMoreOrLess() {
        #expect(PlanComparison(10_501, planned: 10_000) == .more)
        #expect(PlanComparison(9_499, planned: 10_000) == .less)
        #expect(PlanComparison.more.words == "more than planned")
        #expect(PlanComparison.asPlanned.words == "as planned")
        #expect(PlanComparison.less.words == "less than planned")
    }

    // MARK: You saved

    @Test func savedIsPutInAgainstPlannedSaving() {
        #expect(grade(putIn: 20_486, plannedSaving: 13_463).saved == .more)
        #expect(grade(putIn: 13_000, plannedSaving: 13_463).saved == .asPlanned)
        #expect(grade(putIn: 4_000, plannedSaving: 13_463).saved == .less)
    }

    @Test func noPlannedSavingIsNotGraded() {
        #expect(grade(putIn: 5_000, plannedSaving: 0).saved == nil)
        #expect(grade(putIn: 5_000, plannedSaving: -2_000).saved == nil)
        #expect(grade(putIn: 5_000).saved == nil)
    }

    // MARK: You spent

    @Test func spentIsWhatWasSpentAgainstSpendingWhileWorking() {
        #expect(grade(spent: 30_000, plannedSpending: 36_000).spent == .less)
        #expect(grade(spent: 37_000, plannedSpending: 36_000).spent == .asPlanned)
        #expect(grade(spent: 40_000, plannedSpending: 36_000).spent == .more)
    }

    @Test func spentNeedsMoneyInAndOutAndAPlanStillWorking() {
        // No money in and out recorded in the year.
        #expect(grade(plannedSpending: 36_000).spent == nil)
        // The baseline's plan was past working.
        #expect(grade(spent: 30_000).spent == nil)
    }

    // MARK: Markets

    @Test func marketsAreStrongFromEightPercentAndHardFromMinusFive() {
        #expect(MarketYear(markets: 8_000, start: 100_000) == .strong)
        #expect(MarketYear(markets: 7_999, start: 100_000) == .average)
        #expect(MarketYear(markets: -4_999, start: 100_000) == .average)
        #expect(MarketYear(markets: -5_000, start: 100_000) == .hard)
        #expect(MarketYear(markets: 1_000, start: 0) == nil)
    }

    // MARK: VoiceOver
}
