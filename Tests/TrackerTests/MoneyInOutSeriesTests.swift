import Foundation
import Model
import Testing
import TestSupport
import Tracker

/// Trends' money in and out by period (PROGRESS.md, "Trends") on the example
/// library, whose current account records money in and out from July to
/// September 2026: each period matches the savings rate over it.
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
            #expect(period.spent == period.cameIn - period.saved)
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

    @Test func aPeriodCountsPensionsAndWhatEveryAccountSaved() throws {
        let valuator = Valuator(library: library)
        let series = valuator.moneyInOutSeries(.months, through: "2026-09-30")
        let august = try #require(series.periods.first { $0.from == "2026-08-01" })
        #expect(august.moneyIn == 3400)
        #expect(august.pensionContributions == 0)
        #expect(august.cameIn == 3400)
        // The current account's 534.8, the broker's deposit of 200.6 and the mortgage's 650.
        #expect(august.saved == d("1385.4"))
        #expect(august.spent == d("2014.6"))
        #expect(august.rate?.rounded(scale: 4) == d("0.4075"))
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
        #expect(year.saved == months.reduce(Decimal(0)) { $0 + $1.saved })
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

    /// Only the pay's days count: a skipped check-in of the current account,
    /// which the pay comes into, makes September hold August's money too,
    /// though the savings account was checked in August.
    @Test func aSkippedCheckInOfTheAccountThePayComesIntoCoversMore() throws {
        var library = self.library
        library.months["2026-08"]?.valuations.removeAll { $0.account == "conto-fineco" }
        let series = Valuator(library: library).moneyInOutSeries(.months, through: "2026-09-30")
        let september = try #require(series.periods.last)
        #expect(september.covers == CalendarDate("2026-08-01")...CalendarDate("2026-09-30"))
        #expect(september.coversMore(.months))
    }

    /// A savings account checked once a quarter covers three months with
    /// its September value, but the pay came into the current account,
    /// checked each month: September holds its own money.
    @Test func anAccountCheckedRarelyDoesNotCoverMore() throws {
        var library = self.library
        for month: YearMonth in ["2026-07", "2026-08"] {
            library.months[month]?.valuations.removeAll { $0.account == "conto-deposito" }
        }
        let valuator = Valuator(library: library)
        let series = valuator.moneyInOutSeries(.months, through: "2026-09-30")
        expectMatches(series, valuator: valuator)
        // The savings account's value is measured from 30 June.
        #expect(valuator.moneyInOut(from: "2026-09-01", through: "2026-09-30").measuredFrom == "2026-06-30")
        let september = try #require(series.periods.last)
        #expect(september.covers == CalendarDate("2026-09-01")...CalendarDate("2026-09-30"))
        #expect(!series.periods.contains { $0.coversMore(.months) })
    }

    /// A current account valued on the 15th, which the pay comes into, and
    /// a savings account valued at the month's end: January's pay covers 16
    /// December to 15 January, not to the savings account's 31 January.
    @Test func anotherAccountsLaterValueDoesNotCoverMore() throws {
        var library = Library(settings: LibrarySettings(baseCurrency: .eur))
        library.accounts["bank"] = Account(id: "bank", name: "Bank", kind: .cash, currency: .eur,
                                           opened: "2025-12-01")
        library.accounts["savings"] = Account(id: "savings", name: "Savings", kind: .savings, currency: .eur,
                                              opened: "2025-12-01")
        library.upsert(Valuation(account: "bank", date: "2025-12-15", balance: 5000))
        library.upsert(Valuation(account: "savings", date: "2025-12-31", balance: 10000))
        library.upsert(Valuation(account: "bank", date: "2026-01-15", balance: 6000, moneyIn: 3000, moneyOut: 2000))
        library.upsert(Valuation(account: "savings", date: "2026-01-31", balance: 10000, moneyIn: 0, moneyOut: 0))
        let series = Valuator(library: library).moneyInOutSeries(.months, through: "2026-01-31")
        let january = try #require(series.periods.last)
        #expect(january.savings?.moneyInOut.lastCounted == "2026-01-31")
        #expect(january.covers == CalendarDate("2025-12-16")...CalendarDate("2026-01-15"))
        #expect(!january.coversMore(.months))
    }

    /// A month whose value records no money in and out counts nothing, so
    /// the next month's pay covers its own days, not that month's too,
    /// whose money in nobody recorded.
    @Test func aMonthWithNothingCountedDoesntPassOnItsDays() throws {
        var library = Library(settings: LibrarySettings(baseCurrency: .eur))
        library.accounts["bank"] = Account(id: "bank", name: "Bank", kind: .cash, currency: .eur,
                                           opened: "2025-12-01")
        library.upsert(Valuation(account: "bank", date: "2025-12-31", balance: 0))
        library.upsert(Valuation(account: "bank", date: "2026-01-31", balance: 1000, moneyIn: 3000, moneyOut: 2000))
        library.upsert(Valuation(account: "bank", date: "2026-02-28", balance: 2000))
        library.upsert(Valuation(account: "bank", date: "2026-03-31", balance: 3000, moneyIn: 3000, moneyOut: 2000))
        let months = Valuator(library: library).moneyInOutSeries(.months, through: "2026-03-31").periods
        #expect(months.map { $0.savings == nil } == [false, true, false])
        let march = try #require(months.last)
        #expect(march.covers == CalendarDate("2026-03-01")...CalendarDate("2026-03-31"))
        #expect(march.saved == 1000)
        #expect(march.spent == 2000)
    }

    /// January's pay is the bank's, February counts nothing, and March's
    /// is a savings account valued once a quarter, since 31 December. Its
    /// days start after January's, so January's saving counts once, and
    /// the months add up to the quarter.
    @Test func aMonthAfterOneWithNothingCountedDoesntCountEarlierDaysAgain() throws {
        var library = Library(settings: LibrarySettings(baseCurrency: .eur))
        library.accounts["bank"] = Account(id: "bank", name: "Bank", kind: .cash, currency: .eur,
                                           opened: "2025-12-01")
        library.accounts["savings"] = Account(id: "savings", name: "Savings", kind: .savings, currency: .eur,
                                              opened: "2025-12-01")
        library.upsert(Valuation(account: "bank", date: "2025-12-31", balance: 5000))
        library.upsert(Valuation(account: "bank", date: "2026-01-31", balance: 6000, moneyIn: 3000, moneyOut: 2000))
        library.upsert(Valuation(account: "bank", date: "2026-02-28", balance: 7000))
        library.upsert(Valuation(account: "bank", date: "2026-03-31", balance: 8000, moneyIn: 2500, moneyOut: 1500))
        library.upsert(Valuation(account: "savings", date: "2025-12-31", balance: 20000))
        library.upsert(Valuation(account: "savings", date: "2026-03-31", balance: 28000, moneyIn: 8000, moneyOut: 0))
        let valuator = Valuator(library: library)
        let months = valuator.moneyInOutSeries(.months, through: "2026-03-31").periods
        #expect(months.map { $0.savings == nil } == [false, true, false])
        #expect(months.map(\.covers) == ["2026-01-01"..."2026-01-31", nil, "2026-02-01"..."2026-03-31"])
        #expect(months.map(\.saved) == [1000, 0, 10000])
        #expect(months.map(\.spent) == [2000, 0, 500])
        let quarter = try #require(valuator.savingsRate(from: "2026-01-01", through: "2026-03-31"))
        #expect(quarter.saved == months.map(\.saved).reduce(0, +))
        #expect(quarter.spent == months.map(\.spent).reduce(0, +))
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
        library.upsert(Valuation(account: "conto-fineco", date: "2026-10-31", balance: 6000, saved: 400,
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
