import Foundation
import Model
import Testing
import Tracker
@testable import CanIRetireYet

/// *Update Value* and *Edit Value* ask for the same fields as the check-in,
/// by the account's kind (docs/ACCOUNTS.md, "What each kind asks for"), on
/// the example library.
@MainActor
struct ValuationFormsTests {
    private let library = PreviewLibrary.library
    private let locale = Locale(identifier: "en_US")
    private let date: CalendarDate = "2026-10-31"

    private func fields(_ account: AccountID, on date: CalendarDate = "2026-10-31") throws -> AccountValuationFields {
        try #require(AccountValuationDraft(account: account, date: date, library: library).fields)
    }

    // MARK: The fields by kind

    @Test func cashAsksForMoneyInAndOutAndWorksOutItsNewMoney() throws {
        let fields = try fields("conto-fineco")
        #expect(fields.balance && fields.moneyInOut)
        #expect(!fields.interest && !fields.flow)
    }

    @Test func savingsAlsoAsksForTheInterest() throws {
        let fields = try fields("conto-deposito")
        #expect(fields.moneyInOut && fields.interest)
        #expect(!fields.flow)
    }

    @Test func aDebtAsksOnlyForWhatsOwed() throws {
        let fields = try fields("mutuo-casa")
        #expect(fields.balance)
        #expect(!fields.moneyInOut && !fields.interest && !fields.flow)
    }

    @Test(arguments: ["fondo-pensione", "tfr", "casa"] as [AccountID])
    func newMoneyIsAskedForWhereTheKindAsks(_ account: AccountID) throws {
        let fields = try fields(account)
        #expect(fields.flow)
        #expect(!fields.moneyInOut)
    }

    @Test func aTradesAccountRecordsItsCash() throws {
        let fields = try fields("directa")
        #expect(!fields.balance && !fields.moneyInOut)
        #expect(fields.flow)
    }

    /// An account's first value asks only for its balance.
    @Test func aFirstValueAsksOnlyForTheBalance() throws {
        let opened = try #require(library.accounts["conto-deposito"]?.opened)
        let fields = try fields("conto-deposito", on: opened.adding(days: -1))
        #expect(fields.balance)
        #expect(!fields.moneyInOut && !fields.interest && !fields.flow)
    }

    // MARK: Update Value

