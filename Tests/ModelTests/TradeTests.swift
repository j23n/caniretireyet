import Foundation
import Model
import Testing

private func d(_ string: String) -> Decimal { Decimal(fileString: string)! }

struct TradeRecordTests {
    @Test func decimalsAreWrittenAsStringsAndReadBack() throws {
        let trade = Trade(account: "directa", date: "2026-03-12", id: "k3q7vz2m", type: .buy, instrument: "vwce",
                          quantity: 10, price: d("127.35"), fees: 5, note: "monthly")
        let json = try JSONValue(encoding: trade)
        #expect(json == [
            "account": "directa", "date": "2026-03-12", "fees": "5", "id": "k3q7vz2m", "instrument": "vwce",
            "note": "monthly", "price": "127.35", "quantity": "10", "type": "buy",
        ])
        #expect(try json.decode(as: Trade.self) == trade)
        // Plain JSON numbers are read too, exactly.
        let typed: JSONValue = [
            "account": "directa", "amount": .number(d("-1278.5")), "date": "2026-03-12", "id": "a", "type": "buy",
        ]
        #expect(try typed.decode(as: Trade.self).amount == d("-1278.5"))
    }

    @Test func unknownTypesDecode() throws {
        let json: JSONValue = ["account": "a", "date": "2026-01-02", "id": "x", "type": "spinOff"]
        let trade = try json.decode(as: Trade.self)
        #expect(trade.type == "spinOff")
        #expect(!trade.type.isKnown)
        #expect(trade.problems.map(\.field) == ["type"])
        #expect(trade.problems.first?.severity == .warning)
    }

    @Test func keysSortByDateAccountAndID() {
        let a = TradeKey(account: "b", date: "2026-01-01", id: "z")
        let b = TradeKey(account: "a", date: "2026-01-02", id: "a")
        let c = TradeKey(account: "a", date: "2026-01-02", id: "b")
        let e = TradeKey(account: "b", date: "2026-01-02", id: "a")
        #expect([e, c, b, a].sorted() == [a, b, c, e])
        #expect(c.description == "2026-01-02 a b")
    }

    @Test func randomIDsAreEightBase32Characters() {
        var generator = SeededGenerator(seed: 7)
        let first = TradeID.random(using: &generator)
        #expect(first.rawValue.count == 8)
        #expect(first.isValidSlug)
        #expect(first.rawValue.unicodeScalars.allSatisfy { ("a"..."z").contains($0) || ("2"..."7").contains($0) })
        var again = SeededGenerator(seed: 7)
        #expect(TradeID.random(using: &again) == first)
        let many = Set((0..<200).map { _ in TradeID.random() })
        #expect(many.count == 200)
        let fresh = TradeID.random(avoiding: many)
        #expect(fresh.rawValue.count == 8)
        #expect(!many.contains(fresh))
    }

    @Test func monthFilesLeaveOutAnEmptyTradeList() throws {
        let empty = try JSONValue(encoding: MonthFile(month: "2026-09"))
        #expect(empty["trades"] == nil)
        #expect(empty["valuations"] == [])
        let trade = Trade(account: "directa", date: "2026-09-02", id: "a", type: .deposit, amount: 500)
        var file = MonthFile(month: "2026-09", trades: [trade])
        #expect(!file.isEmpty)
        #expect(try JSONValue(encoding: file)["trades"]?.arrayValue?.count == 1)
        file.trades.append(Trade(account: "directa", date: "2026-10-01", id: "b", type: .deposit, amount: 1))
        #expect(file.misplacedDates == ["2026-10-01"])
    }
}

struct TradeProblemTests {
    private func trade(_ type: TradeType, instrument: InstrumentID? = nil, quantity: Decimal? = nil,
                       price: Decimal? = nil, amount: Decimal? = nil, fees: Decimal? = nil, tax: Decimal? = nil,
                       cost: Decimal? = nil, ratio: Decimal? = nil) -> Trade {
        Trade(account: "a", date: "2026-01-02", id: "x", type: type, instrument: instrument, quantity: quantity,
              price: price, amount: amount, fees: fees, tax: tax, cost: cost, ratio: ratio)
    }

    private func errors(_ trade: Trade) -> [String?] {
        trade.problems.filter { $0.severity == .error }.map(\.field)
    }

    private func warnings(_ trade: Trade) -> [String?] {
        trade.problems.filter { $0.severity == .warning }.map(\.field)
    }

    @Test func buysAndSellsNeedAnInstrumentAQuantityAndAPriceOrAmount() {
        #expect(trade(.buy, instrument: "vwce", quantity: 10, price: 100).problems.isEmpty)
        #expect(trade(.sell, instrument: "vwce", quantity: 10, amount: 1000).problems.isEmpty)
        #expect(errors(trade(.buy, instrument: "vwce", quantity: 10)) == ["price"])
        #expect(errors(trade(.sell)) == ["instrument", "quantity", "price"])
        #expect(errors(trade(.buy, instrument: "vwce", quantity: -1, price: 1)) == ["quantity"])
    }

