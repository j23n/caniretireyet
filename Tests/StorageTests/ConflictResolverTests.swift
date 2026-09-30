import Foundation
import Model
import Storage
import Testing
import TestSupport

/// Sync conflicts: history and headline files merge record by record; other
/// files keep the newest version.
struct ConflictResolverTests {
    private let earlier = Date(timeIntervalSince1970: 1_790_000_000)
    private let later = Date(timeIntervalSince1970: 1_790_000_600)

    private func month(_ valuations: [Valuation], prices: [PriceRecord] = []) -> MonthFile {
        MonthFile(month: "2026-10", valuations: valuations, prices: prices)
    }

    @Test func monthFilesKeepEveryRecordFromBothVersions() throws {
        // The phone added a check-in for casa, the Mac one for tfr and a price.
        let base = Valuation(account: "conto-fineco", date: "2026-10-31", balance: 4000)
        let phone = month([base, Valuation(account: "casa", date: "2026-10-31", balance: 320_000)])
        let mac = month([base, Valuation(account: "tfr", date: "2026-10-31", balance: 9500)],
                        prices: [PriceRecord(instrument: "vwce", date: "2026-10-31", price: 140, currency: .eur)])

        let result = try ConflictResolver.merge([
            ConflictVersion(phone, modified: later, source: "iPhone"), ConflictVersion(mac, modified: earlier, source: "Mac"),
        ])
        #expect(result.value.valuations.map(\.account) == ["casa", "conto-fineco", "tfr"])
        #expect(result.value.prices.count == 1)
        #expect(result.recordsAdded == 2)
        #expect(result.conflictingRecords.isEmpty)
        #expect(result.summary == "Merged 2 versions of history for 2026-10: added 2 records that only an older version had.")
    }

    @Test func whenBothChangedARecordTheNewerFileWins() throws {
        let older = month([Valuation(account: "tfr", date: "2026-10-31", balance: 9500)])
        let newer = month([Valuation(account: "tfr", date: "2026-10-31", balance: 9600, note: "corrected")])

        for versions in [
            [ConflictVersion(older, modified: earlier), ConflictVersion(newer, modified: later)],
            [ConflictVersion(newer, modified: later), ConflictVersion(older, modified: earlier)],
        ] {
            let result = try ConflictResolver.merge(versions)
            #expect(result.value == newer)
            #expect(result.recordsAdded == 0)
            #expect(result.conflictingRecords == ["valuations: 2026-10-31 tfr"])
            #expect(result.summary.contains("kept the newest version of 1 record changed on both sides"))
        }
    }

    @Test func tiesAreBrokenTheSameWayOnEveryDevice() throws {
        let a = month([Valuation(account: "tfr", date: "2026-10-31", balance: 1)])
        let b = month([Valuation(account: "tfr", date: "2026-10-31", balance: 2)])
        let first = try ConflictResolver.merge([ConflictVersion(a, modified: later), ConflictVersion(b, modified: later)])
        let second = try ConflictResolver.merge([ConflictVersion(b, modified: later), ConflictVersion(a, modified: later)])
        #expect(first.value == second.value)
    }

    @Test func eachRecordComesFromTheNewestVersionThatHasIt() throws {
        let oldest = month([Valuation(account: "casa", date: "2026-10-31", balance: 1),
                            Valuation(account: "tfr", date: "2026-10-31", balance: 1)])
        let middle = month([Valuation(account: "tfr", date: "2026-10-31", balance: 2)])
        let newest = month([Valuation(account: "conto-fineco", date: "2026-10-31", balance: 3)])
        let result = try ConflictResolver.merge([
            ConflictVersion(oldest, modified: earlier),
            ConflictVersion(newest, modified: later.addingTimeInterval(60)),
            ConflictVersion(middle, modified: later),
        ])
        #expect(result.value.valuations.map(\.balance) == [1, 3, 2])
        #expect(result.recordsAdded == 2)
    }

    @Test func headlineFilesMergeByDate() throws {
        let a = HeadlineFile(headlines: [Headline(date: "2026-01-31", engine: "0.1.0", planHash: "a")])
        let b = HeadlineFile(headlines: [Headline(date: "2026-02-28", engine: "0.1.0", planHash: "b")])
        let result = try ConflictResolver.merge([ConflictVersion(a, modified: earlier), ConflictVersion(b, modified: later)])
        #expect(result.value.headlines.map(\.planHash) == ["a", "b"])
    }

