import Foundation
import Model
import Testing
import TestSupport
import Tracker

/// Trends' money in and out by period (PROGRESS.md, "Trends") on the example
/// library, whose current account records money in and out from July to
/// September 2026: each period matches the savings rate and the money in and
/// out over it.
struct MoneyInOutSeriesTests {
    let library: Library

    init() throws {
        library = try Fixtures.exampleLibrary()
    }

    /// Each period is the savings rate and the money in and out over its days.
    private func expectMatches(_ series: MoneyInOutSeries, valuator: Valuator) {
        for period in series.periods {
            #expect(period.savings == valuator.savingsRate(from: period.from, through: period.through))
            let money = valuator.moneyInOut(from: period.from, through: period.through)
            #expect(period.moneyIn == money.moneyIn)
            #expect(period.moneyOut == money.moneyOut)
        }
    }

    @Test func monthsFromTheFirstWithMoneyInAndOut() throws {
        let valuator = Valuator(library: library)
        let series = valuator.moneyInOutSeries(.months, through: "2026-09-30")
        #expect(series.currency == .eur)
        #expect(series.periods.map(\.from) == ["2026-07-01", "2026-08-01", "2026-09-01"])
        #expect(series.periods.map(\.through) == ["2026-07-31", "2026-08-31", "2026-09-30"])
        expectMatches(series, valuator: valuator)
        // Where money in and out starts: July's value is measured from June's.
        #expect(series.recorded.measuredFrom == "2026-06-30")
        #expect(series.recorded.months.count == 3)
        // Fewer than twelve months: no rate over the last 12.
        #expect(series.periods.allSatisfy { $0.lastTwelveMonths == nil })
    }

    @Test func aPeriodCountsPensionsAndThePrincipalRepaid() throws {
        let valuator = Valuator(library: library)
        let series = valuator.moneyInOutSeries(.months, through: "2026-09-30")
        let august = try #require(series.periods.first { $0.from == "2026-08-01" })
        #expect(august.moneyIn == 3400)
        #expect(august.moneyOut == d("2014.6"))
        #expect(august.pensionContributions == 0)
        #expect(august.cameIn == 3400)
        // 3,400 − 2,014.6 + the mortgage's 650.
        #expect(august.kept == d("2035.4"))
        #expect(august.rate?.rounded(scale: 4) == d("0.5986"))
        // The pension fund's quarterly 1,325 is paid in September.
        let september = try #require(series.periods.last)
        #expect(september.pensionContributions == 1325)
        #expect(september.cameIn == september.moneyIn + 1325)
    }

    @Test func yearsOverTheCalendarYear() throws {
        let valuator = Valuator(library: library)
        let series = valuator.moneyInOutSeries(.years, through: "2026-09-30")
        #expect(series.periods.map(\.from) == ["2026-01-01"])
        #expect(series.periods.map(\.through) == ["2026-09-30"])
        expectMatches(series, valuator: valuator)
        let year = try #require(series.periods.first)
        let months = valuator.moneyInOutSeries(.months, through: "2026-09-30").periods
        #expect(year.moneyIn == months.reduce(Decimal(0)) { $0 + $1.moneyIn })
        #expect(year.moneyOut == months.reduce(Decimal(0)) { $0 + $1.moneyOut })
        #expect(year.lastTwelveMonths == nil)
    }

    @Test func aPeriodWithoutValuesIsEmpty() throws {
        let valuator = Valuator(library: library)
        let series = valuator.moneyInOutSeries(.months, through: "2026-10-10")
        let october = try #require(series.periods.last)
        #expect(october.from == "2026-10-01")
        #expect(october.through == "2026-10-10")
        #expect(october.isEmpty)
        #expect(october.cameIn == 0)
        #expect(october.rate == nil)
        #expect(october.covers == nil)
    }

    @Test func noMoneyInAndOutNoPeriods() throws {
        let valuator = Valuator(library: library)
        let series = valuator.moneyInOutSeries(.months, through: "2026-06-30")
        #expect(series.isEmpty)
        #expect(series.periods.isEmpty)
        #expect(series.recorded.measuredFrom == nil)
    }

    @Test func aValueCountsInThePeriodOfItsDate() throws {
        var library = self.library
        // A skipped August check-in: the current and the savings account have no August value.
        library.months["2026-08"]?.valuations.removeAll { ["conto-fineco", "conto-deposito"].contains($0.account) }
        let valuator = Valuator(library: library)
        let series = valuator.moneyInOutSeries(.months, through: "2026-09-30")
        expectMatches(series, valuator: valuator)
        let august = try #require(series.periods.first { $0.from == "2026-08-01" })
        #expect(august.isEmpty)
        // September's value covers August too.
        let september = try #require(series.periods.last)
        #expect(september.covers == CalendarDate("2026-08-01")...CalendarDate("2026-09-30"))
        #expect(september.coversMore(.months))
        let july = try #require(series.periods.first)
        #expect(july.covers == CalendarDate("2026-07-01")...CalendarDate("2026-07-31"))
        #expect(!july.coversMore(.months))
        // A year of monthly values covers no more than the year.
        let year = try #require(valuator.moneyInOutSeries(.years, through: "2026-09-30").periods.first)
        #expect(!year.coversMore(.years))
    }

    /// The current account records money in and out from November 2025 to
    /// October 2026: twelve months, so October has a rate over the last 12.
    @Test func monthsFromTheTwelfthHaveTheRateOverTheLast12() throws {
        var library = self.library
        for month in Array(library.months.keys) where month >= "2025-11" && month <= "2026-06" {
            guard let index = library.months[month]?.valuations.firstIndex(where: { $0.account == "conto-fineco" })
            else { continue }
            library.months[month]?.valuations[index].moneyIn = 3000
            library.months[month]?.valuations[index].moneyOut = 2500
        }
        library.upsert(Valuation(account: "conto-fineco", date: "2026-10-31", balance: 6000, flow: 400,
                                 moneyIn: 3200, moneyOut: 2800))
        let valuator = Valuator(library: library)
        let series = valuator.moneyInOutSeries(.months, through: "2026-10-31")
        #expect(series.periods.count == 12)
        #expect(series.periods.first?.from == "2025-11-01")
        expectMatches(series, valuator: valuator)
        #expect(series.periods.dropLast().allSatisfy { $0.lastTwelveMonths == nil })
        let october = try #require(series.periods.last)
        #expect(october.lastTwelveMonths == valuator.savingsRate(overYearEndingOn: "2026-10-31"))
        #expect(october.lastTwelveMonths?.rate != nil)
    }
}
