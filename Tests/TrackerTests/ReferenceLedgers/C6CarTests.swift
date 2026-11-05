import Foundation
import Model
import Testing
import TestSupport
import Tracker

/// C6, a car bought, losing value and sold (Resources/ReferenceLedgers/c6-car,
/// expected.md): every number its expected.md works out by hand. The car
/// loses 15% a year from its 15,000 on 10 March: 2,250 a year, by the day.
@Suite struct C6CarTests {
    let valuator: Valuator

    init() throws {
        valuator = Valuator(library: try ReferenceLedger.car.library())
    }

    private func quarter(_ from: CalendarDate, _ to: CalendarDate) -> WhatMoved {
        valuator.whatMoved(valuator.change(from: from, to: to))
    }

    @Test func theCarsEstimatedValue() {
        let car: AccountID = "car"
        #expect(valuator.netWorth(on: "2025-03-10").accounts.first { $0.account == car }?.value == 15000)
        #expect(valuator.netWorth(on: "2025-03-31").accounts.first { $0.account == car }?.value == d("14870.55"))
        #expect(valuator.netWorth(on: "2025-06-30").accounts.first { $0.account == car }?.value == d("14309.59"))
        #expect(valuator.netWorth(on: "2025-09-30").accounts.first { $0.account == car }?.value == d("13742.47"))
        #expect(valuator.netWorth(on: "2025-10-14").accounts.first { $0.account == car }?.value == d("13656.16"))
        #expect(valuator.netWorth(on: "2025-10-31").accounts.contains { $0.account == car } == false)
    }

