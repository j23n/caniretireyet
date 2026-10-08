import Foundation
import Model
import Testing
import TestSupport
import Tracker

/// A made-up broker account in EUR, and trades for it.
enum TradeSamples {
    static let broker = Account(id: "broker", name: "Broker", kind: .brokerage, currency: .eur, opened: "2020-01-01",
                                valuation: .trades)
    static let instruments: [InstrumentID: Instrument] = [
        "vwce": Instrument(id: "vwce", name: "VWCE", kind: .etf, currency: .eur, unit: .share,
                           assetClasses: .single(.equity)),
        "aapl": Instrument(id: "aapl", name: "Apple", kind: .stock, currency: .usd, unit: .share,
                           assetClasses: .single(.equity)),
    ]

    static func trade(_ type: TradeType, _ date: CalendarDate, id: TradeID, instrument: InstrumentID? = nil,
                      quantity: String? = nil, price: String? = nil, amount: String? = nil, fees: String? = nil,
                      tax: String? = nil, cost: String? = nil, ratio: String? = nil,
                      account: AccountID = "broker") -> Trade {
        Trade(account: account, date: date, id: id, type: type, instrument: instrument, quantity: quantity.map(d),
              price: price.map(d), amount: amount.map(d), fees: fees.map(d), tax: tax.map(d), cost: cost.map(d),
              ratio: ratio.map(d))
    }

    static func ledger(_ trades: [Trade], fx: [FXRecord] = []) -> TradeLedger {
        TradeLedger(account: broker, trades: trades, instruments: instruments, fx: FXTable(fx, pivots: [.eur]))
    }
}

struct TradeLedgerTests {
    typealias S = TradeSamples

