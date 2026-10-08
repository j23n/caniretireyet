import Foundation
import Model
import Testing
import TestSupport
import Tracker

/// Made-up gold coins bought from a dealer and paid from the bank: a metals
/// account recording trades, with no cash of its own (docs/TRADES.md, "Paid
/// from outside the account").
private enum GoldLibrary {
    static let base = Library(
        settings: LibrarySettings(baseCurrency: .eur),
        accounts: [
            Account(id: "coins", name: "Gold coins", kind: .metals, currency: .eur, opened: "2024-01-01",
                    valuation: .trades),
            Account(id: "broker", name: "Broker", kind: .brokerage, currency: .eur, opened: "2024-01-01",
                    valuation: .trades),
        ],
        instruments: [
            Instrument(id: "gold", name: "Gold", kind: .metal, currency: .eur, unit: .gram,
                       assetClasses: .single(.gold)),
            Instrument(id: "vwce", name: "VWCE", kind: .etf, currency: .eur, unit: .share,
                       assetClasses: .single(.equity)),
        ])

    /// 31.1 g at 60 €/g with 10 € fees on 15 January (1,876 €); 10 g sold at 68 €/g on 15 March (680 €).
    static func trades(_ settlement: TradeSettlement?) -> [Trade] {
        [
            Trade(account: "coins", date: "2024-01-15", id: "buy1", type: .buy, instrument: "gold",
                  quantity: d("31.1"), price: 60, fees: 10, settlement: settlement),
            Trade(account: "coins", date: "2024-03-15", id: "sell1", type: .sell, instrument: "gold", quantity: 10,
                  price: 68, settlement: settlement),
        ]
    }

    static func withPrices(_ library: Library) -> Library {
        var library = library
        for (date, price) in [("2024-01-15", "60"), ("2024-01-31", "62"), ("2024-02-29", "65"), ("2024-03-15", "68"),
                              ("2024-03-31", "70")] {
            library.upsert(PriceRecord(instrument: "gold", date: CalendarDate(date)!, price: d(price), currency: .eur))
        }
        library.upsert(PriceRecord(instrument: "vwce", date: "2024-01-31", price: 100, currency: .eur))
        library.upsert(PriceRecord(instrument: "vwce", date: "2024-03-31", price: 110, currency: .eur))
        return library
    }

    /// The coins bought and sold outside the account.
    static func external() -> Library {
        var library = withPrices(base)
        for trade in trades(.external) { library.upsert(trade) }
        return library
    }

    /// The same trades through the account's cash, with the old workaround:
    /// a deposit of the cost on the buy's day, a withdrawal of the proceeds.
    static func throughCash() -> Library {
        var library = withPrices(base)
        for trade in trades(nil) { library.upsert(trade) }
        library.upsert(Trade(account: "coins", date: "2024-01-15", id: "dep1", type: .deposit, amount: 1876))
        library.upsert(Trade(account: "coins", date: "2024-03-15", id: "wd1", type: .withdrawal, amount: -680))
        return library
    }
}

struct ExternalSettlementTests {
    @Test func anExternalBuyLeavesTheCashAndAddsItsCostAsAFlow() throws {
        let valuator = Valuator(library: GoldLibrary.external())
        let ledger = try #require(valuator.ledger(for: "coins"))
        let buy = ledger.entries[0]
        #expect(buy.amount == -1876)
        #expect(buy.cashEffect == 0)
        #expect(buy.cost == 1876)
        #expect(buy.externalFlow == 1876)
        #expect(ledger.issues.isEmpty)

        #expect(valuator.tradeCash(of: "coins", on: "2024-01-15") == 0)
        #expect(valuator.tradeCash(of: "coins", on: "2024-03-31") == 0)
        let flows = valuator.tradeFlows(of: "coins", after: nil, through: "2024-01-31")
        #expect(flows.map(\.date) == ["2024-01-15"])
        #expect(flows.map(\.amount) == [1876])
        #expect(flows.first?.trade?.id == "buy1")
        #expect(flows.first?.isResidual == false)

        // Without the settlement, the same buy takes the cash below zero.
        var plain = GoldLibrary.withPrices(GoldLibrary.base)
        for trade in GoldLibrary.trades(nil) { plain.upsert(trade) }
        let throughCash = Valuator(library: plain)
        #expect(throughCash.tradeCash(of: "coins", on: "2024-01-31") == -1876)
        #expect(throughCash.value(of: "coins", on: "2024-01-31")?.value == d("52.2"))
        #expect(throughCash.tradeFlows(of: "coins", after: nil, through: "2024-01-31").isEmpty)
    }

