import Foundation
import Model
import Testing
import TestSupport
import Tracker

/// Converting an account from snapshots to trades keeps its values and
/// flows, and says what it had to estimate.
struct TradeConversionTests {
    /// A made-up broker account recorded as positions at month-end check-ins.
    private func holdingsLibrary() -> Library {
        var library = TradeLibrary.withMarketData(Library(
            settings: LibrarySettings(baseCurrency: .eur),
            accounts: [Account(id: "broker", name: "Broker", kind: .brokerage, currency: .eur, opened: "2024-01-01",
                               valuation: .holdings)],
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
            if let previous {
                valuation.flow = valuator.snapshotFlow(for: valuation, previous: previous)
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
        // Trades are a brokerage account's default.
        #expect(conversion.account.valuation == nil)
        #expect(conversion.account.recordsTrades)
        // The cash each value shows that the buys and sales don't explain is a deposit: the opening cash,
        // then February's 470 and March's 100 of new money. April's buy was paid from the cash.
        #expect(conversion.trades == [
            Trade(account: "broker", date: "2024-01-31", id: "deposit", type: .deposit, amount: 100, source: .import),
            Trade(account: "broker", date: "2024-01-31", id: "opening-vwce", type: .opening, instrument: "vwce",
                  quantity: 10, cost: 1000, source: .import),
            Trade(account: "broker", date: "2024-02-29", id: "buy-vwce", type: .buy, instrument: "vwce", quantity: 5,
                  price: 105, currency: .eur, amount: -520),
            Trade(account: "broker", date: "2024-02-29", id: "deposit", type: .deposit, amount: 470),
            Trade(account: "broker", date: "2024-03-31", id: "deposit", type: .deposit, amount: 100),
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
        let valuations = converted.valuations(for: "broker")
        for (previous, valuation) in zip(valuations, valuations.dropFirst()) {
            #expect(valuator.defaultFlow(for: valuation, previous: previous) == valuation.flow, "\(valuation.date)")
        }
        // The cash is what the trades give: every flow is a trade, and no value has a residual.
        for valuation in valuations {
            #expect(valuator.tradeCash(of: "broker", on: valuation.date) == valuation.cash, "\(valuation.date)")
        }
        #expect(valuator.tradeFlows(of: "broker", after: nil, through: "2024-04-30").allSatisfy { $0.trade != nil })
        #expect(valuator.tradeIssues(for: "broker").isEmpty)
        #expect(converted.conversionToTrades(of: "broker") == nil)
    }

    @Test func theChangeSplitStaysTheSame() throws {
        let library = holdingsLibrary()
        var converted = library
        converted.convertToTrades("broker")
        // Each period from a value to a later one, or to the first value. (Snapshots with an unknown
        // flow in a longer period count all of its change as new money; trades split it.)
        let periods: [(CalendarDate, CalendarDate)] = [
            ("2023-12-31", "2024-01-31"), ("2024-01-31", "2024-02-29"), ("2024-02-29", "2024-03-31"),
            ("2024-03-31", "2024-04-30"), ("2024-01-31", "2024-04-30"), ("2024-02-15", "2024-03-15"),
        ]
        func split(_ library: Library, _ from: CalendarDate, _ to: CalendarDate) -> [Decimal] {
            let change = Valuator(library: library).change(from: from, to: to).accounts.first?.change
            return [change?.start, change?.market, change?.newMoney, change?.other, change?.end].map { $0 ?? -1 }
        }
        for (from, to) in periods {
            #expect(split(converted, from, to) == split(library, from, to), "\(from) – \(to)")
        }
        #expect(split(converted, "2024-01-31", "2024-04-30")[2] == 570)
    }

    @Test func cashTakenOutIsAWithdrawal() throws {
        var library = holdingsLibrary()
        // 300 taken out in May, nothing bought or sold.
        library.upsert(Valuation(account: "broker", date: "2024-05-31", cash: 120, positions: [
            Position(instrument: "aapl", quantity: 2, costBasis: 280),
            Position(instrument: "vwce", quantity: 10, costBasis: d("1013.33")),
        ], flow: -300))
        let conversion = try #require(library.conversionToTrades(of: "broker"))
        #expect(conversion.trades.last == Trade(account: "broker", date: "2024-05-31", id: "withdrawal",
                                                type: .withdrawal, amount: -300))
        #expect(conversion.notes.map(\.kind) == [.priceFromValuation])
        var converted = library
        converted.convertToTrades("broker")
        let valuator = Valuator(library: converted)
        #expect(valuator.tradeCash(of: "broker", on: "2024-05-31") == 120)
        #expect(valuator.tradeIssues(for: "broker").isEmpty)
    }

    @Test func aValueWithoutNewMoneyGetsWhatItsCashShows() throws {
        var library = holdingsLibrary()
        // March's new money wasn't recorded: the cash says 100 came in besides the sale.
        var march = try #require(library.valuations(for: "broker").first { $0.date == "2024-03-31" })
        march.flow = nil
        library.upsert(march)
        let conversion = try #require(library.conversionToTrades(of: "broker"))
        #expect(conversion.trades.filter { $0.type == .deposit }.map(\.amount) == [100, 470, 100])
        #expect(conversion.valuations.map(\.flow) == [nil, 470, nil, 0])
        var converted = library
        converted.convertToTrades("broker")
        #expect(Valuator(library: converted).change(from: "2024-02-29", to: "2024-03-31").total.newMoney == 100)
        #expect(values(converted, on: monthEnds) == values(library, on: monthEnds))
    }

    @Test func aTradeWithoutACashEffectLeavesItsValuesResidual() throws {
        var library = holdingsLibrary()
        // A position bought in February with no price on or before the date, and no cost.
        library.upsert(Valuation(account: "broker", date: "2024-02-29", cash: 50, positions: [
            Position(instrument: "vwce", quantity: 15, costBasis: 1520),
            Position(instrument: "unpriced", quantity: 1),
        ], flow: 470))
        let vwce = try #require(library.instruments["vwce"])
        library.instruments["unpriced"] = Instrument(id: "unpriced", name: "Unpriced", kind: .etf, currency: .eur,
                                                     unit: .share, assetClasses: vwce.assetClasses)
        let conversion = try #require(library.conversionToTrades(of: "broker"))
        #expect(conversion.notes.map(\.kind).contains(.noPrice))
        // February's cash can't be worked out from the trades, so it gets no deposit; adding the buy's
        // amount explains its residual. March's sale of the unpriced position is unknown too.
        #expect(conversion.trades.filter { $0.type == .deposit }.map(\.date) == ["2024-01-31"])
    }

    @Test func aBalanceBecomesCashAndMissingCostsAreEstimated() throws {
        var library = holdingsLibrary()
        library.upsert(Valuation(account: "broker", date: "2023-12-31", balance: 900, source: .import))
        library.upsert(Valuation(account: "broker", date: "2024-01-31", cash: 100,
                                 positions: [Position(instrument: "vwce", quantity: 10)]))
        let conversion = try #require(library.conversionToTrades(of: "broker"))
        #expect(conversion.valuations.first == Valuation(account: "broker", date: "2023-12-31", cash: 900,
                                                          source: .import))
        // The balance is cash put in. Positions after the first valuation are bought, at the
        // valuation's price; without a cost basis before it, February's buy is priced the same way.
        #expect(conversion.trades.prefix(3) == [
            Trade(account: "broker", date: "2023-12-31", id: "deposit", type: .deposit, amount: 900, source: .import),
            Trade(account: "broker", date: "2024-01-31", id: "buy-vwce", type: .buy, instrument: "vwce", quantity: 10,
                  price: 102, currency: .eur),
            Trade(account: "broker", date: "2024-01-31", id: "deposit", type: .deposit, amount: 220),
        ])
        #expect(conversion.notes.map(\.kind)
            == [.cashFromBalance, .priceFromValuation, .priceFromValuation, .priceFromValuation])

        var opening = holdingsLibrary()
        opening.upsert(Valuation(account: "broker", date: "2024-01-31", cash: 100,
                                 positions: [Position(instrument: "vwce", quantity: 10)]))
        let estimated = try #require(opening.conversionToTrades(of: "broker"))
        #expect(estimated.trades.first { $0.type == .opening }?.cost == 1020)
        #expect(estimated.notes.first?.kind == .costFromMarketValue)
        #expect(estimated.notes.first?.message
            == "The opening of 10 vwce has no recorded cost: it's their value then, 1020.")
    }
}