    @Test func averageCostThroughBuysPartialSellsAndSplits() throws {
        let ledger = S.ledger([
            S.trade(.buy, "2024-01-10", id: "b1", instrument: "vwce", quantity: "10", price: "100", fees: "5"),
            S.trade(.buy, "2024-02-10", id: "b2", instrument: "vwce", quantity: "10", price: "120", fees: "5"),
            S.trade(.sell, "2024-03-10", id: "s1", instrument: "vwce", quantity: "5", price: "130", fees: "5",
                    tax: "24.05"),
            S.trade(.split, "2024-04-01", id: "sp", instrument: "vwce", ratio: "2"),
            S.trade(.sell, "2024-05-10", id: "s2", instrument: "vwce", quantity: "30", amount: "2000"),
        ])
        #expect(ledger.issues.isEmpty)
        let entries = ledger.entries
        // Buys cost price × quantity plus fees.
        #expect(entries[0].cashEffect == -1005)
        #expect(entries[0].cost == 1005)
        #expect(entries[1].costAfter == 2210)
        #expect(ledger.position(of: "vwce", on: "2024-02-10") == Position(instrument: "vwce", quantity: 20,
                                                                           costBasis: 2210))
        // A quarter sold: a quarter of the cost goes, and the gain is before tax.
        #expect(entries[2].cashEffect == d("620.95"))
        #expect(entries[2].cost == d("552.5"))
        #expect(entries[2].realizedGain == d("92.5"))
        #expect(entries[2].costAfter == d("1657.5"))
        // A split doubles the units, not the cost.
        #expect(ledger.position(of: "vwce", on: "2024-04-01") == Position(instrument: "vwce", quantity: 30,
                                                                           costBasis: d("1657.5")))
        // Selling everything takes the whole remaining cost.
        #expect(entries[4].cost == d("1657.5"))
        #expect(entries[4].realizedGain == d("342.5"))
        #expect(ledger.positions(on: "2024-05-10").isEmpty)
        #expect(ledger.positions(on: "2024-01-09").isEmpty)
        #expect(ledger.positions(on: "2030-01-01").isEmpty)

        let summary = ledger.summary(for: 2024)
        #expect(summary.realizedGain == 435)
        #expect(summary.realizedGainByInstrument == ["vwce": 435])
        #expect(summary.fees == 15)
        #expect(summary.taxes == d("24.05"))
    }

    @Test func proRataCostIsRoundedToCentsAndAddsUp() {
        let ledger = S.ledger([
            S.trade(.buy, "2024-01-10", id: "b1", instrument: "vwce", quantity: "3", amount: "-100"),
            S.trade(.sell, "2024-02-10", id: "s1", instrument: "vwce", quantity: "1", amount: "40"),
            S.trade(.sell, "2024-03-10", id: "s2", instrument: "vwce", quantity: "1", amount: "40"),
            S.trade(.sell, "2024-04-10", id: "s3", instrument: "vwce", quantity: "1", amount: "40"),
        ])
        #expect(ledger.entries.map(\.cost) == [100, d("33.33"), d("33.34"), d("33.33")])
        #expect(ledger.entries.compactMap(\.realizedGain).reduce(0, +) == 20)
    }

    @Test func eachTypesCashEffect() {
        let ledger = S.ledger([
            S.trade(.deposit, "2024-01-02", id: "a", amount: "5000"),
            S.trade(.opening, "2024-01-02", id: "b", instrument: "vwce", quantity: "100", cost: "9000"),
            S.trade(.buy, "2024-01-10", id: "c", instrument: "vwce", quantity: "10", price: "100", fees: "2",
                    tax: "1"),
            S.trade(.dividend, "2024-03-20", id: "d", instrument: "vwce", amount: "73.6", tax: "26.4"),
            S.trade(.dividend, "2024-03-21", id: "e", instrument: "vwce", quantity: "110", price: "0.5", tax: "14.3"),
            S.trade(.interest, "2024-03-31", id: "f", amount: "7.4", tax: "2.6"),
            S.trade(.fee, "2024-04-01", id: "g", amount: "-3"),
            S.trade(.fee, "2024-04-02", id: "h", fees: "2"),
            S.trade(.tax, "2024-04-03", id: "i", amount: "-34.2"),
            S.trade(.withdrawal, "2024-05-01", id: "j", amount: "-1000"),
            S.trade(.transferIn, "2024-06-01", id: "k", instrument: "vwce", quantity: "5", cost: "400"),
            S.trade(.transferOut, "2024-06-02", id: "l", instrument: "vwce", quantity: "15", fees: "10"),
            S.trade(.sell, "2024-07-01", id: "m", instrument: "vwce", quantity: "10", price: "110", fees: "2",
                    tax: "10"),
        ])
        #expect(ledger.issues.isEmpty)
        #expect(ledger.entries.map(\.cashEffect) == [
            0, 5000, -1003, d("73.6"), d("40.7"), d("7.4"), -3, -2, d("-34.2"), -1000, 0, -10, 1088,
        ])
        // Buys cost price × quantity with fees and a transaction tax; an
        // opening and a transfer in carry their cost; a transfer out takes
        // the average cost of what it moves.
        #expect(ledger.position(of: "vwce", on: "2024-01-10")?.costBasis == 10003)
        #expect(ledger.position(of: "vwce", on: "2024-06-01") == Position(instrument: "vwce", quantity: 115,
                                                                           costBasis: 10403))
        #expect(ledger.entries[11].cost == d("1356.91"))
        #expect(ledger.position(of: "vwce", on: "2024-06-02") == Position(instrument: "vwce", quantity: 100,
                                                                           costBasis: d("9046.09")))
        #expect(ledger.entries[12].cost == d("904.61"))
        #expect(ledger.entries[12].realizedGain == d("193.39"))
        #expect(ledger.cashEffect(after: nil, through: "2024-12-31") == d("4157.5"))
        #expect(ledger.cashEffect(after: "2024-01-02", through: "2024-03-31") == d("-881.3"))
        #expect(ledger.cashEffect(after: "2024-07-01", through: "2024-12-31") == 0)
        #expect(ledger.cashEffect(after: nil, through: "2023-12-31") == 0)

        let summary = ledger.summary(for: 2024)
        #expect(summary.dividends == 155)
        #expect(summary.dividendsByInstrument == ["vwce": 155])
        #expect(summary.interest == 10)
        #expect(summary.incomeTax == d("43.3"))
        #expect(summary.netIncome == d("121.7"))
        #expect(summary.fees == 19)
        #expect(summary.taxes == 1 + d("26.4") + d("14.3") + d("2.6") + d("34.2") + 10)
        #expect(summary.deposits == 5000)
        #expect(summary.withdrawals == 1000)
        #expect(summary.realizedGain == d("193.39"))
        #expect(ledger.years == [2024])
    }

    @Test func pricesInAnotherCurrencyUseTheRateOnTheTradeDate() throws {
        let fx = [
            FXRecord(base: .eur, quote: .usd, date: "2024-03-01", rate: d("1.1")),
            FXRecord(base: .eur, quote: .usd, date: "2024-06-01", rate: d("1.25")),
        ]
        let ledger = S.ledger([
            S.trade(.buy, "2024-03-05", id: "b1", instrument: "aapl", quantity: "10", price: "170", fees: "1"),
            S.trade(.sell, "2024-06-05", id: "s1", instrument: "aapl", quantity: "10", price: "200"),
        ], fx: fx)
        // 1,700 USD at 1.1 USD per EUR, plus 1 EUR of fees.
        #expect(ledger.entries[0].cashEffect == d("-1546.45"))
        // 2,000 USD at 1.25: the gain in euros includes the currency's move.
        #expect(ledger.entries[1].cashEffect == 1600)
        #expect(ledger.entries[1].realizedGain == d("53.55"))
        // Before the first rate, the amount can't be worked out.
        let early = S.ledger([S.trade(.buy, "2024-02-01", id: "b0", instrument: "aapl", quantity: "1", price: "1")],
                             fx: fx)
        #expect(early.entries[0].cashEffect == nil)
        #expect(early.issues.map(\.kind) == [.missingFX])
        #expect(early.unknownCashEffects(after: nil, through: "2024-12-31") == 1)
        #expect(early.position(of: "aapl", on: "2024-02-01") == Position(instrument: "aapl", quantity: 1))
        // A written amount needs no rate.
        let written = S.ledger([S.trade(.buy, "2024-02-01", id: "b0", instrument: "aapl", quantity: "1", price: "1",
                                        amount: "-0.95")], fx: fx)
        #expect(written.issues.isEmpty)
        #expect(written.position(of: "aapl", on: "2024-02-01")?.costBasis == d("0.95"))
    }

    @Test func impossibleTradesAreAppliedAndReported() throws {
        let ledger = S.ledger([
            S.trade(.buy, "2024-01-10", id: "b1", instrument: "vwce", quantity: "10", price: "100"),
            S.trade(.sell, "2024-02-10", id: "s1", instrument: "vwce", quantity: "15", price: "110"),
            S.trade(.buy, "2024-03-10", id: "b2", instrument: "vwce", quantity: "10"),
            S.trade(.split, "2024-04-01", id: "sp", instrument: "aapl", ratio: "4"),
        ])
        #expect(ledger.issues.map(\.kind) == [.oversold, .invalidTrade, .splitNotHeld])
        #expect(ledger.issues[0].severity == .error)
        #expect(ledger.issues[0].trade == TradeKey(account: "broker", date: "2024-02-10", id: "s1"))
        #expect(ledger.issues[0].message == "The sell of vwce on 2024-02-10 (s1): It takes away 5 more than the "
            + "account held then (10). Is a buy or an opening missing, or the date wrong?")
        // The quantity shows the mistake; the sale's gain is unknown.
        #expect(ledger.position(of: "vwce", on: "2024-02-10")?.quantity == -5)
        #expect(ledger.entries[1].realizedGain == nil)
        #expect(ledger.summary(for: 2024).salesWithUnknownGain == [ledger.entries[1].trade.key])
        // The buy without a price or an amount still adds its units, at an unknown cost.
        #expect(ledger.position(of: "vwce", on: "2024-03-10") == Position(instrument: "vwce", quantity: 5))
        #expect(ledger.unknownCashEffects(after: nil, through: "2024-12-31") == 1)
    }

    @Test func anUnknownCostLastsUntilThePositionCloses() {
        let ledger = S.ledger([
            S.trade(.transferIn, "2024-01-10", id: "t1", instrument: "vwce", quantity: "10"),
            S.trade(.buy, "2024-02-10", id: "b1", instrument: "vwce", quantity: "10", amount: "-1000"),
            S.trade(.sell, "2024-03-10", id: "s1", instrument: "vwce", quantity: "5", amount: "600"),
            S.trade(.sell, "2024-04-10", id: "s2", instrument: "vwce", quantity: "15", amount: "1800"),
            S.trade(.buy, "2024-05-10", id: "b2", instrument: "vwce", quantity: "2", amount: "-250"),
        ])
        #expect(ledger.issues.map(\.kind) == [.unknownCost])
        #expect(ledger.position(of: "vwce", on: "2024-02-10") == Position(instrument: "vwce", quantity: 20))
        #expect(ledger.entries[2].realizedGain == nil)
        // Once closed, a new position starts with a known cost.
        #expect(ledger.position(of: "vwce", on: "2024-05-10") == Position(instrument: "vwce", quantity: 2,
                                                                           costBasis: 250))
    }

    @Test func aDaysTradesApplyInProcessingOrder() {
        // Recorded in the file as sell before buy (by ID); applied buy first.
        let ledger = S.ledger([
            S.trade(.sell, "2024-01-10", id: "a", instrument: "vwce", quantity: "10", amount: "1010"),
            S.trade(.buy, "2024-01-10", id: "b", instrument: "vwce", quantity: "10", amount: "-1000"),
        ])
        #expect(ledger.issues.isEmpty)
        #expect(ledger.entries.map(\.trade.id) == ["b", "a"])
        #expect(ledger.entries[1].realizedGain == 10)
    }

    @Test func otherAccountsTradesAreIgnored() {
        let ledger = S.ledger([
            S.trade(.deposit, "2024-01-10", id: "a", amount: "10"),
            S.trade(.deposit, "2024-01-10", id: "b", amount: "20", account: "other"),
        ])
        #expect(ledger.entries.count == 1)
        #expect(ledger.firstDate == "2024-01-10")
    }
}
