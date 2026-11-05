import Foundation
import Model
import Testing
import TestSupport
import Tracker

/// Invariant B2: every screen agrees on one check-in. Today's *What moved
/// it* (`whatMoved`), the Overview's bars and the check-in's split
/// (`savedSplit`), the savings rate (`savingsRate`) and the month-by-month
/// bars (`monthlyChanges`) each count what was saved their own way, over
/// their own days; between two check-ins they give the same numbers.
/// *Your pay* is the savings rate over the check-in's values, so it counts
/// what was saved over the days the pay covers, which are the check-in's
/// only when the pay account has values on both its ends.
/// (Glance's `JourneyGlance` is checked in GlanceTests.)
struct EntryPointInvariantTests {
    @Test(arguments: InvariantLibrary.allCases)
    func everyEntryPointAgreesOnACheckIn(_ which: InvariantLibrary) throws {
        let valuator = Valuator(library: try which.library())
        for (from, to) in Windows.consecutive(valuator) {
            let window = "\(from)…\(to)"
            let report = valuator.change(from: from, to: to)
            let moved = valuator.whatMoved(report)
            let split = valuator.savedSplit(of: report)
            #expect(moved.saved == split.saved, "\(window)")
            #expect(moved.markets == split.market, "\(window)")

            let rate = valuator.savingsRate(from: from.adding(days: 1), through: to)
            #expect((rate == nil) == (moved.pay == nil), "\(window)")
            if let rate, let pay = moved.pay {
                // Your pay is the savings rate over the same values.
                #expect(rate.pay == pay, "\(window)")
                #expect(rate.moneyInOut.moneyIn == pay.moneyIn, "\(window)")
                // Its lines add up to what was saved, the one-offs with it.
                #expect(same(pay.cameIn - pay.tax - pay.spent + pay.oneOffs, pay.saved), "\(window)")
                #expect(pay.from == rate.from && pay.through == rate.payThrough, "\(window)")
                #expect(rate.from <= from && rate.payThrough <= to, "\(window)")
                if rate.from == from, rate.payThrough == to {
                    // Over the check-in's own days, the pay saved what net worth did.
                    #expect(pay.saved == moved.saved, "\(window)")
                } else {
                    // The pay counts what was saved over the days it covers
                    // (PROGRESS.md, "Savings rate"), those of the pay
                    // account's values, which start before this check-in
                    // when that account has no value on it: what net worth
                    // saved over those days.
                    let days = valuator.whatMoved(valuator.change(from: rate.from, to: rate.payThrough))
                    #expect(same(pay.saved, days.saved), "\(window)")
                }
            }

            // The month-by-month bars, where the check-ins are a month's ends.
            if from.isEndOfMonth, to.isEndOfMonth, from.yearMonth.next == to.yearMonth {
                let month = valuator.monthlyChanges(from: to.yearMonth, through: to.yearMonth, asOf: to)
                #expect(month.map(\.saved) == [moved.saved], "\(window)")
                #expect(month.map(\.markets) == [moved.markets], "\(window)")
            }
        }
    }

    /// The trades library's broker has a check-in of its own on 15
    /// January, which the bank, where the pay arrives, skips: the savings
    /// rate's days start at the bank's value before, 31 December.
    @Test func aCheckInThePayAccountSkipsStartsTheRatesDaysEarlier() throws {
        let valuator = Valuator(library: try InvariantLibrary.trades.library())
        let rate = try #require(valuator.savingsRate(from: "2026-01-16", through: "2026-01-31"))
        #expect(rate.from == "2025-12-31")
        #expect(rate.saved == 2000)
        let moved = valuator.whatMoved(valuator.change(from: "2026-01-15", to: "2026-01-31"))
        let pay = try #require(moved.pay)
        #expect(pay.moneyIn == 4000)
        // Your pay counts the same days, the broker's deposit of 5 January with them.
        #expect(pay == rate.pay)
        #expect(pay.saved == 2000)
        #expect(pay.from == "2025-12-31")
        // Net worth's split counts its own: the deposit was before 15 January.
        #expect(moved.saved == 1500)
    }
}
