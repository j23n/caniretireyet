import Foundation
import Model
import Testing
import Tracker
@testable import CanIRetireYet

/// Typing an account's balance by hand (UI.md, "Account detail": *Update
/// Value…*; docs/ACCOUNTS.md, "Typed values"): only accounts that take
/// typed values, a balance only, a debt's typed as what's owed. The example
/// library's home (`casa`) types its values; its current account doesn't.
struct TypedValuesTests {
    private let locale = Locale(identifier: "en_US")
    private let today: CalendarDate = "2026-10-11"

    private func d(_ text: String) -> Decimal { PreviewLibrary.d(text) }

    private func account(_ kind: AccountKind, values: ValueEntry? = .typed) -> Account {
        Account(id: "a", name: "A", kind: kind, currency: .eur, opened: "2024-01-01", values: values)
    }

    // MARK: The form

    @Test func aDebtIsTypedAsWhatsOwedAndRecordedNegative() throws {
        let mortgage = account(.mortgage)
        let previous = Valuation(account: "a", date: "2026-06-30", balance: d("-150000"), source: .import)
        var form = TypedValueForm(new: mortgage, on: today, previous: previous, locale: locale)
        #expect(form.balance == "150000")
        form.balance = "148,500"
        let valuation = try #require(form.valuation(locale: locale))
        #expect(valuation.balance == d("-148500"))
        #expect(valuation.date == today)
        #expect(valuation.source == .manual)
        #expect(valuation.moneyIn == nil && valuation.moneyOut == nil && valuation.saved == nil)
        // In credit: a leading +.
        form.balance = "+20"
        #expect(form.valuation(locale: locale)?.balance == 20)
    }

    @Test func anAssetRecordsWhatWasTyped() {
        var form = TypedValueForm(new: account(.property), on: today, previous: nil, locale: locale)
        #expect(form.balance.isEmpty)
        form.balance = "320000"
        #expect(form.valuation(locale: locale)?.balance == 320_000)
    }

    @Test func editingKeepsTheNoteAndMovesTheDate() throws {
        let original = Valuation(account: "a", date: "2026-06-30", balance: 300_000, note: "agent's estimate",
                                 source: .manual)
        var form = TypedValueForm(editing: original, of: account(.property), locale: locale)
        #expect(form.balance == "300000")
        form.date = "2026-07-31"
        form.balance = "305000"
        let valuation = try #require(form.valuation(locale: locale))
        #expect(valuation.date == "2026-07-31")
        #expect(valuation.balance == 305_000)
        #expect(valuation.note == "agent's estimate")
        #expect(form.original?.key == original.key)
    }