    @Test func otherFilesKeepTheNewestVersion() {
        let mine = Data(#"{ "id": "tfr", "name": "TFR" }"#.utf8)
        let theirs = Data(#"{ "id": "tfr", "name": "TFR (old employer)" }"#.utf8)
        let result = ConflictResolver.merge(path: "accounts/tfr.json", [
            ConflictVersion(mine, modified: earlier, source: "iPhone"), ConflictVersion(theirs, modified: later, source: "Mac"),
        ])
        #expect(result.value == theirs)
        #expect(result.summary == "Kept the newest version of accounts/tfr.json from Mac; the other version was discarded.")

        let plans = ConflictResolver.newest([ConflictVersion(1, modified: later), ConflictVersion(2, modified: earlier)],
                                            name: "plans/base.json")
        #expect(plans.value == 1)
    }

    @Test func mergingFilesKeepsUnknownKeysAndWritesCanonicalJSON() throws {
        let phone = Data("""
            {"month": "2026-10", "fromPhone": true, "valuations": [
              {"account": "casa", "balance": "320000", "date": "2026-10-31", "appraisal": "agency"}]}
            """.utf8)
        let mac = Data("""
            {"month": "2026-10", "valuations": [{"account": "tfr", "balance": "9500", "date": "2026-10-31"}]}
            """.utf8)
        let result = ConflictResolver.merge(path: "history/2026/2026-10.json", [
            ConflictVersion(phone, modified: later), ConflictVersion(mac, modified: earlier),
        ])
        #expect(String(decoding: result.value, as: UTF8.self) == """
            {
              "fromPhone": true,
              "month": "2026-10",
              "valuations": [
                { "account": "casa", "appraisal": "agency", "balance": "320000", "date": "2026-10-31" },
                { "account": "tfr", "balance": "9500", "date": "2026-10-31" }
              ]
            }

            """)
    }

    @Test func whenTheNewestVersionHasEverythingItsBytesAreKept() throws {
        let newest = try Fixtures.data(for: "history/2026/2026-09.json")
        var older = try Fixtures.decode(MonthFile.self, from: "history/2026/2026-09.json")
        older.valuations.removeLast()
        let result = ConflictResolver.merge(path: "history/2026/2026-09.json", [
            ConflictVersion(try JSONEncoder().encode(older), modified: earlier), ConflictVersion(newest, modified: later),
        ])
        #expect(result.value == newest)
        #expect(result.summary == "Merged 2 versions of history/2026/2026-09.json; they had the same records.")
    }

    @Test func withinOneVersionTheLaterDuplicateWinsAsWhenLoading() throws {
        let newest = Data("""
            {"month": "2026-10", "valuations": [
              {"account": "tfr", "balance": "1", "date": "2026-10-31"},
              {"account": "tfr", "balance": "2", "date": "2026-10-31"}]}
            """.utf8)
        let older = Data(#"{"month": "2026-10", "valuations": [{"account": "casa", "balance": "3", "date": "2026-10-31"}]}"#.utf8)
        let result = ConflictResolver.merge(path: "history/2026/2026-10.json", [
            ConflictVersion(older, modified: earlier), ConflictVersion(newest, modified: later),
        ])
        let valuations = try CanonicalJSON.parse(result.value)["valuations"]?.arrayValue ?? []
        #expect(valuations.map { $0["balance"] } == ["3", "2"])
        #expect(result.conflictingRecords.isEmpty)
    }

    @Test func versionsThatAreNotJSONAreLeftOut() {
        let good = Data(#"{"month": "2026-10", "valuations": [{"account": "tfr", "balance": "1", "date": "2026-10-31"}]}"#.utf8)
        let broken = Data("{ not json".utf8)
        let result = ConflictResolver.merge(path: "history/2026/2026-10.json", [
            ConflictVersion(good, modified: earlier), ConflictVersion(broken, modified: later),
        ])
        #expect(result.value == good)
        #expect(result.summary.hasSuffix("1 version wasn't valid JSON and was left out."))
    }
}
