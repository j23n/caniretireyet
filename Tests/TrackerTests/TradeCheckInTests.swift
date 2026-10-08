import Foundation
import Model
import Testing
import TestSupport
import Tracker

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

    /// ``library()`` with gold coins bought in April from a dealer and paid
    /// from the bank: a trades account with no cash of its own.
    private func coinsLibrary() -> Library {
        var library = library()
        library.accounts["coins"] = Account(id: "coins", name: "Gold coins", kind: .metals, currency: .eur,
                                            opened: "2024-01-01", valuation: .trades)
        library.instruments["gold"] = Instrument(id: "gold", name: "Gold", kind: .metal, currency: .eur, unit: .gram,
                                                 assetClasses: .single(.gold))
        library.upsert(Trade(account: "coins", date: "2024-04-10", id: "buy-gold", type: .buy, instrument: "gold",
                             quantity: 10, price: 60, settlement: .external))
        library.upsert(PriceRecord(instrument: "gold", date: "2024-04-30", price: 70, currency: .eur))
        return library
    }

    @Test func aTradesRowStartsFromWhatTheTradesGive() throws {
        let draft = CheckInDraft(date: "2024-04-30", library: library())
        let row = try #require(draft["broker"])
        #expect(row.isTrades)
        #expect(row.mode == .trades)
        #expect(row.state == .unchanged)
        #expect(row.previous?.date == "2024-03-31")
        #expect(row.cash == d("6300.36"))
        #expect(row.positions.isEmpty)
        #expect(row.derived?.positions.map(\.instrument) == ["aapl", "vwce"])
        #expect(row.canMarkUnchanged)
        #expect(draft.instruments == ["aapl", "vwce"])
        #expect(draft["bank"]?.isTrades == false)
        #expect(draft["bank"]?.derived == nil)
    }

    @Test func aTradesRowStartsDoneAsItsTradesSay() throws {
        let draft = CheckInDraft(date: "2024-04-30", library: library())
        let row = try #require(draft["broker"])
        #expect(row.followsTrades)
        #expect(!row.hasStatementCash)
        #expect(row.holdsCash)
        #expect(row.showsCash)
        // Nothing was typed: Cancel needn't ask, and a rebase may fill it in again.
        #expect(!row.hasUserInput)
        // It counts as done; only the bank, which has no value yet, is left.
        #expect(draft.notReviewed == ["bank"])
        #expect(draft.reviewedCount == 1)
        #expect(draft.progressTotal == 2)
        #expect(draft.count(.unchanged) == 1)
        #expect(draft["bank"]?.followsTrades == false)

        // Marking the rest unchanged skips the bank and leaves the broker as it is.
        var marked = draft
        marked.markRestUnchanged()
        #expect(marked["broker"] == row)
        #expect(marked["bank"]?.state == .skipped)
        #expect(marked.isReadyToSave)
    }

    @Test func savingWritesWhatUnchangedWrote() throws {
        let untouched = CheckInDraft(date: "2024-04-30", library: library())
        var marked = untouched
        #expect(marked["broker"]?.markUnchanged() == true)
        let written = untouched.records(in: library()).valuations
        // The derived cash and the recorded deposits since the previous value.
        #expect(written == [Valuation(account: "broker", date: "2024-04-30", cash: d("6300.36"), flow: 1000)])
        #expect(written == marked.records(in: library()).valuations)
        let review = try #require(untouched.review(in: library()).row(for: "broker"))
        #expect(review.state == .unchanged)
        #expect(review.flow == 1000)
    }

    @Test func aTradesRowWithNothingToFollowWaitsForAValue() throws {
        var library = library()
        library.accounts["new-broker"] = Account(id: "new-broker", name: "New broker", kind: .brokerage,
                                                 currency: .eur, opened: "2024-04-15", valuation: .trades)
        library.accounts["later"] = Account(id: "later", name: "Later", kind: .brokerage, currency: .eur,
                                            opened: "2024-06-01", valuation: .trades)
        library.upsert(Trade(account: "later", date: "2024-06-03", id: "dep", type: .deposit, amount: 100))
        let draft = CheckInDraft(date: "2024-04-30", library: library)
        // Nothing recorded yet: its cash is typed, or a trade added.
        let new = try #require(draft["new-broker"])
        #expect(new.state == .notReviewed)
        #expect(new.derived == nil)
        #expect(new.showsCash)
        #expect(!new.canMarkUnchanged)
        // An account that opens after the date stays optional.
        let later = try #require(draft["later"])
        #expect(later.opensLater)
        #expect(later.state == .notReviewed)
        #expect(draft.notReviewed == ["bank", "new-broker"])
    }

    @Test func anAccountWithoutCashShowsNoCash() throws {
        let library = coinsLibrary()
        let valuator = Valuator(library: library)
        #expect(!valuator.holdsCash("coins"))
        #expect(valuator.holdsCash("broker"))
        let draft = CheckInDraft(date: "2024-04-30", library: library)
        let coins = try #require(draft["coins"])
        #expect(coins.followsTrades)
        #expect(!coins.holdsCash)
        #expect(!coins.showsCash)
        #expect(coins.cash == 0)
        #expect(draft["broker"]?.showsCash == true)
        // Its new money is what the coins cost, paid from the bank.
        let review = try #require(draft.review(in: library).row(for: "coins"))
        #expect(review.valuation == Valuation(account: "coins", date: "2024-04-30", cash: 0, flow: 600))
        #expect(review.value?.value == 700)

        // A fee taken from its own cash gives it cash to show.
        var paidFromCash = library
        paidFromCash.upsert(Trade(account: "coins", date: "2024-04-20", id: "fee", type: .fee, amount: -5))
        #expect(Valuator(library: paidFromCash).holdsCash("coins"))
        var rebased = draft
        rebased.rebase(onto: paidFromCash)
        #expect(rebased["coins"]?.showsCash == true)
        #expect(rebased["coins"]?.cash == -5)
        #expect(rebased["coins"]?.followsTrades == true)
    }

    @Test func typingAStatementCashCreatesAResidual() throws {
        var draft = CheckInDraft(date: "2024-04-30", library: library())
        var row = try #require(draft["broker"])
        row.setCash(6310)
        #expect(row.state == .updated)
        #expect(row.hasStatementCash)
        #expect(row.hasUserInput)
        #expect(!row.followsTrades)
        draft["broker"] = row
        let review = try #require(draft.review(in: library()).row(for: "broker"))
        // 1,000 deposited, and 9,64 more cash than the trades give.
        #expect(review.valuation == Valuation(account: "broker", date: "2024-04-30", cash: 6310, flow: d("1009.64")))

        // The trades' own cash is no residual; going back follows the trades again.
        row.setCash(d("6300.36"))
        #expect(!row.hasStatementCash)
        let followsAgain = row.markUnchanged()
        #expect(followsAgain)
        #expect(row.followsTrades)
        #expect(!row.hasUserInput)
    }

    @Test func aRowFollowingTheTradesFollowsANewTrade() throws {
        var draft = CheckInDraft(date: "2024-04-30", library: library())
        var changed = library()
        changed.upsert(TradeLibrary.trade(.deposit, "2024-04-29", id: "dep3", amount: "250"))
        draft.rebase(onto: changed)
        #expect(draft["broker"]?.followsTrades == true)
        #expect(draft["broker"]?.cash == d("6550.36"))
        #expect(draft.records(in: changed).valuations.first?.flow == 1250)
    }

    @Test func aDraftKeptBeforeTradesRowsStartedDoneFollowsTheTrades() throws {
        let draft = CheckInDraft(date: "2024-04-30", library: library())
        // An older draft: the trades row not reviewed, and no `holdsCash`.
        var json = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(draft)) as? [String: Any])
        var rows = try #require(json["rows"] as? [[String: Any]])
        let index = try #require(rows.firstIndex { $0["account"] as? String == "broker" })
        rows[index]["state"] = "notReviewed"
        rows[index]["holdsCash"] = nil
        json["rows"] = rows
        let old = try JSONDecoder().decode(CheckInDraft.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(old["broker"]?.followsTrades == true)
        #expect(old["broker"]?.holdsCash == true)
        #expect(old == draft)

        // Without cash of its own, a row round-trips with it.
        let coins = CheckInDraft(date: "2024-04-30", library: coinsLibrary())
        #expect(try JSONDecoder().decode(CheckInDraft.self, from: JSONEncoder().encode(coins)) == coins)
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

    @Test func statementQuantitiesStartFromTheTradesAndCanBeDropped() throws {
        var draft = CheckInDraft(date: "2024-04-30", library: library())
        var bank = try #require(draft["bank"])
        let enteredForBank = bank.enterStatementQuantities()
        #expect(!enteredForBank)
        var row = try #require(draft["broker"])
        let entered = row.enterStatementQuantities()
        #expect(entered)
        #expect(row.state == .updated)
        #expect(row.mode == .trades)
        #expect(row.positions.map(\.instrument) == ["aapl", "vwce"])
        #expect(row.positions.map(\.quantity) == [10, 40])
        // Once entered, it doesn't start again.
        let enteredAgain = row.enterStatementQuantities()
        #expect(!enteredAgain)
        row.setQuantity(12, of: "vwce")
        draft["broker"] = row
        #expect(draft.review(in: library()).row(for: "broker")?.mismatches.map(\.instrument) == ["vwce"])

        // Removing a statement quantity drops it (not zero, which would be a sale in a holdings row).
        row.removePosition("aapl")
        #expect(row.positions.map(\.instrument) == ["vwce"])
        row.removeStatementQuantities()
        #expect(row.positions.isEmpty)
        #expect(row.state == .updated)
        draft["broker"] = row
        #expect(draft.review(in: library()).row(for: "broker")?.mismatches.isEmpty == true)
    }

    @Test func aTradeSavedMeanwhileRefreshesTheStartingPoint() throws {
        var draft = CheckInDraft(date: "2024-04-30", library: library())
        var edited = draft
        edited["broker"]?.setCash(6400)
        var changed = library()
        changed.upsert(TradeLibrary.trade(.dividend, "2024-04-20", id: "div2", instrument: "vwce", amount: "50"))

        draft.rebase(onto: changed)
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
