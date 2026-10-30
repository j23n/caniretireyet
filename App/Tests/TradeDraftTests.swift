import Foundation
import Model
import Testing
@testable import CanIRetireYet

/// A trade typed in on a brokerage month (UI.md, "A brokerage month"): the
/// trade it makes and the cash it moves, on made-up numbers.
struct TradeDraftTests {
    private func d(_ text: String) -> Decimal { PreviewLibrary.d(text) }

    @Test func aBuyTakesItsCostAndFees() throws {
        var draft = TradeDraft(date: "2026-10-20", instrument: "vwce")
        draft.quantity = 5
        draft.price = d("103.90")
        draft.fees = d("2.95")
        #expect(draft.cashEffect(sameCurrency: true) == d("-522.45"))
        #expect(draft.cashEffect(sameCurrency: false) == nil)
        let trade = try #require(draft.trade(in: "directa", id: "t1"))
        #expect(trade == Trade(account: "directa", date: "2026-10-20", id: "t1", type: .buy, instrument: "vwce",
                               quantity: 5, price: d("103.90"), fees: d("2.95"), source: .manual))
    }

    @Test func aSaleBringsInLessItsFees() {
        var draft = TradeDraft(type: .sell, date: "2026-10-20", instrument: "vwce", quantity: 2, price: 100,
                               fees: 1)
        #expect(draft.cashEffect(sameCurrency: true) == 199)
        draft.quantity = 0
        #expect(draft.trade(in: "directa") == nil)
    }

    @Test func cashTradesTakeTheirSignFromTheType() throws {
        var draft = TradeDraft(type: .withdrawal, date: "2026-10-20", amount: 300)
        #expect(draft.cashEffect(sameCurrency: true) == -300)
        #expect(try #require(draft.trade(in: "directa")).amount == -300)
        draft.type = .deposit
        #expect(try #require(draft.trade(in: "directa")).amount == 300)
        #expect(try #require(draft.trade(in: "directa")).instrument == nil)
        draft.type = .fee
        #expect(draft.cashEffect(sameCurrency: true) == -300)
    }

    @Test func aDividendNeedsItsInstrument() throws {
        var draft = TradeDraft(type: .dividend, date: "2026-10-20", amount: d("12.40"))
        #expect(draft.trade(in: "directa") == nil)
        draft.instrument = "vwce"
        let trade = try #require(draft.trade(in: "directa"))
        #expect(trade.instrument == "vwce")
        #expect(trade.amount == d("12.40"))
    }
}