    @Test func anExternalSellsProceedsAreMoneyTakenOut() throws {
        let valuator = Valuator(library: GoldLibrary.external())
        let sell = try #require(valuator.ledger(for: "coins")?.entries.last)
        #expect(sell.amount == 680)
        #expect(sell.cashEffect == 0)
        #expect(sell.externalFlow == -680)
        #expect(valuator.tradeCash(of: "coins", on: "2024-03-15") == 0)
        let flows = valuator.tradeFlows(of: "coins", after: "2024-01-31", through: "2024-03-31")
        #expect(flows.map(\.date) == ["2024-03-15"])
        #expect(flows.map(\.amount) == [-680])
        #expect(valuator.tradeFlowTotal(of: "coins", after: nil, through: "2024-03-31") == 1196)
        #expect(valuator.ledger(for: "coins")?.positions(on: "2024-03-31").map(\.quantity) == [d("21.1")])
    }

    @Test func costBasisAndGainsAreThoseOfTheSameTradesPaidFromCash() throws {
        let external = Valuator(library: GoldLibrary.external())
        let throughCash = Valuator(library: GoldLibrary.throughCash())
        let outside = try #require(external.ledger(for: "coins"))
        let inside = try #require(throughCash.ledger(for: "coins"))
        for date: CalendarDate in ["2024-01-15", "2024-02-29", "2024-03-31"] {
            #expect(outside.positions(on: date) == inside.positions(on: date), "\(date)")
        }
        #expect(outside.positions(on: "2024-01-31") == [Position(instrument: "gold", quantity: d("31.1"),
                                                                 costBasis: 1876)])
        let sale = try #require(outside.entries.last)
        let same = try #require(inside.entries.first { $0.trade.id == "sell1" })
        // 680 less the average cost of 10 of 31.1 g: 1,876 × 10 / 31.1 = 603.22.
        #expect(sale.realizedGain == d("76.78"))
        #expect(sale.realizedGain == same.realizedGain)
        #expect(sale.cost == same.cost)
        #expect(outside.summary(for: 2024).realizedGain == inside.summary(for: 2024).realizedGain)
        #expect(outside.summary(for: 2024).fees == 10)
        #expect(external.instrumentReturn(of: "gold", in: "coins", from: "2024-01-01", to: "2024-03-31")?.gain
            == throughCash.instrumentReturn(of: "gold", in: "coins", from: "2024-01-01", to: "2024-03-31")?.gain)
    }

    @Test func theGoldAccountIsWorthTheGold() throws {
        let valuator = Valuator(library: GoldLibrary.external())
        let january = try #require(valuator.value(of: "coins", on: "2024-01-31"))
        #expect(january.isComplete)
        #expect(january.value == d("31.1") * 62)
        #expect(valuator.value(of: "coins", on: "2024-03-31")?.value == d("21.1") * 70)
        #expect(valuator.snapshot(of: "coins", on: "2024-03-31")?.cash == 0)
        #expect(valuator.netWorth(on: "2024-01-31").total == d("31.1") * 62)
        #expect(valuator.breakdown(by: .assetClass, on: "2024-01-31").value(of: .assetClass(.gold)) == d("31.1") * 62)

        // The change since the start: the cost is new money, the rest is the market.
        let change = try #require(valuator.change(of: "coins", from: "2024-01-01", to: "2024-01-31"))
        #expect(change.change.newMoney == 1876)
        #expect(change.change.market == d("31.1") * 62 - 1876)
        #expect(change.problems.isEmpty)
        let spring = try #require(valuator.change(of: "coins", from: "2024-01-31", to: "2024-03-31"))
        #expect(spring.change.newMoney == -680)
        #expect(spring.change.market == d("21.1") * 70 - d("31.1") * 62 + 680)

        // Performance counts the purchase as money in, not as a gain.
        let performance = try #require(valuator.performance(of: .account("coins"), from: "2024-01-01",
                                                            to: "2024-03-31"))
        #expect(performance.accounts == ["coins"])
        #expect(performance.netFlows == 1196)
        #expect(performance.endValue == d("21.1") * 70)
        let gold = try #require(valuator.performance(of: .assetClass(.gold, .netWorth), from: "2024-01-01",
                                                     to: "2024-03-31"))
        #expect(gold.netFlows == 1196)
        #expect(gold.timeWeighted?.cumulative.rounded(6) == performance.timeWeighted?.cumulative.rounded(6))
        // The same as recording a deposit and a withdrawal around each trade.
        let workaround = try #require(Valuator(library: GoldLibrary.throughCash())
            .performance(of: .account("coins"), from: "2024-01-01", to: "2024-03-31"))
        #expect(performance.timeWeighted?.cumulative.rounded(6) == workaround.timeWeighted?.cumulative.rounded(6))
        #expect(performance.moneyWeighted?.cumulative.rounded(6) == workaround.moneyWeighted?.cumulative.rounded(6))
    }

    @Test func theCheckInStartsFromNoCashAndCountsTheCostAsNewMoney() throws {
        let library = GoldLibrary.external()
        var draft = CheckInDraft(date: "2024-01-31", library: library)
        let row = try #require(draft["coins"])
        #expect(row.isTrades)
        #expect(row.cash == 0)
        #expect(row.derived?.positions.map(\.quantity) == [d("31.1")])
        #expect(draft["coins"]?.markUnchanged() == true)
        let review = try #require(draft.review(in: library).row(for: "coins"))
        #expect(review.defaultFlow == 1876)
        #expect(review.valuation == Valuation(account: "coins", date: "2024-01-31", cash: 0, flow: 1876))
    }

    @Test func anExternalFeeIsACostOfTheAccountPaidFromElsewhere() throws {
        var library = GoldLibrary.external()
        library.upsert(Trade(account: "coins", date: "2024-02-10", id: "vault", type: .fee, amount: -40,
                             note: "safe deposit box", settlement: .external))
        let valuator = Valuator(library: library)
        #expect(valuator.tradeCash(of: "coins", on: "2024-02-29") == 0)
        #expect(valuator.tradeFlows(of: "coins", after: "2024-01-31", through: "2024-02-29").map(\.amount) == [40])
        #expect(valuator.ledger(for: "coins")?.summary(for: 2024).fees == 50)
        let change = try #require(valuator.change(of: "coins", from: "2024-01-31", to: "2024-02-29"))
        #expect(change.change.newMoney == 40)
        #expect(change.change.market == d("31.1") * 3 - 40)
    }

    @Test func anExternalBuyWithoutARateIsAnUnknownFlowNotUnknownCash() throws {
        var library = GoldLibrary.external()
        library.upsert(Trade(account: "coins", date: "2024-02-15", id: "usd", type: .buy, instrument: "gold",
                             quantity: 1, price: 70, currency: .usd, settlement: .external))
        let valuator = Valuator(library: library)
        #expect(valuator.tradeCash(of: "coins", on: "2024-02-29") == 0)
        #expect(valuator.value(of: "coins", on: "2024-02-29")?.problems.isEmpty == true)
        #expect(valuator.tradeFlowTotal(of: "coins", after: "2024-01-31", through: "2024-02-29") == nil)
        #expect(valuator.ledger(for: "coins")?.issues.map(\.kind) == [.missingFX])
        let change = try #require(valuator.change(of: "coins", from: "2024-01-31", to: "2024-02-29"))
        #expect(change.problems == [.missingFX(account: "coins", from: .usd, to: .eur)])
    }

    @Test func aMixedAccountKeepsItsCashForTheTradesPaidFromIt() throws {
        var library = GoldLibrary.withPrices(GoldLibrary.base)
        let trades = [
            Trade(account: "broker", date: "2024-01-02", id: "dep", type: .deposit, amount: 1000),
            Trade(account: "broker", date: "2024-01-10", id: "buy", type: .buy, instrument: "vwce", quantity: 8,
                  price: 100),
            // Bought with a bonus paid straight to the broker by the employer's plan, say.
            Trade(account: "broker", date: "2024-01-20", id: "ext", type: .buy, instrument: "vwce", quantity: 5,
                  price: 100, settlement: .external),
            Trade(account: "broker", date: "2024-03-20", id: "sell", type: .sell, instrument: "vwce", quantity: 3,
                  price: 110),
            Trade(account: "broker", date: "2024-03-25", id: "out", type: .sell, instrument: "vwce", quantity: 2,
                  price: 110, settlement: .external),
        ]
        for trade in trades { library.upsert(trade) }
        let valuator = Valuator(library: library)
        #expect(valuator.tradeCash(of: "broker", on: "2024-01-31") == 200)
        #expect(valuator.tradeCash(of: "broker", on: "2024-03-31") == 530)
        #expect(valuator.value(of: "broker", on: "2024-01-31")?.value == 1500)  // 13 × 100 + 200
        #expect(valuator.value(of: "broker", on: "2024-03-31")?.value == 1410)  // 8 × 110 + 530
        #expect(valuator.tradeFlows(of: "broker", after: nil, through: "2024-03-31").map(\.amount) == [1000, 500, -220])
        #expect(valuator.ledger(for: "broker")?.positions(on: "2024-03-31")
            == [Position(instrument: "vwce", quantity: 8, costBasis: 800)])
        #expect(valuator.ledger(for: "broker")?.summary(for: 2024).realizedGain == 50)
        // The check-in counts the deposit and the purchase from outside as new money.
        var draft = CheckInDraft(date: "2024-01-31", library: library)
        #expect(draft["broker"]?.cash == 200)
        #expect(draft["broker"]?.markUnchanged() == true)
        #expect(draft.review(in: library).row(for: "broker")?.defaultFlow == 1500)
        let january = Valuation(account: "broker", date: "2024-01-31", cash: 200)
        #expect(valuator.defaultFlow(for: january) == 1500)
    }

    @Test func theDefaultIsOutsideForMetalsAndAccountsThatNeverHeldCash() throws {
        var library = GoldLibrary.external()
        #expect(!library.hasHeldCash("coins"))
        #expect(library.defaultSettlement(for: .buy, in: "coins") == .external)
        #expect(library.defaultSettlement(for: .sell, in: "coins") == .external)
        #expect(library.defaultSettlement(for: .fee, in: "coins") == .external)
        #expect(library.defaultSettlement(for: .dividend, in: "coins") == nil)
        #expect(library.defaultSettlement(for: .buy, in: "nowhere") == nil)
        // A brokerage account with nothing yet: its buys would take its cash below zero.
        #expect(library.defaultSettlement(for: .buy, in: "broker") == .external)

        library.upsert(Trade(account: "broker", date: "2024-01-02", id: "dep", type: .deposit, amount: 1000))
        #expect(library.hasHeldCash("broker"))
        #expect(library.defaultSettlement(for: .buy, in: "broker") == .account)

        // A sale whose proceeds stayed is cash held; a metals account stays outside anyway.
        library.upsert(Trade(account: "coins", date: "2024-03-20", id: "kept", type: .sell, instrument: "gold",
                             quantity: 1, price: 70))
        #expect(library.hasHeldCash("coins"))
        #expect(library.defaultSettlement(for: .buy, in: "coins") == .external)

        var typed = GoldLibrary.base
        typed.upsert(Valuation(account: "broker", date: "2024-01-31", cash: 0))
        #expect(!typed.hasHeldCash("broker"))
        typed.upsert(Valuation(account: "broker", date: "2024-02-29", cash: 25))
        #expect(typed.hasHeldCash("broker"))
        #expect(typed.defaultSettlement(for: .sell, in: "broker") == .account)
    }
}

