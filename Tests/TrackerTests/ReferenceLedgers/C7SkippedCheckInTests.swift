import Foundation
import Model
import Testing
import TestSupport
import Tracker

/// C7, a check-in skipped in February (Resources/ReferenceLedgers/c7-skipped-check-in,
/// expected.md): every number its expected.md works out by hand.
@Suite struct C7SkippedCheckInTests {
    let library: Library
    let valuator: Valuator

    init() throws {
        library = try ReferenceLedger.skippedCheckIn.library()
        valuator = Valuator(library: library)
    }

    @Test func netWorth() {
        #expect(valuator.netWorth(on: "2024-12-31").total == 25000)
        #expect(valuator.netWorth(on: "2025-01-31").total == 26410)
        #expect(valuator.netWorth(on: "2025-02-28").total == 26110)
        #expect(valuator.netWorth(on: "2025-03-31").total == 28932)
        #expect(valuator.checkInDates() == ["2024-12-31", "2025-01-31", "2025-03-31"])
    }

    @Test func january() throws {
        let moved = valuator.whatMoved(valuator.change(from: "2024-12-31", to: "2025-01-31"))
        #expect(moved.change == 1410)
        #expect(moved.saved == 1200)
        #expect(moved.markets == 210)
        #expect(moved.unexplained == 0)
        #expect(moved.pay?.cameIn == 3000)
        #expect(moved.pay?.spent == 1800)
        #expect(moved.pay?.savedShare == d("0.4"))
    }

    /// The check-in after the skipped one holds both months.
    @Test func februaryAndMarch() throws {
        let moved = valuator.whatMoved(valuator.change(from: "2025-01-31", to: "2025-03-31"))
        #expect(moved.change == 2522)
        #expect(moved.saved == 2200)
        #expect(moved.markets == 322)
        #expect(moved.unexplained == 0)
        let pay = try #require(moved.pay)
        #expect(pay.cameIn == 6000)
        #expect(pay.spent == 3800)
        #expect(pay.savedShare == Decimal(2200) / 6000)
    }

    /// February's bar has markets only; March's has both months' saving.
    @Test func monthlyChanges() {
        let months = valuator.monthlyChanges(from: YearMonth(year: 2025, month: 1)!,
                                             through: YearMonth(year: 2025, month: 3)!, asOf: "2025-03-31")
        #expect(months.map(\.month) == [YearMonth(year: 2025, month: 1)!, YearMonth(year: 2025, month: 2)!,
                                        YearMonth(year: 2025, month: 3)!])
        #expect(months.map(\.saved) == [1200, 0, 2200])
        #expect(months.map(\.markets) == [210, -300, 622])
    }

    @Test func moneyInOutSeries() throws {
        let series = valuator.moneyInOutSeries(.months, through: "2025-03-31")
        #expect(series.periods.map(\.from) == ["2025-01-01", "2025-02-01", "2025-03-01"])
        let january = series.periods[0]
        #expect(january.cameIn == 3000)
        #expect(january.saved == 1200)
        #expect(january.spent == 1800)
        #expect(!january.coversMore(.months))
        #expect(series.periods[1].isEmpty)
        let march = series.periods[2]
        #expect(march.cameIn == 6000)
        #expect(march.saved == 2200)
        #expect(march.spent == 3800)
        #expect(march.covers == "2025-02-01"..."2025-03-31")
        #expect(march.coversMore(.months))
        let savings = try #require(march.savings)
        #expect(savings.from == "2025-01-31")
        #expect(savings.spentPerYear == d("23508.47"))
        #expect(savings.moneyInOut.moneyOutPerYear == d("23508.47"))
    }

    @Test func theYearSoFar() throws {
        let rate = try #require(valuator.savingsRate(from: "2025-01-01", through: "2025-03-31"))
        #expect(rate.from == "2024-12-31")
        #expect(rate.income == 9000)
        #expect(rate.saved == 3400)
        #expect(rate.spent == 5600)
        #expect(rate.spentPerYear == d("22711.11"))
        #expect(rate.rate == Decimal(3400) / 9000)

        let year = try #require(valuator.changeThisYear(asOf: "2025-03-31"))
        #expect(year.total.saved == 3400)
        #expect(year.total.market == 532)
        #expect(year.total.other == 0)

        let sources = valuator.moneySources(.months, through: "2025-03-31")
        #expect(sources.points == [
            MoneySourcesPoint(date: "2024-12-31", total: 25000, startedWith: 25000, saved: 0),
            MoneySourcesPoint(date: "2025-01-31", total: 26410, startedWith: 25000, saved: 1200),
            MoneySourcesPoint(date: "2025-02-28", total: 26110, startedWith: 25000, saved: 1200),
            MoneySourcesPoint(date: "2025-03-31", total: 28932, startedWith: 25000, saved: 3400),
        ])
    }

    /// Only the current account skips February: the savings account has a
    /// value on 28 February. The months add up to the quarter, as the
    /// check-ins' bars do: the current account's value on 31 March covers
    /// February too, so February's pay covers no days, and March's covers
    /// both months, the savings account's February 500 with them.
    @Test func onlyTheCurrentAccountSkipsFebruary() throws {
        var library = library
        library.upsert(Valuation(account: "savings", date: "2025-02-28", balance: 11021, moneyIn: 0, moneyOut: 0,
                                 interest: 11))
        library.upsert(Valuation(account: "savings", date: "2025-03-31", balance: 11532, moneyIn: 0, moneyOut: 0,
                                 interest: 11))
        let valuator = Valuator(library: library)
        let months = valuator.monthlyChanges(from: YearMonth(year: 2025, month: 1)!,
                                             through: YearMonth(year: 2025, month: 3)!, asOf: "2025-03-31")
        #expect(months.map(\.saved) == [1200, 500, 1700])

        let quarter = try #require(valuator.savingsRate(from: "2025-01-01", through: "2025-03-31"))
        #expect(quarter.saved == 3400)
        #expect(quarter.spent == 5600)
        let periods = valuator.moneyInOutSeries(.months, through: "2025-03-31").periods
        #expect(periods.map(\.cameIn) == [3000, 0, 6000])
        // February: the savings account's value, with nothing come in, and no days of pay.
        #expect(periods[1].saved == 0)
        #expect(periods[1].spent == 0)
        #expect(periods[1].noRate == .nothingCameIn)
        #expect(periods[1].covers == nil)
        #expect(periods[1].savings?.from == "2025-01-31")
        #expect(periods[1].savings?.payThrough == "2025-01-31")
        // March: both months, from 31 January.
        #expect(periods[2].saved == 2200)
        #expect(periods[2].spent == 3800)
        #expect(periods[2].covers == "2025-02-01"..."2025-03-31")
        #expect(periods.map(\.saved).reduce(0, +) == quarter.saved)
        #expect(periods.map(\.spent).reduce(0, +) == quarter.spent)
    }
}
