import Foundation
import Model
import Testing
import Tracker
@testable import CanIRetireYet

/// The check-in's month so far (UI.md, "Check-in"), on the example library's
/// latest check-in.
struct CheckInSoFarTests {
    @Test func theBarsPartsAddUpToTheChange() throws {
        let library = PreviewLibrary.library
        let valuator = Valuator(library: library)
        let date = PreviewLibrary.latestCheckIn
        let from = try #require(valuator.checkInGroups(on: date, in: library).from)
        let rate = valuator.savingsRate(from: from.adding(days: 1), through: date)
        let change = valuator.change(from: from, to: date)
        let soFar = CheckInSoFar(rate: rate, split: valuator.savedSplit(of: change))
        let parts = soFar.netSaved + soFar.markets + soFar.lost
        let total = change.total.change
        #expect(parts == total)
        #expect(soFar.saved == rate?.saved ?? 0)
        let amounts = soFar.wentTo.map(\.amount)
        let sorted = amounts.sorted(by: >)
        #expect(amounts == sorted)
        #expect(!amounts.contains(0))
    }

    @Test func theDoneCountSaysAccountOnce() {
        let casa = TypedCheckInAccount(account: "casa", last: nil, estimate: nil, isUpdated: false)
        let one = CheckInGroups(date: "2026-10-31", from: nil, money: [], investments: [], typed: [casa],
                                others: [])
        #expect(CheckInWording.doneCount(one) == "0 of 1 account done")
    }

    @Test func withoutAMonthItsAllZero() {
        let soFar = CheckInSoFar(rate: nil, split: nil)
        #expect(soFar.saved == 0)
        #expect(soFar.rate == nil)
        #expect(soFar.wentTo.isEmpty)
        let split = soFar.split(currency: .eur, locale: Locale(identifier: "en_US"))
        #expect(split.parts.count > 1)
    }
}