    /// Between a statement line and the current account's next value, net
    /// worth counts the car but not the money that moved (IMPORT.md, "Moved
    /// to or from an account"): high by 15,000 from 10 March, low by
    /// 12,000 from 15 October.
    @Test func netWorth() {
        #expect(valuator.netWorth(on: "2024-12-31").total == 20000)
        #expect(valuator.netWorth(on: "2025-03-09").total == 20000)
        #expect(valuator.netWorth(on: "2025-03-10").total == 35000)
        #expect(valuator.netWorth(on: "2025-03-31").total == d("25870.55"))
        #expect(valuator.netWorth(on: "2025-06-30").total == d("31309.59"))
        #expect(valuator.netWorth(on: "2025-09-30").total == d("36742.47"))
        #expect(valuator.netWorth(on: "2025-10-15").total == 23000)
        #expect(valuator.netWorth(on: "2025-12-31").total == 41000)
        #expect(valuator.checkInDates() == ["2024-12-31", "2025-03-09", "2025-03-10", "2025-03-31", "2025-06-30",
                                            "2025-09-30", "2025-10-15", "2025-12-31"])
    }

    /// The purchase is saved, not spent; the car's loss by its depreciation
    /// is lost value.
    @Test func theQuarterItWasBought() throws {
        let moved = quarter("2024-12-31", "2025-03-31")
        #expect(moved.change == d("5870.55"))
        #expect(moved.saved == 6000)
        #expect(moved.lost == d("-129.45"))
        #expect(moved.markets == 0)
        #expect(moved.startedWith == 0)
        #expect(moved.unexplained == 0)
        #expect(moved.pay?.cameIn == 12000)
        #expect(moved.pay?.spent == 6000)
    }

    @Test func theQuartersItLostValue() {
        let second = quarter("2025-03-31", "2025-06-30")
        #expect(second.saved == 6000)
        #expect(second.lost == d("-560.96"))
        #expect(second.unexplained == 0)
        let third = quarter("2025-06-30", "2025-09-30")
        #expect(third.saved == 6000)
        #expect(third.lost == d("-567.12"))
        #expect(third.unexplained == 0)
    }

    /// Sold for 1,650 less than its estimate: that much is spent.
    @Test func theQuarterItWasSold() throws {
        let moved = quarter("2025-09-30", "2025-12-31")
        #expect(moved.change == d("4257.53"))
        #expect(moved.saved == 4350)
        #expect(moved.lost == d("-92.47"))
        #expect(moved.markets == 0)
        #expect(moved.unexplained == 0)
        let pay = try #require(moved.pay)
        #expect(pay.cameIn == 12000)
        #expect(pay.spent == 7650)
    }

    /// The sale's day is a check-in of its own: the car's value leaves as
    /// saved there, and the money it brought in arrives at the current
    /// account's next value.
    @Test func theCheckInsAroundTheSale() throws {
        let sale = quarter("2025-09-30", "2025-10-15")
        #expect(sale.change == d("-13742.47"))
        #expect(sale.saved == -13650)
        #expect(sale.lost == d("-92.47"))
        #expect(sale.pay == nil)
        let after = quarter("2025-10-15", "2025-12-31")
        #expect(after.change == 18000)
        #expect(after.saved == 18000)
    }

    /// Today's *Your pay* at the quarters' check-ins after the purchase and
    /// the sale: the check-in before each is the car's value on the line's
    /// day, but the current account's value covers the whole quarter, the
    /// money moved to or from the car included. What came in is the
    /// quarter's, so what was saved is the quarter's too, as the savings
    /// rate counts it: the car bought is saved, not spent, and only the
    /// 1,650 it sold below its estimate is spent. Net worth's split stays
    /// over the check-in's own days.
    @Test(arguments: [("2025-03-31", "2025-03-10", "2024-12-31", 6000, -9000),
                      ("2025-12-31", "2025-10-15", "2025-09-30", 7650, 18000)]
          as [(CalendarDate, CalendarDate, CalendarDate, Decimal, Decimal)])
    func todaysPayAfterTheCarsCheckIns(checkIn: CalendarDate, before: CalendarDate, payFrom: CalendarDate,
                                       spent: Decimal, savedSinceBefore: Decimal) throws {
        let report = try #require(valuator.changeSinceLastCheckIn(asOf: checkIn))
        #expect(report.from == before)
        let today = valuator.whatMoved(report)
        let rate = try #require(valuator.savingsRate(from: before.adding(days: 1), through: checkIn))
        #expect(rate.pay.cameIn == 12000)
        #expect(rate.pay.spent == spent)
        let pay = try #require(today.pay)
        #expect(pay == rate.pay)
        #expect(pay.cameIn == 12000)
        #expect(pay.spent == spent)
        #expect(pay.saved == 12000 - spent)
        #expect(pay.from == payFrom)
        #expect(pay.through == checkIn)
        #expect(today.saved == savedSinceBefore)
    }

    @Test func theYear() throws {
        let year = try #require(valuator.changeThisYear(asOf: "2025-12-31"))
        #expect(year.total.change == 21000)
        #expect(year.total.saved == 22350)
        #expect(year.total.lost == -1350)
        #expect(year.total.market == 0)
        #expect(year.total.other == 0)
        let moved = valuator.whatMoved(year)
        #expect(moved.saved == 22350)
        #expect(moved.lost == -1350)
        #expect(moved.unexplained == 0)
        let split = valuator.savedSplit(of: year)
        #expect(split.saved == 22350)
        #expect(split.lost == -1350)
        #expect(split.other == 0)

        let rate = try #require(valuator.savingsRate(from: "2025-01-01", through: "2025-12-31"))
        #expect(rate.income == 48000)
        #expect(rate.saved == 22350)
        #expect(rate.spent == 25650)
        #expect(rate.spentPerYear == 25650)
        #expect(rate.rate == d("0.465625"))
    }

    /// Lost value is under markets in *Where your money came from*.
    @Test func moneySources() {
        let sources = valuator.moneySources(.years, through: "2025-12-31")
        #expect(sources.points == [
            MoneySourcesPoint(date: "2024-12-31", total: 20000, startedWith: 20000, saved: 0),
            MoneySourcesPoint(date: "2025-12-31", total: 41000, startedWith: 20000, saved: 22350),
        ])
        #expect(sources.points.last?.markets == -1350)
    }

    /// A quarter's values in the month that ends it: each holds three
    /// months.
    @Test func moneyInOutSeries() throws {
        let series = valuator.moneyInOutSeries(.months, through: "2025-12-31")
        let counted = series.periods.filter { !$0.isEmpty }
        #expect(counted.map(\.from) == ["2025-03-01", "2025-06-01", "2025-09-01", "2025-12-01"])
        #expect(counted.map(\.saved) == [6000, 6000, 6000, 4350])
        #expect(counted.map(\.spent) == [6000, 6000, 6000, 7650])
        #expect(counted.allSatisfy { $0.coversMore(.months) })
    }
}
