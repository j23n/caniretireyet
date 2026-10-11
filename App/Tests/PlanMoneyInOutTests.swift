import Foundation
import Model
import Testing
import Tracker
@testable import CanIRetireYet

/// Trends' cards on money in and out (UI.md, "Trends"): where it starts, the
/// last 12 months against the 12 before, and the plan's references, on the
/// example library (``PreviewLibrary``: money in and out from July to
/// September 2026, measured from 30 June; the base plan pays 40.000 € a year
/// in 2026 and spends 36.000 € while working).
struct PlanMoneyInOutTests {
    private let locale = Locale(identifier: "en_US")
    private let latest = PreviewLibrary.latestCheckIn

    private func money(_ grain: PeriodGrain = .months, from start: CalendarDate? = nil,
                       through end: CalendarDate = PreviewLibrary.latestCheckIn) -> PlanMoneyInOut {
        let valuator = Valuator(library: PreviewLibrary.library)
        return PlanMoneyInOut(valuator.moneyInOutSeries(grain, through: end), from: start,
                              firstRecord: valuator.firstValuationDate(in: .planAssets), through: end)
    }

    private func savings(moneyIn: Decimal, moneyOut: Decimal, pensions: Decimal = 0,
                         perYear: Decimal? = nil) -> SavingsRate {
        let summary = MoneyInOutSummary(from: "2025-10-01", through: "2026-09-30", currency: .eur, moneyIn: moneyIn,
                                        moneyOut: moneyOut, months: ["2026-09"], moneyOutPerYear: perYear ?? moneyOut,
                                        measuredFrom: "2025-09-30", lastCounted: "2026-09-30")
        return SavingsRate(moneyInOut: summary, from: "2025-09-30", through: "2026-09-30",
                           pensionContributions: pensions)
    }

    // MARK: Where it starts

