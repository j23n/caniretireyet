import Foundation
import Model
import Testing
import Tracker
@testable import CanIRetireYet

/// What Trends' cards on money in and out say (UI.md, "Trends"): where it
/// starts, the last 12 months against the 12 before, and spending against
/// the plan, on the example library (``PreviewLibrary``: money in and out
/// from July to September 2026, measured from 30 June). What they draw is
/// Tracker's, tested in `TrackerTests`.
struct PlanMoneyInOutTests {
    private let locale = Locale(identifier: "en_US")
    private let latest = PreviewLibrary.latestCheckIn

    private func money(_ grain: PeriodGrain = .months, from start: CalendarDate? = nil,
                       through end: CalendarDate = PreviewLibrary.latestCheckIn) -> PlanMoneyInOut {
        let valuator = Valuator(library: PreviewLibrary.library)
        return PlanMoneyInOut(valuator.moneyInOutSeries(grain, through: end), from: start,
                              firstRecord: valuator.firstValuationDate(in: .planAssets), through: end)
    }

    /// What came in and what was spent over 365 days, so what was spent a
    /// year is what was spent.
    private func savings(moneyIn: Decimal, spent: Decimal) -> SavingsRate {
        let summary = MoneyInOutSummary(from: "2025-10-01", through: "2026-09-30", currency: .eur, moneyIn: moneyIn,
                                        months: ["2026-09"], measuredFrom: "2025-09-30", lastCounted: "2026-09-30")
        return SavingsRate(moneyInOut: summary, from: "2025-09-30", through: "2026-09-30",
                           savedByAccount: ["bank": moneyIn - spent])
    }

    @Test func saysWhereMoneyInAndOutStarts() {
        #expect(money().whereItStarts(locale: locale) == "Money in and out is recorded since Jun 30, 2026: "
            + "3 months so far.")
        // A span that starts after it doesn't say so.
        #expect(money(from: "2026-07-15").whereItStarts(locale: locale) == nil)
        #expect(money(through: "2026-06-30").whereItStarts(locale: locale) == nil)
    }

    @Test func aMonthAfterASkippedCheckInSaysWhatItCovers() throws {
        var library = PreviewLibrary.library
        library.months["2026-08"]?.valuations.removeAll { ["conto-fineco", "conto-deposito"].contains($0.account) }
        let valuator = Valuator(library: library)
        let money = PlanMoneyInOut(valuator.moneyInOutSeries(.months, through: latest), from: nil,
                                   firstRecord: valuator.firstValuationDate(in: .planAssets), through: latest)
        let september = try #require(money.periods.last)
        #expect(money.coverWords(september, locale: locale) == "covers Aug – Sep")
        let july = try #require(money.periods.first)
        #expect(money.coverWords(july, locale: locale) == nil)
    }

    // MARK: Your last 12 months

    @Test func lessThanTwelveMonthsIsTitledByWhereItStarts() throws {
        let year = try #require(PlanLastTwelveMonths(valuator: PreviewLibrary.valuator, through: latest,
                                                     recordedSince: "2026-06-30"))
        #expect(year.title(locale: locale) == "Since Jun 30, 2026")
        #expect(year.tiles.map(\.title) == ["Savings rate", "Saved", "Came in", "Spent"])
        #expect(year.tiles.allSatisfy { $0.change == nil })
        #expect(year.tiles[0].figure == .rate(year.current.rate))
        #expect(year.tiles[1].figure == .amount(year.current.saved))
        #expect(year.tiles[2].figure == .amount(year.current.income))
        #expect(year.tiles[3].figure == .amount(year.current.spent))
    }

    @Test func twelveMonthsAgainstTheTwelveBefore() throws {
        let year = PlanLastTwelveMonths(current: savings(moneyIn: 45_800, spent: 31_600),
                                        previous: savings(moneyIn: 44_400, spent: 32_200), since: nil)
        #expect(year.title(locale: locale) == "Your last 12 months")
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

        #expect(changes.map { $0?.text(currency: .eur, locale: locale) }
            == ["▲ 4 points", "▲ €2,000", "▲ 3%", "▼ 2%"])
        let same = PlanLastTwelveMonths.TileChange(value: .percent(0.001), direction: 0, isGood: true)
        #expect(same.text(currency: .eur, locale: locale) == "No change")
        let one = PlanLastTwelveMonths.TileChange(value: .points(-1), direction: -1, isGood: false)
        #expect(one.text(currency: .eur, locale: locale) == "▼ 1 point")

        let worse = PlanLastTwelveMonths(current: savings(moneyIn: 40_000, spent: 36_000),
                                         previous: savings(moneyIn: 45_800, spent: 31_600), since: nil)
        #expect(worse.tiles.map { $0.change?.isGood } == [false, false, false, false])
    }

    @Test func spendingAgainstThePlanWhileWorking() throws {
        func words(perYear: Decimal) -> String? {
            PlanLastTwelveMonths(current: savings(moneyIn: 45_000, spent: perYear), previous: nil, since: nil)
                .spendingWords(planned: 36_000, locale: locale)?.text
        }
        #expect(words(perYear: 31_680) == "Your plan spends €36,000 a year while you work: you spent 12% less.")
        #expect(words(perYear: 38_880) == "Your plan spends €36,000 a year while you work: you spent 8% more.")
        #expect(words(perYear: 36_500) == "Your plan spends €36,000 a year while you work: you spent about "
            + "the same.")
        let year = PlanLastTwelveMonths(current: savings(moneyIn: 45_000, spent: 30_000), previous: nil, since: nil)
        // Past working: left out.
        #expect(year.spendingWords(planned: nil, locale: locale) == nil)
        #expect(year.spendingWords(planned: 36_000, locale: locale)?.hasAmounts == true)
    }
}
