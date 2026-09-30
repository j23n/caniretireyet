import Foundation
import Model
import Storage
import Testing
import TestSupport

/// Problems in single files are reported with the path and never stop the
/// rest of the library from loading.
struct LoaderTests {
    private func load(_ folder: TemporaryFolder) throws -> LoadResult {
        try folder.library.load()
    }

    @Test func malformedJSONIsReportedWithLineAndColumn() throws {
        let folder = try TemporaryFolder.exampleLibrary()
        try folder.write("accounts/directa.json", "{\n  \"id\": \"directa\",\n  \"name\": \"Directa\"\n  \"kind\": \"brokerage\"\n}\n")
        let result = try load(folder)

        let issues = result.report.issues(for: "accounts/directa.json")
        #expect(issues.count == 1)
        #expect(issues.first?.severity == .error)
        #expect(issues.first?.message.contains("Line 4, column 3") == true)
        #expect(result.library.accounts["directa"] == nil)
        #expect(result.library.accounts.count == 9)
        #expect(result.library.months.count == 12)
    }

    @Test func wrongTypesAreReportedWithTheirPlace() throws {
        let folder = try TemporaryFolder.exampleLibrary()
        try folder.write("instruments/gold.json", #"""
            {
              "assetClasses": { "gold": "1" },
              "currency": "EUR",
              "id": "gold",
              "kind": "metal",
              "name": ["Gold"],
              "unit": "g"
            }
            """#)
        let result = try load(folder)
        let issue = try #require(result.report.issues(for: "instruments/gold.json").first)
        #expect(issue.severity == .error)
        #expect(issue.message.hasPrefix("name: expected text, found a list."))
        #expect(result.library.instruments["gold"] == nil)
        #expect(result.library.instruments.count == 2)
    }

    @Test func aTopLevelListIsReported() throws {
        let folder = try TemporaryFolder.exampleLibrary()
        try folder.write("plans/base.json", "[]\n")
        let result = try load(folder)
        #expect(result.report.issues(for: "plans/base.json").first?.message.contains("JSON object") == true)
        #expect(result.library.plans.keys.sorted() == ["part-time-from-50"])
    }

    @Test func badRecordsAreSkippedAndTheRestOfTheMonthLoads() throws {
        let folder = try TemporaryFolder.exampleLibrary()
        try folder.write("history/2026/2026-09.json", #"""
            {
              "fx": [],
              "month": "2026-09",
              "prices": [
                { "currency": "EUR", "date": "2026-09-30", "instrument": "vwce", "price": "lots" }
              ],
              "valuations": [
                { "account": "conto-deposito", "balance": "17365.55", "date": "2026-09-30" },
                { "account": "conto-fineco", "date": "2026-09-31", "balance": "1" },
                { "account": "mutuo-casa", "balance": "-141050", "date": "2026-09-30" }
              ]
            }
            """#)
        let result = try load(folder)
        let month = try #require(result.library.months["2026-09"])
        #expect(month.valuations.map(\.account) == ["conto-deposito", "mutuo-casa"])
        #expect(month.prices.isEmpty)

        let messages = result.report.issues(for: "history/2026/2026-09.json").map(\.message)
        #expect(messages.count == 2)
        #expect(messages.contains { $0.hasPrefix("prices[0].price: Expected a decimal") && $0.hasSuffix("This record was skipped.") })
        #expect(messages.contains { $0.hasPrefix("valuations[1].date: Expected a date") })
    }

    @Test func recordsInTheWrongMonthAreKeptWithAWarning() throws {
        let folder = try TemporaryFolder.exampleLibrary()
        var month = try Fixtures.decode(MonthFile.self, from: "history/2026/2026-09.json")
        month.valuations.append(Valuation(account: "tfr", date: "2026-08-31", balance: 1))
        try folder.write("history/2026/2026-09.json", JSONEncoder().encode(month))

        let result = try load(folder)
        let issues = result.report.issues(for: "history/2026/2026-09.json")
        #expect(issues.count == 1)
        #expect(issues.first?.severity == .warning)
        #expect(issues.first?.message.contains("2026-08-31") == true)
        #expect(result.library.months["2026-09"]?.valuations.contains { $0.date == "2026-08-31" } == true)
    }

    @Test func aFileNameThatDoesNotMatchTheIDWins() throws {
        let folder = try TemporaryFolder.exampleLibrary()
        try folder.write("accounts/second-broker.json", Fixtures.data(for: "accounts/directa.json"))
        let result = try load(folder)
        let issue = try #require(result.report.issues(for: "accounts/second-broker.json").first)
        #expect(issue.severity == .warning)
        #expect(issue.message.contains("\"directa\" doesn't match the file name"))
        #expect(result.library.accounts["second-broker"]?.id == "second-broker")
        #expect(result.library.accounts["second-broker"]?.name == "Directa")
        #expect(result.library.accounts["directa"]?.id == "directa")
    }

    @Test func aMonthFileSaysWhichMonthByItsName() throws {
        let folder = try TemporaryFolder.exampleLibrary()
        let original = try folder.text("history/2026/2026-09.json")
        try folder.write("history/2026/2026-09.json", original.replacingOccurrences(of: "\"month\": \"2026-09\"",
                                                                                   with: "\"month\": \"2026-08\""))
        let result = try load(folder)
        #expect(result.report.issues(for: "history/2026/2026-09.json").first?.severity == .warning)
        #expect(result.library.months["2026-09"]?.month == "2026-09")
        #expect(result.library.months["2026-09"]?.valuations.count == 5)
    }

    @Test func numbersAreAcceptedWhereTextIsExpected() throws {
        let folder = try TemporaryFolder.exampleLibrary()
        try folder.write("accounts/numbered.json", #"""
            { "currency": "EUR", "id": "numbered", "kind": "cash", "name": 2026, "opened": "2020-01-01", "tags": [1, 2.5] }
            """#)
        try folder.write("history/2026/2026-10.json", #"""
            { "month": "2026-10", "valuations": [{ "account": "numbered", "balance": 1234.56, "date": "2026-10-31", "note": 7 }] }
            """#)
        try folder.write("plans/numbers.json", #"""
            { "endAge": "90", "id": "numbers", "name": "Numbers", "retirement": { "age": 60 },
              "spending": { "retired": 30000, "working": 32000.5 } }
            """#)
        let result = try load(folder)
        #expect(result.report.issues.isEmpty, "\(result.report.issues)")
        #expect(result.library.accounts["numbered"]?.name == "2026")
        #expect(result.library.accounts["numbered"]?.tags == ["1", "2.5"])
        let valuation = try #require(result.library.months["2026-10"]?.valuations.first)
        #expect(valuation.balance == .d("1234.56"))
        #expect(valuation.note == "7")
        #expect(result.library.plans["numbers"]?.endAge == 90)
    }

    @Test func unknownFilesAreIgnored() throws {
        let folder = try TemporaryFolder.exampleLibrary()
        try folder.write("notes.txt", "my notes")
        try folder.write("accounts/.hidden.json", "not json")
        try folder.write("accounts/readme.md", "# accounts")
        try folder.write("backups/2026-01-01-v0/accounts/old.json", "{")
        try folder.write("stuff/thing.json", "{")
        try folder.write("history/2026/notes.json", "{}")
        try folder.write("accounts/My Account.json", "{}")
        let result = try load(folder)
        #expect(result.library == (try Fixtures.exampleLibrary()))
        // JSON files with names the library can't use get a warning, nothing else is mentioned.
        #expect(result.report.issues.map(\.path) == ["accounts/My Account.json", "history/2026/notes.json"])
        #expect(result.report.issues.allSatisfy { $0.severity == .warning })
    }

    @Test func duplicateRecordsKeepTheLastOne() throws {
        let folder = try TemporaryFolder.exampleLibrary()
        try folder.write("history/2026/2026-10.json", #"""
            {
              "month": "2026-10",
              "valuations": [
                { "account": "tfr", "balance": "1", "date": "2026-10-31" },
                { "account": "tfr", "balance": "2", "date": "2026-10-31" }
              ]
            }
            """#)
        let result = try load(folder)
        #expect(result.library.months["2026-10"]?.valuations.map(\.balance) == [.d("2")])
        #expect(result.report.issues(for: "history/2026/2026-10.json").first?.message.contains("two valuations") == true)
    }

    @Test func recordsAreSortedWhenLoaded() throws {
        let folder = try TemporaryFolder.exampleLibrary()
        try folder.write("history/2026/2026-10.json", #"""
            { "month": "2026-10", "valuations": [
              { "account": "tfr", "balance": "1", "date": "2026-10-31" },
              { "account": "casa", "balance": "2", "date": "2026-10-31" },
              { "account": "tfr", "balance": "3", "date": "2026-10-15" }
            ] }
            """#)
        let result = try load(folder)
        let keys = result.library.months["2026-10"]?.valuations.map { "\($0.date) \($0.account)" }
        #expect(keys == ["2026-10-15 tfr", "2026-10-31 casa", "2026-10-31 tfr"])
    }

    @Test func brokenReferencesAreWarnings() throws {
        let folder = try TemporaryFolder.exampleLibrary()
        try FileManager.default.removeItem(at: folder.url.appendingPathComponent("instruments/btc.json"))
        let result = try load(folder)
        let issues = result.report.issues.filter { $0.message.contains("instruments that don't exist: btc") }
        #expect(issues.count == 12)
        #expect(issues.allSatisfy { $0.severity == .warning })
    }

    @Test func aMissingSettingsFileIsAnError() throws {
        let folder = try TemporaryFolder.exampleLibrary()
        try FileManager.default.removeItem(at: folder.url.appendingPathComponent("library.json"))
        let result = try load(folder)
        #expect(result.report.errors.map(\.path) == ["library.json"])
        #expect(result.report.schemaVersion == nil)
        #expect(result.library.settings == LibrarySettings())
        #expect(result.library.accounts.count == 10)
    }

    @Test func aMissingFolderThrows() {
        let folder = LibraryFolder(root: URL(fileURLWithPath: "/nonexistent-\(UUID().uuidString)"))
        #expect(throws: StorageError.self) { try folder.load() }
    }

    @Test func reloadReplacesOrRemovesOneEntity() throws {
        let folder = try TemporaryFolder.exampleLibrary()
        var library = try load(folder).library

        var account = try #require(library.accounts["tfr"])
        account.name = "TFR (employer)"
        try folder.write("accounts/tfr.json", JSONEncoder().encode(account))
        #expect(folder.library.reload(.account("tfr"), into: &library).isEmpty)
        #expect(library.accounts["tfr"]?.name == "TFR (employer)")

        try FileManager.default.removeItem(at: folder.url.appendingPathComponent("history/2026/2026-09.json"))
        #expect(folder.library.reload(.month("2026-09"), into: &library).isEmpty)
        #expect(library.months["2026-09"] == nil)

        try folder.write("plans/base.json", "{")
        let issues = folder.library.reload(.plan("base"), into: &library)
        #expect(issues.map(\.severity) == [.error])
        #expect(library.plans["base"] == nil)
    }
}