    @Test func saysWhereMoneyInAndOutStarts() throws {
        let money = self.money()
        #expect(!money.isEmpty)
        #expect(money.periods.map(\.from) == ["2026-07-01", "2026-08-01", "2026-09-01"])
        #expect(money.recordedSince == "2026-06-30")
        // The history goes back to October 2025.
        #expect(money.whereItStarts(locale: locale) == "Money in and out is recorded since Jun 30, 2026: "
            + "3 months so far.")
        // A span that starts after it doesn't say so.
        #expect(self.money(from: "2026-07-15").whereItStarts(locale: locale) == nil)
    }

    @Test func foldsWithoutMoneyInAndOut() {
        let money = self.money(through: "2026-06-30")
        #expect(money.isEmpty)
        #expect(money.periods.isEmpty)
        #expect(money.whereItStarts(locale: locale) == nil)
        #expect(PlanLastTwelveMonths(valuator: Valuator(library: PreviewLibrary.library), through: "2026-06-30",
                                     recordedSince: nil) == nil)
    }

    @Test func theCurrentPeriodIsSoFar() throws {
        let months = money(through: "2026-10-10")
        let october = try #require(months.periods.last)
        let july = try #require(months.periods.first)
        #expect(months.isSoFar(october))
        #expect(!months.isSoFar(july))
        let years = money(.years)
        let thisYear = try #require(years.periods.last)
        #expect(years.isSoFar(thisYear))
        // September ends on its last day.
        let throughSeptember = money()
        let september = try #require(throughSeptember.periods.last)
        #expect(!throughSeptember.isSoFar(september))
    }

    @Test func aMonthAfterASkippedCheckInSaysWhatItCovers() throws {
        var library = PreviewLibrary.library
        library.months["2026-08"]?.valuations.removeAll { ["conto-fineco", "conto-deposito"].contains($0.account) }
        let valuator = Valuator(library: library)
        let money = PlanMoneyInOut(valuator.moneyInOutSeries(.months, through: latest), from: nil,
                                   firstRecord: valuator.firstValuationDate(in: .planAssets), through: latest)
        let september = try #require(money.periods.last)
        #expect(money.coversMore(september))
        #expect(money.hasCoversMore)
        #expect(money.coverWords(september, locale: locale) == "covers Aug – Sep")
        let july = try #require(money.periods.first)
        #expect(money.coverWords(july, locale: locale) == nil)
    }

    @Test func eachPeriodSpansItsWholeMonthOrYear() throws {
        let money = self.money(through: "2026-10-10")
        let october = try #require(money.periods.last)
        let span = money.timeSpan(of: october)
        #expect(span == CalendarDate("2026-10-01").dateValue...CalendarDate("2026-11-01").dateValue)
        let domain = try #require(money.domain)
        #expect(domain.lowerBound == CalendarDate("2026-07-01").dateValue)
        #expect(domain.upperBound == span.upperBound)
        #expect(money.period(nearest: CalendarDate("2026-08-20").dateValue)?.from == "2026-08-01")
        #expect(PlanMoneyInOut.date(0.5, across: span) > CalendarDate("2026-10-15").dateValue)
        let years = self.money(.years)
        let year = try #require(years.periods.first)
        #expect(years.timeSpan(of: year).upperBound == CalendarDate("2027-01-01").dateValue)
    }

    /// A month of money in and out, as the series counts it.
    private func period(_ month: YearMonth, moneyIn: Decimal, moneyOut: Decimal,
                        lastTwelveMonths: SavingsRate? = nil) -> MoneyInOutPeriod {
        let money = MoneyInOutSummary(from: month.firstDay, through: month.lastDay, currency: .eur, moneyIn: moneyIn,
                                      moneyOut: moneyOut, months: [month],
                                      measuredFrom: month.firstDay.adding(days: -1), lastCounted: month.lastDay)
        return MoneyInOutPeriod(from: month.firstDay, through: month.lastDay,
                                savings: SavingsRate(moneyInOut: money, from: month.firstDay.adding(days: -1),
                                                     through: month.lastDay),
                                lastTwelveMonths: lastTwelveMonths)
    }

    private func series(_ periods: [MoneyInOutPeriod]) -> PlanMoneyInOut {
        let recorded = MoneyInOutSummary(from: "2026-07-01", through: "2026-09-30", currency: .eur,
                                         months: periods.map(\.from.yearMonth), measuredFrom: "2026-06-30")
        let series = MoneyInOutSeries(currency: .eur, grain: .months, periods: periods, recorded: recorded)
        return PlanMoneyInOut(series, from: nil, firstRecord: nil, through: "2026-09-30")
    }

    /// Fractions to whole percentages, so a decimal's conversion doesn't matter.
    private func percents(_ values: [Double]) -> [Int] {
        values.map { Int(($0 * 100).rounded()) }
    }

    @Test func theRateAxisFitsBarsWithinAHundredPercent() {
        // July keeps 30%, August 5 € in and 2.000 € out: −39.900%.
        let money = series([period("2026-07", moneyIn: 3_000, moneyOut: 2_100),
                            period("2026-08", moneyIn: 5, moneyOut: 2_000)])
        let values = money.rateAxisValues(planRate: Decimal(string: "0.1"))
        #expect(percents(values) == [30, -100, 10])
        #expect(values.min() == -PlanMoneyInOut.rateAxisLimit)
        // The bar is drawn to the axis's edge.
        #expect(PlanMoneyInOut.clampedRate(-399, to: -105...35) == -105)
        #expect(PlanMoneyInOut.clampedRate(30, to: -105...35) == 30)
    }

    @Test func theRateAxisAlwaysFitsTheLineAndThePlansRate() {
        // A rate over the last 12 months below −100%, and a plan that spends more than its pay.
        let rolling = SavingsRate(
            moneyInOut: MoneyInOutSummary(from: "2025-10-01", through: "2026-09-30", currency: .eur, moneyIn: 1_000,
                                          moneyOut: 3_000, months: ["2026-09"], measuredFrom: "2025-09-30"),
            from: "2025-09-30", through: "2026-09-30")
        let money = series([period("2026-09", moneyIn: 3_000, moneyOut: 2_100, lastTwelveMonths: rolling)])
        #expect(percents(money.rateAxisValues(planRate: Decimal(string: "-1.5"))) == [30, -200, -150])
        #expect(percents(money.rateAxisValues(planRate: nil)) == [30, -200])
    }

    @Test func theHiddenAxisIsInMultiplesOfTheAverageCameIn() throws {
        let money = self.money()
        let base = try #require(money.relativeBase)
        let average = money.counted.reduce(0.0) { $0 + $1.cameIn.doubleValue } / Double(money.counted.count)
        #expect(abs(base - average) < 0.001)
    }

    // MARK: Your last 12 months

    @Test func lessThanTwelveMonthsIsTitledByWhereItStarts() throws {
        let year = try #require(PlanLastTwelveMonths(valuator: PreviewLibrary.valuator, through: latest,
                                                     recordedSince: "2026-06-30"))
        #expect(year.since == "2026-06-30")
        #expect(year.title(locale: locale) == "Since Jun 30, 2026")
        // Less than two years: no change.
        #expect(year.previous == nil)
        #expect(year.tiles.map(\.title) == ["Savings rate", "Kept", "Came in", "Went out"])
        #expect(year.tiles.allSatisfy { $0.change == nil })
        #expect(year.tiles[0].figure == .rate(year.current.rate))
        #expect(year.tiles[1].figure == .amount(year.current.saved))
        #expect(year.tiles[2].figure == .amount(year.current.income))
        #expect(year.tiles[3].figure == .amount(year.current.moneyInOut.moneyOut))
    }

    @Test func twelveMonthsAgainstTheTwelveBefore() throws {
        let year = PlanLastTwelveMonths(current: savings(moneyIn: 45_800, moneyOut: 31_600),
                                        previous: savings(moneyIn: 44_400, moneyOut: 32_200), since: nil)
        #expect(year.title(locale: locale) == "Your last 12 months")
        let changes = year.tiles.map(\.change)
        // 31% against 27%.
        #expect(changes[0] == PlanLastTwelveMonths.TileChange(value: .points(4), direction: 1, isGood: true))
        // Kept 14.200 € against 12.200 €.
        #expect(changes[1] == PlanLastTwelveMonths.TileChange(value: .amount(2_000), direction: 1, isGood: true))
        // Came in 3% more: good news.
        #expect(changes[2]?.direction == 1)
        #expect(changes[2]?.isGood == true)
        // Went out 2% less: good news too.
        #expect(changes[3]?.direction == -1)
        #expect(changes[3]?.isGood == true)

        #expect(changes.map { $0?.text(currency: .eur, locale: locale) }
            == ["▲ 4 points", "▲ €2,000", "▲ 3%", "▼ 2%"])
        let same = PlanLastTwelveMonths.TileChange(value: .percent(0.001), direction: 0, isGood: true)
        #expect(same.text(currency: .eur, locale: locale) == "No change")
        let one = PlanLastTwelveMonths.TileChange(value: .points(-1), direction: -1, isGood: false)
        #expect(one.text(currency: .eur, locale: locale) == "▼ 1 point")

        let worse = PlanLastTwelveMonths(current: savings(moneyIn: 40_000, moneyOut: 36_000),
                                         previous: savings(moneyIn: 45_800, moneyOut: 31_600), since: nil)
        #expect(worse.tiles.map { $0.change?.isGood } == [false, false, false, false])
    }

    @Test func spendingAgainstThePlanWhileWorking() throws {
        func words(perYear: Decimal) -> String? {
            PlanLastTwelveMonths(current: savings(moneyIn: 45_000, moneyOut: perYear, perYear: perYear),
                                 previous: nil, since: nil)
                .spendingWords(planned: 36_000, locale: locale)?.text
        }
        #expect(words(perYear: 31_680) == "Your plan spends €36,000 a year while you work: you spent 12% less.")
        #expect(words(perYear: 38_880) == "Your plan spends €36,000 a year while you work: you spent 8% more.")
        #expect(words(perYear: 36_500) == "Your plan spends €36,000 a year while you work: you spent about "
            + "the same.")
        let year = PlanLastTwelveMonths(current: savings(moneyIn: 45_000, moneyOut: 30_000), previous: nil, since: nil)
        // Past working: left out.
        #expect(year.spendingWords(planned: nil, locale: locale) == nil)
        #expect(year.spendingWords(planned: 36_000, locale: locale)?.hasAmounts == true)
    }

    // MARK: The plan's references

    @Test func thePlansSpendingAndSavingsRateWhileWorking() throws {
        let plan = try #require(PreviewLibrary.library.plans["base"])
        let birth = PreviewLibrary.library.settings.person?.birthDate
        let reference = PlanMoneyReference(plan: plan, on: latest, earliestAge: nil, birthDate: birth)
        #expect(reference.spendingWhileWorking == 36_000)
        #expect(reference.spending(per: .months) == 3_000)
        #expect(reference.spending(per: .years) == 36_000)
        // 40.000 € of pay, 36.000 € spent: 10%.
        #expect(reference.savingsRate == Decimal(string: "0.1"))

        // Before any work phase: no rate, though it still works later.
        let before = PlanMoneyReference(plan: plan, on: "2025-12-31", earliestAge: nil, birthDate: birth)
        #expect(before.savingsRate == nil)
        #expect(before.spendingWhileWorking == 36_000)

        // Every work phase over: past working.
        var retired = plan
        retired.work = [WorkPhase(from: "2020-01-01", until: .date("2025-12-31"), netIncome: 40_000)]
        let past = PlanMoneyReference(plan: retired, on: latest, earliestAge: nil, birthDate: birth)
        #expect(past.spendingWhileWorking == nil)
        #expect(past.spending(per: .months) == nil)
        #expect(past.savingsRate == nil)

        #expect(PlanMoneyReference(plan: nil, on: latest, earliestAge: nil, birthDate: birth)
            == PlanMoneyReference(spendingWhileWorking: nil, savingsRate: nil))
    }
}
