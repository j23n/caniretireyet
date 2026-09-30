import Foundation
import Model
import Testing
import TestSupport
import Tracker

private func d(_ string: String) -> Decimal { Decimal(fileString: string)! }

/// Filling in history for accounts added in the app: they open on the day
/// they were added, so a check-in dated last year lists them as opening
/// later, and saving a value for one moves its opening date back.
struct PastCheckInTests {
    /// Accounts created on 30 Sep 2026 with their first value, one account
    /// with a history, and one closed before the back-filled dates.
    let library: Library = {
        var library = Library()
        library.accounts["fineco"] = Account(id: "fineco", name: "Fineco", kind: .cash, currency: .eur,
                                             opened: "2026-09-30")
        library.accounts["fondo"] = Account(id: "fondo", name: "Fondo", kind: .pensionFund, currency: .eur,
                                            opened: "2026-09-30")
        library.accounts["old"] = Account(id: "old", name: "Old savings", kind: .savings, currency: .eur,
                                          opened: "2020-01-01")
        library.accounts["gone"] = Account(id: "gone", name: "Gone", kind: .cash, currency: .eur,
                                           opened: "2019-01-01", closed: "2023-12-31")
        library.upsert(Valuation(account: "fineco", date: "2026-09-30", balance: 5000, flow: 5000))
        library.upsert(Valuation(account: "fondo", date: "2026-09-30", balance: 20000))
        library.upsert(Valuation(account: "old", date: "2023-12-31", balance: 9000, flow: 9000))
        library.upsert(Valuation(account: "old", date: "2026-09-30", balance: 10000, flow: 1000))
        return library
    }()

    @Test func listsAccountsOpeningLaterWithoutCountingThem() throws {
        let draft = CheckInDraft(date: "2024-03-31", library: library)
        #expect(draft.rows.map(\.account) == ["fineco", "old", "fondo"])
        #expect(draft.rowsOpeningLater.map(\.account) == ["fineco", "fondo"])
        #expect(draft["old"]?.opensLater == false)
        #expect(draft["gone"] == nil)
        // Only the account open on the date is expected.
        #expect(draft.progressTotal == 1)
        #expect(draft.notReviewed == ["old"])
        #expect(draft.count(.notReviewed) == 1)
        #expect(!draft.isReadyToSave)

        // Mark rest unchanged passes over them, and they write nothing.
        var marked = draft
        marked.markRestUnchanged()
        #expect(marked["old"]?.state == .unchanged)
        #expect(marked["fineco"]?.state == .notReviewed)
        #expect(marked.isReadyToSave)
        #expect(marked.reviewedCount == 1)
        let records = marked.records(in: library)
        #expect(records.valuations.map(\.account) == ["old"])
        #expect(records.openingMoves.isEmpty)
        var saved = library
        marked.apply(to: &saved)
        #expect(saved.accounts == library.accounts)

        // Today's check-in lists them as usual.
        let today = CheckInDraft(date: "2026-09-30", library: library)
        #expect(today.rowsOpeningLater.isEmpty)
        #expect(today.progressTotal == 3)
    }

    @Test func aValueMovesTheOpeningDateAndTheNextFlowFollows() throws {
        var draft = CheckInDraft(date: "2024-03-31", library: library)
        draft["fineco"]?.setBalance(3000)
        draft.markRestUnchanged()
        // Entered, it joins the progress.
        #expect(draft.progressTotal == 2)
        #expect(draft.reviewedCount == 2)
        #expect(draft.isReadyToSave)

        let review = draft.review(in: library)
        #expect(review.openingMoves == ["fineco"])
        #expect(review.netWorth.total == 12000)
        #expect(review.row(for: "fineco")?.flow == 3000)

        var saved = library
        let flows = draft.apply(to: &saved)
        #expect(saved.accounts["fineco"]?.opened == "2024-03-31")
        #expect(saved.accounts["fondo"]?.opened == "2026-09-30")
        #expect(saved.valuations(for: "fineco").map(\.balance) == [3000, 5000])
        // The first value's flow was the whole amount (automatic): now the change since March 2024.
        #expect(saved.valuations(for: "fineco").last?.flow == 2000)
        #expect(flows.recomputed.map(\.key) == [ValuationKey(account: "fineco", date: "2026-09-30")])
        // Old savings' flow of 1000 was the automatic change: 10000 − 9000 as it stays.
        #expect(saved.valuations(for: "old").last?.flow == 1000)
        #expect(Valuator(library: saved).netWorth(on: "2024-03-31").total == 12000)
    }

