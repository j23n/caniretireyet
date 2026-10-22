import Foundation
import Model
import Testing
import TestSupport
import Tracker

/// Trends' money in and out (UI.md, "Trends"), on the example library:
/// money in and out from July to September 2026, measured from 30 June;
/// the last 12 months against the plan; what markets did in a year.
struct PlanMoneyInOutTests {
    let library: Library
    let valuator: Valuator
    private let latest: CalendarDate = "2026-09-30"

    init() throws {
        library = try Fixtures.exampleLibrary()
        valuator = Valuator(library: library)
    }

    private func money(_ grain: PeriodGrain = .months, from start: CalendarDate? = nil,
                       through end: CalendarDate = "2026-09-30") -> PlanMoneyInOut {
        PlanMoneyInOut(valuator.moneyInOutSeries(grain, through: end), from: start,
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

    // MARK: Where it starts

    @Test func startsAtTheFirstRecordOfMoneyInAndOut() {
        let money = self.money()
        #expect(!money.isEmpty)
        #expect(money.periods.map(\.from) == ["2026-07-01", "2026-08-01", "2026-09-01"])
        #expect(money.recordedSince == "2026-06-30")
        #expect(money.recordedMonths == 3)
        #expect(money.startsInSpan)
        // A span that starts after it doesn't.
        #expect(!self.money(from: "2026-07-15").startsInSpan)
    }

    @Test func isEmptyWithoutMoneyInAndOut() {
        let money = self.money(through: "2026-06-30")
        #expect(money.isEmpty)
        #expect(money.periods.isEmpty)
        #expect(PlanLastTwelveMonths(valuator: valuator, through: "2026-06-30", recordedSince: nil) == nil)
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

    @Test func aMonthAfterASkippedCheckInCoversMore() throws {
        var library = self.library
        library.months["2026-08"]?.valuations.removeAll { ["conto-fineco", "conto-deposito"].contains($0.account) }
        let valuator = Valuator(library: library)
        let money = PlanMoneyInOut(valuator.moneyInOutSeries(.months, through: latest), from: nil,
                                   firstRecord: valuator.firstValuationDate(in: .planAssets), through: latest)
        let september = try #require(money.periods.last)
        #expect(money.coversMore(september))
        #expect(money.hasCoversMore)
        let july = try #require(money.periods.first)
        #expect(!money.coversMore(july))
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

    // MARK: The rate axis

    /// A month of what came in and was spent, as the series counts it.
    private func period(_ month: YearMonth, moneyIn: Decimal, spent: Decimal,
                        lastTwelveMonths: SavingsRate? = nil) -> MoneyInOutPeriod {
        let money = MoneyInOutSummary(from: month.firstDay, through: month.lastDay, currency: .eur, moneyIn: moneyIn,
                                      months: [month], measuredFrom: month.firstDay.adding(days: -1),
                                      lastCounted: month.lastDay)
        return MoneyInOutPeriod(from: month.firstDay, through: month.lastDay,
                                savings: SavingsRate(moneyInOut: money, from: month.firstDay.adding(days: -1),
                                                     through: month.lastDay, savedByAccount: ["bank": moneyIn - spent]),
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
        // July saves 30%, August 5 € in and 2.000 € spent: −39.900%.
        let money = series([period("2026-07", moneyIn: 3_000, spent: 2_100),
                            period("2026-08", moneyIn: 5, spent: 2_000)])
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
                                          months: ["2026-09"], measuredFrom: "2025-09-30"),
            from: "2025-09-30", through: "2026-09-30", savedByAccount: ["bank": -2_000])
        let money = series([period("2026-09", moneyIn: 3_000, spent: 2_100, lastTwelveMonths: rolling)])
        #expect(percents(money.rateAxisValues(planRate: Decimal(string: "-1.5"))) == [30, -200, -150])
        #expect(percents(money.rateAxisValues(planRate: nil)) == [30, -200])
    }

    // MARK: The 12-month line

    /// 12 months ending on `through` with what came in and what was spent.
    private func twelveMonths(through: CalendarDate, moneyIn: Decimal, spent: Decimal) -> SavingsRate {
        let from = through.adding(years: -1)
        let money = MoneyInOutSummary(from: from.adding(days: 1), through: through, currency: .eur,
                                      moneyIn: moneyIn, months: [through.yearMonth], measuredFrom: from)
        return SavingsRate(moneyInOut: money, from: from, through: through,
                           savedByAccount: ["bank": moneyIn - spent])
    }

    @Test func theLineBreaksWhereTwelveMonthsHaveNoRate() {
        // August's 12 months had nothing come in: no rate there. September's
        // is far below its bar, but stands on its own.
        let money = series([
            period("2026-06", moneyIn: 3_000, spent: 2_100,
                   lastTwelveMonths: twelveMonths(through: "2026-06-30", moneyIn: 30_000, spent: 24_000)),
            period("2026-07", moneyIn: 3_000, spent: 2_100,
                   lastTwelveMonths: twelveMonths(through: "2026-07-31", moneyIn: 27_000, spent: 24_000)),
            period("2026-08", moneyIn: 0, spent: 2_000,
                   lastTwelveMonths: twelveMonths(through: "2026-08-31", moneyIn: 0, spent: 24_000)),
            period("2026-09", moneyIn: 3_000, spent: 2_100,
                   lastTwelveMonths: twelveMonths(through: "2026-09-30", moneyIn: 3_000, spent: 24_000)),
        ])
        #expect(money.lastTwelveMonthsRuns.map { $0.map(\.from) }
            == [["2026-06-01", "2026-07-01"], ["2026-09-01"]])
        #expect(money.hasLastTwelveMonths)
    }

    @Test func theLineStartsAtTheTwelfthMonth() {
        let money = series([
            period("2026-08", moneyIn: 3_000, spent: 2_100),
            period("2026-09", moneyIn: 3_000, spent: 2_100,
                   lastTwelveMonths: twelveMonths(through: "2026-09-30", moneyIn: 30_000, spent: 24_000)),
        ])
        #expect(money.lastTwelveMonthsRuns.map { $0.map(\.from) } == [["2026-09-01"]])
        #expect(series([period("2026-09", moneyIn: 3_000, spent: 2_100)]).lastTwelveMonthsRuns.isEmpty)
    }

    @Test func aMonthWithSpendingButNothingInHasNoBar() {
        let empty = MoneyInOutPeriod(from: "2026-07-01", through: "2026-07-31", savings: nil)
        let money = series([empty,
                            period("2026-08", moneyIn: 0, spent: 2_000),
                            period("2026-09", moneyIn: 3_000, spent: 2_100)])
        // July has nothing counted, so nothing to show; August spent with nothing in.
        #expect(money.countedWithoutRate.map(\.from) == ["2026-08-01"])
        #expect(self.money().countedWithoutRate.isEmpty)
    }

    @Test func aPeriodWithoutARateSaysWhy() {
        func savings(moneyIn: Decimal, taxes: Decimal = 0, pension: Decimal = 0) -> SavingsRate {
            let money = MoneyInOutSummary(from: "2026-08-01", through: "2026-08-31", currency: .eur,
                                          moneyIn: moneyIn, taxes: taxes, months: ["2026-08"],
                                          measuredFrom: "2026-07-31")
            return SavingsRate(moneyInOut: money, from: "2026-07-31", through: "2026-08-31",
                               pensionContributions: pension, savedByAccount: ["bank": -2_000])
        }
        #expect(savings(moneyIn: 0).noRate == .nothingCameIn)
        #expect(savings(moneyIn: -500).noRate == .lessThanNothingCameIn)
        // Pension contributions count as came in.
        #expect(savings(moneyIn: -500, pension: 400).noRate == .lessThanNothingCameIn)
        #expect(savings(moneyIn: -500, pension: 500).noRate == .nothingCameIn)
        #expect(savings(moneyIn: 3_000, taxes: 4_000).noRate == .moreTaxThanCameIn)
        #expect(savings(moneyIn: 0, taxes: 100).noRate == .moreTaxThanCameIn)
        #expect(savings(moneyIn: 3_000, taxes: 3_000).noRate == .moreTaxThanCameIn)
        // With a rate, no reason.
        #expect(savings(moneyIn: 3_000, taxes: 1_000).noRate == nil)
        #expect(MoneyInOutPeriod(from: "2026-08-01", through: "2026-08-31", savings: nil).noRate == nil)
    }

    @Test func theHiddenAxisIsInMultiplesOfTheAverageCameIn() throws {
        let money = self.money()
        let base = try #require(money.relativeBase)
        let average = money.counted.reduce(0.0) { $0 + $1.cameIn.doubleValue } / Double(money.counted.count)
        #expect(abs(base - average) < 0.001)
    }

    // MARK: Your last 12 months

    @Test func lessThanTwelveMonthsCountsFromWhereItStarts() throws {
        let year = try #require(PlanLastTwelveMonths(valuator: valuator, through: latest,
                                                     recordedSince: "2026-06-30"))
        #expect(year.since == "2026-06-30")
        // Less than two years: nothing to compare with.
        #expect(year.previous == nil)
    }

