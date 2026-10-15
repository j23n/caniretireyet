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
        #expect(form.recordsTrades)
        let account = form.account(id: "new-account", locale: locale)
        #expect(account.recordsTrades)
        // The kind's default: nothing to write.
        #expect(account.valuation == nil)
    }

    /// An edited account keeps its own mode when its kind changes.
    @Test func anEditedAccountKeepsItsMode() {
        let account = Account(id: "old", name: "Old", kind: .brokerage, currency: .eur, opened: "2020-01-01")
        var form = AccountForm(editing: account)
        #expect(form.valuationMode == .trades)
        form.setKind(.cash)
        #expect(form.valuationMode == .trades)
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

    /// A tax pot counts in neither net worth nor plans unless chosen by
    /// hand, and the file writes only what differs from the kind.
    @Test func aTaxPotIsLeftOutOfNetWorthAndPlans() {
        var form = newAccount(.taxPot)
        #expect(!form.includedInNetWorth && !form.includedInPlan)
        #expect(form.account(id: "pot", locale: locale).includeIn == nil)
        form.chosenNetWorthInclusion = true
        #expect(form.account(id: "pot", locale: locale).includeIn == IncludeIn(netWorth: true))
        // Chosen by hand, it stays when the kind changes; the plan follows the kind.
        form.setKind(.savings)
        #expect(form.includedInNetWorth && form.includedInPlan)
        #expect(form.account(id: "pot", locale: locale).includeIn == nil)
    }

    /// A current account turned into a tax pot keeps counting where it did,
    /// so the file writes it.
    @Test func anAccountTurnedIntoATaxPotKeepsItsInclusion() {
        let bank = Account(id: "bank", name: "Bank", kind: .cash, currency: .eur, opened: "2026-01-01")
        var form = AccountForm(editing: bank)
        form.setKind(.taxPot)
        let pot = form.account(id: "bank", locale: locale)
        #expect(pot.includeIn == IncludeIn(netWorth: true, plan: true))
        #expect(pot.includedInNetWorth && pot.includedInPlan)
    }
}