    @Test func updateValueOnACashAccountRecordsMoneyInAndOut() throws {
        // 4.210,55 → 4.510,55 with 3.400 in: money out follows, 3.100.
        let base = AccountValuationDraft(account: "conto-fineco", date: date, library: library)
        var input = AccountValuationInput()
        input.balance = "4510.55"
        input.moneyIn = "3400"
        #expect(input.problems(locale: locale).isEmpty)
        let valuation = try #require(input.applied(to: base, isLiability: false, locale: locale)
            .valuation(in: library))
        #expect(valuation.balance == Decimal(string: "4510.55"))
        #expect(valuation.flow == 300)
        #expect(valuation.moneyIn == 3_400)
        #expect(valuation.moneyOut == 3_100)
        #expect(valuation.moved == 0)
    }

    @Test func updateValueSavedAsItIsRecordsNothingCameInOrWentOut() throws {
        let base = AccountValuationDraft(account: "conto-fineco", date: date, library: library)
        let valuation = try #require(base.valuation(in: library))
        #expect(valuation.flow == 0)
        #expect(valuation.moneyIn == 0)
        #expect(valuation.moneyOut == 0)
    }

    @Test func updateValueTakesASavingsAccountsInterestOutOfItsNewMoney() throws {
        // 17.365,55 → 17.415,55, of which 20 interest: new money 30, moved 30.
        let base = AccountValuationDraft(account: "conto-deposito", date: date, library: library)
        var input = AccountValuationInput()
        input.balance = "17415.55"
        input.interest = "20"
        let valuation = try #require(input.applied(to: base, isLiability: false, locale: locale)
            .valuation(in: library))
        #expect(valuation.interest == 20)
        #expect(valuation.flow == 30)
        #expect(valuation.moneyIn == 0 && valuation.moneyOut == 0)
        #expect(valuation.moved == 30)
    }

    @Test func updateValueRejectsNegativeMoneyInAndOut() {
        var input = AccountValuationInput()
        input.moneyOut = "-20"
        #expect(input.problems(locale: locale) == ["Money in and out can't be negative."])
        input.moneyOut = "abc"
        #expect(input.problems(locale: locale) == ["The money out can't be read."])
    }

    // MARK: Edit Value

    private func form(_ account: AccountID, on date: CalendarDate) throws -> AccountValuationForm {
        let valuation = try #require(library.valuations(for: account).first { $0.date == date })
        let kind = try #require(library.accounts[account]?.kind)
        return AccountValuationForm(valuation, kind: kind, holdsPositions: false, locale: locale)
    }

    @Test func editValueWorksOutACashAccountsNewMoney() throws {
        var form = try form("conto-fineco", on: "2026-09-30")
        let fields = form.fields(in: library)
        #expect(fields.moneyInOut && !fields.flow)
        let previous = try #require(form.previous(in: library)?.balance)
        form.balance = "5000"
        form.flow = "123"  // Not shown: ignored.
        let valuation = try #require(form.valuation(in: library, locale: locale))
        #expect(valuation.flow == 5_000 - previous)
        #expect(valuation.source == .manual)
    }

    @Test func editValueAsksForASavingsAccountsInterest() throws {
        var form = try form("conto-deposito", on: "2026-09-30")
        #expect(form.fields(in: library).interest)
        #expect(form.interest == "35.05")
        let before = try #require(library.valuations(for: "conto-deposito").first { $0.date == "2026-09-30" })
        form.interest = "45.05"
        let valuation = try #require(form.valuation(in: library, locale: locale))
        #expect(valuation.interest == Decimal(string: "45.05"))
        #expect(valuation.flow == (before.flow ?? 0) - 10)
    }

    @Test func editValueKeepsAskingForNewMoneyWhereTheKindAsks() throws {
        var form = try form("fondo-pensione", on: "2026-09-30")
        let fields = form.fields(in: library)
        #expect(fields.flow && !fields.moneyInOut)
        form.flow = "1400"
        #expect(try #require(form.valuation(in: library, locale: locale)).flow == 1_400)
    }

    @Test func editValueOfAFirstValueAsksOnlyForTheBalance() throws {
        let first = try #require(library.valuations(for: "conto-fineco").first)
        let form = try form("conto-fineco", on: first.date)
        let fields = form.fields(in: library)
        #expect(!fields.moneyInOut && !fields.interest && !fields.flow)
        #expect(form.problems(in: library, locale: locale).isEmpty)
    }

    @Test func editingANoteKeepsADebtsNewMoney() throws {
        var library = self.library
        var typed = try #require(library.valuations(for: "mutuo-casa").first { $0.date == "2026-08-31" })
        typed.flow = 900  // Typed or imported before, not the whole change.
        library.upsert(typed)
        var form = AccountValuationForm(typed, kind: .mortgage, holdsPositions: false, locale: locale)
        form.note = "Statement checked"
        let valuation = try #require(form.valuation(in: library, locale: locale))
        #expect(valuation.flow == 900)
        #expect(valuation.source == typed.source)
        form.balance = "141000"
        #expect(try #require(form.valuation(in: library, locale: locale)).flow != 900)
    }

    /// A value from before money in and out were asked for has neither,
    /// and may keep it: both or neither.
    @Test func editValueOfAnOlderValueAsksForBothMoneyInAndOutOrNeither() throws {
        var form = try form("conto-fineco", on: "2026-06-30")
        #expect(!form.recordsMoneyInOut)
        #expect(try #require(form.valuation(in: library, locale: locale)).moneyIn == nil)
        form.moneyOut = "100"
        #expect(form.problems(in: library, locale: locale) == ["Enter both money in and out, or neither."])
    }

    /// A value that records money in and out reads empty fields as *Update
    /// Value* does: money in 0, money out what money in and the new money
    /// suggest.
    @Test func editValueFillsEmptyMoneyInAndOutOfAValueThatRecordsThem() throws {
        var form = try form("conto-fineco", on: "2026-09-30")
        #expect(form.recordsMoneyInOut)
        form.moneyIn = ""
        form.moneyOut = ""
        #expect(form.problems(in: library, locale: locale).isEmpty)
        let valuation = try #require(form.valuation(in: library, locale: locale))
        let flow = try #require(valuation.flow)
        #expect(valuation.moneyIn == 0)
        #expect(valuation.moneyOut == max(0, -flow))
        #expect(form.suggestedMoneyOut(in: library, locale: locale) == valuation.moneyOut)
    }
}