/// Converting a holdings account that never held cash to trades.
struct ExternalConversionTests {
    /// Made-up coins recorded as positions only, with the check-in's default flows.
    private func coins() -> Library {
        var library = GoldLibrary.withPrices(Library(
            settings: LibrarySettings(baseCurrency: .eur),
            accounts: [Account(id: "coins", name: "Gold coins", kind: .metals, currency: .eur, opened: "2024-01-01")],
            instruments: Array(GoldLibrary.base.instruments.values)))
        let valuations = [
            Valuation(account: "coins", date: "2024-01-31",
                      positions: [Position(instrument: "gold", quantity: d("31.1"), costBasis: 1876)]),
            // Bought 31.1 g for 2,030.
            Valuation(account: "coins", date: "2024-02-29",
                      positions: [Position(instrument: "gold", quantity: d("62.2"), costBasis: 3906)]),
            // Sold 10 g.
            Valuation(account: "coins", date: "2024-03-31",
                      positions: [Position(instrument: "gold", quantity: d("52.2"), costBasis: d("3278.03"))]),
        ]
        let valuator = Valuator(library: library)
        var previous: Valuation?
        for var valuation in valuations {
            if let previous {
                let paid: [InstrumentID: Decimal] = valuation.positions[0].quantity > previous.positions[0].quantity
                    ? ["gold": valuation.positions[0].costBasis! - previous.positions[0].costBasis!] : [:]
                valuation.flow = valuator.defaultFlow(for: valuation, previous: previous, paid: paid)
            }
            library.upsert(valuation)
            previous = valuation
        }
        return library
    }

