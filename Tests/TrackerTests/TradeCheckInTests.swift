import Foundation
import Model
import Testing
import Tracker

private func d(_ string: String) -> Decimal { Decimal(fileString: string)! }

/// A check-in for an account that records trades: it records the account's
/// cash, starts from what the trades give, and its flow counts the recorded
/// deposits and the difference in cash.
struct TradeCheckInTests {
    private func library() -> Library {
        var library = TradeLibrary.typedCash()
        library.upsert(TradeLibrary.trade(.deposit, "2024-04-10", id: "dep2", amount: "1000"))
        library.upsert(PriceRecord(instrument: "vwce", date: "2024-04-30", price: 111, currency: .eur))
        library.upsert(PriceRecord(instrument: "aapl", date: "2024-04-30", price: 165, currency: .usd))
        library.upsert(FXRecord(base: .eur, quote: .usd, date: "2024-04-30", rate: d("1.2")))
        return library
    }

    @Test func aTradesRowStartsFromWhatTheTradesGive() throws {
        let draft = CheckInDraft(date: "2024-04-30", library: library())
        let row = try #require(draft["broker"])
        #expect(row.isTrades)
        #expect(row.mode == .trades)
        #expect(row.state == .notReviewed)
        #expect(row.previous?.date == "2024-03-31")
        #expect(row.cash == d("6300.36"))
        #expect(row.positions.isEmpty)
        #expect(row.derived?.positions.map(\.instrument) == ["aapl", "vwce"])
        #expect(row.canMarkUnchanged)
        #expect(draft.instruments == ["aapl", "vwce"])
        #expect(draft["bank"]?.isTrades == false)
        #expect(draft["bank"]?.derived == nil)
    }

    @Test func typedCashAddsAResidualToTheRecordedDeposits() throws {
        var draft = CheckInDraft(date: "2024-04-30", library: library())
        draft["broker"]?.setCash(6310)
        let review = draft.review(in: library())
        let row = try #require(review.row(for: "broker"))
        #expect(row.valuation == Valuation(account: "broker", date: "2024-04-30", cash: 6310, flow: d("1009.64")))
        #expect(row.defaultFlow == d("1009.64"))
        // The review shows what the trades hold.
        #expect(row.positions.map(\.instrument) == ["aapl", "vwce"])
        #expect(row.positions.map(\.quantity) == [10, 40])
        #expect(row.positions.map(\.previousQuantity) == [10, 40])
        #expect(row.positions.last?.costBasis == d("3936.67"))
        #expect(row.value?.value == 40 * 111 + 10 * 165 / d("1.2") + 6310)
        #expect(row.mismatches.isEmpty)
        #expect(row.warnings.isEmpty)
    }

    @Test func unchangedMeansAsTheTradesSay() throws {
        var draft = CheckInDraft(date: "2024-04-30", library: library())
        #expect(draft["broker"]?.markUnchanged() == true)
        let records = draft.records(in: library())
        let written = try #require(records.valuations.first { $0.account == "broker" })
        #expect(written == Valuation(account: "broker", date: "2024-04-30", cash: d("6300.36"), flow: 1000))

        var saved = library()
        draft.apply(to: &saved)
        #expect(Valuator(library: saved).tradeFlows(of: "broker", after: "2024-03-31", through: "2024-04-30")
            .map(\.amount) == [1000])
    }

    @Test func positionsEnteredAreCheckedAgainstTheTrades() throws {
        var draft = CheckInDraft(date: "2024-04-30", library: library())
        draft["broker"]?.setQuantity(9, of: "aapl")
        #expect(draft["broker"]?.mode == .trades)
        #expect(draft["broker"]?.positions.first?.previousQuantity == 10)
        let row = try #require(draft.review(in: library()).row(for: "broker"))
        #expect(row.valuation?.positions == [Position(instrument: "aapl", quantity: 9)])
        // A statement lists every position, so VWCE, held but not entered, counts as zero.
        #expect(row.mismatches.map(\.instrument) == ["aapl", "vwce"])
        #expect(row.mismatches.map(\.listed) == [9, 0])
        // No "did you sell?" warning: the quantity is a check, not a sale.
        #expect(row.warnings.isEmpty)
    }

    @Test func aTradeSavedMeanwhileRefreshesTheStartingPoint() throws {
        var draft = CheckInDraft(date: "2024-04-30", library: library())
        var edited = draft
        edited["broker"]?.setCash(6400)
        var changed = library()
        changed.upsert(TradeLibrary.trade(.dividend, "2024-04-20", id: "div2", instrument: "vwce", amount: "50"))

        let result = draft.rebase(onto: changed)
        #expect(result.refreshed == ["broker"])
        #expect(draft["broker"]?.cash == d("6350.36"))
        // What was typed stays, and the flow follows the new trades.
        edited.rebase(onto: changed)
        #expect(edited["broker"]?.cash == 6400)
        #expect(edited["broker"]?.derived?.cash == d("6350.36"))
        #expect(edited.review(in: changed).row(for: "broker")?.flow == d("1049.64"))
    }

    @Test func aDraftWithATradesRowRoundTripsThroughJSON() throws {
        var draft = CheckInDraft(date: "2024-04-30", library: library())
        draft["broker"]?.setCash(6310)
        let data = try JSONEncoder().encode(draft)
        #expect(try JSONDecoder().decode(CheckInDraft.self, from: data) == draft)
    }
}
