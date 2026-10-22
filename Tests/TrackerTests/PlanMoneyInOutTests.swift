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

    /// A month of what came in and was spent, as the series counts it, its
    /// values covering the `covering` months that end with it.
    private func period(_ month: YearMonth, moneyIn: Decimal, spent: Decimal, covering: Int = 1,
                        lastTwelveMonths: SavingsRate? = nil) -> MoneyInOutPeriod {
        let first = month.adding(months: 1 - covering).firstDay
        let money = MoneyInOutSummary(from: first, through: month.lastDay, currency: .eur, moneyIn: moneyIn,
                                      months: [month], measuredFrom: first.adding(days: -1),
                                      lastCounted: month.lastDay)
        return MoneyInOutPeriod(from: month.firstDay, through: month.lastDay,
                                savings: SavingsRate(moneyInOut: money, from: first.adding(days: -1),
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

    @Test func theRateAxisFitsBarsAroundTheTypicalRate() {
        // July saves 30%, August 25%, September 5 € in and 2.000 € spent: −39.900%.
        let money = series([period("2026-07", moneyIn: 3_000, spent: 2_100),
                            period("2026-08", moneyIn: 4_000, spent: 3_000),
                            period("2026-09", moneyIn: 5, spent: 2_000)])
        // Typically 25%, give or take 50 points, and 50 points below zero.
        #expect(money.rateAxisBands.allSatisfy { $0 == -0.5...0.75 })
        let values = money.rateAxisValues(planRate: Decimal(string: "0.1"))
        #expect(percents(values) == [30, 25, -50, 10])
        #expect(money.cutsRates(planRate: Decimal(string: "0.1")))
        // The bar is drawn to the axis's edge.
        let domain = money.rateScale(planRate: Decimal(string: "0.1")).domain
        #expect(domain.lowerBound > -60)
        #expect(PlanMoneyInOut.clamped(-39_900, to: domain) == domain.lowerBound)
        #expect(PlanMoneyInOut.clamped(30, to: domain) == 30)
    }

    @Test func theRateAxisKeepsRatesThatVaryTogether() {
        // A rate that swings from −40% to 70% month to month isn't cut.
        let money = series([period("2026-05", moneyIn: 3_000, spent: 4_200),
                            period("2026-06", moneyIn: 3_000, spent: 900),
                            period("2026-07", moneyIn: 3_000, spent: 2_100),
                            period("2026-08", moneyIn: 3_000, spent: 3_300)])
        #expect(percents(money.rateAxisValues(planRate: nil)) == [-40, 70, 30, -10])
        #expect(!money.cutsRates(planRate: nil))
    }

    @Test func theRateAxisKeepsTheLineToTheBarsBandButAlwaysFitsThePlansRate() {
        // Over the 12 months ending in September 1.000 € came in and 3.300 € was spent:
        // −230%. August had nothing in, so no bar; what it spent pulls its 12 months to −150%.
        // And a plan that spends more than its pay.
        func rolling(through: CalendarDate, saved: Decimal) -> SavingsRate {
            SavingsRate(moneyInOut: MoneyInOutSummary(from: through.adding(years: -1).adding(days: 1),
                                                      through: through, currency: .eur, moneyIn: 1_000,
                                                      months: [through.yearMonth],
                                                      measuredFrom: through.adding(years: -1)),
                        from: through.adding(years: -1), through: through, savedByAccount: ["bank": saved])
        }
        let money = series([
            period("2026-07", moneyIn: 4_000, spent: 3_000),
            period("2026-08", moneyIn: 0, spent: 2_000,
                   lastTwelveMonths: rolling(through: "2026-08-31", saved: -1_500)),
            period("2026-09", moneyIn: 4_000, spent: 3_000,
                   lastTwelveMonths: rolling(through: "2026-09-30", saved: -2_300)),
        ])
        // Typically 25%, give or take 50 points; August takes July's band.
        #expect(money.rateAxisBands == [-0.5...0.75, -0.5...0.75, -0.5...0.75])
        #expect(percents(money.rateAxisValues(planRate: Decimal(string: "-1.5"))) == [25, 25, -50, -50, -150])
        #expect(percents(money.rateAxisValues(planRate: nil)) == [25, 25, -50, -50])
        #expect(money.cutsRates(planRate: nil))
        // The plan's rate is in view, and the line beyond it still cut.
        let domain = money.rateScale(planRate: Decimal(string: "-1.5")).domain
        #expect(domain.contains(-150))
        #expect(money.cutsRates(planRate: Decimal(string: "-1.5")))
        // Without a rate anywhere, nothing is kept.
        let none = series([period("2026-08", moneyIn: 0, spent: 2_000,
                                  lastTwelveMonths: rolling(through: "2026-08-31", saved: -1_500))])
        #expect(none.rateAxisBands == [nil])
        #expect(percents(none.rateAxisValues(planRate: nil)) == [-150])
    }

    /// A month for each of `amounts`, what came in and what was spent, from January 2025.
    private func months(_ amounts: [(moneyIn: Decimal, spent: Decimal)]) -> PlanMoneyInOut {
        let january: YearMonth = "2025-01"
        return series(amounts.enumerated().map { index, amount in
            period(january.adding(months: index), moneyIn: amount.moneyIn, spent: amount.spent)
        })
    }

    @Test func oneLargeMonthDoesNotStretchTheAmountAxis() {
        // 4.000 € in and 2.800 € spent a month; in June an inheritance of 100.000 €, in
        // September a car for 40.000 €.
        var amounts = [(moneyIn: Decimal, spent: Decimal)](repeating: (4_000, 2_800), count: 12)
        amounts[5] = (104_000, 2_800)
        amounts[8] = (4_000, 40_000)
        let money = months(amounts)
        // Typically 4.000 € came in: the axis fits 2.5 times that either side of zero.
        #expect(money.amountAxisLimits.allSatisfy { $0 == 10_000 })
        let values = money.amountAxisValues(planSpending: 3_000)
        #expect(values.max() == 10_000)
        #expect(values.min() == -10_000)
        // The plan's spending is always in view.
        #expect(values.last == 3_000)
        #expect(money.amountScale(planSpending: 3_000).domain.upperBound < 12_000)
        #expect(money.cutsAmounts(planSpending: 3_000))
        // Without them nothing is cut, and the axis fits the values themselves.
        let usual = months([(moneyIn: Decimal, spent: Decimal)](repeating: (4_000, 2_800), count: 12))
        #expect(!usual.cutsAmounts(planSpending: 3_000))
        #expect(usual.amountAxisValues(planSpending: nil).max() == 4_000)
    }

    @Test func thePlansSpendingIsNeverCut() {
        let money = months([(moneyIn: Decimal, spent: Decimal)](repeating: (4_000, 2_800), count: 3))
        let values = money.amountAxisValues(planSpending: 50_000)
        #expect(values.max() == 50_000)
        #expect(money.amountScale(planSpending: 50_000).domain.contains(50_000))
    }

    @Test func theAmountAxisFollowsWhatsTypicalAroundEachMonth() {
        // A year at 2.000 € in, then a year at 6.000 €; in the first month a bonus of 9.000 €.
        var amounts = [(moneyIn: Decimal, spent: Decimal)](repeating: (2_000, 1_500), count: 12)
            + [(moneyIn: Decimal, spent: Decimal)](repeating: (6_000, 4_500), count: 12)
        amounts[0] = (9_000, 1_500)
        let money = months(amounts)
        let limits = money.amountAxisLimits
        #expect(limits.first == 5_000)
        #expect(limits.last == 15_000)
        // The bonus and what it saved are kept to the first year's limit, so the axis
        // fits the second year's months and the bonus is cut.
        let values = money.amountAxisValues(planSpending: nil)
        #expect(Array(values.prefix(3)) == [5_000, 1_500, 5_000])
        #expect(values.max() == 6_000)
        #expect(money.cutsAmounts(planSpending: nil))
    }

    @Test func aPeriodThatHoldsMoreIsComparedWithAsManyTypicalMonths() throws {
        // 4.000 € in and 2.800 € spent a month through June, then a check-in each quarter:
        // September and December each hold three months' money.
        let january: YearMonth = "2025-01"
        let money = series((0..<6).map { period(january.adding(months: $0), moneyIn: 4_000, spent: 2_800) }
            + [period("2025-09", moneyIn: 12_000, spent: 8_400, covering: 3),
               period("2025-12", moneyIn: 12_000, spent: 8_400, covering: 3)])
        let december = try #require(money.counted.last)
        #expect(money.coversMore(december))
        #expect(abs(money.length(of: december) - 3) < 0.05)
        #expect(money.length(of: money.counted[0]) == 1)
        // Typically 4.000 € came in a month: a month fits 10.000 €, a quarter three times that.
        let limits = money.amountAxisLimits
        #expect(limits.first == 10_000)
        #expect(abs((limits.last.flatMap { $0 } ?? 0) - 30_000) < 500)
        #expect(!money.cutsAmounts(planSpending: nil))
    }

    @Test func theHiddenAxisIsInMultiplesOfTheMedianCameIn() throws {
        // Twelve months of 4.000 € and one with an inheritance of 100.000 €.
        var amounts = [(moneyIn: Decimal, spent: Decimal)](repeating: (4_000, 2_800), count: 13)
        amounts[6] = (104_000, 2_800)
        #expect(months(amounts).relativeBase == 4_000)
        // Nothing came in: no base.
        #expect(months([(moneyIn: 0, spent: 2_000)]).relativeBase == nil)
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
