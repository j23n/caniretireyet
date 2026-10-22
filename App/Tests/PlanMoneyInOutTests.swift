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

    /// What came in, was taxed and was spent between `from` (exclusive) and
    /// `through`.
    private func savings(from: CalendarDate, through: CalendarDate, moneyIn: Decimal, taxes: Decimal = 0,
                         spent: Decimal) -> SavingsRate {
        let money = MoneyInOutSummary(from: from.adding(days: 1), through: through, currency: .eur,
                                      moneyIn: moneyIn, taxes: taxes, months: [through.yearMonth],
                                      measuredFrom: from, lastCounted: through)
        return SavingsRate(moneyInOut: money, from: from, through: through,
                           savedByAccount: ["bank": moneyIn - taxes - spent])
    }

    /// A month, with the 12 months ending at it when `twelveMonthsIn` is
    /// given (24.000 € spent over them).
    private func month(_ month: YearMonth, moneyIn: Decimal, taxes: Decimal = 0, spent: Decimal,
                       twelveMonthsIn: Decimal? = nil) -> MoneyInOutPeriod {
        MoneyInOutPeriod(
            from: month.firstDay, through: month.lastDay,
            savings: savings(from: month.firstDay.adding(days: -1), through: month.lastDay, moneyIn: moneyIn,
                             taxes: taxes, spent: spent),
            lastTwelveMonths: twelveMonthsIn.map {
                savings(from: month.lastDay.adding(years: -1), through: month.lastDay, moneyIn: $0, spent: 24_000)
            })
    }

    private func series(_ periods: [MoneyInOutPeriod]) -> PlanMoneyInOut {
        let through = periods.last?.through ?? latest
        let recorded = MoneyInOutSummary(from: periods.first?.from ?? latest, through: through, currency: .eur,
                                         months: periods.map(\.from.yearMonth),
                                         measuredFrom: periods.first?.from.adding(days: -1))
        return PlanMoneyInOut(MoneyInOutSeries(currency: .eur, grain: .months, periods: periods, recorded: recorded),
                              from: nil, firstRecord: nil, through: through)
    }

    /// *Savings rate*'s summary names the months with money in and out but
    /// no bar, each with why.
    @Test func theSummaryNamesTheMonthsWithoutABar() {
        let money = series([month("2026-07", moneyIn: 3_000, spent: 2_100),
                            month("2026-08", moneyIn: 0, spent: 2_000)])
        #expect(money.withoutRateWords(locale: locale) == "No rate in Aug 2026 (nothing came in), so it has no bar.")
        #expect(money.lineWords() == nil)

        // Every month of the example library has a rate.
        let example = PlanMoneyInOut(PreviewLibrary.valuator.moneyInOutSeries(.months, through: latest), from: nil,
                                     firstRecord: nil, through: latest)
        #expect(example.withoutRateWords(locale: locale) == nil)
    }

    /// With the line drawn, the summary says what was spent counts in it,
    /// and says the line has a gap only when it breaks.
    @Test func theSummaryDescribesTheLineAndItsGaps() {
        // One run: the 12 months ending at July still had money come in.
        let unbroken = series([month("2026-06", moneyIn: 3_000, spent: 2_100, twelveMonthsIn: 30_000),
                               month("2026-07", moneyIn: 0, spent: 2_000, twelveMonthsIn: 27_000)])
        #expect(unbroken.lineWords() == "A line shows the rate over the 12 months ending at each month.")
        #expect(unbroken.withoutRateWords(locale: locale)
            == "No rate in Jul 2026 (nothing came in), so it has no bar; "
            + "what was spent then counts in the rate over 12 months.")

        // August's 12 months have nothing come in, so the line breaks there.
        let broken = series([
            month("2026-06", moneyIn: 3_000, spent: 2_100, twelveMonthsIn: 30_000),
            month("2026-07", moneyIn: 0, spent: 2_000, twelveMonthsIn: 27_000),
            month("2026-08", moneyIn: 3_000, taxes: 4_000, spent: 2_000, twelveMonthsIn: 0),
            month("2026-09", moneyIn: 3_000, spent: 2_100, twelveMonthsIn: 3_000),
            month("2026-10", moneyIn: -500, spent: 1_000, twelveMonthsIn: 3_000),
        ])
        #expect(broken.lineWords() == "A line shows the rate over the 12 months ending at each month, "
            + "with a gap where those 12 months have no rate.")
        #expect(broken.withoutRateWords(locale: locale)
            == "No rate in Jul 2026 (nothing came in), Aug 2026 (more tax than came in) "
            + "and Oct 2026 (less than nothing came in), so they have no bar; "
            + "what was spent then counts in the rate over 12 months.")
    }

    /// The plan's spending is an amount, which hides with the eye.
    @Test func spendingAgainstThePlanWhileWorking() throws {
        let year = PlanLastTwelveMonths(current: savings(moneyIn: 45_000, spent: 30_000), previous: nil, since: nil)
        // Past working: left out.
        #expect(year.spendingWords(planned: nil, locale: locale) == nil)
        #expect(year.spendingWords(planned: 36_000, locale: locale)?.hasAmounts == true)
    }
}
