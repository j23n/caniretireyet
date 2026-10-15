import Foundation
import Model
import Testing
import TestSupport
import Tracker

/// Removing a trade says what went wrong.
struct TradeEditTests {
    @Test func removingABuyShowsTheSaleItLeavesUncovered() throws {
        var library = TradeLibrary.recordedDeposits()
        let buy = TradeLibrary.trades[0]
        let newIssues = library.removeTrade(buy.key)
        #expect(newIssues.map(\.kind) == [.oversold])
        #expect(newIssues.first?.trade?.id == "sel1")
        #expect(library.trade(buy.key) == nil)
        // Importing it again clears the issue.
        library.upsert(buy)
        #expect(Valuator(library: library).tradeIssues(for: "broker").isEmpty)
    }
}