    @Test func aPensionFundsJoiningDateMovesWithItsOpeningDate() throws {
        var library = self.library
        library.accounts["fondo"]?.tax = AccountTax(wrapper: "it.pensionFund", details: ["joined": "2026-09-30"])
        var draft = CheckInDraft(date: "2024-03-31", library: library)
        draft["fondo"]?.setBalance(15000)
        draft.markRestUnchanged()
        #expect(draft.review(in: library).openingMoves == ["fondo"])
        draft.apply(to: &library)
        #expect(library.accounts["fondo"]?.opened == "2024-03-31")
        #expect(library.accounts["fondo"]?.tax?.joined == "2024-03-31")

        // A joining date typed by hand stays.
        var typed = self.library
        typed.accounts["fondo"]?.tax = AccountTax(wrapper: "it.pensionFund", details: ["joined": "2010-01-01"])
        draft.apply(to: &typed)
        #expect(typed.accounts["fondo"]?.opened == "2024-03-31")
        #expect(typed.accounts["fondo"]?.tax?.joined == "2010-01-01")
    }

    @Test func emptyOrSkippedRowsChangeNothing() throws {
        var draft = CheckInDraft(date: "2024-03-31", library: library)
        draft["old"]?.setBalance(9100)
        draft["fondo"]?.skip()
        #expect(draft.progressTotal == 2)
        #expect(draft.count(.skipped) == 1)
        var saved = library
        draft.apply(to: &saved)
        #expect(saved.accounts == library.accounts)
        #expect(saved.valuations(for: "fineco") == library.valuations(for: "fineco"))
        #expect(saved.valuations(for: "fondo") == library.valuations(for: "fondo"))
        // A typed pension contribution… none here; the savings account's next flow was automatic.
        #expect(saved.valuations(for: "old").last?.flow == 900)
    }

    @Test func rebaseFollowsAnOpeningDateMovedElsewhere() throws {
        var draft = CheckInDraft(date: "2024-03-31", library: library)
        draft["fineco"]?.setBalance(3000)
        var changed = library
        changed.accounts["fineco"]?.opened = "2024-01-01"
        let result = draft.rebase(onto: changed)
        #expect(result.refreshed == ["fineco"])
        #expect(draft["fineco"]?.opensLater == false)
        #expect(draft["fineco"]?.balance == 3000)
        #expect(draft.records(in: changed).openingMoves.isEmpty)

        // Closed before the date on the other device: the row leaves.
        changed.accounts["fondo"]?.opened = "2019-01-01"
        changed.accounts["fondo"]?.closed = "2023-01-31"
        #expect(draft.rebase(onto: changed).removed == ["fondo"])
    }

    @Test func changingTheDateMovesRowsInAndOut() throws {
        var draft = CheckInDraft(date: "2026-09-30", library: library)
        draft["fineco"]?.setBalance(5100)
        draft.changeDate(to: "2024-03-31", library: library)
        #expect(draft["fineco"]?.opensLater == true)
        #expect(draft["fineco"]?.balance == 5100)
        #expect(draft["fineco"]?.countsInProgress == true)
        draft.changeDate(to: "2023-06-30", library: library)
        #expect(draft["gone"]?.opensLater == false)
        #expect(draft.notReviewed == ["gone", "old"])
    }

