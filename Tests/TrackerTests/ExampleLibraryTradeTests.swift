import Foundation
import Model
import Testing
import TestSupport
import Tracker

/// The example library with Directa recorded as positions at each check-in,
/// converted back from its trades: for tests of accounts that hold positions.
func exampleLibraryWithHoldings() throws -> Library {
    var library = try Fixtures.exampleLibrary()
    let conversion = try #require(library.conversionToSnapshots(of: "directa"))
    conversion.apply(to: &library)
    return library
}

/// Directa in the example library records trades: an opening, monthly
/// deposits and buys of VWCE, and a sale in July. Its values and flows at
/// each check-in are the ones it had as positions.
struct ExampleLibraryTradeTests {
    let library: Library
    let valuator: Valuator

    init() throws {
        library = try Fixtures.exampleLibrary()
        valuator = Valuator(library: library)
    }

    /// Month-end values and flows of Directa when it recorded positions
    /// (before it recorded trades), and its quantities.
    private let monthEnds: [(CalendarDate, cash: String, quantity: String, flow: String?)] = [
        ("2025-10-31", "215.4", "338", nil), ("2025-11-30", "188.9", "348", "1267.5"),
        ("2025-12-31", "402.15", "358", "1523.75"), ("2026-01-31", "256.8", "368", "1180.65"),
        ("2026-02-28", "310.45", "378", "1355.65"), ("2026-03-31", "150.2", "388", "1118.25"),
        ("2026-04-30", "1480.6", "391", "1726.1"), ("2026-05-31", "402.9", "401", "259.3"),
        ("2026-06-30", "290.35", "411", "1228.95"), ("2026-07-31", "1452.7", "402.5", "-0.45"),
        ("2026-08-31", "300.8", "412.5", "200.6"), ("2026-09-30", "312.1", "412.5", "11.3"),
    ]

    @Test func directaRecordsTrades() throws {
        #expect(library.accounts["directa"]?.recordsTrades == true)
        #expect(library.trades(for: "directa").count == 20)
        #expect(valuator.tradeIssues().isEmpty)
        #expect(valuator.reconciliation(of: "directa").isEmpty)
        #expect(library.valuations(for: "directa").allSatisfy { $0.positions.isEmpty && $0.cash != nil })
    }

    @Test func itsHoldingsCashAndFlowsAreTheSameAsBefore() throws {
        var previous: Valuation?
        for (date, cash, quantity, flow) in monthEnds {
            let snapshot = try #require(valuator.snapshot(of: "directa", on: date))
            #expect(snapshot.cash == d(cash), "\(date)")
            #expect(snapshot.positions.map(\.quantity) == [d(quantity)], "\(date)")
            let valuation = try #require(library.valuations(for: "directa").first { $0.date == date })
            #expect(valuation.flow == flow.map(d), "\(date)")
            if let flow {
                #expect(valuator.defaultFlow(for: valuation, previous: previous) == d(flow), "\(date)")
            }
            previous = valuation
        }
        // The cash between check-ins follows the trades: the November deposit, then the buy.
        #expect(valuator.tradeCash(of: "directa", on: "2025-11-04") == d("1482.9"))
        #expect(valuator.tradeCash(of: "directa", on: "2025-11-12") == d("188.9"))
    }

    @Test func itsAverageCostIsTheBrokersCarryingValue() throws {
        let september = try #require(valuator.holdings(of: "directa", on: "2026-09-30").first)
        #expect(september.costBasis == 48200)
        #expect(september.unrealizedGain == d("8898.25"))
        #expect(valuator.snapshot(of: "directa", on: "2025-12-31")?.positions.first?.costBasis == d("40856.13"))
    }

    @Test func theJulySaleAndTheYearsIncome() throws {
        let sale = try #require(valuator.ledger(for: "directa")?.entries.first { $0.type == .sell })
        #expect(sale.cost == d("989.33"))
        #expect(sale.realizedGain == d("234.42"))
        let year = valuator.tradeSummary(for: 2026)
        #expect(year.realizedGain == d("234.42"))
        #expect(year.taxes == d("60.95"))
        #expect(year.fees == d("36.5"))
        #expect(year.deposits == d("7069.5"))
        #expect(year.dividends == 0)
        #expect(valuator.tradeSummary(for: 2025).deposits == d("2791.25"))
    }

    @Test func convertingBackToPositionsKeepsEveryValue() throws {
        let holdings = try exampleLibraryWithHoldings()
        #expect(holdings.accounts["directa"]?.valuation == nil)
        #expect(holdings.trades(for: "directa").isEmpty)
        let other = Valuator(library: holdings)
        for (date, _, _, _) in monthEnds {
            #expect(other.netWorth(on: date).total == valuator.netWorth(on: date).total, "\(date)")
        }
        let september = try #require(holdings.valuations(for: "directa").last)
        #expect(september == Valuation(account: "directa", date: "2026-09-30", cash: d("312.1"), positions: [
            Position(instrument: "vwce", quantity: d("412.5"), costBasis: 48200),
        ], flow: d("11.3")))
        // And to trades again: the same values.
        var again = holdings
        let converted = again.convertToTrades("directa")
        let conversion = try #require(converted)
        #expect(conversion.notes.map(\.kind).allSatisfy { $0 == .priceFromValuation })
        let third = Valuator(library: again)
        for (date, _, _, _) in monthEnds {
            #expect(third.netWorth(on: date).total == valuator.netWorth(on: date).total, "\(date)")
        }
    }
}
