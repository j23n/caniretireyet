import Foundation
import Model
import Testing
@testable import CanIRetireYet

/// A new account records its values the way its kind does, with no choice
/// to make: brokerage, crypto and metals record trades, the others a
/// balance (docs/ACCOUNTS.md, "Decisions"; UI.md, "Add account").
struct AccountFormTests {
    private let locale = Locale(identifier: "en_US")
    private let today: CalendarDate = "2026-10-11"

    private func newAccount(_ kind: AccountKind) -> AccountForm {
        var form = AccountForm(residence: "IT", currency: .eur, today: today)
        form.setKind(kind)
        form.name = "New account"
        return form
    }

    @Test(arguments: [AccountKind.brokerage, .crypto, .metals])
    func aNewAccountOfAKindThatHoldsPositionsRecordsTrades(_ kind: AccountKind) {
        let form = newAccount(kind)
        #expect(form.valuationMode == .trades)
        #expect(form.recordsTrades && form.holdsPositions)
        let account = form.account(id: "new-account", locale: locale)
        #expect(account.recordsTrades)
        // The kind's default: nothing to write.
        #expect(account.valuation == nil)
    }

    @Test(arguments: [AccountKind.cash, .savings, .pensionFund, .property, .mortgage])
    func otherNewAccountsRecordABalance(_ kind: AccountKind) {
        let form = newAccount(kind)
        #expect(form.valuationMode == .balance)
        #expect(!form.holdsPositions)
    }

    @Test func aNewBrokeragesPositionsBecomeOpeningTrades() throws {
        let account = newAccount(.brokerage).account(id: "new-account", locale: locale)
        var opening = AccountOpeningForm()
        opening.cash = "250"
        opening.addPosition("vwce")
        opening[position: 0].quantity = "10"
        opening[position: 0].cost = "1000"
        #expect(opening.problems(holdsPositions: true, locale: locale).isEmpty)

        let trades = opening.openingTrades(for: account, locale: locale)
        #expect(trades.count == 1)
        #expect(trades.first?.type == .opening)
        #expect(trades.first?.quantity == 10)
        #expect(trades.first?.cost == 1_000)

        let valuation = try #require(opening.valuation(for: account, in: PreviewLibrary.library, locale: locale))
        #expect(valuation.cash == 250)
        #expect(valuation.positions.isEmpty)
        #expect(valuation.balance == nil)
    }

    /// An edited account keeps its own mode, also one written before
    /// format version 4.
    @Test func anEditedAccountKeepsItsMode() {
        var account = Account(id: "old", name: "Old", kind: .brokerage, currency: .eur, opened: "2020-01-01")
        account.valuation = .holdings
        var form = AccountForm(editing: account)
        #expect(form.valuationMode == .holdings)
        form.setKind(.cash)
        #expect(form.valuationMode == .holdings)
    }

    /// Belongings ask for their loss of value a year, in per cent.
    @Test func belongingsTakeTheirLossOfValueAYear() {
        var form = AccountForm(residence: "IT", currency: .eur, today: today)
        #expect(!form.takesDepreciation)
        form.setKind(.belongings)
        form.name = "Car"
        form.depreciation = "15"
        #expect(form.problems(locale: locale).isEmpty)
        #expect(form.account(id: "car", locale: locale).depreciation == Decimal(string: "0.15"))
        form.depreciation = "120"
        #expect(form.problems(locale: locale) == ["Type the loss of value a year as a percentage from 0 to 99."])
        form.depreciation = ""
        #expect(form.account(id: "car", locale: locale).depreciation == nil)
        // 0 is no loss of value: nothing is stored.
        form.depreciation = "0"
        #expect(form.problems(locale: locale).isEmpty)
        #expect(form.account(id: "car", locale: locale).depreciation == nil)
        var car = Account(id: "car", name: "Car", kind: .belongings, currency: .eur, opened: "2026-01-01")
        car.depreciation = Decimal(string: "0.12")
        #expect(AccountForm(editing: car, locale: locale).depreciation == "12")
        // Another kind doesn't lose value: it drops the loss of value.
        var edited = AccountForm(editing: car, locale: locale)
        edited.setKind(.property)
        #expect(!edited.takesDepreciation)
        #expect(edited.account(id: "car", locale: locale).depreciation == nil)
        edited.setKind(.other)
        #expect(!edited.takesDepreciation)
    }
}
