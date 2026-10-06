import Foundation
import Model
import Testing
import TestSupport
import Tracker

private func d(_ string: String) -> Decimal { Decimal(fileString: string)! }

struct DateGridTests {
    @Test func monthEndsFromTheStartMonthThroughTheEnd() {
        #expect(DateGrid.monthEnds(from: "2025-10-15", through: "2026-01-10")
            == ["2025-10-31", "2025-11-30", "2025-12-31", "2026-01-10"])
        #expect(DateGrid.monthEnds(from: "2026-01-31", through: "2026-02-28") == ["2026-01-31", "2026-02-28"])
        #expect(DateGrid.monthEnds(from: "2024-02-01", through: "2024-02-29") == ["2024-02-29"])
        #expect(DateGrid.monthEnds(from: "2026-03-01", through: "2026-02-28").isEmpty)
    }

    /// 9999-12-31, a common "no end date" in bank exports, is the last date
    /// there is: the grid stops there instead of stepping into year 10000.
    @Test func monthEndsStopAtTheLastRepresentableMonth() {
        #expect(DateGrid.monthEnds(from: "9999-10-15", through: "9999-12-31")
            == ["9999-10-31", "9999-11-30", "9999-12-31"])
        #expect(DateGrid.monthEnds(from: "9999-12-31", through: "9999-12-31") == ["9999-12-31"])
        #expect(DateGrid.monthEnds(from: "9999-11-01", through: "9999-12-30") == ["9999-11-30", "9999-12-30"])
    }

    /// Progress's line: each check-in, and the end of each month without one.
    @Test func checkInsAndTheEndsOfMonthsWithoutOne() {
        let checkIns: [CalendarDate] = ["2025-09-30", "2025-11-15", "2026-01-31", "2026-03-10"]
        #expect(DateGrid.checkInsAndMonthEnds(from: "2025-10-20", through: "2026-03-10", checkIns: checkIns)
            == ["2025-10-20", "2025-10-31", "2025-11-15", "2025-12-31", "2026-01-31", "2026-02-28", "2026-03-10"])
        // Both ends are on it, also an end that's neither a check-in nor a month end.
        #expect(DateGrid.checkInsAndMonthEnds(from: "2026-01-31", through: "2026-02-15", checkIns: checkIns)
            == ["2026-01-31", "2026-02-15"])
        #expect(DateGrid.checkInsAndMonthEnds(from: "2026-03-01", through: "2026-02-28", checkIns: checkIns).isEmpty)
    }

    @Test func seriesThroughTheLastDateThereIsDoesNotTrap() {
        var library = Library()
        library.accounts["cash"] = Account(id: "cash", name: "Cash", kind: .cash, currency: .eur, opened: "9999-01-01")
        library.upsert(Valuation(account: "cash", date: "9999-11-30", balance: 100))
        let series = Valuator(library: library).series(through: "9999-12-31")
        #expect(series.map(\.date) == ["9999-11-30", "9999-12-31"])
        #expect(series.last?.value == 100)
    }
}

/// Series of the example library, checked against totals worked out by hand.
struct ExampleLibrarySeriesTests {
    let valuator: Valuator

    init() throws {
        valuator = Valuator(library: try Fixtures.exampleLibrary())
    }

    @Test func netWorthOnMonthEnds() {
        let series = valuator.series(through: "2026-09-30")
        #expect(series.count == 12)
        #expect(series.first?.date == "2025-10-31")
        #expect(series.first?.value.rounded(2) == d("289190.28"))
        #expect(series[10].date == "2026-08-31")
        #expect(series[10].value.rounded(2) == d("327037.83"))
        #expect(series.last?.value.rounded(2) == d("332455.49"))
        #expect(series.allSatisfy { $0.isComplete })
    }

    @Test func monthEndGridEndsOnTheGivenDateAndCheckInGridOnTheLastCheckIn() {
        let monthly = valuator.series(through: "2026-10-15")
        #expect(monthly.count == 13)
        #expect(monthly.last?.date == "2026-10-15")
        let checkIns = valuator.series(grid: .checkIns, through: "2026-10-15")
        #expect(checkIns.count == 12)
        #expect(checkIns.last?.date == "2026-09-30")
        #expect(valuator.series(grid: .checkIns, through: "2025-10-30").isEmpty)
    }

    @Test func planAssetsLeaveOutTheHomeAndMortgage() {
        let plan = valuator.series(.planAssets, through: "2026-09-30")
        // 289,190.28 − 305,000 (home) + 148,200 (mortgage).
        #expect(plan.first?.value.rounded(2) == d("132390.28"))
        #expect(plan.last?.value.rounded(2) == d("161505.49"))
    }

    @Test func accountSeries() {
        let fund = valuator.series(of: "fondo-pensione", through: "2026-09-30")
        #expect(fund.count == 12)
        #expect(fund.prefix(3).map(\.value) == [16120, 16120, d("16850.4")])
        let statements = valuator.series(of: "fondo-pensione", grid: .checkIns, through: "2026-09-30")
        #expect(statements.map(\.date) == ["2025-10-31", "2025-12-31", "2026-03-31", "2026-06-30", "2026-09-30"])
        // Old bank closed on 2025-11-15: zero afterwards.
        #expect(valuator.series(of: "old-bank", through: "2025-12-31").map(\.value) == [850, 0, 0])
        let sparkline = valuator.series(of: "conto-fineco", from: "2026-06-30", through: "2026-09-30")
        #expect(sparkline.map(\.value) == [d("6240.95"), d("3980.4"), d("4515.2"), d("4210.55")])
        #expect(valuator.series(of: "nope", through: "2026-09-30").isEmpty)
    }

    @Test func checkInDates() {
        #expect(valuator.checkInDates().count == 12)
        #expect(valuator.firstValuationDate() == "2025-10-31")
        #expect(valuator.latestCheckIn(onOrBefore: "2026-09-15") == "2026-08-31")
        #expect(valuator.previousCheckIn(before: "2026-09-30") == "2026-08-31")
        #expect(valuator.previousCheckIn(before: "2025-10-31") == nil)
    }
}

/// Holdings with purchase cost and unrealised gain, for the account detail.
struct HoldingsTests {
    @Test func positionsWithCostAndGain() throws {
        let valuator = Valuator(library: try Fixtures.exampleLibrary())
        let directa = valuator.holdings(of: "directa", on: "2026-09-30")
        #expect(directa.count == 1)
        let vwce = try #require(directa.first)
        #expect(vwce.instrument == "vwce")
        #expect(vwce.quantity == d("412.5"))
        #expect(vwce.price?.price == d("138.42"))
        #expect(vwce.amount == d("57098.25"))
        #expect(vwce.value == d("57098.25"))
        #expect(vwce.unrealizedGain == d("8898.25"))

        // BTC is priced in USD: the amount is in the account's currency (EUR).
        let btc = try #require(valuator.holdings(of: "ledger-wallet", on: "2026-09-30").first)
        #expect(btc.amount?.rounded(2) == d("44128"))
        #expect(btc.costBasis == nil)
        #expect(btc.unrealizedGain == nil)

        #expect(valuator.holdings(of: "conto-fineco", on: "2026-09-30").isEmpty)
    }
}
