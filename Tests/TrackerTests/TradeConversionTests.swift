import Foundation
import Model
import Testing
import TestSupport
import Tracker

/// Converting an account between snapshots and trades keeps its values and
/// flows, and says what it had to estimate.
struct TradeConversionTests {
    /// A made-up broker account recorded as positions at month-end check-ins.
    private func holdingsLibrary() -> Library {
        var library = TradeLibrary.withMarketData(Library(
            settings: LibrarySettings(baseCurrency: .eur),
            accounts: [Account(id: "broker", name: "Broker", kind: .brokerage, currency: .eur, opened: "2024-01-01")],
            instruments: Array(TradeLibrary.base.instruments.values)))
        library.upsert(PriceRecord(instrument: "aapl", date: "2024-04-30", price: 170, currency: .usd))
        library.upsert(PriceRecord(instrument: "vwce", date: "2024-04-30", price: 112, currency: .eur))
        library.upsert(FXRecord(base: .eur, quote: .usd, date: "2024-04-30", rate: d("1.25")))
        let valuations = [
            Valuation(account: "broker", date: "2024-01-31", cash: 100,
                      positions: [Position(instrument: "vwce", quantity: 10, costBasis: 1000)], source: .import),
            // Bought 5 for 520.
            Valuation(account: "broker", date: "2024-02-29", cash: 50,
                      positions: [Position(instrument: "vwce", quantity: 15, costBasis: 1520)]),
            // Sold 5.
            Valuation(account: "broker", date: "2024-03-31", cash: 700,
                      positions: [Position(instrument: "vwce", quantity: 10, costBasis: d("1013.33"))]),
            // Bought 2 AAPL for 280.
            Valuation(account: "broker", date: "2024-04-30", cash: 420, positions: [
                Position(instrument: "aapl", quantity: 2, costBasis: 280),
                Position(instrument: "vwce", quantity: 10, costBasis: d("1013.33")),
            ], note: "statement"),
        ]
        let valuator = Valuator(library: library)
        var previous: Valuation?
        for var valuation in valuations {
            if previous != nil {
                let paid = [InstrumentID: Decimal](valuation.positions.compactMap { position in
                    let before = previous?.position(for: position.instrument)
                    guard position.quantity > (before?.quantity ?? 0), let cost = position.costBasis else { return nil }
                    return (position.instrument, cost - (before?.costBasis ?? 0))
                }, uniquingKeysWith: { first, _ in first })
                valuation.flow = valuator.defaultFlow(for: valuation, previous: previous, paid: paid)
            }
            library.upsert(valuation)
            previous = valuation
        }
        return library
    }

    private func values(_ library: Library, on dates: [CalendarDate]) -> [Decimal?] {
        let valuator = Valuator(library: library)
        return dates.map { valuator.value(of: "broker", on: $0)?.value?.rounded(10) }
    }

    private let monthEnds: [CalendarDate] = ["2024-01-31", "2024-02-29", "2024-03-15", "2024-03-31", "2024-04-30"]

