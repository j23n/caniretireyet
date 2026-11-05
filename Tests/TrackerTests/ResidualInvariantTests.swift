import Foundation
import Model
import Testing
import TestSupport
import Tracker

/// Invariant B1: where every amount is known, nothing is left unexplained.
///
/// `ValueChange.market` and `WhatMoved.unexplained` are what's left once
/// the other parts are counted, so they add up by construction, and a
/// wrong saved amount would show up only as wrong markets. These tests
/// check that the rest is zero wherever nothing is unknown: every value's
/// saved amount known (``InvariantLibrary/everythingKnown(_:)``), every
/// price and rate there, and, for an account's own other, its records
/// starting before the window. A depreciating car's loss is lost value,
/// its own part, so it's no exception.
struct ResidualInvariantTests {
    @Test(arguments: InvariantLibrary.allCases)
    func nothingIsUnexplainedWhereEverythingIsKnown(_ which: InvariantLibrary) throws {
        let valuator = Valuator(library: InvariantLibrary.everythingKnown(try which.library()))
        for (from, to) in Windows.all(valuator) {
            let report = valuator.change(from: from, to: to)
            #expect(report.isPriced, "\(from)…\(to)")
            let moved = valuator.whatMoved(report)
            #expect(same(moved.unexplained, 0), "\(from)…\(to)")
            for account in report.accounts {
                guard let first = valuator.firstRecordDate(of: account.account), first <= from else { continue }
                #expect(same(account.change.other, 0), "\(account.account) \(from)…\(to)")
            }
            // The Overview's split puts what nothing explains, one-offs and
            // what new accounts started with under other: here only the last two.
            let split = valuator.savedSplit(of: report)
            #expect(same(split.other, moved.oneOffs + moved.startedWith), "\(from)…\(to)")
            #expect(split.lost == moved.lost, "\(from)…\(to)")
        }
    }

    /// Trends' *Where your money came from*: between two points, markets
    /// grew by what the change report counts as markets and lost value,
    /// and nothing else.
    @Test(arguments: InvariantLibrary.allCases)
    func marketsAreOnlyMarketsWhereEverythingIsKnown(_ which: InvariantLibrary) throws {
        let valuator = Valuator(library: InvariantLibrary.everythingKnown(try which.library()))
        let end = try #require(Windows.checkIns(valuator).last)
        for grain in PeriodGrain.allCases {
            let points = valuator.moneySources(grain, through: end).points
            for (before, after) in zip(points, points.dropFirst()) {
                let report = valuator.change(from: before.date, to: after.date, in: .planAssets)
                #expect(same(after.markets - before.markets, report.total.market + report.total.lost),
                        "\(grain) \(before.date)…\(after.date)")
            }
        }
    }

    /// The example library as it is: the home's value of 30 June has no
    /// saved amount, so its change is other there, and only there.
    @Test func theExampleLibrarysOnlyUnknownIsTheHomesJune() throws {
        let valuator = Valuator(library: try Fixtures.exampleLibrary())
        for (from, to) in Windows.consecutive(valuator) {
            let report = valuator.change(from: from, to: to)
            let unknown = report.accounts.filter { !same($0.change.other, 0) }.map(\.account)
            #expect(unknown == (to == "2026-06-30" ? ["casa"] : []), "\(from)…\(to)")
            #expect(same(valuator.whatMoved(report).unexplained, report.total.other), "\(from)…\(to)")
        }
    }
}