    @Test func spendingAgainstThePlanWhileWorking() {
        func difference(perYear: Decimal) -> Decimal? {
            PlanLastTwelveMonths(current: savings(moneyIn: 45_000, spent: perYear), previous: nil, since: nil)
                .spendingDifference(planned: 36_000)?.rounded(4)
        }
        // 12% less, 8% more.
        #expect(difference(perYear: 31_680) == Decimal(string: "-0.12"))
        #expect(difference(perYear: 38_880) == Decimal(string: "0.08"))
        // Within 2%: the same.
        #expect(difference(perYear: 36_500) == 0)
        // Past working: nothing to compare with.
        let year = PlanLastTwelveMonths(current: savings(moneyIn: 45_000, spent: 30_000), previous: nil, since: nil)
        #expect(year.spendingDifference(planned: nil) == nil)
    }

    // MARK: Markets

    @Test func marketsAreStrongFromEightPercentAndHardFromMinusFive() {
        #expect(MarketYear(markets: 8_000, start: 100_000) == .strong)
        #expect(MarketYear(markets: 7_999, start: 100_000) == .average)
        #expect(MarketYear(markets: -4_999, start: 100_000) == .average)
        #expect(MarketYear(markets: -5_000, start: 100_000) == .hard)
        #expect(MarketYear(markets: 1_000, start: 0) == nil)
    }
}
