import Foundation
import Model
import Storage
import Testing
import TestSupport

/// Trades in the monthly history files: written in the canonical layout,
/// merged record by record like valuations, keeping unknown keys and
/// unreadable records, and checked when the library loads.
struct TradeStorageTests {
    private let october = "history/2026/2026-10.json"

    /// A made-up broker account whose holdings come from its trades.
    private func addBroker(to folder: TemporaryFolder) throws {
        try folder.write("accounts/broker.json", """
            {
              "currency": "EUR",
              "id": "broker",
              "kind": "brokerage",
              "name": "Broker",
              "opened": "2026-10-01",
              "valuation": "trades"
            }
            """)
    }

    private let deposit = Trade(account: "broker", date: "2026-10-02", id: "dep1abcd", type: .deposit, amount: 2000)
    private let buy = Trade(account: "broker", date: "2026-10-12", id: "buy1abcd", type: .buy, instrument: "vwce",
                            quantity: 10, price: .d("139.1"), fees: 5)

    @Test func tradesAreWrittenOnePerLineAndReadBack() throws {
        let folder = try TemporaryFolder.exampleLibrary()
        try addBroker(to: folder)
        let previous = try folder.library.load().library
        var library = previous
        library.upsert(buy)
        library.upsert(deposit)
        library.upsert(Valuation(account: "broker", date: "2026-10-31", cash: .d("604.0"), flow: 2000))
        try folder.library.save(library, previous: previous)

        #expect(try folder.text(october) == """
            {
              "fx": [],
              "indices": [],
              "month": "2026-10",
              "prices": [],
              "trades": [
                { "account": "broker", "amount": "2000", "date": "2026-10-02", "id": "dep1abcd", "type": "deposit" },
                {
                  "account": "broker",
                  "date": "2026-10-12",
                  "fees": "5",
                  "id": "buy1abcd",
                  "instrument": "vwce",
                  "price": "139.1",
                  "quantity": "10",
                  "type": "buy"
                }
              ],
              "valuations": [
                { "account": "broker", "cash": "604", "date": "2026-10-31", "flow": "2000" }
              ]
            }

            """)
        let loaded = try folder.library.load()
        #expect(loaded.library.trades(for: "broker") == [deposit, buy])
        #expect(loaded.report.issues(for: october).isEmpty)
        #expect(CanonicalJSON.isCanonical(try folder.data(october)))

        // Saving again with nothing changed writes nothing.
        #expect(try folder.library.save(loaded.library, previous: loaded.library).written.isEmpty)
    }

    @Test func unknownKeysInATradeFollowItByKey() throws {
        let folder = try TemporaryFolder.exampleLibrary()
        try addBroker(to: folder)
        try folder.write(october, """
            {
              "month": "2026-10",
              "trades": [
                { "account": "broker", "amount": "2000", "date": "2026-10-02", "id": "dep1abcd", "type": "deposit" },
                { "account": "broker", "date": "2026-10-12", "id": "buy1abcd", "instrument": "vwce", "orderRef": "A-17", "price": "139.1", "quantity": "10", "type": "buy" }
              ]
            }
            """)
        let previous = try folder.library.load().library
        var library = previous
        // A deposit earlier in the day sorts before the buy; the buy's fees are corrected.
        library.upsert(Trade(account: "broker", date: "2026-10-01", id: "dep0abcd", type: .deposit, amount: 1))
        var corrected = buy
        corrected.fees = 5
        library.upsert(corrected)
        try folder.library.save(library, previous: previous)

        let trades = try #require(folder.json(october)["trades"]?.arrayValue)
        #expect(trades.map { $0["id"] } == ["dep0abcd", "dep1abcd", "buy1abcd"])
        #expect(trades[2]["orderRef"] == "A-17")
        #expect(trades[2]["fees"] == "5")
    }

    @Test func aTradeTheModelCannotReadIsKeptOnRewrite() throws {
        let folder = try TemporaryFolder.exampleLibrary()
        try addBroker(to: folder)
        try folder.write(october, """
            {
              "month": "2026-10",
              "trades": [
                { "account": "broker", "amount": "2000", "date": "2026-10-02", "id": "dep1abcd", "type": "deposit" },
                { "account": "broker", "date": "2026-10-12", "id": "buy1abcd", "price": "139,1", "type": "buy" }
              ]
            }
            """)
        let result = try folder.library.load()
        #expect(result.report.errors.map(\.message) == [
            #"trades[1].price: Expected a decimal such as "1234.56", found "139,1". This record was skipped."#,
        ])
        #expect(result.library.trades(for: "broker") == [deposit])

        var library = result.library
        library.upsert(Valuation(account: "broker", date: "2026-10-31", cash: 2000))
        try folder.library.save(library, previous: result.library)
        let trades = try #require(folder.json(october)["trades"]?.arrayValue)
        #expect(trades.count == 2)
        #expect(trades.last?["price"] == "139,1")
    }

    @Test func tradesAddedOnDiskAndHereAreBothKept() throws {
        let folder = try TemporaryFolder.exampleLibrary()
        try addBroker(to: folder)
        var start = try folder.library.load().library
        start.upsert(deposit)
        try folder.library.save(start, previous: try folder.library.load().library)
        let previous = try folder.library.load().library

        // The other device records the buy; this one a second deposit on the same day as the first.
        var remote = previous
        remote.upsert(buy)
        try folder.write(october, CanonicalJSON.data(encoding: remote.months["2026-10"]!))

        var library = previous
        let second = Trade(account: "broker", date: "2026-10-02", id: "dep2abcd", type: .deposit, amount: 2000)
        library.upsert(second)
        let report = try folder.library.save(library, previous: previous)

        #expect(report.issues.isEmpty)
        #expect(try folder.library.load().library.trades(for: "broker") == [deposit, second, buy])
    }

    @Test func aTradeEditedOnBothSidesIsAConflictThatKeepsOurs() throws {
        let folder = try TemporaryFolder.exampleLibrary()
        try addBroker(to: folder)
        var start = try folder.library.load().library
        start.upsert(buy)
        try folder.library.save(start, previous: try folder.library.load().library)
        let previous = try folder.library.load().library

        var remote = previous
        var theirs = buy
        theirs.price = .d("139.2")
        remote.upsert(theirs)
        try folder.write(october, CanonicalJSON.data(encoding: remote.months["2026-10"]!))

        var library = previous
        var ours = buy
        ours.quantity = 11
        library.upsert(ours)
        let report = try folder.library.save(library, previous: previous)

        #expect(report.issues.map(\.records) == [["trades: 2026-10-12 broker buy1abcd"]])
        #expect(try folder.library.load().library.trade(buy.key) == ours)
    }

    @Test func syncConflictsMergeTradesByKey() throws {
        let earlier = Date(timeIntervalSince1970: 1_790_000_000)
        let later = Date(timeIntervalSince1970: 1_790_000_600)
        // Both devices recorded a deposit of 2,000 on the same day: two trades, not one.
        let phoneDeposit = Trade(account: "broker", date: "2026-10-02", id: "phone123", type: .deposit, amount: 2000)
        let macDeposit = Trade(account: "broker", date: "2026-10-02", id: "mac45678", type: .deposit, amount: 2000)
        var macBuy = buy
        macBuy.fees = 4
        let phone = MonthFile(month: "2026-10", trades: [phoneDeposit, buy])
        let mac = MonthFile(month: "2026-10", trades: [macDeposit, macBuy])

        let result = try ConflictResolver.merge([
            ConflictVersion(phone, modified: later, source: "iPhone"), ConflictVersion(mac, modified: earlier, source: "Mac"),
        ])
        #expect(result.value.trades == [buy, macDeposit, phoneDeposit].sortedByKey())
        #expect(result.recordsAdded == 1)
        #expect(result.conflictingRecords == ["trades: 2026-10-12 broker buy1abcd"])
    }

    @Test func threeWayMergeOfTradeLists() {
        let base = MonthFile(month: "2026-10", trades: [deposit, buy])
        var ours = base
        ours.trades[1].fees = 5
        var theirs = base
        theirs.trades.removeFirst()
        theirs.trades.append(Trade(account: "broker", date: "2026-10-20", id: "div1abcd", type: .dividend, amount: 3))
        let merged = RecordMerger.merge(base: base, ours: ours, theirs: theirs, month: "2026-10", rule: .ours)
        #expect(merged.conflicts.isEmpty)
        #expect(merged.value.trades.map(\.id) == ["buy1abcd", "div1abcd"])
        #expect(merged.value.trades[0].fees == 5)
    }

    @Test func loadingPointsOutTradesThatCannotBeAppliedAsTheyAre() throws {
        let folder = try TemporaryFolder.exampleLibrary()
        try addBroker(to: folder)
        try folder.write(october, """
            {
              "month": "2026-10",
              "trades": [
                { "account": "broker", "amount": "2000", "date": "2026-10-02", "id": "dep1abcd", "type": "deposit" },
                { "account": "broker", "date": "2026-10-12", "id": "buy1abcd", "instrument": "vwce", "quantity": "10", "type": "buy" },
                { "account": "broker", "amount": "700", "date": "2026-10-20", "id": "sel1abcd", "instrument": "vwce", "quantity": "15", "type": "sell" },
                { "account": "tfr", "amount": "10", "date": "2026-10-21", "id": "int1abcd", "type": "interest" }
              ],
              "valuations": [
                { "account": "broker", "balance": "1500", "date": "2026-10-31" }
              ]
            }
            """)
        let result = try folder.library.load()
        #expect(result.report.errors.isEmpty)
        #expect(result.report.issues(for: october).map(\.message) == [
            "The buy of vwce in broker on 2026-10-12 (buy1abcd): A buy needs a price or an amount.",
            "The sell of vwce in broker on 2026-10-20 (sel1abcd) takes away 5 more than the account held then (10). "
                + "Is a buy or an opening missing, or the date wrong?",
            "tfr records balance, not trades, so its trades here are left out of its values. Set \"valuation\": "
                + "\"trades\" on the account to use them.",
            "The valuation of broker on 2026-10-31 has a balance, but the account's holdings come from its trades: "
                + "record its cash instead. The balance isn't used.",
        ])
        // Nothing was dropped.
        #expect(result.library.months["2026-10"]?.trades.count == 4)
    }

    @Test func tradesBeforeTheAccountOpenedOrOfUnknownAccountsArePointedOut() throws {
        let folder = try TemporaryFolder.exampleLibrary()
        try addBroker(to: folder)
        try folder.write("history/2026/2026-09.json", try folder.text("history/2026/2026-09.json")
            .replacingOccurrences(of: "  \"valuations\": [\n", with: """
                  "trades": [
                    { "account": "broker", "amount": "5", "date": "2026-09-30", "id": "early123", "type": "deposit" },
                    { "account": "nobody", "amount": "5", "date": "2026-09-30", "id": "who12345", "type": "deposit" },
                    { "account": "broker", "date": "2026-09-30", "id": "ghost123", "instrument": "ghost", "quantity": "1", "type": "opening" }
                  ],
                  "valuations": [

                """))
        let messages = try folder.library.load().report.issues(for: "history/2026/2026-09.json").map(\.message)
        #expect(messages.contains("Refers to accounts that don't exist: nobody."))
        #expect(messages.contains("Refers to instruments that don't exist: ghost."))
        #expect(messages.contains("The deposit in broker on 2026-09-30 (early123) is dated before the account opened (2026-10-01)."))
    }
}