    @Test func aStoredDraftKeepsItsRowsOpeningLater() throws {
        var draft = CheckInDraft(date: "2024-03-31", library: library)
        draft["fineco"]?.setBalance(3000)
        let data = try JSONEncoder().encode(draft)
        let decoded = try JSONDecoder().decode(CheckInDraft.self, from: data)
        #expect(decoded == draft)
        #expect(decoded["fineco"]?.opensLater == true)
        #expect(decoded["old"]?.opensLater == false)
    }
}

/// Values added, corrected, moved or removed outside a check-in, and the
/// flows of the values after them.
struct ValuationEditTests {
    let library: Library = {
        var library = Library()
        library.accounts["cash"] = Account(id: "cash", name: "Cash", kind: .cash, currency: .eur, opened: "2026-01-31")
        library.accounts["broker"] = Account(id: "broker", name: "Broker", kind: .brokerage, currency: .eur,
                                             opened: "2026-01-31")
        library.accounts["fondo"] = Account(id: "fondo", name: "Fondo", kind: .pensionFund, currency: .eur,
                                            opened: "2026-01-31")
        library.upsert(Valuation(account: "cash", date: "2026-01-31", balance: 1000, flow: 1000))
        library.upsert(Valuation(account: "cash", date: "2026-03-31", balance: 1500, flow: 500))
        library.upsert(Valuation(account: "broker", date: "2026-01-31",
                                 positions: [Position(instrument: "etf", quantity: 10, costBasis: 1000)], flow: 1000))
        library.upsert(Valuation(account: "broker", date: "2026-03-31",
                                 positions: [Position(instrument: "etf", quantity: 20, costBasis: 2100)], flow: 1100))
        library.upsert(Valuation(account: "fondo", date: "2026-01-31", balance: 20000))
        library.upsert(Valuation(account: "fondo", date: "2026-03-31", balance: 21000, flow: 800))
        return library
    }()

    @Test func aValueInsertedBetweenTwoRecomputesTheNextAutomaticFlow() throws {
        var library = self.library
        let edit = library.saveValue(Valuation(account: "cash", date: "2026-02-28", balance: 1200, flow: 200))
        #expect(edit.movedOpeningFrom == nil)
        #expect(library.valuations(for: "cash").map(\.flow) == [1000, 200, 300])
        #expect(edit.flows.recomputed.map(\.flow) == [300])
        #expect(edit.flows.kept.isEmpty)

        // Removing it puts the flow back.
        let removed = library.removeValue(ValuationKey(account: "cash", date: "2026-02-28"))
        #expect(library.valuations(for: "cash").map(\.flow) == [1000, 500])
        #expect(removed.recomputed.map(\.key) == [ValuationKey(account: "cash", date: "2026-03-31")])
    }

    @Test func aTypedFlowIsKept() throws {
        var library = self.library
        library.upsert(Valuation(account: "cash", date: "2026-03-31", balance: 1500, flow: 450))
        let edit = library.saveValue(Valuation(account: "cash", date: "2026-02-28", balance: 1200, flow: 200))
        #expect(library.valuations(for: "cash").last?.flow == 450)
        #expect(edit.flows.kept.map(\.key) == [ValuationKey(account: "cash", date: "2026-03-31")])
        #expect(edit.flows.recomputed.isEmpty)

        // A pension fund's contributions are always typed.
        let fondo = library.saveValue(Valuation(account: "fondo", date: "2026-02-28", balance: 20500, flow: 400))
        #expect(library.valuations(for: "fondo").last?.flow == 800)
        #expect(fondo.flows.kept.count == 1)
    }

