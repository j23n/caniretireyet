import Foundation
import Model
import Testing
import TestSupport
import Tracker

/// Adding, changing and removing trades keeps the flows of later
/// valuations and the opening date in step, and says what went wrong.
struct TradeEditTests {
    private let transfer = TradeLibrary.trade(.transferIn, "2024-02-10", id: "tin0", instrument: "vwce",
                                              quantity: "5", cost: "450")

    @Test func addingATradeRecomputesTheAutomaticFlowAfterIt() throws {
        var library = TradeLibrary.typedCash()
        let original = library
        #expect(original.previewAddingTrade(transfer).flows.recomputed.map(\.date) == ["2024-02-29"])
        #expect(original == TradeLibrary.typedCash())

        let edit = library.addTrade(transfer)
        #expect(edit.saved == transfer)
        #expect(edit.removed == nil)
        #expect(edit.movedOpeningFrom == nil)
        #expect(edit.flows.recomputed.map(\.flow) == [510])
        #expect(edit.issues.isEmpty)
        #expect(library.trade(transfer.key) == transfer)
        #expect(library.valuations(for: "broker")[1].flow == 510)
    }

    @Test func addingNeverReplacesAnotherTrade() throws {
        var library = TradeLibrary.typedCash()
        var twin = TradeLibrary.trades[0]
        twin.quantity = 1
        let edit = library.addTrade(twin)
        let saved = try #require(edit.saved)
        #expect(saved.id != twin.id)
        #expect(saved.id.rawValue.count == 8)
        #expect(library.trades(for: "broker").filter { $0.date == "2024-01-05" }.count == 2)
    }

    @Test func movingATradeToAnotherDateReplacesItAndItsFlows() throws {
        var library = TradeLibrary.typedCash()
        library.addTrade(transfer)
        var moved = transfer
        moved.date = "2024-03-05"
        let edit = library.updateTrade(moved, replacing: transfer.key)
        #expect(edit.removed == transfer)
        #expect(library.trade(transfer.key) == nil)
        #expect(library.trade(moved.key) == moved)
        // February goes back to no flow; March gains the transfer at the latest price then (105).
        #expect(edit.flows.recomputed.map(\.date) == ["2024-02-29", "2024-03-31"])
        #expect(edit.flows.recomputed.map(\.flow) == [0, 1075])
    }

    @Test func removingABuyShowsTheSaleItLeavesUncovered() throws {
        var library = TradeLibrary.recordedDeposits()
        let buy = TradeLibrary.trades[0]
        let edit = library.removeTrade(buy.key)
        #expect(edit.removed == buy)
        #expect(edit.saved == nil)
        #expect(edit.newIssues.map(\.kind) == [.oversold])
        #expect(edit.newIssues.first?.trade?.id == "sel1")
        #expect(library.trade(buy.key) == nil)
        // Correcting it again clears the issue.
        #expect(library.addTrade(buy).issues.isEmpty)
    }

    @Test func aTradeBeforeTheAccountOpenedMovesTheOpeningBack() throws {
        var library = TradeLibrary.recordedDeposits()
        let opening = TradeLibrary.trade(.opening, "2023-11-30", id: "open", instrument: "vwce", quantity: "3",
                                         cost: "270")
        let edit = library.addTrade(opening)
        #expect(edit.movedOpeningFrom == "2024-01-01")
        #expect(library.accounts["broker"]?.opened == "2023-11-30")
        #expect(edit.issues.isEmpty)
    }
}