    @Test func eachTypesFields() {
        #expect(trade(.dividend, amount: 12).problems.isEmpty)
        #expect(trade(.dividend, instrument: "vwce", quantity: 100, price: d("0.4"), tax: 10).problems.isEmpty)
        #expect(errors(trade(.dividend, instrument: "vwce")) == ["amount"])
        #expect(errors(trade(.interest)) == ["amount"])
        #expect(trade(.fee, fees: 2).problems.isEmpty)
        #expect(errors(trade(.fee)) == ["amount"])
        #expect(trade(.tax, amount: d("-34.2")).problems.isEmpty)
        #expect(errors(trade(.tax)) == ["amount"])
        #expect(errors(trade(.deposit)) == ["amount"])
        #expect(errors(trade(.withdrawal)) == ["amount"])
        #expect(trade(.transferIn, instrument: "vwce", quantity: 5, cost: 500).problems.isEmpty)
        #expect(trade(.opening, instrument: "vwce", quantity: 5).problems.isEmpty)
        #expect(errors(trade(.transferOut, instrument: "vwce")) == ["quantity"])
        #expect(trade(.split, instrument: "vwce", ratio: 2).problems.isEmpty)
        #expect(errors(trade(.split, instrument: "vwce")) == ["ratio"])
        #expect(errors(trade(.split, instrument: "vwce", ratio: 0)) == ["ratio"])
        #expect(errors(trade(.buy, instrument: "vwce", quantity: 1, price: 1, fees: -1, tax: -1)) == ["fees", "tax"])
    }

    @Test func signsThatContradictTheTypeAndUnusedFieldsAreWarnings() {
        #expect(warnings(trade(.buy, instrument: "vwce", quantity: 1, amount: 100)) == ["amount"])
        #expect(warnings(trade(.deposit, amount: -100)) == ["amount"])
        #expect(warnings(trade(.withdrawal, amount: 100)) == ["amount"])
        #expect(trade(.withdrawal, amount: -100).problems.isEmpty)
        #expect(warnings(trade(.buy, instrument: "vwce", quantity: 1, price: 1, cost: 1, ratio: 2)) == ["ratio", "cost"])
        #expect(warnings(trade(.split, instrument: "vwce", quantity: 1, ratio: 2)) == [nil])
    }
}

struct HeldQuantityTests {
    private func trade(_ type: TradeType, _ quantity: Decimal? = nil, date: CalendarDate = "2026-01-02",
                       id: TradeID = "x", ratio: Decimal? = nil) -> Trade {
        Trade(account: "a", date: date, id: id, type: type, instrument: "vwce", quantity: quantity, price: 1,
              ratio: ratio)
    }

    @Test func tradesAddTakeAwayAndSplitUnits() {
        var held = HeldQuantities()
        #expect(held.apply(trade(.opening, 100)) == nil)
        #expect(held.apply(trade(.buy, 20)) == nil)
        #expect(held.apply(trade(.transferIn, 5)) == nil)
        #expect(held["vwce"] == 125)
        #expect(held.apply(trade(.sell, 25)) == nil)
        #expect(held.apply(trade(.split, ratio: 2)) == nil)
        #expect(held["vwce"] == 200)
        #expect(held.apply(trade(.transferOut, 200)) == nil)
        #expect(held["vwce"] == 0)
        #expect(held.held.isEmpty)
        #expect(held.quantities == ["vwce": 0])
        // Dividends and deposits don't change quantities.
        #expect(held.apply(Trade(account: "a", date: "2026-01-03", id: "d", type: .dividend, instrument: "vwce",
                                 amount: 5)) == nil)
        #expect(held["vwce"] == 0)
    }

    @Test func sellingMoreThanIsHeldIsReportedAndShown() {
        var held = HeldQuantities()
        held.apply(trade(.buy, 10))
        #expect(held.apply(trade(.sell, 15)) == 5)
        #expect(held["vwce"] == -5)
        #expect(held.apply(trade(.sell, 1)) == 1)
    }

    @Test func aDaysTradesApplySplitsFirstAndBuysBeforeSells() {
        let sell = trade(.sell, 10, id: "a")
        let buy = trade(.buy, 10, id: "b")
        let split = trade(.split, id: "c", ratio: 2)
        let earlier = trade(.buy, 5, date: "2026-01-01", id: "z")
        #expect([sell, buy, split, earlier].inProcessingOrder() == [earlier, split, buy, sell])
        // Bought and sold the same day: nothing is oversold.
        #expect(HeldQuantities([sell, buy]).held.isEmpty)
        // The split doubles what was held before the day's buy.
        #expect(HeldQuantities([sell, buy, split, earlier])["vwce"] == 10)
    }
}

struct LibraryTradeTests {
    @Test func upsertRemoveAndQuery() {
        var library = Library()
        let march = Trade(account: "directa", date: "2026-03-12", id: "b", type: .buy, instrument: "vwce",
                          quantity: 10, price: 127)
        let early = Trade(account: "directa", date: "2026-03-02", id: "a", type: .deposit, amount: 1300)
        let other = Trade(account: "ibkr", date: "2026-03-01", id: "c", type: .deposit, amount: 1)
        library.upsert(march)
        library.upsert(early)
        library.upsert(other)
        #expect(library.months["2026-03"]?.trades.map(\.id) == ["c", "a", "b"])
        #expect(library.trades(for: "directa") == [early, march])
        #expect(library.allTrades.map(\.id) == ["c", "a", "b"])
        #expect(library.trade(march.key) == march)
        #expect(library.heldQuantities(of: "directa", on: "2026-03-11").isEmpty)
        #expect(library.heldQuantities(of: "directa", on: "2026-03-12") == ["vwce": 10])

        var edited = march
        edited.quantity = 12
        library.upsert(edited)
        #expect(library.trades(for: "directa").count == 2)
        #expect(library.heldQuantities(of: "directa", on: "2026-03-31") == ["vwce": 12])
        #expect(library.removeTradeRecord(march.key) == edited)
        #expect(library.removeTradeRecord(march.key) == nil)
        #expect(library.trades(for: "directa") == [early])
        // Trades aren't check-ins.
        #expect(library.checkInDates.isEmpty)
    }
}

/// A small deterministic generator (SplitMix64) for tests.
struct SeededGenerator: RandomNumberGenerator {
    var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
