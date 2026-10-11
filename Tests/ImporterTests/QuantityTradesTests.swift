import Foundation
@testable import Importer
import Model
import Testing
import TestSupport
import Tracker

/// Quantities imported into an account that records trades become trades
/// (IMPORT.md, "Quantities in a trades account").
struct QuantityTradesTests {
    /// The small library, with Directa recording trades, as a brokerage account does by default.
    private func tradesLibrary() -> Library {
        var library = smallLibrary()
        library.accounts["directa"]?.valuation = nil
        return library
    }

    @Test func aSheetOfQuantitiesBecomesAnOpeningThenABuyPerChange() throws {
        let library = tradesLibrary()
        let session = try Samples.session("positions.csv")
        let preview = session.preview(against: library)
        #expect(preview.cellErrors.isEmpty)
        #expect(preview.issues == [
            ImportIssue(kind: .quantitiesAsTrades("directa", openings: 2, buys: 1, sales: 0, settledOutside: true)),
        ])
        #expect(preview.issues.map(\.description) == [
            "directa records trades, so its quantities became 2 openings and 1 buy: one per change in what it "
                + "holds, at the date's price unless the file gives the purchase cost. It has never held cash, so its "
                + "buys and sales are paid from and into another account.",
        ])
        // No valuations: the account's values hold no positions.
        #expect(!preview.records.contains { if case .valuation = $0.imported.key { true } else { false } })
        let trades = preview.records.compactMap(\.imported.trade)
        #expect(trades == [
            Trade(account: "directa", date: "2026-01-31", id: "opening-swda", type: .opening, instrument: "swda",
                  quantity: 50, cost: 4500, source: .import),
            Trade(account: "directa", date: "2026-01-31", id: "opening-vwce", type: .opening, instrument: "vwce",
                  quantity: 368, cost: 40200, source: .import),
            // The purchase cost rose by 1,300: what the buy paid. SWDA didn't change.
            Trade(account: "directa", date: "2026-02-28", id: "buy-vwce", type: .buy, instrument: "vwce",
                  quantity: 10, price: d("130.2"), currency: .eur, amount: -1300, source: .import,
                  settlement: .external),
        ])
        #expect(preview.record(.trade(TradeKey(account: "directa", date: "2026-02-28", id: "buy-vwce")))?.cells
            == [ImportCellRef(row: 4, column: 4), ImportCellRef(row: 4, column: 7)])
        #expect(preview.summary.description
            == "7 new, 0 updated, 0 identical, 0 conflicts; 3 trades among them; 1 new instrument")

        // The holdings that follow are the file's, with its purchase costs.
        let result = preview.apply(to: library)
        #expect(result.tradesWritten == 3)
        let valuator = Valuator(library: result.library)
        for (date, vwce, cost) in [("2026-01-31", 368, 40200), ("2026-02-28", 378, 41500)] {
            let snapshot = try #require(valuator.snapshot(of: "directa", on: CalendarDate(date)!))
            #expect(snapshot.positions == [
                Position(instrument: "swda", quantity: 50, costBasis: 4500),
                Position(instrument: "vwce", quantity: Decimal(vwce), costBasis: Decimal(cost)),
            ])
            #expect(snapshot.cash == 0)
        }
        #expect(valuator.reconcile(Valuation(account: "directa", date: "2026-02-28", positions: [
            Position(instrument: "swda", quantity: 50), Position(instrument: "vwce", quantity: 378),
        ])).isEmpty)

        // Importing again finds the same trades.
        let again = session.preview(against: result.library)
        #expect(again.records.allSatisfy { $0.status == .identical })
        #expect(!again.apply(to: result.library).hasChanges)
    }

    /// The trades are the ones Tracker's conversion makes for the same values held as snapshots.
    @Test func theTradesAreTheConversions() throws {
        let imported = try Samples.session("positions.csv").preview(against: tradesLibrary())
        var snapshots = smallLibrary()
        snapshots.instruments["swda"] = imported.newInstruments.first?.instrument
        for record in imported.records {
            if case .price = record.imported.key, case .price(let price) = record.incoming { snapshots.upsert(price) }
        }
        snapshots.upsert(Valuation(account: "directa", date: "2026-01-31", positions: [
            Position(instrument: "swda", quantity: 50, costBasis: 4500),
            Position(instrument: "vwce", quantity: 368, costBasis: 40200),
        ]))
        snapshots.upsert(Valuation(account: "directa", date: "2026-02-28", positions: [
            Position(instrument: "swda", quantity: 50, costBasis: 4500),
            Position(instrument: "vwce", quantity: 378, costBasis: 41500),
        ]))
        let conversion = try #require(snapshots.conversionToTrades(of: "directa"))
        let converted = conversion.trades.map { trade in
            var trade = trade
            trade.source = .import
            return trade
        }
        #expect(imported.records.compactMap(\.imported.trade) == converted)
    }

    @Test func changesFromTheHoldingsOfAnAccountWithCash() throws {
        var library = Library(
            accounts: [Account(id: "broker", name: "Broker", kind: .brokerage, currency: .eur, opened: "2026-01-01")],
            instruments: [Instrument(id: "etf", name: "ETF", kind: .etf, currency: .eur, unit: .share,
                                     assetClasses: .single(.equity))])
        library.upsert(Trade(account: "broker", date: "2026-01-05", id: "dep", type: .deposit, amount: 5000))
        library.upsert(Trade(account: "broker", date: "2026-01-10", id: "buy", type: .buy, instrument: "etf",
                             quantity: 10, price: 100, amount: -1000))
        library.upsert(PriceRecord(instrument: "etf", date: "2026-02-28", price: 100, currency: .eur))
        library.upsert(PriceRecord(instrument: "etf", date: "2026-03-15", price: 110, currency: .eur))
        var session = try ImportSession(data: Data("""
            Date;ETF;Cash
            2026-01-31;10;4000
            2026-02-28;14;3600
            2026-03-31;12;3820
            """.utf8))
        session.setMapping(ImportColumn(target: .quantity, account: "broker", instrument: "etf"), forColumn: 2)
        session.setMapping(ImportColumn(target: .cash, account: "broker"), forColumn: 3)
        let preview = session.preview(against: library)
        #expect(preview.issues.map(\.kind) == [
            .quantitiesAsTrades("broker", openings: 0, buys: 1, sales: 1, settledOutside: false),
        ])
        // January holds what the trades say: no trade. The cash stays a valuation's, which anchors it.
        #expect(preview.records.map(\.imported.key.description) == [
            "broker on 2026-01-31", "broker on 2026-02-28", "broker trade buy-etf on 2026-02-28",
            "broker on 2026-03-31", "broker trade sell-etf on 2026-03-31",
        ])
        #expect(preview.records.compactMap(\.imported.trade) == [
            Trade(account: "broker", date: "2026-02-28", id: "buy-etf", type: .buy, instrument: "etf", quantity: 4,
                  price: 100, currency: .eur, source: .import),
            // Priced at the latest price before the date.
            Trade(account: "broker", date: "2026-03-31", id: "sell-etf", type: .sell, instrument: "etf", quantity: 2,
                  price: 110, currency: .eur, source: .import),
        ])
        #expect(preview.record(.valuation("broker", "2026-02-28"))?.imported.cash == 3600)
        #expect(preview.record(.valuation("broker", "2026-02-28"))?.imported.positions == [])

        let result = preview.apply(to: library)
        let valuator = Valuator(library: result.library)
        #expect(result.library.heldQuantities(of: "broker", on: "2026-03-31") == ["etf": 12])
        #expect(valuator.snapshot(of: "broker", on: "2026-03-31")?.cash == 3820)
        #expect(valuator.holdings(of: "broker", on: "2026-02-28").map(\.quantity) == [14])
    }

    @Test func pricesAndCostsTheFileAndLibraryLackAreNoted() throws {
        var library = Library(accounts: [
            Account(id: "wallet", name: "Wallet", kind: .crypto, currency: .eur, opened: "2026-01-01"),
        ], instruments: [
            Instrument(id: "btc", name: "Bitcoin", kind: .crypto, currency: .usd, unit: "BTC",
                       assetClasses: .single(.crypto)),
        ])
        library.upsert(PriceRecord(instrument: "btc", date: "2026-02-28", price: 100_000, currency: .usd))
        library.upsert(FXRecord(base: .eur, quote: .usd, date: "2026-02-27", rate: d("1.25")))
        var session = try ImportSession(data: Data("Date;BTC\n2026-01-31;1\n2026-02-28;0.5\n".utf8))
        session.setMapping(ImportColumn(target: .quantity, account: "wallet", instrument: "btc"), forColumn: 2)
        var preview = session.preview(against: library)
        #expect(preview.issues.map(\.kind) == [
            .quantitiesAsTrades("wallet", openings: 1, buys: 0, sales: 1, settledOutside: true),
            .openingsWithoutCost("wallet", count: 1),
        ])
        #expect(preview.issues.last?.description
            == "wallet: 1 opening has no purchase cost and no price, so its cost is unknown.")
        #expect(preview.records.compactMap(\.imported.trade).map(\.cost) == [nil, nil])

        // With January's price, the opening costs its value then, in the account's currency.
        library.upsert(PriceRecord(instrument: "btc", date: "2026-01-31", price: 90_000, currency: .usd))
        library.upsert(FXRecord(base: .eur, quote: .usd, date: "2026-01-30", rate: d("1.2")))
        preview = session.preview(against: library)
        #expect(preview.records.compactMap(\.imported.trade).first?.cost == 75_000)

        // Without a price before the sale, its amount is unknown.
        var noPrices = library
        noPrices.months = noPrices.months.mapValues { month in
            var month = month
            month.prices = []
            return month
        }
        preview = session.preview(against: noPrices)
        #expect(preview.issues.map(\.description).contains(
            "wallet: 1 buy or sale has no price on or before its date and no purchase cost: import the prices "
            + "too, or add its amount."))
    }

    // MARK: - Decided together

    /// The example library with the Italian net worth sheet: the wallet's sale on January 31 is new, and its
    /// buy on March 31 a conflict with the library's.
    @Test func keepingAConflictKeepsAllOfTheAccountsLibraryTrades() throws {
        let library = try Fixtures.exampleLibrary()
        let profile = try #require(library.importProfiles["net-worth-sheet"])
        let preview = try ImportSession(data: Samples.data("italian-excel-1252.csv"), profile: profile)
            .preview(against: library)
        let sale = ImportRecordKey.trade(TradeKey(account: "ledger-wallet", date: "2026-01-31", id: "sell-btc"))
        let buy = ImportRecordKey.trade(TradeKey(account: "ledger-wallet", date: "2026-03-31", id: "buy-btc"))
        #expect(preview.record(sale)?.status == .new)
        #expect(preview.record(buy)?.status == .conflict)
        #expect(preview.records.filter(\.isFromQuantities).map(\.id) == [sale, buy])
        #expect(preview.conflicts(decidedWith: buy) == [buy])

        // Kept, or undecided: the new sale is left out too, and the wallet holds what the library says, not
        // 0.245 BTC, which neither says.
        for resolution in [ConflictPolicy.keep, .ask] {
            var kept = preview
            kept.resolveConflicts(resolution)
            #expect(kept.leftOutRecords == 1)
            let result = kept.apply(to: library)
            #expect(result.skipped == 1)
            #expect(result.library.trades(for: "ledger-wallet") == library.trades(for: "ledger-wallet"))
            #expect(result.library.heldQuantities(of: "ledger-wallet", on: "2026-03-31") == ["btc": d("0.4515")])
        }

        // Overwritten: all of the file's apply, and the wallet holds what the sheet says.
        var overwritten = preview
        overwritten.resolveConflicts(.overwrite)
        #expect(overwritten.leftOutRecords == 0)
        let result = overwritten.apply(to: library)
        #expect(result.library.trades(for: "ledger-wallet").map(\.id) == ["opening-btc", "sell-btc", "buy-btc"])
        for (date, quantity) in [("2026-01-31", "0.215"), ("2026-02-28", "0.215"), ("2026-03-31", "0.2201")] {
            #expect(result.library.heldQuantities(of: "ledger-wallet", on: CalendarDate(date)!) == ["btc": d(quantity)])
        }
    }

    /// The library's trades with the keys the import makes, on the file's dates, that the file no longer
    /// makes: a sale on January 31, when the wallet still holds its opening, and a buy on March 31, when it sold.
    @Test func acceptingRemovesTheLibrarysTradesTheFileNoLongerMakes() throws {
        var library = try Fixtures.exampleLibrary()
        library.upsert(Trade(account: "ledger-wallet", date: "2026-01-31", id: "sell-btc", type: .sell,
                             instrument: "btc", quantity: d("0.1"), price: 100_000, currency: .usd,
                             settlement: .external))
        var session = try ImportSession(data: Data("Date;BTC\n2026-01-31;0.4215\n2026-03-31;0.4\n".utf8))
        session.setMapping(ImportColumn(target: .quantity, account: "ledger-wallet", instrument: "btc"), forColumn: 2)
        let preview = session.preview(against: library)
        let januarySale = ImportRecordKey.trade(TradeKey(account: "ledger-wallet", date: "2026-01-31", id: "sell-btc"))
        let marchBuy = ImportRecordKey.trade(TradeKey(account: "ledger-wallet", date: "2026-03-31", id: "buy-btc"))
        #expect(preview.statuses == [
            "ledger-wallet trade sell-btc on 2026-01-31": .conflict,
            "ledger-wallet trade buy-btc on 2026-03-31": .conflict,
            "ledger-wallet trade sell-btc on 2026-03-31": .new,
        ])
        #expect(preview.records.filter(\.removesExisting).map(\.id) == [januarySale, marchBuy])
        #expect(preview.record(marchBuy)?.cells == [ImportCellRef(row: 3, column: 2)])
        #expect(preview.conflicts(decidedWith: marchBuy) == [januarySale, marchBuy])

        // One kept and one overwritten: all of the library's trades stay, and none of the file's are added.
        var mixed = preview
        for index in mixed.records.indices where mixed.records[index].status == .conflict {
            mixed.records[index].resolution = mixed.records[index].id == marchBuy ? .overwrite : .keep
        }
        var result = mixed.apply(to: library)
        #expect(result.library.trades(for: "ledger-wallet") == library.trades(for: "ledger-wallet"))
        #expect((result.kept, result.undecided, result.removed, result.skipped) == (2, 0, 0, 1))

        // Overwritten: the two are removed, and the wallet holds what the sheet says.
        var accepted = preview
        accepted.resolveConflicts(.overwrite)
        result = accepted.apply(to: library)
        #expect((result.added, result.removed) == (1, 2))
        #expect(result.changedMonths == ["2026-01", "2026-03"])
        #expect(result.library.trades(for: "ledger-wallet").map { "\($0.date) \($0.id)" }
            == ["2025-10-31 opening-btc", "2026-03-31 sell-btc"])
        #expect(result.library.heldQuantities(of: "ledger-wallet", on: "2026-01-31") == ["btc": d("0.4215")])
        #expect(result.library.heldQuantities(of: "ledger-wallet", on: "2026-03-31") == ["btc": d("0.4")])

        // Importing again changes nothing.
        let again = session.preview(against: result.library)
        #expect(again.records.allSatisfy { $0.status == .identical })
        #expect(!again.apply(to: result.library).hasChanges)
    }

    @Test func aCostWithoutAQuantityIsACellProblem() throws {
        var session = try ImportSession(data: Data("Date;VWCE cost\n2026-01-31;1000\n".utf8))
        session.setMapping(ImportColumn(target: .costBasis, account: "directa", instrument: "vwce"), forColumn: 2)
        let preview = session.preview(against: tradesLibrary())
        #expect(preview.cellErrors.map(\.problem) == [.costWithoutQuantity])
        #expect(preview.records.isEmpty)
    }

    // MARK: - New accounts

    /// A new account with quantities records trades, and its quantities are trades.
    @Test func aQuantityColumnProposesAnAccountThatRecordsTrades() throws {
        var library = Library()
        library.instruments["btc"] = Instrument(id: "btc", name: "Bitcoin", kind: .crypto, currency: .eur, unit: "BTC",
                                                assetClasses: .single(.crypto))
        var session = try ImportSession(data: Data("Date;BTC\n2026-01-31;0.5\n".utf8))
        session.setMapping(ImportColumn(target: .quantity, account: "kraken", instrument: "btc"), forColumn: 2)
        var preview = session.preview(against: library)
        let account = try #require(preview.newAccounts.first?.account)
        #expect(account.kind == .crypto)
        #expect(account.valuation == nil)
        #expect(account.recordsTrades)
        #expect(preview.records.compactMap(\.imported.trade).map(\.id) == ["opening-btc"])

        // Its kind edited to one that records a balance: it still records the trades the import makes.
        preview.newAccounts[0].account.kind = .other
        let result = preview.apply(to: library)
        #expect(result.library.accounts["kraken"]?.valuation == .trades)
        #expect(result.library.trades(for: "kraken").count == 1)
    }
}