    @Test func snapshotsBecomeAnOpeningThenABuyOrSellPerChange() throws {
        let library = holdingsLibrary()
        #expect(library.valuations(for: "broker").map(\.flow) == [nil, 470, 100, 0])
        let conversion = try #require(library.conversionToTrades(of: "broker"))
        #expect(conversion.account.valuation == .trades)
        #expect(conversion.trades == [
            Trade(account: "broker", date: "2024-01-31", id: "opening-vwce", type: .opening, instrument: "vwce",
                  quantity: 10, cost: 1000, source: .import),
            Trade(account: "broker", date: "2024-02-29", id: "buy-vwce", type: .buy, instrument: "vwce", quantity: 5,
                  price: 105, currency: .eur, amount: -520),
            Trade(account: "broker", date: "2024-03-31", id: "sell-vwce", type: .sell, instrument: "vwce",
                  quantity: 5, price: 110, currency: .eur),
            Trade(account: "broker", date: "2024-04-30", id: "buy-aapl", type: .buy, instrument: "aapl", quantity: 2,
                  price: 170, currency: .usd, amount: -280),
        ])
        #expect(conversion.valuations.map(\.positions) == [[], [], [], []])
        #expect(conversion.valuations.map(\.cash) == [100, 50, 700, 420])
        #expect(conversion.valuations.map(\.flow) == [nil, 470, 100, 0])
        #expect(conversion.valuations.last?.note == "statement")
        // Only the sale's price had to be guessed.
        #expect(conversion.notes.map(\.kind) == [.priceFromValuation])
        #expect(conversion.notes.first?.message == "The sale of 5 vwce is priced at the valuation's price.")
        #expect(conversion.months == ["2024-01", "2024-02", "2024-03", "2024-04"])

        var converted = library
        #expect(converted.convertToTrades("broker") == conversion)
        #expect(converted.accounts["broker"]?.recordsTrades == true)
        // The same values, and flows that are what the trades give.
        #expect(values(converted, on: monthEnds) == values(library, on: monthEnds))
        let valuator = Valuator(library: converted)
        for valuation in converted.valuations(for: "broker").dropFirst() {
            #expect(valuator.defaultFlow(for: valuation) == valuation.flow, "\(valuation.date)")
        }
        #expect(valuator.tradeIssues(for: "broker").isEmpty)
        #expect(converted.conversionToTrades(of: "broker") == nil)
    }

    @Test func aRoundTripGivesBackTheSnapshots() throws {
        let library = holdingsLibrary()
        var converted = library
        converted.convertToTrades("broker")
        let back = try #require(converted.conversionToSnapshots(of: "broker"))
        #expect(back.notes.map(\.kind) == [.tradesRemoved])
        #expect(back.removedTrades.count == 4)
        converted.convertToSnapshots("broker")
        #expect(converted == library)
    }

    @Test func tradesWithoutValuationsBecomeASnapshotAtEachMonthsLastTrade() throws {
        let library = TradeLibrary.recordedDeposits()
        let conversion = try #require(library.conversionToSnapshots(of: "broker"))
        #expect(conversion.account.valuation == nil)
        #expect(conversion.notes.map(\.kind) == [.tradesRemoved, .addedValuation, .addedValuation, .addedValuation])
        #expect(conversion.valuations == [
            Valuation(account: "broker", date: "2024-01-05", cash: 4995,
                      positions: [Position(instrument: "vwce", quantity: 50, costBasis: 5005)], flow: 10000),
            Valuation(account: "broker", date: "2024-02-15", cash: 5015,
                      positions: [Position(instrument: "vwce", quantity: 50, costBasis: 5005)], flow: 0),
            Valuation(account: "broker", date: "2024-03-25", cash: d("5295.36"), positions: [
                Position(instrument: "aapl", quantity: 10, costBasis: d("1364.64")),
                Position(instrument: "vwce", quantity: 40, costBasis: d("3936.67")),
            ], flow: 550),
        ])
        var converted = library
        converted.convertToSnapshots("broker")
        #expect(converted.trades(for: "broker").isEmpty)
        // Month ends keep their values; in between, snapshots carry the last one.
        let dates = monthEnds.filter(\.isEndOfMonth)
        #expect(values(converted, on: dates) == values(library, on: dates))
    }

    @Test func aBalanceBecomesCashAndMissingCostsAreEstimated() throws {
        var library = holdingsLibrary()
        library.upsert(Valuation(account: "broker", date: "2023-12-31", balance: 900, source: .import))
        library.upsert(Valuation(account: "broker", date: "2024-01-31", cash: 100,
                                 positions: [Position(instrument: "vwce", quantity: 10)]))
        let conversion = try #require(library.conversionToTrades(of: "broker"))
        #expect(conversion.valuations.first == Valuation(account: "broker", date: "2023-12-31", cash: 900,
                                                          source: .import))
        // Positions after the first valuation are bought, at the valuation's price; without a
        // cost basis before it, February's buy is priced the same way.
        #expect(conversion.trades.first?.type == .buy)
        #expect(conversion.trades.first?.amount == nil)
        #expect(conversion.notes.map(\.kind)
            == [.cashFromBalance, .priceFromValuation, .priceFromValuation, .priceFromValuation])

        var opening = holdingsLibrary()
        opening.upsert(Valuation(account: "broker", date: "2024-01-31", cash: 100,
                                 positions: [Position(instrument: "vwce", quantity: 10)]))
        let estimated = try #require(opening.conversionToTrades(of: "broker"))
        #expect(estimated.trades.first?.cost == 1020)
        #expect(estimated.notes.first?.kind == .costFromMarketValue)
        #expect(estimated.notes.first?.message
            == "The opening of 10 vwce has no recorded cost: it's their value then, 1020.")
    }
}
