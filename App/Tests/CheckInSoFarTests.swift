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
        let split = valuator.savedSplit(of: change)
        let soFar = CheckInSoFar(rate: rate, split: split)
        let markets = split.market + split.other
        #expect(soFar.markets == markets)
        // Decimal division leaves differences in the last of its 38 digits.
        let gap = abs(soFar.netSaved + soFar.markets + soFar.lost - change.total.change)
        let tolerance = Decimal(sign: .plus, exponent: -6, significand: 1)
        #expect(gap < tolerance)
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

    @Test func theProgressLineSaysDoneAndSaved() {
        let locale = Locale(identifier: "en_US")
        let car = TypedCheckInAccount(account: "car", last: nil, estimate: nil, isUpdated: false)
        let groups = CheckInGroups(date: "2026-10-31", from: nil, money: [], investments: [], typed: [car],
                                   others: [])
        #expect(CheckInWording.progress(groups, saved: 984, currency: .eur, locale: locale).text
            == "0 of 1 done · saved €984 so far")
        let none = CheckInGroups(date: "2026-10-31", from: nil, money: [], investments: [], typed: [], others: [])
        #expect(CheckInWording.progress(none, saved: 0, currency: .eur, locale: locale).text == "Saved €0 so far")
        #expect(CheckInWording.progress(none, saved: -500, currency: .eur, locale: locale).text
            == "€500 more went out than came in so far")
        #expect(CheckInWording.progress(groups, saved: -500, currency: .eur, locale: locale).text
            == "0 of 1 done · €500 more went out than came in so far")
    }

    @Test func withoutAMonthItsAllZero() {
        let soFar = CheckInSoFar(rate: nil, split: nil)
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
        #expect(line.hasSuffix(" · 1 account done · change it later from the check-in\u{2019}s date menu"))
        groups.typed = [TypedCheckInAccount(account: "car", last: nil, estimate: nil, isUpdated: false)]
        #expect(CheckInWording.savedLine(on: "2026-10-31", groups: groups, locale: locale)
            .contains("0 of 1 account done"))
    }
}
