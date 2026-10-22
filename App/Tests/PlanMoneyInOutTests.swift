import Foundation
import Model
import Testing
import Tracker
@testable import CanIRetireYet

/// Trends' *Your last 12 months* (UI.md, "Trends"): the tiles and their
/// changes against the 12 months before, on the example library
/// (``PreviewLibrary``: money in and out from July to September 2026,
/// measured from 30 June). What they draw is Tracker's, tested in
/// `TrackerTests`.
struct PlanMoneyInOutTests {
    private let locale = Locale(identifier: "en_US")
    private let latest = PreviewLibrary.latestCheckIn

    /// What came in and what was spent over 365 days, so what was spent a
    /// year is what was spent.
    private func savings(moneyIn: Decimal, spent: Decimal) -> SavingsRate {
        let summary = MoneyInOutSummary(from: "2025-10-01", through: "2026-09-30", currency: .eur, moneyIn: moneyIn,
                                        months: ["2026-09"], measuredFrom: "2025-09-30", lastCounted: "2026-09-30")
        return SavingsRate(moneyInOut: summary, from: "2025-09-30", through: "2026-09-30",
                           savedByAccount: ["bank": moneyIn - spent])
    }

    @Test func lessThanTwelveMonthsHasNoChanges() throws {
        let year = try #require(PlanLastTwelveMonths(valuator: PreviewLibrary.valuator, through: latest,
                                                     recordedSince: "2026-06-30"))
        #expect(year.tiles.allSatisfy { $0.change == nil })
        #expect(year.tiles[0].figure == .rate(year.current.rate))
        #expect(year.tiles[1].figure == .amount(year.current.saved))
        #expect(year.tiles[2].figure == .amount(year.current.income))
        #expect(year.tiles[3].figure == .amount(year.current.spent))
    }

    @Test func twelveMonthsAgainstTheTwelveBefore() throws {
        let year = PlanLastTwelveMonths(current: savings(moneyIn: 45_800, spent: 31_600),
                                        previous: savings(moneyIn: 44_400, spent: 32_200), since: nil)
        let changes = year.tiles.map(\.change)
        // 31% against 27%.
        #expect(changes[0] == PlanLastTwelveMonths.TileChange(value: .points(4), direction: 1, isGood: true))
        // Saved 14.200 € against 12.200 €.
        #expect(changes[1] == PlanLastTwelveMonths.TileChange(value: .amount(2_000), direction: 1, isGood: true))
        // Came in 3% more: good news.
        #expect(changes[2]?.direction == 1)
        #expect(changes[2]?.isGood == true)
        // Spent 2% less: good news too.
        #expect(changes[3]?.direction == -1)
        #expect(changes[3]?.isGood == true)

        let worse = PlanLastTwelveMonths(current: savings(moneyIn: 40_000, spent: 36_000),
                                         previous: savings(moneyIn: 45_800, spent: 31_600), since: nil)
        #expect(worse.tiles.map { $0.change?.isGood } == [false, false, false, false])
    }

    /// *Savings rate*'s summary names the months with money in and out but
    /// no bar.
    @Test func theSummaryNamesTheMonthsWithoutABar() {
        func month(_ month: YearMonth, moneyIn: Decimal, spent: Decimal) -> MoneyInOutPeriod {
            let from = month.firstDay.adding(days: -1)
            let money = MoneyInOutSummary(from: month.firstDay, through: month.lastDay, currency: .eur,
                                          moneyIn: moneyIn, months: [month], measuredFrom: from,
                                          lastCounted: month.lastDay)
            return MoneyInOutPeriod(from: month.firstDay, through: month.lastDay,
                                    savings: SavingsRate(moneyInOut: money, from: from, through: month.lastDay,
                                                         savedByAccount: ["bank": moneyIn - spent]))
        }
        let periods = [month("2026-07", moneyIn: 3_000, spent: 2_100), month("2026-08", moneyIn: 0, spent: 2_000)]
        let recorded = MoneyInOutSummary(from: "2026-07-01", through: "2026-08-31", currency: .eur,
                                         months: ["2026-07", "2026-08"], measuredFrom: "2026-06-30")
        let money = PlanMoneyInOut(MoneyInOutSeries(currency: .eur, grain: .months, periods: periods,
                                                    recorded: recorded),
                                   from: nil, firstRecord: nil, through: "2026-08-31")
        #expect(money.withoutRateWords(locale: locale) == "In Aug 2026 nothing came in, so it has no bar.")

        // Every month of the example library has a rate.
        let example = PlanMoneyInOut(PreviewLibrary.valuator.moneyInOutSeries(.months, through: latest), from: nil,
                                     firstRecord: nil, through: latest)
        #expect(example.withoutRateWords(locale: locale) == nil)
    }

    /// The plan's spending is an amount, which hides with the eye.
    @Test func spendingAgainstThePlanWhileWorking() throws {
        let year = PlanLastTwelveMonths(current: savings(moneyIn: 45_000, spent: 30_000), previous: nil, since: nil)
        // Past working: left out.
        #expect(year.spendingWords(planned: nil, locale: locale) == nil)
        #expect(year.spendingWords(planned: 36_000, locale: locale)?.hasAmounts == true)
    }
}
