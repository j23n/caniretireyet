import Foundation
import Model
import Testing
import Tracker
@testable import CanIRetireYet

/// The fields of a typed account in the check-in (UI.md, "Check-in": *To
/// confirm*), from the example library: the home (`casa`) types its
/// values, the last on 30 June 2026 at 312.000 €, so a new one asks what
/// was added.
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
        #expect(form.asksWhatMoved)
        #expect(form.added.isEmpty)
    }

    /// A check-in opened again edits the value typed on its date, so what
    /// moved keeps what was typed.
    @Test func aValueTypedOnTheDateIsEdited() throws {
        var library = PreviewLibrary.library
        library.upsert(Valuation(account: "casa", date: "2026-10-31", balance: d("318000"), saved: d("1500"),
                                 source: .manual))
        let home = try #require(library.accounts["casa"])
        let form = CheckInTypedValue.form(for: home, on: "2026-10-31", valuator: Valuator(library: library),
                                          today: "2026-10-31", locale: locale)
        #expect(form.original?.date == "2026-10-31")
        #expect(form.balance == "318000")
        #expect(form.added == "1500")
        #expect(form.asksWhatMoved)
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
        #expect(form.isMissingWhatMoved(locale: locale))
        form.added = "0"
        #expect(form.problems(for: home, today: "2026-10-31", locale: locale).isEmpty)
        let valuation = try #require(form.valuation(locale: locale))
        #expect(valuation.account == "casa")
        #expect(valuation.date == "2026-10-31")
        #expect(valuation.balance == d("318000"))
        #expect(valuation.saved == 0)
        #expect(valuation.source == .manual)
    }

    @Test @MainActor func aChangedFieldIsSavedWithTheCheckIn() throws {
        let library = PreviewLibrary.library
        let home = try #require(library.accounts["casa"])
        let form = CheckInTypedValue.form(for: home, on: "2026-10-31", valuator: Valuator(library: library),
                                          today: "2026-10-31", locale: locale)
        let edits = CheckInTypedEdits()
        edits.note(home, form: form, edited: form)
        #expect(try edits.valuations(today: "2026-10-31", locale: locale).isEmpty)
        var edited = form
        edited.balance = "318,000"
        edited.added = "1500"
        edits.note(home, form: form, edited: edited)
        let valuations = try edits.valuations(today: "2026-10-31", locale: locale)
        #expect(valuations.map { $0.account } == ["casa"])
        #expect(valuations.first?.balance == d("318000"))
        #expect(valuations.first?.saved == 1500)
        // Typed back to where it started, it needs no save.
        edits.note(home, form: form, edited: form)
        #expect(edits.edits.isEmpty)
    }

    @Test @MainActor func aFieldThatCantBeSavedStopsTheCheckInNamingItsAccount() throws {
        let library = PreviewLibrary.library
        let home = try #require(library.accounts["casa"])
        let form = CheckInTypedValue.form(for: home, on: "2026-10-31", valuator: Valuator(library: library),
                                          today: "2026-10-31", locale: locale)
        let edits = CheckInTypedEdits()
        var edited = form
        edited.balance = "318,000"
        edits.note(home, form: form, edited: edited)
        // What was added is still missing.
        #expect(throws: CheckInTypedEdits.Problem.self) {
            try edits.valuations(today: "2026-10-31", locale: locale)
        }
        edited.added = "0"
        edited.balance = "abc"
        edits.note(home, form: form, edited: edited)
        #expect(throws: CheckInTypedEdits.Problem.self) {
            try edits.valuations(today: "2026-10-31", locale: locale)
        }
        do {
            _ = try edits.valuations(today: "2026-10-31", locale: locale)
        } catch {
            #expect(error.localizedDescription.hasPrefix("\(home.name): "))
        }
    }

    @Test func thePriceButtonSaysTheStatusInAFewWords() {
        #expect(CheckInPriceStatus(kind: .updated, title: "Prices and FX updated (4)").shortTitle
            == "Prices updated")
        #expect(CheckInPriceStatus(kind: .needsAttention, title: "1 price couldn't be fetched").shortTitle
            == "Check prices")
    }
}