extension Valuator {
    /// The new money a snapshot check-in recorded before format version 4:
    /// the change in cash, plus each change in quantity at the new price,
    /// or what was paid for a quantity that went up (read from the cost
    /// bases). Made-up snapshot accounts in these tests record their flows
    /// so, as the example library's did.
    func snapshotFlow(for valuation: Valuation, previous: Valuation) -> Decimal? {
        guard let account = accounts[valuation.account] else { return nil }
        var flow = (valuation.cash ?? 0) - (previous.cash ?? 0)
        var instruments = valuation.positions.map(\.instrument)
        for position in previous.positions where !instruments.contains(position.instrument) {
            instruments.append(position.instrument)
        }
        for instrument in instruments {
            let now = valuation.position(for: instrument)
            let before = previous.position(for: instrument)
            let change = (now?.quantity ?? 0) - (before?.quantity ?? 0)
            if change == 0 { continue }
            // What was paid: the cost basis added.
            let paid: Decimal? = if change > 0, let cost = now?.costBasis {
                (before?.quantity ?? 0) <= 0 ? cost : before?.costBasis.map { cost - $0 }
            } else {
                nil
            }
            if let paid {
                flow += paid
            } else if let value = marketValue(of: change, of: instrument, in: account.currency, on: valuation.date) {
                flow += value
            } else {
                return nil
            }
        }
        return flow.rounded(scale: 2)
    }
}
