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
                // The same values' money in, one-offs and tax.
                #expect(rate.moneyInOut.moneyIn == pay.moneyIn, "\(window)")
                #expect(rate.oneOffs == moved.oneOffs, "\(window)")
                if rate.from == from {
                    #expect(rate.pay == pay, "\(window)")
                } else {
                    // The savings rate counts what was saved over the days
                    // the pay covers (PROGRESS.md, "Savings rate"): from the
                    // value before the pay account's, which is before this
                    // check-in when the pay account has none on it. So it's
                    // what moved net worth over those days, and, as saved
                    // adds up over a check-in (B3), this window's saved plus
                    // the days before it.
                    #expect(rate.from < from, "\(window)")
                    let wider = valuator.whatMoved(valuator.change(from: rate.from, to: to))
                    let before = valuator.whatMoved(valuator.change(from: rate.from, to: from))
                    #expect(rate.pay == wider.pay, "\(window)")
                    #expect(rate.saved == before.saved + moved.saved, "\(window)")
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
        #expect(try #require(moved.pay).moneyIn == 4000)
        // The broker's deposit of 5 January was before 15 January.
        #expect(moved.saved == 1500)
    }
}