    @Test func holdingsFollowWhatWasPaid() throws {
        var library = self.library
        // Bought 5 more in February for 550: March's 10 more cost 1100 in all, so 550 of it after February.
        library.saveValue(Valuation(account: "broker", date: "2026-02-28",
                                    positions: [Position(instrument: "etf", quantity: 15, costBasis: 1550)], flow: 550))
        #expect(library.valuations(for: "broker").map(\.flow) == [1000, 550, 550])
    }

    @Test func aValueBeforeTheOpeningDateMovesIt() throws {
        var library = self.library
        let preview = library.previewSavingValue(Valuation(account: "cash", date: "2025-12-31", balance: 800, flow: 800))
        #expect(preview.movedOpeningFrom == "2026-01-31")
        #expect(library.accounts["cash"]?.opened == "2026-01-31")

        let edit = library.saveValue(Valuation(account: "cash", date: "2025-12-31", balance: 800, flow: 800))
        #expect(edit == preview)
        #expect(library.accounts["cash"]?.opened == "2025-12-31")
        #expect(library.valuations(for: "cash").map(\.flow) == [800, 200, 500])
        #expect(Valuator(library: library).netWorth(on: "2025-12-31").total == 800)
    }

    @Test func aValueBeforeAPensionFundOpenedMovesItsJoiningDate() throws {
        var library = self.library
        library.accounts["fondo"]?.tax = AccountTax(wrapper: "it.pensionFund", details: ["joined": "2026-01-31"])
        let edit = library.saveValue(Valuation(account: "fondo", date: "2021-06-30", balance: 5000))
        #expect(edit.movedOpeningFrom == "2026-01-31")
        #expect(library.accounts["fondo"]?.opened == "2021-06-30")
        #expect(library.accounts["fondo"]?.tax?.joined == "2021-06-30")
    }

    @Test func movingAValueFollowsBothPlaces() throws {
        var library = self.library
        library.upsert(Valuation(account: "cash", date: "2026-05-31", balance: 1600, flow: 100))
        // March's value moves to June: May now follows January, and June follows May.
        library.saveValue(Valuation(account: "cash", date: "2026-06-30", balance: 1500, flow: -100),
                          replacing: ValuationKey(account: "cash", date: "2026-03-31"))
        #expect(library.valuations(for: "cash").map(\.date) == ["2026-01-31", "2026-05-31", "2026-06-30"])
        #expect(library.valuations(for: "cash").map(\.flow) == [1000, 600, -100])
    }

    @Test func flowsFollowAChangeMadeToACopy() throws {
        // As an import does: values inserted in a copy of the library.
        var imported = self.library
        imported.upsert(Valuation(account: "cash", date: "2026-02-28", balance: 1200))
        imported.upsert(Valuation(account: "broker", date: "2026-02-28",
                                  positions: [Position(instrument: "etf", quantity: 15, costBasis: 1550)]))
        let flows = imported.followFlows(from: self.library)
        #expect(imported.valuations(for: "cash").map(\.flow) == [1000, nil, 300])
        #expect(imported.valuations(for: "broker").map(\.flow) == [1000, nil, 550])
        #expect(flows.recomputed.map(\.key) == [ValuationKey(account: "broker", date: "2026-03-31"),
                                                ValuationKey(account: "cash", date: "2026-03-31")])

        // Valuations whose flows the change gives (a journal's) are kept as they are.
        var journal = self.library
        journal.upsert(Valuation(account: "cash", date: "2026-02-28", balance: 1200, flow: 150))
        let kept = journal.followFlows(from: self.library,
                                       keeping: [ValuationKey(account: "cash", date: "2026-03-31")])
        #expect(journal.valuations(for: "cash").map(\.flow) == [1000, 150, 500])
        #expect(kept.isEmpty)
    }

    @Test func otherEditsLeaveFlowsAlone() throws {
        var library = self.library
        let flows = library.editValuations { $0.accounts["cash"]?.name = "Current account" }
        #expect(flows.isEmpty)
        #expect(library.valuations(for: "cash") == self.library.valuations(for: "cash"))
    }
}
