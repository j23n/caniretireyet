import Foundation
import Model
import Testing
import Tracker
@testable import CanIRetireYet

/// Which fields the check-in shows for each account kind (docs/ACCOUNTS.md,
/// "What each kind asks for"; UI.md, "Check-in"), on the example library's
/// October check-in: money in and out for cash and savings, a savings
/// account's interest, new money typed only where the kind asks for it, and
/// a trades account waiting for a trade or *No Trades*.
@MainActor
struct CheckInModelTests {
    private let library = PreviewLibrary.library
    private let date: CalendarDate = "2026-10-31"
    private let locale = Locale(identifier: "en_GB")

    private func draft(_ edit: (inout CheckInDraft) -> Void = { _ in }) -> CheckInDraft {
        var draft = CheckInDraft(date: date, library: library)
        edit(&draft)
        return draft
    }

    private func row(_ account: AccountID, in draft: CheckInDraft) throws -> CheckInRow {
        try #require(draft[account])
    }

    private func rule(of account: AccountID) -> FlowDefault {
        library.accounts[account]?.kind.defaultFlow ?? .ask
    }

    // MARK: Money in and out, interest

    @Test func cashAsksForMoneyInAndOut() throws {
        let row = try row("conto-fineco", in: draft())
        #expect(CheckInRowDisplay.showsMoneyInOut(row))
        #expect(!CheckInRowDisplay.showsInterest(row))
    }

    @Test func savingsAsksForMoneyInAndOutAndInterest() throws {
        let row = try row("conto-deposito", in: draft())
        #expect(CheckInRowDisplay.showsMoneyInOut(row))
        #expect(CheckInRowDisplay.showsInterest(row))
    }

    @Test(arguments: ["mutuo-casa", "fondo-pensione", "casa", "directa", "gold-coins"] as [AccountID])
    func otherKindsAskForNeitherMoneyInAndOutNorInterest(_ account: AccountID) throws {
        let row = try row(account, in: draft())
        #expect(!CheckInRowDisplay.showsMoneyInOut(row))
        #expect(!CheckInRowDisplay.showsInterest(row))
    }

    @Test func anUnchangedOrSkippedRowHidesMoneyInAndOut() throws {
        let draft = draft { draft in
            draft["conto-fineco"]?.markUnchanged()
            draft["conto-deposito"]?.skip()
        }
        #expect(!CheckInRowDisplay.showsMoneyInOut(try row("conto-fineco", in: draft)))
        #expect(!CheckInRowDisplay.showsInterest(try row("conto-deposito", in: draft)))
    }

    /// An account's first value asks only for its balance: there's no value
    /// before it to measure money in and out from.
    @Test func anAccountsFirstValueAsksOnlyForItsBalance() throws {
        var library = self.library
        library.accounts["new-bank"] = Account(id: "new-bank", name: "New bank", kind: .savings, currency: .eur,
                                               opened: "2026-10-01")
        let draft = CheckInDraft(date: date, library: library)
        let row = try #require(draft["new-bank"])
        #expect(!CheckInRowDisplay.showsMoneyInOut(row))
        #expect(!CheckInRowDisplay.showsInterest(row))
        #expect(!CheckInRowDisplay.showsFlowField(row, rule: .changeLessInterest, isEditing: false))
    }

    // MARK: New money

    @Test(arguments: ["conto-fineco", "conto-deposito", "mutuo-casa"] as [AccountID])
    func workedOutNewMoneyIsNeverTyped(_ account: AccountID) throws {
        let row = try row(account, in: draft { $0[account]?.setBalance(1_000) })
        #expect(!CheckInRowDisplay.canEditFlow(row, rule: rule(of: account)))
        #expect(!CheckInRowDisplay.showsFlowField(row, rule: rule(of: account), isEditing: true))
        #expect(!CheckInRowDisplay.offersEditFlow(row, rule: rule(of: account), isEditing: false))
    }

    @Test(arguments: ["fondo-pensione", "tfr", "casa"] as [AccountID])
    func newMoneyIsAskedForWhereTheKindAsks(_ account: AccountID) throws {
        let row = try row(account, in: draft())
        #expect(rule(of: account) == .ask)
        #expect(CheckInRowDisplay.canEditFlow(row, rule: .ask))
        #expect(CheckInRowDisplay.showsFlowField(row, rule: .ask, isEditing: false))
    }

    @Test func aTradesAccountsNewMoneyIsTypedOnlyWithAStatementsCash() throws {
        let following = try row("directa", in: draft())
        #expect(!CheckInRowDisplay.canEditFlow(following, rule: .trades))
        let statement = try row("directa", in: draft { $0["directa"]?.setCash(400) })
        #expect(CheckInRowDisplay.canEditFlow(statement, rule: .trades))
        #expect(CheckInRowDisplay.offersEditFlow(statement, rule: .trades, isEditing: false))
        #expect(!CheckInRowDisplay.offersEditFlow(statement, rule: .trades, isEditing: true))
    }

