import Foundation
import Model
import Testing
import Tracker
@testable import CanIRetireYet

/// The field of a typed account in the check-in (UI.md, "Check-in": *To
/// confirm*), from the example library: the home (`casa`) types its
/// values, the last on 30 June 2026 at 312.000 €.
struct CheckInTypedValueTests {
    private let locale = Locale(identifier: "en_US")

    private func d(_ text: String) -> Decimal { PreviewLibrary.d(text) }

    @Test func theFieldStartsFromTheLastValueOnTheCheckInsDate() throws {
        let library = PreviewLibrary.library
        let home = try #require(library.accounts["casa"])
        let form = CheckInTypedValue.form(for: home, on: "2026-10-31", valuator: Valuator(library: library),
                                          today: "2026-10-31", locale: locale)
        #expect(form.date == "2026-10-31")
        #expect(form.original == nil)
        #expect(form.balance == "312000")
    }

    @Test func aDateAfterTodayIsBroughtBackToToday() throws {
        let library = PreviewLibrary.library
        let home = try #require(library.accounts["casa"])
        let form = CheckInTypedValue.form(for: home, on: "2026-10-31", valuator: Valuator(library: library),
                                          today: "2026-10-24", locale: locale)
        #expect(form.date == "2026-10-24")
    }

    @Test func savingTheFieldWritesATypedBalanceOnTheDate() throws {
        let library = PreviewLibrary.library
        let home = try #require(library.accounts["casa"])
        var form = CheckInTypedValue.form(for: home, on: "2026-10-31", valuator: Valuator(library: library),
                                          today: "2026-10-31", locale: locale)
        form.balance = "318,000"
        #expect(form.problems(for: home, today: "2026-10-31", locale: locale).isEmpty)
        let valuation = try #require(form.valuation(locale: locale))
        #expect(valuation.account == "casa")
        #expect(valuation.date == "2026-10-31")
        #expect(valuation.balance == d("318000"))
        #expect(valuation.source == .manual)
    }

    @Test func thePriceButtonSaysTheStatusInAFewWords() {
        #expect(CheckInPriceStatus(kind: .updated, title: "Prices and FX updated (4)").shortTitle
            == "Prices updated")
        #expect(CheckInPriceStatus(kind: .needsAttention, title: "1 price couldn't be fetched").shortTitle
            == "Check prices")
    }
}
