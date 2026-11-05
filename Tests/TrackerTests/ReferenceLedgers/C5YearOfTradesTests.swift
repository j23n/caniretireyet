import Foundation
import Model
import Testing
import TestSupport
import Tracker

/// C5, a year of one fund's trades (Resources/ReferenceLedgers/c5-year-of-trades,
/// expected.md): every number its expected.md works out by hand.
@Suite struct C5YearOfTradesTests {
    let valuator: Valuator
    let ledger: TradeLedger

    init() throws {
        valuator = Valuator(library: try ReferenceLedger.yearOfTrades.library())
        ledger = try #require(valuator.ledger(for: "broker"))
    }

    /// What each trade did, in processing order: its cash effect, the cost
    /// it moved, its realised gain, and the quantity and cost after it.
    @Test func eachTrade() {
        struct Row: Equatable {
            var id: TradeID
            var amount: Decimal?
            var cost: Decimal?
            var gain: Decimal?
            var quantity: Decimal?
            var costAfter: Decimal?
        }
        let rows = ledger.entries.map {
            Row(id: $0.trade.id, amount: $0.amount, cost: $0.cost, gain: $0.realizedGain, quantity: $0.quantityAfter,
                costAfter: $0.costAfter)
        }
        #expect(rows == [
            Row(id: "deposit-jan", amount: 10000),
            Row(id: "buy-jan", amount: -5005, cost: 5005, quantity: 50, costAfter: 5005),
            Row(id: "buy-mar", amount: -3305, cost: 3305, quantity: 80, costAfter: 8310),
            Row(id: "dividend-may", amount: d("29.6")),
            Row(id: "split-jun", amount: 0, quantity: 160, costAfter: 8310),
            Row(id: "sell-jul", amount: d("2312.45"), cost: d("2077.5"), gain: d("317.5"), quantity: 120,
                costAfter: d("6232.5")),
            Row(id: "buy-sep", amount: -1105, cost: 1105, quantity: 140, costAfter: d("7337.5")),
            Row(id: "sell-nov", amount: 3495, cost: d("3668.75"), gain: d("-173.75"), quantity: 70,
                costAfter: d("3668.75")),
            Row(id: "custody-fee", amount: -10),
            Row(id: "withdrawal-dec", amount: -1000),
            Row(id: "stamp-duty", amount: -20),
        ])
    }

    @Test func holdingsAndCash() throws {
        #expect(ledger.positions(on: "2025-05-31") == [Position(instrument: "world-fund", quantity: 80,
                                                                  costBasis: 8310)])
        #expect(ledger.positions(on: "2025-06-02") == [Position(instrument: "world-fund", quantity: 160,
                                                                  costBasis: 8310)])
        #expect(ledger.positions(on: "2025-12-31") == [Position(instrument: "world-fund", quantity: 70,
                                                                  costBasis: d("3668.75"))])
        #expect(valuator.tradeCash(of: "broker", on: "2025-12-31") == d("5392.05"))
        let holding = try #require(valuator.holdings(of: "broker", on: "2025-12-31").first)
        #expect(holding.value == 3640)
        #expect(holding.unrealizedGain == d("-28.75"))
    }

    @Test func netWorth() {
        #expect(valuator.netWorth(on: "2024-12-31").total == 0)
        #expect(valuator.netWorth(on: "2025-03-31").total == 10650)
        #expect(valuator.netWorth(on: "2025-06-30").total == d("10839.6"))
        #expect(valuator.netWorth(on: "2025-09-30").total == d("10767.05"))
        #expect(valuator.netWorth(on: "2025-12-31").total == d("9032.05"))
    }

    @Test func theYearsSummary() {
        let summary = ledger.summary(for: 2025)
        #expect(summary.realizedGain == d("143.75"))
        #expect(summary.realizedGainByInstrument == ["world-fund": d("143.75")])
        #expect(summary.salesWithUnknownGain.isEmpty)
        #expect(summary.dividends == 40)
        #expect(summary.interest == 0)
        #expect(summary.fees == 35)
        #expect(summary.taxes == d("112.95"))
        #expect(summary.incomeTax == d("10.4"))
        #expect(summary.netIncome == d("29.6"))
        #expect(summary.deposits == 10000)
        #expect(summary.withdrawals == 1000)
        #expect(valuator.tradeSummary(for: 2025) == summary)
    }

    /// Saved is the money put in less the money taken out; markets are the
    /// rest: realised and unrealised gains, the dividend, less the fee and
    /// the taxes.
    @Test func theYearsChange() throws {
        let year = try #require(valuator.changeThisYear(asOf: "2025-12-31"))
        #expect(year.total.change == d("9032.05"))
        #expect(year.total.saved == 9000)
        #expect(year.total.market == d("32.05"))
        #expect(year.total.other == 0)
        let moved = valuator.whatMoved(year)
        #expect(moved.saved == 9000)
        #expect(moved.markets == d("32.05"))
        #expect(moved.unexplained == 0)
        #expect(moved.pay == nil)
        let summary = ledger.summary(for: 2025)
        #expect(summary.realizedGain + d("-28.75") + summary.dividends - 10 - summary.taxes == d("32.05"))
    }
}
