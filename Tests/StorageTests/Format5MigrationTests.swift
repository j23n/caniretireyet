import Foundation
import Model
@testable import Storage
import Testing
import TestSupport

/// The upgrade from format version 4 to 5 (docs/schema/README.md,
/// "Versioning"), on small made-up libraries.
struct Format5MigrationTests {
    private let date = Date(timeIntervalSince1970: 1_790_000_000)  // 2026-09-21

    /// Runs the step on `files`, given as text by path.
    private func upgrade(_ files: [String: String]) throws -> (files: [String: JSONValue], notes: [String]) {
        var json = try files.mapValues { try CanonicalJSON.parse(Data($0.utf8)) }
        let notes = try Migration.format5.apply(&json)
        return (json, notes)
    }

    private static let accounts = [
        "accounts/bank.json": #"{ "currency": "EUR", "id": "bank", "kind": "cash", "name": "Bank", "opened": "2026-01-01" }"#,
        "accounts/deposit.json":
            #"{ "currency": "EUR", "id": "deposit", "kind": "savings", "name": "Deposit", "opened": "2026-01-01" }"#,
        "accounts/car.json": #"{ "currency": "EUR", "id": "car", "kind": "vehicle", "name": "Car", "opened": "2026-01-01" }"#,
        "accounts/pension.json":
            #"{ "currency": "EUR", "id": "pension", "kind": "pensionFund", "name": "Pension", "opened": "2026-01-01" }"#,
        "accounts/broker.json":
            #"{ "currency": "EUR", "id": "broker", "kind": "brokerage", "name": "Broker", "opened": "2026-01-01" }"#,
    ]

    private static let history = [
        "history/2026/2026-01.json": """
            { "month": "2026-01", "valuations": [
              { "account": "bank", "balance": "1000", "date": "2026-01-31" },
              { "account": "car", "balance": "9000", "date": "2026-01-31", "flow": "9000" },
              { "account": "deposit", "balance": "5000", "date": "2026-01-31" },
              { "account": "pension", "balance": "100", "date": "2026-01-31" }
            ] }
            """,
        "history/2026/2026-02.json": """
            { "month": "2026-02", "valuations": [
              { "account": "bank", "balance": "1200", "date": "2026-02-28", "flow": "200", "moneyIn": "900", "moneyOut": "700" },
              { "account": "broker", "cash": "50", "date": "2026-02-28", "flow": "50" },
              { "account": "car", "balance": "8500", "date": "2026-02-28", "flow": "-400" },
              { "account": "deposit", "balance": "5040", "date": "2026-02-28", "flow": "0" },
              { "account": "pension", "balance": "300", "date": "2026-02-28", "flow": "150" }
            ] }
            """,
    ]

    @Test func kindsAndStatementClassesAreRenamed() throws {
        let (files, _) = try upgrade(Self.accounts.merging([
            "imports/bank.json": """
                { "id": "bank", "layout": "statement", "name": "Bank",
                  "rules": [{ "class": "paidBack", "match": "Rimborso" }, { "class": "income", "match": "Stipendio" }],
                  "answers": [{ "amount": "-12", "class": "paidBack", "date": "2026-02-03", "match": "Storno" }] }
                """,
        ]) { $1 })
        #expect(files["accounts/car.json"]?["kind"] == "belongings")
        #expect(files["accounts/bank.json"]?["kind"] == "cash")
        let profile = try #require(files["imports/bank.json"])
        #expect(profile["rules"]?.arrayValue?.map { $0["class"] } == ["spending", "income"])
        #expect(profile["answers"]?[0]?["class"] == "spending")
    }

    @Test func aReturnGivenBothWaysKeepsItsMedian() throws {
        let returns = """
            "returns": {
              "crypto": { "medianReal": "0", "real": "0.16629", "volatility": "0.7" },
              "equity": { "real": "0.045", "volatility": "0.17" }
            }
            """
        let (files, _) = try upgrade([
            "plans/base.json": #"{ "id": "base", "assumptions": { "#  + returns + " } }",
            "projections/base/baselines/2026-01-05.json": #"{ "plan": { "assumptions": { "# + returns + " } } }",
        ])
        let median: JSONValue = ["medianReal": "0", "volatility": "0.7"]
        let mean: JSONValue = ["real": "0.045", "volatility": "0.17"]
        let plan = files["plans/base.json"]?["assumptions"]?["returns"]
        #expect(plan?["crypto"] == median && plan?["equity"] == mean)
        let baseline = files["projections/base/baselines/2026-01-05.json"]?["plan"]?["assumptions"]?["returns"]
        #expect(baseline?["crypto"] == median && baseline?["equity"] == mean)
    }

