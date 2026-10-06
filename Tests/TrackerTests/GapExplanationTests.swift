import Foundation
import Model
import Testing
import Tracker

/// Why you're ahead of or behind a baseline (PROGRESS.md, "Actual vs. a
/// baseline", *Why*): the parts add up to the gap, saving and markets are
/// measured against what was planned and expected, and inflation apart.
struct GapExplanationTests {
    /// A year that started on plan (100,000 both), planning to save 12,000
    /// and expecting 5,000 from markets: you saved 10,000, markets added
    /// 3,000, a balance moved 500 without a flow, and prices rose, so the
    /// 113,500 you have is 111,200 in the baseline's money.
    @Test func thePartsAddUpToTheGap() {
        let change = ValueChange(start: 100_000, market: 3_000, newMoney: 10_000, other: 500, end: 113_500)
        let gap = GapExplanation(actual: (start: 100_000, end: 111_200), expected: (start: 100_000, end: 117_000),
                                 plannedSaving: 12_000, change: change, isInflationAdjusted: true)
        #expect(gap.start == 0)
        #expect(gap.saving == -2_000)
        #expect(gap.expectedMarket == 5_000)
        #expect(gap.markets == -2_000)
        #expect(gap.inflation == -2_300)
        #expect(gap.other == 500)
        #expect(gap.end == -5_800)
        #expect(gap.end == Decimal(111_200) - 117_000)
    }

    /// Against a baseline from an earlier year, the gap going into the year
    /// carries over; without an inflation index, what's left is other.
    @Test func aGapCarriedInAndNoInflationIndex() {
        let change = ValueChange(start: 200_000, market: 8_000, newMoney: 6_000, other: 0, end: 214_000)
        let gap = GapExplanation(actual: (start: 200_000, end: 214_100), expected: (start: 190_000, end: 205_000),
                                 plannedSaving: 6_000, change: change, isInflationAdjusted: false)
        #expect(gap.start == 10_000)
        #expect(gap.saving == 0)
        #expect(gap.markets == -1_000)
        #expect(gap.inflation == nil)
        #expect(gap.other == 100)
        #expect(gap.end == 9_100)
    }
}
