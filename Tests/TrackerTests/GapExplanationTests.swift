import Foundation
import Model
import Testing
import Tracker

/// Why you're ahead of or behind a baseline (PROGRESS.md, "Actual vs. a
/// baseline", *Why*): the parts add up to the gap, saving and markets are
/// measured against what was planned and expected, and inflation apart.
struct GapExplanationTests {
    private func d(_ string: String) -> Decimal { Decimal(fileString: string)! }

    /// A year that started on plan (100,000 both), planning to save 12,000
    /// and expecting 5,000 from markets: you saved 10,000, markets added
    /// 3,000, a balance moved 500 without a flow, and prices rose, so the
    /// 113,500 you have is 111,200 in the baseline's money.
    @Test func thePartsAddUpToTheGap() {
        let change = ValueChange(start: 100_000, market: 3_000, newMoney: 10_000, other: 500, end: 113_500)
        let gap = GapExplanation(actual: (start: 100_000, end: 111_200), expected: (start: 100_000, end: 117_000),
                                 plannedSaving: 12_000, change: change, asItWas: (start: 100_000, end: 113_500))
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
                                 plannedSaving: 6_000, change: change, asItWas: nil)
        #expect(gap.start == 10_000)
        #expect(gap.actualStart == 200_000)
        #expect(gap.expectedStart == 190_000)
        #expect(gap.saving == 0)
        #expect(gap.markets == -1_000)
        #expect(gap.inflation == nil)
        #expect(gap.other == 100)
        #expect(gap.end == 9_100)
    }

    /// The baseline started from 100,000, but the library now values that
    /// day at 112,000 (past prices filled in since): the difference is the
    /// gap at the start, not inflation, which only takes what rising prices
    /// took (127,000 as it was is 125,000 in the baseline's money).
    @Test func aStartTheLibraryNowValuesDifferently() {
        let change = ValueChange(start: 112_000, market: 6_000, newMoney: 9_000, other: 0, end: 127_000)
        let gap = GapExplanation(actual: (start: 112_000, end: 125_000), expected: (start: 100_000, end: 110_000),
                                 plannedSaving: 8_000, change: change, asItWas: (start: 112_000, end: 127_000))
        #expect(gap.start == 12_000)
        #expect(gap.saving == 1_000)
        #expect(gap.markets == 4_000)
        #expect(gap.inflation == -2_000)
        #expect(gap.other == 0)
        #expect(gap.end == 15_000)
    }

    /// From a later stretch of the baseline, inflation counts only what
    /// prices took over the stretch: the start is already in its money.
    @Test func inflationOverTheStretchOnly() {
        let change = ValueChange(start: 103_000, market: 2_000, newMoney: 5_000, other: 0, end: 110_000)
        let gap = GapExplanation(actual: (start: 100_000, end: 105_000), expected: (start: 101_000, end: 106_000),
                                 plannedSaving: 4_000, change: change, asItWas: (start: 103_000, end: 110_000))
        #expect(gap.start == -1_000)
        #expect(gap.inflation == -2_000)
        #expect(gap.other == 0)
        #expect(gap.end == Decimal(105_000) - 106_000)
    }

    /// Rounded one by one, this year's parts add up to 5.801 below plan
    /// while the gap is 5.800. In whole units each part is the difference
    /// of the rounded amounts its sentence names, and inflation takes what
    /// rounding leaves.
    @Test func inWholeUnitsThePartsStillAddUp() {
        let change = ValueChange(start: d("100000.4"), market: d("3000.4"), newMoney: d("10000.4"), other: 0,
                                 end: d("113500.6"))
        let gap = GapExplanation(actual: (start: d("100000.4"), end: d("111200.3")),
                                 expected: (start: 100_000, end: d("117000.2")), plannedSaving: d("12000.3"),
                                 change: change, asItWas: (start: d("100000.4"), end: d("113500.6")))
        #expect(gap.markets == d("-1999.5"))
        #expect(gap.other == d("499.4"))
        let whole = gap.inWholeUnits
        #expect(whole.start == 0)
        #expect(whole.saving == -2_000)
        #expect(whole.saving == whole.newMoney - whole.plannedSaving)
        #expect(whole.market == 3_000)
        #expect(whole.expectedMarket == 5_000)
        #expect(whole.markets == -2_000)
        #expect(whole.other == 499)
        #expect(whole.inflation == -2_299)
        #expect(whole.end == -5_800)
    }

    /// Without an inflation index, what rounding leaves goes to other.
    @Test func inWholeUnitsWithoutAnIndexOtherTakesWhatsLeft() {
        let change = ValueChange(start: 200_000, market: d("8000.4"), newMoney: d("6000.4"), other: 0,
                                 end: d("214100.2"))
        let gap = GapExplanation(actual: (start: d("200000.4"), end: d("214100.2")),
                                 expected: (start: 190_000, end: d("205000.4")), plannedSaving: d("6000.3"),
                                 change: change, asItWas: nil).inWholeUnits
        #expect(gap.start == 10_000)
        #expect(gap.saving == 0)
        #expect(gap.markets == -1_000)
        #expect(gap.inflation == nil)
        #expect(gap.other == 100)
        #expect(gap.end == 9_100)
    }
}