    @Test func aCashlessHoldingsAccountBecomesTradesPaidFromOutside() throws {
        let library = coins()
        #expect(library.valuations(for: "coins").map(\.flow) == [nil, 2030, -700])
        let conversion = try #require(library.conversionToTrades(of: "coins"))
        #expect(conversion.trades == [
            Trade(account: "coins", date: "2024-01-31", id: "opening-gold", type: .opening, instrument: "gold",
                  quantity: d("31.1"), cost: 1876),
            Trade(account: "coins", date: "2024-02-29", id: "buy-gold", type: .buy, instrument: "gold",
                  quantity: d("31.1"), price: 65, currency: .eur, amount: -2030, settlement: .external),
            Trade(account: "coins", date: "2024-03-31", id: "sell-gold", type: .sell, instrument: "gold", quantity: 10,
                  price: 70, currency: .eur, settlement: .external),
        ])
        #expect(conversion.notes.map(\.kind) == [.settledOutside, .priceFromValuation])

        var converted = library
        converted.convertToTrades("coins")
        let valuator = Valuator(library: converted)
        let dates: [CalendarDate] = ["2024-01-31", "2024-02-15", "2024-02-29", "2024-03-15", "2024-03-31"]
        // No cash, ever, and no residuals: the trades are the new money.
        for date in dates {
            #expect(valuator.tradeCash(of: "coins", on: date) == 0, "\(date)")
        }
        let flows = valuator.tradeFlows(of: "coins", after: nil, through: "2024-03-31")
        #expect(flows.filter(\.isResidual).isEmpty)
        #expect(valuator.tradeFlows(of: "coins", after: "2024-01-31", through: "2024-03-31").map(\.amount)
            == [2030, -700])
        for valuation in converted.valuations(for: "coins").dropFirst() {
            #expect(valuator.defaultFlow(for: valuation) == valuation.flow, "\(valuation.date)")
        }
        let before = Valuator(library: library)
        for date in dates {
            #expect(valuator.value(of: "coins", on: date)?.value == before.value(of: "coins", on: date)?.value,
                    "\(date)")
        }
        #expect(valuator.tradeIssues(for: "coins").isEmpty)

        // Without its valuations' cash anchoring it, the cash still stays at zero.
        var unanchored = converted
        for valuation in unanchored.valuations(for: "coins") { unanchored.removeValuation(valuation.key) }
        #expect(Valuator(library: unanchored).tradeCash(of: "coins", on: "2024-03-31") == 0)

        // Back to snapshots gives the same positions.
        #expect(converted.convertToSnapshots("coins") != nil)
        #expect(converted.valuations(for: "coins").map(\.positions) == library.valuations(for: "coins").map(\.positions))
    }

    @Test func theExampleGoldCoinsConvertToABuyPaidFromOutside() throws {
        let library = try Fixtures.exampleLibrary()
        #expect(!library.hasHeldCash("gold-coins"))
        let conversion = try #require(library.conversionToTrades(of: "gold-coins"))
        let buy = try #require(conversion.trades.first { $0.type == .buy })
        #expect(buy.settlement == .external)
        #expect(buy.amount == d("-3026.03"))
        var converted = library
        converted.convertToTrades("gold-coins")
        let valuator = Valuator(library: converted)
        let original = Valuator(library: library)
        for valuation in converted.valuations(for: "gold-coins") {
            #expect(valuator.tradeCash(of: "gold-coins", on: valuation.date) == 0)
            #expect(valuator.value(of: "gold-coins", on: valuation.date)?.value
                == original.value(of: "gold-coins", on: valuation.date)?.value)
        }
        #expect(valuator.netWorth(on: "2026-09-30").total == original.netWorth(on: "2026-09-30").total)
    }

    /// An account made of trades only, with no valuation yet: "unchanged" at
    /// a check-in counts as new money only what was bought since the
    /// previous check-in, not every purchase since the first trade.
    @Test func aFirstCheckInCountsOnlyTheFlowsSinceThePreviousCheckIn() throws {
        var library = GoldLibrary.external()
        // An earlier check-in of another account, on 29 February.
        library.upsert(Valuation(account: "broker", date: "2024-02-29", cash: 100))
        let valuator = Valuator(library: library)
        // The coins' first valuation, on 31 March: only the March sale is in the period.
        let march = Valuation(account: "coins", date: "2024-03-31", cash: 0)
        #expect(valuator.defaultFlow(for: march, previous: nil) == -680)

        // With no earlier check-in at all, the whole history counts.
        let alone = Valuator(library: GoldLibrary.external())
        #expect(alone.defaultFlow(for: march, previous: nil) == 1196)

        // A check-in where nothing was bought or sold: no new money.
        library.upsert(Valuation(account: "broker", date: "2024-03-31", cash: 100))
        let april = Valuation(account: "coins", date: "2024-04-30", cash: 0)
        #expect(Valuator(library: library).defaultFlow(for: april, previous: nil) == 0)
    }

    /// The parts a check-in shows of a trades account's new money count
    /// from the same start as the flow it saves: at the account's first
    /// check-in, the library's previous check-in, not its first trade.
    @Test func theFlowPartsCountFromTheSameStartAsTheFlow() throws {
        var library = GoldLibrary.external()
        library.upsert(Trade(account: "broker", date: "2024-01-10", id: "dep1", type: .deposit, amount: 1_000))
        library.upsert(Trade(account: "broker", date: "2024-03-10", id: "dep2", type: .deposit, amount: 500))
        library.upsert(Trade(account: "broker", date: "2024-03-12", id: "buy1", type: .buy, instrument: "vwce",
                             quantity: 2, price: 105, settlement: .external))
        // An earlier check-in of another account, on 29 February.
        library.upsert(Valuation(account: "coins", date: "2024-02-29", cash: 0))
        let valuator = Valuator(library: library)

        // The broker's first valuation, on 31 March: the March deposit and
        // the buy paid from outside, not the January deposit.
        let parts = valuator.tradeFlowParts(of: "broker", on: "2024-03-31", previous: nil)
        #expect(parts == TradeFlowParts(recorded: 710, paidOutside: 210))
        let march = Valuation(account: "broker", date: "2024-03-31")
        #expect(valuator.defaultFlow(for: march, previous: nil) == parts.recorded)

        // After a valuation of its own, from that one.
        let january = Valuation(account: "broker", date: "2024-01-31", cash: 1_000)
        library.upsert(january)
        let since = Valuator(library: library).tradeFlowParts(of: "broker", on: "2024-03-31", previous: january)
        #expect(since == TradeFlowParts(recorded: 710, paidOutside: 210))
        let fromStart = Valuator(library: library).tradeFlowParts(of: "broker", on: "2024-01-31", previous: nil)
        #expect(fromStart == TradeFlowParts(recorded: 1_000, paidOutside: 0))

        // The coins' sale paid into the bank, and nothing for an account
        // that doesn't record trades.
        #expect(valuator.tradeFlowParts(of: "coins", on: "2024-03-31", previous: library.valuations(for: "coins").first)
            == TradeFlowParts(recorded: -680, paidOutside: -680))
        #expect(valuator.tradeFlowParts(of: "nowhere", on: "2024-03-31", previous: nil)
            == TradeFlowParts(recorded: 0, paidOutside: 0))
    }
}
