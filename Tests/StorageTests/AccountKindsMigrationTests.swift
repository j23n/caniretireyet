import Foundation
import Model
import Storage
import Testing
import TestSupport
import Tracker

/// The upgrade to format version 4: each account kind records its money one
/// way (docs/ACCOUNTS.md, "Migration").
struct AccountKindsMigrationTests {
    private let date = Date(timeIntervalSince1970: 1_790_000_000)  // 2026-09-21

    /// Storage's step, then the conversion the app and the command line add.
    private let steps = Migration.all + [
        Migration.library(from: 3, summary: Library.snapshotConversionSummary) { library in
            library.convertSnapshotAccountsToTrades()
        },
    ]

    @Test func eachAccountRecordsWhatItsKindDoes() throws {
        let folder = try TemporaryFolder.version3Library()
        let report = try #require(try folder.library.migrate(steps: steps, date: date))
        #expect(report.fromVersion == 3)
        #expect(report.toVersion == 4)
        #expect(report.steps == steps.map(\.summary))
        #expect(try folder.json("library.json")["schemaVersion"] == 4)

        // Money in and out is no longer an opt-in.
        #expect(try folder.json("accounts/bank.json")["moneyInOut"] == nil)
        // Snapshots with positions: converted to trades, the kind's default now.
        #expect(try folder.json("accounts/broker.json")["valuation"] == nil)
        #expect(try folder.json("accounts/broker.json")["myNote"] == "kept")
        // Snapshots with no values: trades, the kind's default now.
        #expect(try folder.json("accounts/new-broker.json")["valuation"] == nil)
        // Investment accounts recorded as a balance become other accounts.
        #expect(try folder.json("accounts/exchange.json")["kind"] == "other")
        #expect(try folder.json("accounts/exchange.json")["valuation"] == nil)
        #expect(try folder.json("accounts/wallet.json")["kind"] == "other")
        #expect(try folder.json("accounts/wallet.json")["valuation"] == nil)
        // Other kinds recorded as snapshots of balances record a balance.
        #expect(try folder.json("accounts/fund.json")["valuation"] == "balance")

        let result = try folder.library.load()
        #expect(result.report.issues.isEmpty)
        let library = result.library
        #expect(library.accounts.mapValues(\.valuationMode) == [
            "bank": .balance, "broker": .trades, "new-broker": .trades, "exchange": .balance, "wallet": .balance,
            "fund": .balance,
        ])
        #expect(library.allTrades.map(\.id) == ["opening-vwce", "buy-vwce"])
        #expect(library.valuations(for: "broker").map(\.positions) == [[], []])
        // The broker's first positions had no purchase cost, so the conversion estimated
        // it, and the buy's price.
        #expect(report.notes == [
            "Broker: 2026-01-31: The opening of 10 vwce has no recorded cost: it's their value then, 1000.",
            "Broker: 2026-02-28: The buy of 5 vwce is priced at the valuation's price.",
        ])
    }

    @Test func valuesAndNewMoneyStayTheSame() throws {
        let folder = try TemporaryFolder.version3Library()
        var before = try folder.library.load().library
        // Version 3's default for brokerage and crypto accounts.
        for id: AccountID in ["broker", "new-broker", "wallet"] { before.accounts[id]?.valuation = .holdings }
        try folder.library.migrate(steps: steps, date: date)
        let after = try folder.library.load().library

        let dates: [CalendarDate] = ["2026-01-31", "2026-02-15", "2026-02-28"]
        for id in before.accounts.keys {
            for day in dates {
                #expect(Valuator(library: after).value(of: id, on: day)?.value
                    == Valuator(library: before).value(of: id, on: day)?.value, "\(id) on \(day)")
            }
        }
        func split(_ library: Library) -> [AccountID: [Decimal]] {
            let report = Valuator(library: library).change(from: "2026-01-31", to: "2026-02-28")
            return Dictionary(uniqueKeysWithValues: report.accounts.map {
                ($0.account, [$0.change.market, $0.change.newMoney, $0.change.other])
            })
        }
        #expect(split(after) == split(before))
        #expect(split(after)["broker"]?[1] == 520)
        // Values without a flow keep the whole change as new money, as version 3 filled it in.
        #expect(split(after)["exchange"] == [0, 50, 0])
        #expect(split(after)["wallet"] == [d("0.004"), 10, 0])
        // Rounded to cents, as version 3 filled it in.
        #expect(after.valuations(for: "wallet").map(\.flow) == [nil, 10])
    }

    @Test func aBackupIsTakenFirst() throws {
        let folder = try TemporaryFolder.version3Library()
        let original = try folder.text("accounts/bank.json")
        let report = try #require(try folder.library.migrate(steps: steps, date: date))
        let day = CalendarDate(date, in: .current)
        #expect(report.backup.name == "\(day)-v3")
        #expect(try folder.text("backups/\(day)-v3/accounts/bank.json") == original)
    }

    @Test func nothingIsWrittenWhenAStepFails() throws {
        struct Failure: Error {}
        let folder = try TemporaryFolder.version3Library()
        let files = try folder.allFiles()
        let failing = Migration.library(from: 3, summary: "Fails") { _ in throw Failure() }
        #expect(throws: Failure.self) { try folder.library.migrate(steps: Migration.all + [failing], date: date) }
        #expect(try folder.allFiles() == files)
        #expect(try folder.json("accounts/bank.json")["moneyInOut"] == true)
        #expect(try folder.json("library.json")["schemaVersion"] == 3)
    }

    /// Without the conversion, Storage's step alone keeps the snapshot
    /// accounts with positions recorded as snapshots, so their values still
    /// count, and loading points them out.
    @Test func storagesStepAloneKeepsSnapshotsWithPositions() throws {
        let folder = try TemporaryFolder.version3Library()
        let report = try #require(try folder.library.migrate(date: date))
        #expect(report.notes.isEmpty)
        #expect(try folder.json("accounts/broker.json")["valuation"] == "holdings")
        let result = try folder.library.load()
        #expect(result.report.warnings.map(\.path) == ["accounts/broker.json"])
        #expect(Valuator(library: result.library).value(of: "broker", on: "2026-02-28")?.value == 1670)
    }

    @Test func loadingPointsOutInterestOnOtherKinds() throws {
        let folder = try TemporaryFolder.version3Library()
        try folder.library.migrate(steps: steps, date: date)
        let month = try folder.text("history/2026/2026-02.json")
        try folder.write("history/2026/2026-02.json", month.replacingOccurrences(
            of: #""balance": "1200","#, with: #""balance": "1200", "interest": "1","#))
        let warnings = try folder.library.load().report.warnings
        #expect(warnings.contains { $0.message.contains("records interest, but only savings accounts do") })
    }
}