    @Test func saveNeedsABalanceAndADateUpToToday() {
        let property = account(.property)
        var form = TypedValueForm(new: property, on: today, previous: nil, locale: locale)
        #expect(form.problems(for: property, today: today, locale: locale)
            == ["Enter the balance. To record nothing owed or held, type 0."])
        form.balance = "abc"
        #expect(form.problems(for: property, today: today, locale: locale) == ["The balance can't be read."])
        form.balance = "0"
        #expect(form.problems(for: property, today: today, locale: locale).isEmpty)
        form.date = "2026-10-12"
        #expect(form.problems(for: property, today: today, locale: locale) == ["Choose a date up to today."])
        var closed = property
        closed.closed = "2026-09-30"
        form.date = "2026-10-01"
        #expect(form.problems(for: closed, today: today, locale: locale)
            == ["Choose a date up to the day the account closed."])
        #expect(TypedValueForm.latestDate(of: closed, today: today) == "2026-09-30")
        #expect(TypedValueForm.latestDate(of: property, today: today) == today)
    }

    @Test func onlyTypedValuesOfAnAccountThatTakesThemAreEditable() {
        let typed = Valuation(account: "a", date: "2026-06-30", balance: 1, source: .manual)
        let imported = Valuation(account: "a", date: "2026-06-30", balance: 1, source: .import)
        #expect(TypedValueForm.canEdit(typed, of: account(.pensionFund)))
        #expect(!TypedValueForm.canEdit(imported, of: account(.pensionFund)))
        #expect(!TypedValueForm.canEdit(typed, of: account(.pensionFund, values: nil)))
        #expect(!TypedValueForm.canEdit(typed, of: account(.cash)))
    }

    // MARK: Saving

    @Test func savingReplacesTheEditedValueAndMovesTheOpeningDateBack() throws {
        var library = PreviewLibrary.library
        let old = Valuation(account: "casa", date: "2026-08-31", balance: 310_000, source: .manual)
        try library.saveTypedValue(old)
        #expect(library.valuations(for: "casa").contains(old))
        var moved = old
        moved.date = "2026-07-31"
        try library.saveTypedValue(moved, replacing: old.key)
        let dates = library.valuations(for: "casa").map(\.date)
        #expect(dates.contains("2026-07-31"))
        #expect(!dates.contains("2026-08-31"))
        let early = Valuation(account: "casa", date: "2024-01-31", balance: 290_000, source: .manual)
        try library.saveTypedValue(early)
        #expect(library.accounts["casa"]?.opened == "2024-01-31")
    }

    @Test func anImportOnlyAccountRefusesTypedValues() {
        var library = PreviewLibrary.library
        let value = Valuation(account: "conto-fineco", date: "2026-10-05", balance: 1000, source: .manual)
        do {
            try library.saveTypedValue(value)
            Issue.record("A current account took a typed value.")
        } catch {
            #expect(error as? LibraryEditError == .valuesNotTyped("conto-fineco"))
        }
        #expect(library == PreviewLibrary.library)
    }

    // MARK: The account's form

    @Test func onlyBalanceKindsWithoutMoneyInOutOfferTypedValues() {
        for kind in AccountKind.knownValues {
            var form = AccountForm(editing: account(kind, values: nil))
            form.values = .typed
            let offered = [.pensionFund, .tfr, .property, .belongings, .loan, .mortgage, .other].contains(kind)
                && form.valuationMode == .balance
            #expect(form.offersTypedValues == offered, "\(kind)")
            #expect(form.account(id: "a").values == (offered ? .typed : nil), "\(kind)")
        }
    }

    @Test func switchingBackToImportedLeavesTheFieldOut() {
        var form = AccountForm(editing: account(.pensionFund))
        #expect(form.values == .typed)
        #expect(form.account(id: "a").values == .typed)
        form.values = .imported
        #expect(form.account(id: "a").values == nil)
        // A kind that doesn't take typed values drops it.
        var current = AccountForm(editing: account(.pensionFund))
        current.setKind(.cash)
        #expect(!current.offersTypedValues)
        #expect(current.account(id: "a").values == nil)
    }

    @Test func aStartingEstimateHasNoChoiceToMake() {
        var estimate = account(.pensionFund, values: nil)
        estimate.tags = [Account.startingEstimateTag]
        let form = AccountForm(editing: estimate)
        #expect(!form.offersTypedValues)
        #expect(form.account(id: "a").values == nil)
    }

    // MARK: Where they show

    @Test func theDetailOffersUpdateValueOnlyForTypedAccounts() throws {
        var library = PreviewLibrary.library
        try library.saveTypedValue(Valuation(account: "casa", date: "2026-09-30", balance: 315_000, source: .manual))
        let valuator = Valuator(library: library)
        func detail(_ id: AccountID) throws -> AccountDetailData {
            let account = try #require(library.accounts[id])
            return AccountDetailData(account: account, library: library, valuator: valuator,
                                     today: PreviewLibrary.latestCheckIn, stalenessThreshold: 45)
        }
        let home = try detail("casa")
        #expect(home.offersUpdateValue)
        #expect(home.valuesSource == "Values come from your imports and from Update Value.")
        #expect(home.valuations.filter(home.isEditable).map(\.id.date) == ["2026-09-30"])
        let current = try detail("conto-fineco")
        #expect(!current.offersUpdateValue)
        #expect(current.valuesSource == "Values come from your imports.")
        #expect(!current.valuations.contains(where: current.isEditable))
    }
}