    // MARK: Field order

    @Test func moneyInOutAndInterestFollowTheBalance() throws {
        let draft = draft()
        let rows = try ["conto-fineco", "conto-deposito", "mutuo-casa"].map { try row($0, in: draft) }
        let shown = Set(rows.filter(CheckInRowDisplay.showsMoneyInOut).map(\.account))
        let review = draft.review(in: library)
        let list = CheckInFieldOrder.list(rows: rows, review: review, expanded: [], editingFlows: [],
                                          moneyInOut: shown)
        #expect(list.fields == [
            .balance("conto-fineco"), .moneyIn("conto-fineco"), .moneyOut("conto-fineco"),
            .balance("conto-deposito"), .moneyIn("conto-deposito"), .moneyOut("conto-deposito"),
            .interest("conto-deposito"),
            .balance("mutuo-casa"),
        ])
        #expect(CheckInFieldOrder.nowColumn(rows: rows, moneyInOut: shown).fields == list.fields)
        #expect(CheckInField.interest("conto-deposito").name(in: library) == "Conto deposito · interest")
    }

    // MARK: Trades accounts

    @Test func aTradesAccountWithoutNewTradesWaitsForATradeOrNoTrades() throws {
        let waiting = try row("directa", in: draft())
        #expect(waiting.state == .notReviewed)
        #expect(CheckInRowDisplay.offersNoTrades(waiting))
        #expect(CheckInWording.caption(for: waiting, locale: locale) == "Add a trade, or say there were none")
        #expect(CheckInWording.markUnchangedTitle(for: waiting) == "No Trades")
        #expect(CheckInWording.markUnchangedSwipeTitle(for: waiting) == "No Trades")

        let none = try row("directa", in: draft { $0["directa"]?.markUnchanged() })
        #expect(!CheckInRowDisplay.offersNoTrades(none))
        #expect(CheckInWording.stateName(for: none) == "No trades")
        #expect(CheckInWording.caption(for: none, locale: locale)?.hasPrefix("No trades since ") == true)
    }

    @Test func aTradesAccountWithNewTradesFollowsThem() throws {
        var library = self.library
        library.upsert(Trade(account: "directa", date: "2026-10-05", id: "octdepos", type: .deposit, amount: 1_450,
                             source: .manual))
        let row = try #require(CheckInDraft(date: date, library: library)["directa"])
        #expect(row.followsTrades)
        #expect(!CheckInRowDisplay.offersNoTrades(row))
        #expect(CheckInWording.stateName(for: row) == "From trades")
        #expect(CheckInWording.caption(for: row, locale: locale) == "As the trades say")
    }

    // MARK: Moved

    @Test func movedIsWorkedOutAndShownReadOnly() throws {
        // 4.210,55 → 4.510,55: 3.400 in, 3.100 out, so nothing moved.
        let draft = draft { draft in
            draft["conto-fineco"]?.setBalance(Decimal(string: "4510.55"))
            draft["conto-fineco"]?.setMoneyIn(3_400)
            draft["conto-fineco"]?.setMoneyOut(3_100)
            // 500 from the current account, as savings with no money in or out.
            draft["conto-deposito"]?.setBalance(Decimal(string: "17865.55"))
        }
        let review = draft.review(in: library)
        #expect(review.row(for: "conto-fineco")?.moved == 0)
        #expect(review.row(for: "conto-deposito")?.moved == 500)
        #expect(CheckInReviewDisplay.movedRows(review).map(\.account) == ["conto-deposito"])
        let text = try #require(CheckInWording.moved(review.row(for: "conto-deposito")?.moved, locale: locale))
        #expect(text.text.hasPrefix("Moved"))
        #expect(text.text.hasSuffix("+500.00 between your accounts"))
        #expect(text.hasAmounts)
        #expect(CheckInWording.moved(nil, locale: locale) == nil)
    }

    @Test func theReviewSaysWhetherWhatMovedCancelsOut() throws {
        // 500 out of the current account (money out left at 0), into savings.
        let cancels = draft { draft in
            draft["conto-fineco"]?.setBalance(Decimal(string: "3710.55"))
            draft["conto-fineco"]?.setMoneyIn(0)
            draft["conto-fineco"]?.setMoneyOut(0)
            draft["conto-deposito"]?.setBalance(Decimal(string: "17865.55"))
        }.review(in: library)
        #expect(cancels.movedNotCancelledOut == nil)
        #expect(CheckInReviewDisplay.movedSummary(cancels, currency: .eur, locale: locale).text
            .hasPrefix("It cancels out"))

        let left = draft { $0["conto-deposito"]?.setBalance(Decimal(string: "17865.55")) }.review(in: library)
        #expect(left.movedNotCancelledOut == 500)
        let summary = CheckInReviewDisplay.movedSummary(left, currency: .eur, locale: locale)
        #expect(summary.text.contains("doesn't cancel out"))
        #expect(summary.hasAmounts)
    }
}
