import Foundation
import Model
import Testing
import TestSupport
import Tracker

/// A made-up library with a broker account that records trades, in two
/// styles: every deposit recorded (A), or cash typed at month-end check-ins
/// with deposits left out (B).
enum TradeLibrary {
    static let base = Library(
        settings: LibrarySettings(baseCurrency: .eur),
        accounts: [
            Account(id: "broker", name: "Broker", kind: .brokerage, currency: .eur, opened: "2024-01-01",
                    valuation: .trades),
            Account(id: "bank", name: "Bank", kind: .cash, currency: .eur, opened: "2024-01-01"),
        ],
        instruments: [
            Instrument(id: "vwce", name: "VWCE", kind: .etf, currency: .eur, unit: .share,
                       assetClasses: .single(.equity)),
            Instrument(id: "aapl", name: "Apple", kind: .stock, currency: .usd, unit: .share,
                       assetClasses: .single(.equity)),
        ])

    static func trade(_ type: TradeType, _ date: CalendarDate, id: TradeID, instrument: InstrumentID? = nil,
                      quantity: String? = nil, price: String? = nil, amount: String? = nil, fees: String? = nil,
                      tax: String? = nil, cost: String? = nil) -> Trade {
        Trade(account: "broker", date: date, id: id, type: type, instrument: instrument, quantity: quantity.map(d),
              price: price.map(d), amount: amount.map(d), fees: fees.map(d), tax: tax.map(d), cost: cost.map(d))
    }

    /// Every trade but the opening deposit.
    static let trades = [
        trade(.buy, "2024-01-05", id: "buy1", instrument: "vwce", quantity: "50", price: "100", fees: "5"),
        trade(.dividend, "2024-02-15", id: "div1", instrument: "vwce", amount: "20", tax: "5"),
        trade(.buy, "2024-03-01", id: "buy2", instrument: "aapl", quantity: "10", price: "150", fees: "1"),
        trade(.transferIn, "2024-03-10", id: "tin1", instrument: "vwce", quantity: "10", cost: "900"),
        trade(.sell, "2024-03-20", id: "sel1", instrument: "vwce", quantity: "20", price: "108", fees: "5", tax: "10"),
        trade(.withdrawal, "2024-03-25", id: "wd1", amount: "-500"),
    ]

    static func withMarketData(_ library: Library) -> Library {
        var library = library
        for (date, price) in [("2024-01-05", "100"), ("2024-01-31", "102"), ("2024-02-29", "105"), ("2024-03-31", "110")] {
            library.upsert(PriceRecord(instrument: "vwce", date: CalendarDate(date)!, price: d(price), currency: .eur))
        }
        for (date, price) in [("2024-03-01", "150"), ("2024-03-31", "160")] {
            library.upsert(PriceRecord(instrument: "aapl", date: CalendarDate(date)!, price: d(price), currency: .usd))
        }
        for (date, rate) in [("2024-01-31", "1.1"), ("2024-03-01", "1.1"), ("2024-03-31", "1.2")] {
            library.upsert(FXRecord(base: .eur, quote: .usd, date: CalendarDate(date)!, rate: d(rate)))
        }
        return library
    }

    /// Style A: the deposit is recorded, and there are no valuations.
    static func recordedDeposits() -> Library {
        var library = withMarketData(base)
        library.upsert(trade(.deposit, "2024-01-02", id: "dep1", amount: "10000"))
        for trade in trades { library.upsert(trade) }
        return library
    }

    /// Style B: no deposit recorded; cash typed at each month end.
    static func typedCash() -> Library {
        var library = withMarketData(base)
        for trade in trades { library.upsert(trade) }
        library.upsert(Valuation(account: "broker", date: "2024-01-31", cash: 5000, flow: 10005))
        library.upsert(Valuation(account: "broker", date: "2024-02-29", cash: 5020, flow: 0))
        library.upsert(Valuation(account: "broker", date: "2024-03-31", cash: d("5300.36"), flow: 550))
        return library
    }

