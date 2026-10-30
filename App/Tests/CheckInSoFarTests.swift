import Foundation
import Model
import Testing
import Tracker
@testable import CanIRetireYet

/// The check-in's month so far (UI.md, "Check-in"), on the example library's
/// latest check-in.
struct CheckInSoFarTests {
    @Test func theMonthSoFarAddsUp() throws {
        let library = PreviewLibrary.library
        let valuator = Valuator(library: library)
        let date = PreviewLibrary.latestCheckIn
        let from = try #require(valuator.checkInGroups(on: date, in: library).from)
        let rate = valuator.savingsRate(from: from.adding(days: 1), through: date)
        let change = valuator.change(from: from, to: date)
        let soFar = CheckInSoFar(rate: rate, change: change)
        #expect(soFar.cameIn - soFar.tax - soFar.spent == soFar.saved)
        #expect(soFar.markets == change.total.market + change.total.other)
        let amounts = soFar.wentTo.map(\.amount)
        #expect(amounts == amounts.sorted(by: >))
        #expect(!amounts.contains(0))
    }

    @Test func withoutAMonthItsAllZero() {
        let soFar = CheckInSoFar(rate: nil, change: nil)
        #expect(soFar.saved == 0)
        #expect(soFar.rate == nil)
        #expect(soFar.wentTo.isEmpty)
        let split = soFar.split(currency: .eur, locale: Locale(identifier: "en_US"))
        #expect(split.parts.count > 1)
    }

    @Test func theSavedLineSaysHowManyAreDone() {
        let locale = Locale(identifier: "en_US")
        var groups = CheckInGroups(date: "2026-10-31", from: "2026-09-30", money: [], investments: [],
                                   typed: [TypedCheckInAccount(account: "car", last: nil, estimate: 100,
                                                               isUpdated: false)],
                                   others: [])
        let line = CheckInWording.savedLine(on: "2026-10-31", groups: groups, locale: locale)
        #expect(line.hasSuffix(" · all 1 account done · change it later from the check-in\u{2019}s date menu"))
        groups.typed = [TypedCheckInAccount(account: "car", last: nil, estimate: nil, isUpdated: false)]
        #expect(CheckInWording.savedLine(on: "2026-10-31", groups: groups, locale: locale)
            .contains("0 of 1 account done"))
    }
}
