import Foundation
import Model
import Storage
import Testing
import TestSupport

/// Saving writes only the files whose canonical bytes changed, and deletes
/// the files of removed entities.
struct SaverTests {
    private let longAgo = Date(timeIntervalSince1970: 1_000_000_000)

    /// A copy of the example library whose files all have an old modification date.
    private func exampleFolder() throws -> (TemporaryFolder, Library) {
        let folder = try TemporaryFolder.exampleLibrary()
        for path in try folder.allFiles() {
            try folder.setModificationDate(longAgo, for: path)
        }
        return (folder, try folder.library.load().library)
    }

    private func touchedFiles(_ folder: TemporaryFolder) throws -> [String] {
        try folder.allFiles().filter { try folder.modificationDate($0) != longAgo }
    }

    @Test func onlyTheChangedMonthIsWritten() throws {
        let (folder, previous) = try exampleFolder()
        var library = previous
        library.upsert(Valuation(account: "tfr", date: "2026-09-30", balance: .d("9876.5"), flow: 0))

        let report = try folder.library.save(library, previous: previous)
        #expect(report.written == ["history/2026/2026-09.json"])
        #expect(report.deleted.isEmpty)
        #expect(try touchedFiles(folder) == ["history/2026/2026-09.json"])
        #expect(try folder.text("history/2026/2026-09.json").contains(
            #"    { "account": "tfr", "balance": "9876.5", "date": "2026-09-30", "flow": "0" }"#))
        #expect(try folder.library.load().library == library)
    }

    @Test func equalValuesInADifferentFormAreNotWritten() throws {
        let (folder, previous) = try exampleFolder()
        var library = previous
        // Same records in another order, same decimal written differently: same canonical bytes.
        library.months["2026-09"]?.valuations.reverse()
        library.months["2026-09"]?.valuations[0].balance = Decimal(string: "-141050.000")
        #expect(library != previous)
        #expect(try folder.library.save(library, previous: previous).isEmpty)
        #expect(try touchedFiles(folder).isEmpty)
    }

    @Test func removedEntitiesAreDeleted() throws {
        let (folder, previous) = try exampleFolder()
        var library = previous
        library.accounts["old-bank"] = nil
        library.plans["part-time-from-50"] = nil
        library.projections["base"]?.headlines[2026] = nil
        // Emptying a month deletes its file.
        library.months["2025-10"] = MonthFile(month: "2025-10")

        let report = try folder.library.save(library, previous: previous)
        #expect(report.written.isEmpty)
        #expect(report.deleted == [
            "accounts/old-bank.json", "history/2025/2025-10.json", "plans/part-time-from-50.json",
            "projections/base/headlines/2026.json",
        ])
        #expect(!folder.exists("accounts/old-bank.json"))
        #expect(!folder.exists("history/2025/2025-10.json"))
    }

    @Test func newEntitiesGetNewFiles() throws {
        let (folder, previous) = try exampleFolder()
        var library = previous
        library.accounts["ibkr"] = Account(id: "ibkr", name: "Interactive Brokers", kind: .brokerage, currency: .usd,
                                           opened: "2026-10-01", country: .ie)
        library.upsert(Valuation(account: "ibkr", date: "2026-10-31", cash: 1000))
        library.projections["part-time-from-50", default: PlanProjections()].headlines[2026] = HeadlineFile(headlines: [
            Headline(date: "2026-09-30", earliestAge: 58, engine: "0.1.0", planHash: "abc123"),
        ])

        let report = try folder.library.save(library, previous: previous)
        #expect(report.written == [
            "accounts/ibkr.json", "history/2026/2026-10.json", "projections/part-time-from-50/headlines/2026.json",
        ])
        #expect(try folder.text("accounts/ibkr.json") == """
            {
              "country": "IE",
              "currency": "USD",
              "id": "ibkr",
              "kind": "brokerage",
              "name": "Interactive Brokers",
              "opened": "2026-10-01"
            }

            """)
        #expect(try folder.text("history/2026/2026-10.json") == """
            {
              "fx": [],
              "indices": [],
              "month": "2026-10",
              "prices": [],
              "valuations": [
                { "account": "ibkr", "cash": "1000", "date": "2026-10-31" }
              ]
            }

            """)
    }

    @Test func granularSavesWriteOneFile() throws {
        let (folder, library) = try exampleFolder()
        var account = try #require(library.accounts["conto-fineco"])
        #expect(try folder.library.save(account).isEmpty)

        account.notes = "Main current account."
        #expect(try folder.library.save(account).written == ["accounts/conto-fineco.json"])

        var plan = try #require(library.plans["base"])
        plan.endAge = 100
        #expect(try folder.library.save(plan).written == ["plans/base.json"])

        var month = try #require(library.months["2026-08"])
        month.prices.reverse()
        #expect(try folder.library.save(month).isEmpty, "records are sorted before writing")

        #expect(try folder.library.save(MonthFile(month: "2026-08")).deleted == ["history/2026/2026-08.json"])
        #expect(try folder.library.delete(.instrument("gold")).deleted == ["instruments/gold.json"])
        #expect(try folder.library.delete(.instrument("gold")).isEmpty)

        var settings = library.settings
        settings.mainPlan = "part-time-from-50"
        #expect(try folder.library.save(settings).written == ["library.json"])

        let baseline = try #require(library.projections["base"]?.baselines["2026-01-05"])
        #expect(try folder.library.save(baseline, id: "2026-01-05", plan: "base").isEmpty)
        #expect(try folder.library.save(baseline, id: "2026-06-30", plan: "base").written == [
            "projections/base/baselines/2026-06-30.json",
        ])

        let profile = try #require(library.importProfiles["net-worth-sheet"])
        #expect(try folder.library.save(profile).isEmpty)
        let instrument = try #require(library.instruments["vwce"])
        #expect(try folder.library.save(instrument).isEmpty)
        let headlines = try #require(library.projections["base"]?.headlines[2026])
        #expect(try folder.library.save(headlines, year: 2026, plan: "base").isEmpty)

        #expect(try touchedFiles(folder) == [
            "accounts/conto-fineco.json", "library.json", "plans/base.json",
            "projections/base/baselines/2026-06-30.json",
        ])
    }

    @Test func aFileThatIsNotJSONIsBackedUpBeforeItIsOverwritten() throws {
        let (folder, previous) = try exampleFolder()
        try folder.write("history/2026/2026-10.json", "{ \"month\": \"2026-10\", \"valuations\": [ oops ] }\n")
        var library = previous
        library.upsert(Valuation(account: "tfr", date: "2026-10-31", balance: 1))

        let report = try folder.library.save(library, previous: previous)
        #expect(report.written == ["history/2026/2026-10.json"])
        let backup = try #require(report.backups.first)
        #expect(backup.label == "unreadable")
        #expect(backup.files == ["history/2026/2026-10.json"])
        #expect(try folder.text("\(backup.path)/history/2026/2026-10.json").contains("oops"))
        #expect(try folder.library.load().library.months["2026-10"]?.valuations.count == 1)
    }

    @Test func savingIntoAnEmptyFolderWritesEverything() throws {
        let folder = try TemporaryFolder()
        let library = Library(settings: LibrarySettings(baseCurrency: .chf), accounts: [
            Account(id: "cash", name: "Cash", kind: .cash, currency: .chf, opened: "2026-01-01"),
        ])
        let report = try folder.library.save(library)
        #expect(report.written == ["accounts/cash.json", "library.json"])
        #expect(try folder.library.load().library == library)
    }
}