    /// The value of 10 AAPL on 2024-03-31 in euros: 1,600 USD at 1.2.
    static let apple = d("1600") / d("1.2")
}

struct TradeValuationTests {
    @Test func holdingsComeFromTheTradesAndCashFromEveryDeposit() throws {
        let valuator = Valuator(library: TradeLibrary.recordedDeposits())
        #expect(valuator.value(of: "broker", on: "2024-01-01")?.status == .noValuation)
        #expect(valuator.snapshot(of: "broker", on: "2024-01-01") == nil)

        let january = try #require(valuator.value(of: "broker", on: "2024-01-31"))
        #expect(january.value == 10095)
        #expect(january.valuation == Valuation(account: "broker", date: "2024-01-05", cash: 4995,
                                               positions: [Position(instrument: "vwce", quantity: 50, costBasis: 5005)]))
        #expect(valuator.tradeCash(of: "broker", on: "2024-02-29") == 5015)
        #expect(valuator.value(of: "broker", on: "2024-02-29")?.value == 10265)

        let march = try #require(valuator.value(of: "broker", on: "2024-03-31"))
        #expect(march.isComplete)
        #expect(march.value?.rounded(20) == (4400 + TradeLibrary.apple + d("5295.36")).rounded(20))
        #expect(march.components.map(\.kind) == [.cash, .position("aapl"), .position("vwce")])
        #expect(valuator.snapshot(of: "broker", on: "2024-03-31")?.positions == [
            Position(instrument: "aapl", quantity: 10, costBasis: d("1364.64")),
            Position(instrument: "vwce", quantity: 40, costBasis: d("3936.67")),
        ])
        // The account detail's holdings, with cost and gain.
        let holdings = valuator.holdings(of: "broker", on: "2024-03-31")
        #expect(holdings.map(\.instrument) == ["aapl", "vwce"])
        #expect(holdings[1].unrealizedGain == d("463.33"))
        // Net worth and breakdowns include the derived positions.
        #expect(valuator.netWorth(on: "2024-03-31").total == march.knownValue)
        let breakdown = valuator.breakdown(by: .assetClass, on: "2024-03-31")
        #expect(breakdown.value(of: .assetClass(.equity)) == 4400 + TradeLibrary.apple)
        #expect(breakdown.value(of: .assetClass(.cash)) == d("5295.36"))
    }

    @Test func typedCashAnchorsTheCashAndTradesCarryItForward() throws {
        let valuator = Valuator(library: TradeLibrary.typedCash())
        #expect(valuator.tradeCash(of: "broker", on: "2024-01-20") == -5005)
        #expect(valuator.tradeCash(of: "broker", on: "2024-01-31") == 5000)
        #expect(valuator.tradeCash(of: "broker", on: "2024-03-15") == d("3655.36"))
        #expect(valuator.tradeCash(of: "broker", on: "2024-03-31") == d("5300.36"))
        #expect(valuator.tradeCash(of: "bank", on: "2024-03-31") == nil)
        #expect(valuator.value(of: "broker", on: "2024-03-31")?.value?.rounded(20) == (4400 + TradeLibrary.apple + d("5300.36")).rounded(20))
        // A valuation without cash doesn't anchor it.
        var library = TradeLibrary.typedCash()
        library.upsert(Valuation(account: "broker", date: "2024-03-15", note: "statement received"))
        #expect(Valuator(library: library).tradeCash(of: "broker", on: "2024-03-15") == d("3655.36"))
    }

    @Test func flowsAreDepositsWithdrawalsTransfersAndResiduals() throws {
        let recorded = Valuator(library: TradeLibrary.recordedDeposits())
        let flows = recorded.tradeFlows(of: "broker", after: nil, through: "2024-03-31")
        #expect(flows.map(\.date) == ["2024-01-02", "2024-03-10", "2024-03-25"])
        // The transfer in counts at its market value on its date (February's 105), not its cost.
        #expect(flows.map(\.amount) == [10000, 1050, -500])
        #expect(recorded.tradeFlows(of: "broker", after: "2024-01-31", through: "2024-03-31").map(\.amount)
            == [1050, -500])

        let typed = Valuator(library: TradeLibrary.typedCash())
        let residuals = typed.tradeFlows(of: "broker", after: nil, through: "2024-03-31")
        #expect(residuals.map(\.date) == ["2024-01-31", "2024-03-10", "2024-03-25"])
        // The cash typed on 31 January is 10,005 more than the trades give: an unrecorded deposit.
        #expect(residuals[0].trade == nil)
        #expect(residuals[0].amount == 10005)
        #expect(residuals[0].since == "2024-01-01")
        #expect(typed.tradeFlows(of: "bank", after: nil, through: "2024-03-31").isEmpty)

        // The check-in's default flow is the same thing, since the previous valuation.
        let library = TradeLibrary.typedCash()
        let valuations = library.valuations(for: "broker")
        #expect(typed.defaultFlow(for: valuations[0], previous: nil) == 10005)
        #expect(typed.defaultFlow(for: valuations[1], previous: valuations[0]) == 0)
        #expect(typed.defaultFlow(for: valuations[2], previous: valuations[1]) == 550)
        // Typed cash that's 12.5 more than the trades give adds a residual.
        var more = valuations[2]
        more.cash = d("5312.86")
        #expect(typed.defaultFlow(for: more, previous: valuations[1]) == d("562.5"))
    }

    @Test func theChangeSplitsMarketFromNewMoney() throws {
        let valuator = Valuator(library: TradeLibrary.recordedDeposits())
        let change = try #require(valuator.change(of: "broker", from: "2024-01-31", to: "2024-03-31"))
        #expect(change.flow == 550)
        #expect(change.change.start == 10095)
        #expect(change.change.newMoney == 550)
        // The dividend, the gain on the sale and the price moves are market.
        #expect(change.change.market.rounded(20) == (4400 + TradeLibrary.apple + d("5295.36") - 10095 - 550).rounded(20))
        #expect(change.change.other == 0)
    }

    @Test func aTradesAccountStartsAtItsFirstTradeAndIsStaleByItsLatestRecord() {
        let valuator = Valuator(library: TradeLibrary.recordedDeposits())
        #expect(valuator.firstValuationDate() == "2024-01-02")
        #expect(valuator.firstRecordDate(of: "broker") == "2024-01-02")
        #expect(valuator.series(of: "broker", through: "2024-02-29").map(\.value) == [10095, 10265])
        #expect(valuator.staleness(of: "broker", on: "2024-04-30") == nil)
        #expect(valuator.staleness(of: "broker", on: "2024-05-31")?.lastValuation == "2024-03-25")
        #expect(valuator.dateRange(of: .sinceStart, for: .account("broker"), asOf: "2024-03-31")
            == "2024-01-02"..."2024-03-31")
    }

    @Test func aMissingRateLeavesTheCashIncomplete() throws {
        var library = TradeLibrary.recordedDeposits()
        library.upsert(TradeLibrary.trade(.buy, "2024-01-20", id: "early", instrument: "aapl", quantity: "1",
                                          price: "140"))
        let valuator = Valuator(library: library)
        let value = try #require(valuator.value(of: "broker", on: "2024-01-20"))
        #expect(value.problems.contains(.missingFX(account: "broker", from: .usd, to: .eur)))
        #expect(!value.isComplete)
        #expect(valuator.tradeIssues(for: "broker").map(\.kind) == [.missingFX])
    }

    @Test func listedPositionsAreAReconciliationCheck() throws {
        var library = TradeLibrary.typedCash()
        library.upsert(Valuation(account: "broker", date: "2024-03-31", cash: d("5300.36"), positions: [
            Position(instrument: "aapl", quantity: 9), Position(instrument: "vwce", quantity: 40, costBasis: 3900),
        ], flow: 550))
        let valuator = Valuator(library: library)
        // The value comes from the trades, whatever the valuation lists.
        #expect(valuator.value(of: "broker", on: "2024-03-31")?.value?.rounded(20) == (4400 + TradeLibrary.apple + d("5300.36")).rounded(20))
        let mismatches = valuator.reconciliation(of: "broker")
        #expect(mismatches == [PositionMismatch(account: "broker", date: "2024-03-31", instrument: "aapl", listed: 9,
                                                derived: 10)])
        #expect(mismatches[0].difference == -1)
        #expect(mismatches[0].description
            == "The valuation on 2024-03-31 lists 9 aapl, but the trades give 10. Is a trade missing or wrong?")
        #expect(valuator.tradeIssues(for: "broker").map(\.kind) == [.reconciliation])
        // A check-in's positions can be checked before saving.
        #expect(valuator.reconcile(Valuation(account: "broker", date: "2024-03-31", positions: [
            Position(instrument: "aapl", quantity: 10), Position(instrument: "vwce", quantity: 40),
        ])).isEmpty)
    }

    @Test func balancesAndTradesOfOtherAccountsAreLeftOutAndReported() throws {
        var library = TradeLibrary.recordedDeposits()
        library.upsert(Valuation(account: "broker", date: "2024-03-31", balance: 99999))
        library.upsert(Valuation(account: "bank", date: "2024-03-31", balance: 100))
        library.upsert(Trade(account: "bank", date: "2024-03-02", id: "x", type: .deposit, amount: 5))
        library.upsert(TradeLibrary.trade(.deposit, "2023-12-31", id: "early", amount: "1"))
        let valuator = Valuator(library: library)
        #expect(valuator.value(of: "broker", on: "2024-03-31")?.value?.rounded(20) == (4400 + TradeLibrary.apple + d("5296.36")).rounded(20))
        #expect(valuator.value(of: "bank", on: "2024-03-31")?.value == 100)
        #expect(valuator.ledger(for: "bank") == nil)
        #expect(valuator.tradeIssues().map(\.kind) == [.outsideAccountDates, .notTradesAccount, .balanceIgnored])
        #expect(valuator.tradeIssues(for: "bank").first?.message
            == "The deposit on 2024-03-02 (x) is left out: bank records balance, not trades.")
    }

    @Test func aYearOfTradesInTheBaseCurrency() {
        let summary = Valuator(library: TradeLibrary.recordedDeposits()).tradeSummary(for: 2024)
        #expect(summary.currency == .eur)
        #expect(summary.realizedGain == d("186.67"))
        #expect(summary.realizedGainByInstrument == ["vwce": d("186.67")])
        #expect(summary.dividends == 25)
        #expect(summary.taxes == 15)
        #expect(summary.fees == 11)
        #expect(summary.deposits == 10000)
        #expect(summary.withdrawals == 500)
        #expect(summary.unconverted.isEmpty)
    }

    @Test func editingTradesKeepsAutomaticFlowsInStep() throws {
        var library = TradeLibrary.typedCash()
        let before = library
        // Units moved in on 10 February: February's flow becomes their market value.
        library.upsert(TradeLibrary.trade(.transferIn, "2024-02-10", id: "tin0", instrument: "vwce", quantity: "5",
                                          cost: "450"))
        let followUp = library.followFlows(from: before)
        #expect(followUp.recomputed.map(\.date) == ["2024-02-29"])
        #expect(followUp.recomputed.first?.flow == 510)
        #expect(followUp.kept.isEmpty)

        // A flow typed by hand is kept.
        var typed = TradeLibrary.typedCash()
        typed.upsert(Valuation(account: "broker", date: "2024-02-29", cash: 5020, flow: 7))
        let typedBefore = typed
        typed.upsert(TradeLibrary.trade(.transferIn, "2024-02-10", id: "tin0", instrument: "vwce", quantity: "5",
                                        cost: "450"))
        let kept = typed.followFlows(from: typedBefore)
        #expect(kept.recomputed.isEmpty)
        #expect(kept.kept.map(\.date) == ["2024-02-29"])
    }
}
