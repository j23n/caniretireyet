import Foundation
import Model
import Testing
import TestSupport
import Tracker

/// Invariant B4: months add up to the year. Trends' money in and out by
/// month against by year, the check-in's and *Your year*'s month-by-month
/// bars against the Overview's *This year*, and *Where your money came
/// from* by month against by year. Every library here is checked in at
/// each month end, so a year's days are its months' days.
struct MonthsAddUpTests {
    @Test(arguments: InvariantLibrary.allCases)
    func moneyInAndOutByMonthAddsUpToTheYear(_ which: InvariantLibrary) throws {
        let valuator = Valuator(library: try which.library())
        let end = try #require(Windows.checkIns(valuator).last)
        let months = valuator.moneyInOutSeries(.months, through: end).periods
        let years = valuator.moneyInOutSeries(.years, through: end).periods
        #expect(!years.isEmpty || which == .example)
        for year in years where !year.isEmpty {
            let inYear = months.filter { $0.from.year == year.from.year }
            let name = "\(year.from.year)"
            #expect(same(inYear.map(\.moneyIn).sum, year.moneyIn), "\(name)")
            #expect(same(inYear.map { $0.savings?.moneyInOut.moneyOut ?? 0 }.sum,
                         year.savings?.moneyInOut.moneyOut ?? 0), "\(name)")
            #expect(same(inYear.map(\.tax).sum, year.tax), "\(name)")
            #expect(same(inYear.map(\.oneOffs).sum, year.oneOffs), "\(name)")
            #expect(same(inYear.map(\.saved).sum, year.saved), "\(name)")
            #expect(same(inYear.map(\.cameIn).sum, year.cameIn), "\(name)")
            #expect(same(inYear.map(\.spent).sum, year.spent), "\(name)")
            // Each pension's contributions are at least zero in every period.
            #expect(inYear.map(\.pensionContributions).sum >= year.pensionContributions, "\(name)")
        }
    }

    @Test(arguments: InvariantLibrary.allCases)
    func theMonthsBarsAddUpToThisYear(_ which: InvariantLibrary) throws {
        let valuator = Valuator(library: try which.library())
        let dates = Windows.checkIns(valuator)
        for year in Set(dates.map(\.year)).sorted() {
            guard let asOf = dates.last(where: { $0.year == year }),
                  let report = valuator.changeThisYear(asOf: asOf) else { continue }
            let split = valuator.savedSplit(of: report)
            let months = valuator.monthlyChanges(from: YearMonth(year: year, month: 1) ?? asOf.yearMonth,
                                                 through: asOf.yearMonth, asOf: asOf)
            #expect(same(months.map(\.saved).sum, split.saved), "\(year)")
            #expect(same(months.map(\.markets).sum, split.market), "\(year)")
        }
    }

    @Test(arguments: InvariantLibrary.allCases)
    func whereTheMoneyCameFromByMonthMeetsTheYears(_ which: InvariantLibrary) throws {
        let valuator = Valuator(library: try which.library())
        let end = try #require(Windows.checkIns(valuator).last)
        let months = Dictionary(valuator.moneySources(.months, through: end).points.map { ($0.date, $0) },
                                uniquingKeysWith: { _, last in last })
        let years = valuator.moneySources(.years, through: end).points
        #expect(!years.isEmpty)
        for point in years {
            let month = try #require(months[point.date], "\(point.date)")
            #expect(month.total == point.total, "\(point.date)")
            #expect(same(month.saved, point.saved), "\(point.date)")
            #expect(same(month.startedWith, point.startedWith), "\(point.date)")
        }
        // And the years' own increments add up to the last point.
        let sources = valuator.moneySources(.years, through: end)
        #expect(same(sources.years.map(\.saved).sum, years.last?.saved ?? 0))
    }
}