    /// Flows stay only on the pension fund, which asks for one. The savings
    /// value's typed flow left its interest out, so it gets that interest;
    /// the car's flow wasn't its change, which a note says.
    @Test func flowsStayOnlyWhereTheyreAskedFor() throws {
        let (files, notes) = try upgrade(Self.accounts.merging(Self.history) { $1 })
        let february = try #require(files["history/2026/2026-02.json"]?["valuations"]?.arrayValue)
        let byAccount = Dictionary(uniqueKeysWithValues: february.map { ($0["account"]?.stringValue ?? "", $0) })
        #expect(byAccount["bank"] == ["account": "bank", "balance": "1200", "date": "2026-02-28", "moneyIn": "900",
                                      "moneyOut": "700"])
        #expect(byAccount["broker"]?["flow"] == nil)
        #expect(byAccount["car"]?["flow"] == nil)
        #expect(byAccount["deposit"] == ["account": "deposit", "balance": "5040", "date": "2026-02-28",
                                         "interest": "40"])
        #expect(byAccount["pension"]?["flow"] == "150")
        let january = try #require(files["history/2026/2026-01.json"]?["valuations"]?.arrayValue)
        #expect(january.allSatisfy { $0["flow"] == nil })
        #expect(notes == ["Car: what 1 value saved wasn't the change in balance; it's now worked out from the "
            + "balances."])
    }

    @Test func cryptoIsPricedFromYahoo() throws {
        let (files, notes) = try upgrade([
            "instruments/btc.json": """
                { "currency": "EUR", "id": "btc", "kind": "crypto", "name": "Bitcoin", "unit": "BTC",
                  "priceSource": { "provider": "coingecko", "symbol": "bitcoin" } }
                """,
            "instruments/eth.json": """
                { "currency": "USD", "id": "eth", "kind": "crypto", "name": "Ether", "unit": "share",
                  "priceSource": { "provider": "coingecko", "symbol": "ETH" } }
                """,
            "instruments/odd.json": """
                { "currency": "EUR", "id": "odd", "kind": "crypto", "name": "Odd coin", "unit": "share",
                  "priceSource": { "provider": "coingecko", "symbol": "odd-coin" } }
                """,
            "instruments/gold.json": """
                { "currency": "EUR", "id": "gold", "kind": "metal", "name": "Gold", "unit": "g",
                  "priceSource": { "provider": "gold-api", "symbol": "XAU" } }
                """,
        ])
        #expect(files["instruments/btc.json"]?["priceSource"] == ["provider": "yahoo", "symbol": "BTC-EUR"])
        #expect(files["instruments/eth.json"]?["priceSource"] == ["provider": "yahoo", "symbol": "ETH-USD"])
        #expect(files["instruments/odd.json"]?["priceSource"] == nil)
        #expect(files["instruments/odd.json"]?["name"] == "Odd coin")
        #expect(files["instruments/gold.json"]?["priceSource"] == ["provider": "gold-api", "symbol": "XAU"])
        #expect(notes.count == 1 && notes.first?.hasPrefix("Odd coin was priced from CoinGecko") == true)
    }

    /// A version-4 library is upgraded after a backup and then loads at
    /// version 5; upgrading again does nothing.
    @Test func aVersion4LibraryIsUpgradedAfterABackup() throws {
        let folder = try TemporaryFolder()
        let original = Self.accounts.merging(Self.history) { $1 }
            .merging(["library.json": #"{ "baseCurrency": "EUR", "schemaVersion": 4 }"#]) { $1 }
        for (path, text) in original { try folder.write(path, text) }
        #expect(try folder.library.load().report.needsMigration)

        let report = try #require(try folder.library.migrate(date: date))
        #expect(report.fromVersion == 4 && report.toVersion == 5)
        #expect(report.steps == [Migration.format5.summary])
        let day = CalendarDate(date, in: .current)
        #expect(report.backup.name == "\(day)-v4")
        for (path, text) in original {
            #expect(try folder.text("backups/\(day)-v4/\(path)") == text)
        }

        let loaded = try folder.library.load()
        #expect(loaded.report.errors.isEmpty)
        #expect(!loaded.report.needsMigration)
        #expect(loaded.library.settings.schemaVersion == 5)
        #expect(loaded.library.accounts["car"]?.kind == .belongings)
        #expect(loaded.library.valuations(for: "pension").map(\.flow) == [nil, 150])
        #expect(loaded.library.valuations(for: "bank").map(\.flow) == [nil, nil])
        #expect(try folder.library.migrate(date: date) == nil)
    }
}
