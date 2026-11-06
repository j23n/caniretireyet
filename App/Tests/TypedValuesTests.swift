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
        var form = TypedValueForm(new: mortgage, on: today, previous: previous, firstValue: previous.date,
                                  locale: locale)
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
        var form = TypedValueForm(new: account(.property), on: today, previous: nil, firstValue: nil, locale: locale)
        #expect(form.balance.isEmpty)
        form.balance = "320000"
        #expect(form.valuation(locale: locale)?.balance == 320_000)
    }

    @Test func editingKeepsTheNoteAndMovesTheDate() throws {
        var original = Valuation(account: "a", date: "2026-06-30", balance: 300_000, note: "agent's estimate",
                                 source: .manual)
        original.saved = 1000
        original.moneyIn = 200
        original.moneyOut = 100
        var form = TypedValueForm(editing: original, of: account(.property), firstOtherValue: nil, locale: locale)
        #expect(form.balance == "300000")
        form.date = "2026-07-31"
        form.balance = "305000"
        let valuation = try #require(form.valuation(locale: locale))
        #expect(valuation.date == "2026-07-31")
        #expect(valuation.balance == 305_000)
        #expect(valuation.note == "agent's estimate")
        #expect(valuation.saved == nil && valuation.moneyIn == nil && valuation.moneyOut == nil)
        #expect(form.original?.key == original.key)
    }

    @Test func saveNeedsABalanceAndADateUpToToday() {
        let property = account(.property)
        var form = TypedValueForm(new: property, on: today, previous: nil, firstValue: nil, locale: locale)
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

    // MARK: What moved

    /// After the account's first value, an investment's or pension's typed
    /// value asks what was added, required, 0 allowed; its first doesn't.
    @Test func aValueAfterTheFirstAsksWhatWasAdded() throws {
        let fund = account(.pensionFund)
        var first = TypedValueForm(new: fund, on: today, previous: nil, firstValue: nil, locale: locale)
        first.balance = "20000"
        #expect(!first.asksWhatMoved)
        #expect(first.problems(for: fund, today: today, locale: locale).isEmpty)
        #expect(first.valuation(locale: locale)?.saved == nil)

        let previous = Valuation(account: "a", date: "2026-06-30", balance: 19000, source: .manual)
        var form = TypedValueForm(new: fund, on: today, previous: previous, firstValue: previous.date,
                                  locale: locale)
        #expect(form.whatMoved == .added)
        #expect(form.addedLabel == "Paid in")
        #expect(form.asksWhatMoved)
        form.balance = "20000"
        #expect(form.isMissingWhatMoved(locale: locale))
        #expect(form.problems(for: fund, today: today, locale: locale)
            == ["Enter what you added since the last value. If nothing, type 0."])
        #expect(form.valuation(locale: locale) == nil)
        form.added = "0"
        #expect(form.problems(for: fund, today: today, locale: locale).isEmpty)
        #expect(form.valuation(locale: locale)?.saved == 0)
        form.added = "400"
        let valuation = try #require(form.valuation(locale: locale))
        #expect(valuation.saved == 400)
        #expect(valuation.moneyIn == nil && valuation.interest == nil)

        var brokerage = account(.brokerage)
        brokerage.valuation = .balance
        let typed = TypedValueForm(new: brokerage, on: today, previous: previous, firstValue: previous.date,
                                   locale: locale)
        #expect(typed.whatMoved == .added && typed.addedLabel == "You added")
    }

    /// A savings account's typed value after its first asks what came in,
    /// what went out and the interest, each required, the first two
    /// without a sign.
    @Test func aSavingsValueAfterTheFirstAsksMoneyInAndOutAndInterest() throws {
        let savings = account(.savings)
        let previous = Valuation(account: "a", date: "2026-06-30", balance: 20000, source: .manual)
        var form = TypedValueForm(new: savings, on: today, previous: previous, firstValue: previous.date,
                                  locale: locale)
        #expect(form.whatMoved == .moneyInOut)
        form.balance = "20040"
        form.cameIn = "0"
        #expect(form.problems(for: savings, today: today, locale: locale)
            == ["Enter what came in, what went out and the interest since the last value. If nothing, type 0."])
        form.wentOut = "-5"
        form.interest = "40"
        #expect(form.problems(for: savings, today: today, locale: locale)
            == ["Type what came in and what went out without a sign."])
        form.wentOut = "0"
        let valuation = try #require(form.valuation(locale: locale))
        #expect(valuation.moneyIn == 0 && valuation.moneyOut == 0 && valuation.interest == 40)
        #expect(valuation.saved == nil)
    }

    /// Editing keeps what moved; moved to before every other value, it's
    /// the first and records a balance only. A starting estimate, a debt
    /// and belongings never ask.
    @Test func editingKeepsWhatMovedUntilItsTheFirstValue() throws {
        let fund = account(.pensionFund)
        let original = Valuation(account: "a", date: "2026-07-31", balance: 20000, saved: 400, source: .manual)
        var form = TypedValueForm(editing: original, of: fund, firstOtherValue: "2026-06-30", locale: locale)
        #expect(form.added == "400")
        #expect(form.valuation(locale: locale)?.saved == 400)
        form.date = "2026-05-31"
        #expect(!form.asksWhatMoved)
        #expect(form.valuation(locale: locale)?.saved == nil)

        var estimate = account(.savings)
        estimate.tags = [Account.startingEstimateTag]
        for other in [estimate, account(.mortgage), account(.belongings)] {
            let typed = TypedValueForm(new: other, on: today, previous: original, firstValue: original.date,
                                       locale: locale)
            #expect(!typed.asksWhatMoved, "\(other.kind)")
        }
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

    @Test func everyKindButCurrentCardsAndTaxPotsOffersTypedValues() {
        let importOnly: [AccountKind] = [.cash, .creditCard, .taxPot]
        for kind in AccountKind.knownValues {
            var form = AccountForm(editing: account(kind, values: nil))
            form.values = .typed
            let offered = !importOnly.contains(kind)
            #expect(form.offersTypedValues == offered, "\(kind)")
            #expect(form.account(id: "a").values == (offered ? .typed : nil), "\(kind)")
            #expect(form.account(id: "a").acceptsTypedValues == offered, "\(kind)")
        }
    }

    /// A new account can be typed by you from the start; an investment
    /// account is then recorded as a balance.
    @Test func aNewAccountCanBeTypedFromTheStart() {
        var form = AccountForm(residence: nil, currency: .eur, today: today)
        form.chosenKind = .cash
        #expect(!form.offersTypedValues)
        form.chosenKind = .brokerage
        #expect(form.offersTypedValues)
        form.values = .typed
        let account = form.account(id: "new")
        #expect(account.values == .typed)
        #expect(account.valuation == .balance)
        #expect(account.acceptsTypedValues)
    }

    @Test func anInvestmentAccountSwitchesToABalanceUntilItHasTrades() {
        var form = AccountForm(editing: account(.brokerage, values: nil))
        #expect(form.valuationMode == .trades)
        form.values = .typed
        #expect(form.valuationMode == .balance)
        let typed = form.account(id: "a")
        #expect(typed.valuation == .balance)
        #expect(typed.acceptsTypedValues)
        #expect(typed.typedValuesCountInTrends)
        #expect(form.typedWhatMoved == .added)
        form.chosenNetWorthInclusion = false
        #expect(!form.account(id: "a").typedValuesCountInTrends)
        // Switched back, it stays a balance: its typed values are balances.
        var back = AccountForm(editing: typed)
        back.values = .imported
        #expect(back.account(id: "a").valuation == .balance)
        #expect(back.account(id: "a").values == nil)
        // With trades, it can't switch.
        let withTrades = AccountForm(editing: account(.brokerage, values: nil), hasTrades: true)
        #expect(!withTrades.offersTypedValues)
        #expect(withTrades.account(id: "a").valuation == nil)
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

    @Test func theCheckInListsTheTypedAccountsApart() {
        let library = PreviewLibrary.library
        let date = PreviewLibrary.latestCheckIn
        let groups = Valuator(library: library).checkInGroups(on: date, in: library)
        #expect(groups.typed.map(\.account) == ["casa"])
        var withEstimate = library
        withEstimate.accounts["fondo-pensione"]?.tags = [Account.startingEstimateTag]
        let estimates = Valuator(library: withEstimate).checkInGroups(on: date, in: withEstimate)
        #expect(Set(estimates.typed.map(\.account)) == ["casa", "fondo-pensione"])
    }

    @Test func typedSavingsOrInvestmentsWithoutWhatMovedTurnTrendsOff() {
        var library = PreviewLibrary.library
        #expect(library.accountsTurningOffTrends.isEmpty)
        library.accounts["conto-deposito"]?.values = .typed
        library.accounts["fondo-pensione"]?.values = .typed
        #expect(library.accountsTurningOffTrends.isEmpty)
        let date = PreviewLibrary.latestCheckIn.adding(days: 1)
        library.upsert(Valuation(account: "conto-deposito", date: date, balance: 20000, source: .manual))
        library.upsert(Valuation(account: "fondo-pensione", date: date, balance: 20000, source: .manual))
        #expect(library.accountsTurningOffTrends.map(\.id) == ["conto-deposito"])
        library.accounts["conto-deposito"]?.closed = "2026-09-30"
        #expect(library.accountsTurningOffTrends.isEmpty)
    }

    @Test func needsAttentionSaysHowToFillAnAccountWithoutValues() {
        var library = PreviewLibrary.library
        library.accounts["boat"] = Account(id: "boat", name: "Boat", kind: .belongings, currency: .eur,
                                           opened: "2026-01-01", values: .typed)
        library.accounts["second-bank"] = Account(id: "second-bank", name: "Second bank", kind: .cash,
                                                  currency: .eur, opened: "2026-01-01")
        let items = TodayAttention.items(library: library, valuator: Valuator(library: library),
                                            on: PreviewLibrary.latestCheckIn, stalenessThreshold: 45)
        #expect(items.first { $0.id == "stale.boat" }?.detail == "No value yet")
        #expect(items.first { $0.id == "stale.boat" }?.action == "Update")
        #expect(items.first { $0.id == "stale.second-bank" }?.action == "Import")
    }
}
