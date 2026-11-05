import Foundation
import Model
import Testing
import TestSupport
import Tracker

/// C2, a tax pot over a year (Resources/ReferenceLedgers/c2-tax-pot,
/// expected.md): every number its expected.md works out by hand.
@Suite struct C2TaxPotTests {
    let library: Library
    let valuator: Valuator

    init() throws {
        library = try ReferenceLedger.taxPot.library()
        valuator = Valuator(library: library)
    }

    static let monthEnds: [CalendarDate] = (1...12).map { YearMonth(year: 2025, month: $0)!.lastDay }

    @Test func netWorthLeavesThePotOut() {
        #expect(valuator.netWorth(on: "2024-12-31").total == 3000)
        #expect(valuator.netWorth(on: "2025-06-30").total == 9000)
        #expect(valuator.netWorth(on: "2025-12-31").total == 15000)
        #expect(valuator.netWorth(on: "2025-12-31").accounts.map(\.account) == ["current"])
    }

    /// Every month alike, June's bill paid from the pot included.
    @Test(arguments: monthEnds)
    func eachMonth(_ end: CalendarDate) throws {
        let start = end.startOfMonth.adding(days: -1)
        let moved = valuator.whatMoved(valuator.change(from: start, to: end))
        #expect(moved.change == 1000)
        #expect(moved.saved == 1000)
        #expect(moved.markets == 0)
        #expect(moved.unexplained == 0)
        let pay = try #require(moved.pay)
        #expect(pay.moneyIn == 4000)
        #expect(pay.pension == 0)
        #expect(pay.tax == 1000)
        #expect(pay.afterTax == 3000)
        #expect(pay.spent == 2000)
        #expect(pay.savedShare == Decimal(1000) / 3000)
    }

    @Test func theYear() throws {
        let year = try #require(valuator.savingsRate(from: "2025-01-01", through: "2025-12-31"))
        #expect(year.from == "2024-12-31")
        #expect(year.moneyInOut.moneyIn == 48000)
        #expect(year.moneyInOut.moneyOut == 24000)
        #expect(year.moneyInOut.taxes == 0)
        #expect(year.taxSetAside == 12000)
        #expect(year.tax == 12000)
        #expect(year.pensionContributions == 0)
        #expect(year.income == 36000)
        #expect(year.saved == 12000)
        #expect(year.spent == 24000)
        #expect(year.spentPerYear == 24000)
        #expect(year.rate == Decimal(12000) / 36000)
        #expect(year.rate?.rounded(2) == d("0.33"))
        #expect(year.noRate == nil)
        #expect(year.isPriced)
    }

    @Test func moneyInOutSeries() throws {
        let months = valuator.moneyInOutSeries(.months, through: "2025-12-31")
        #expect(months.periods.map(\.from) == Self.monthEnds.map(\.startOfMonth))
        for month in months.periods {
            #expect(month.beforeTax == 4000)
            #expect(month.tax == 1000)
            #expect(month.cameIn == 3000)
            #expect(month.saved == 1000)
            #expect(month.spent == 2000)
            #expect(!month.coversMore(.months))
        }
        let lastTwelve = try #require(months.periods.last?.lastTwelveMonths)
        #expect(lastTwelve.income == 36000)
        #expect(lastTwelve.spent == 24000)

        let years = valuator.moneyInOutSeries(.years, through: "2025-12-31")
        let year = try #require(years.periods.first)
        #expect(years.periods.count == 1)
        #expect(year.beforeTax == 48000)
        #expect(year.tax == 12000)
        #expect(year.cameIn == 36000)
        #expect(year.spent == 24000)
        let bars = try #require(year.bars)
        #expect(bars.cameIn == [.init(part: .moneyIn, from: 0, to: 48000)])
        #expect(bars.wentOut == [.init(part: .spent, from: 0, to: 24000), .init(part: .tax, from: 24000, to: 36000)])
        #expect(bars.top == 48000)
    }

    @Test func changeThisYearAndMoneySources() throws {
        let year = try #require(valuator.changeThisYear(asOf: "2025-12-31"))
        #expect(year.total.change == 12000)
        #expect(year.total.saved == 12000)
        #expect(year.total.market == 0)
        #expect(year.total.other == 0)
        #expect(valuator.savedSplit(of: year).saved == 12000)

        let sources = valuator.moneySources(.years, through: "2025-12-31")
        #expect(sources.points == [
            MoneySourcesPoint(date: "2024-12-31", total: 3000, startedWith: 3000, saved: 0),
            MoneySourcesPoint(date: "2025-12-31", total: 15000, startedWith: 3000, saved: 12000),
        ])
    }

    /// The pot's values without money in and out: each value's whole change
    /// is what moved, and June's drop is taken as the bill, so the 1,000 put
    /// in that month is lost (PROGRESS.md, "Savings rate").
    @Test func aPotWithoutMoneyInAndOut() throws {
        var library = library
        for valuation in library.months.values.flatMap(\.valuations) where valuation.account == "tax-pot" {
            var bare = valuation
            bare.moneyIn = nil
            bare.moneyOut = nil
            library.upsert(bare)
        }
        let valuator = Valuator(library: library)
        let year = try #require(valuator.savingsRate(from: "2025-01-01", through: "2025-12-31"))
        #expect(year.taxSetAside == 11000)
        #expect(year.income == 37000)
        #expect(year.saved == 12000)
        #expect(year.spent == 25000)
        let june = valuator.whatMoved(valuator.change(from: "2025-05-31", to: "2025-06-30"))
        #expect(june.pay?.tax == 0)
        #expect(june.pay?.spent == 3000)
    }

    /// Without a pot, the bill paid from the current account in June: June
    /// pays more tax than came in, and the year's rate is the pot's
    /// (PROGRESS.md, "Savings rate").
    @Test func theBillPaidFromTheCurrentAccount() throws {
        var library = library
        library.accounts["tax-pot"] = nil
        for month in library.months.keys {
            library.months[month]?.valuations.removeAll { $0.account == "tax-pot" }
            library.months[month]?.lines.removeAll { $0.account == "tax-pot" || $0.otherAccount == "tax-pot" }
        }
        var balance = Decimal(3000)
        for end in Self.monthEnds {
            let isJune = end.month == 6
            balance += isJune ? 2000 - 12000 : 2000
            library.upsert(Valuation(account: "current", date: end, balance: balance, moneyIn: 4000,
                                     moneyOut: isJune ? 14000 : 2000, tax: isJune ? 12000 : nil))
        }
        let valuator = Valuator(library: library)
        let year = try #require(valuator.savingsRate(from: "2025-01-01", through: "2025-12-31"))
        #expect(year.tax == 12000)
        #expect(year.income == 36000)
        #expect(year.saved == 12000)
        #expect(year.spent == 24000)
        #expect(year.rate == Decimal(12000) / 36000)

        let june = try #require(valuator.savingsRate(from: "2025-06-01", through: "2025-06-30"))
        #expect(june.income == -8000)
        #expect(june.saved == -10000)
        #expect(june.spent == 2000)
        #expect(june.rate == nil)
        #expect(june.noRate == .moreTaxThanCameIn)
    }
}
