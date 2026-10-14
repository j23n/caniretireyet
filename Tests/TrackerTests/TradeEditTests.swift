import Foundation
import Model
import Testing
import TestSupport
import Tracker

/// Removing a trade keeps the flows of later valuations in step, and says
/// what went wrong.
struct TradeEditTests {
    @Test func removingATradeRecomputesTheAutomaticFlowAfterIt() throws {
        var library = TradeLibrary.typedCash()
        let transfer = TradeLibrary.trade(.transferIn, "2024-02-10", id: "tin0", instrument: "vwce",
                                          quantity: "5", cost: "450")
        library.editValuations { $0.upsert(transfer) }
        #expect(library.valuations(for: "broker")[1].flow == 510)
        let edit = library.removeTrade(transfer.key)
        #expect(library.trade(transfer.key) == nil)
        #expect(edit.flows.recomputed.map(\.date) == ["2024-02-29"])
        #expect(edit.flows.recomputed.map(\.flow) == [0])
        #expect(edit.newIssues.isEmpty)
    }

    @Test func removingABuyShowsTheSaleItLeavesUncovered() throws {
        var library = TradeLibrary.recordedDeposits()
        let buy = TradeLibrary.trades[0]
        let edit = library.removeTrade(buy.key)
        #expect(edit.newIssues.map(\.kind) == [.oversold])
        #expect(edit.newIssues.first?.trade?.id == "sel1")
        #expect(library.trade(buy.key) == nil)
        // Importing it again clears the issue.
        library.upsert(buy)
        #expect(Valuator(library: library).tradeIssues(for: "broker").isEmpty)
    }
}
