import Foundation
import Model
import Storage
import Testing
import TestSupport

/// Saving never loses a change made on disk after the library was loaded:
/// history and headline files are merged record by record, other files are
/// backed up before they're replaced and kept instead of deleted.
struct SaveMergeTests {
    private let september = "history/2026/2026-09.json"

    /// Adds a line to the start of a record list in a file, as a text editor or the other device would.
    private func insert(_ record: String, into list: String, of path: String, in folder: TemporaryFolder) throws {
        let text = try folder.text(path)
        let edited = text.replacingOccurrences(of: "\"\(list)\": [\n", with: "\"\(list)\": [\n    \(record),\n")
        #expect(edited != text)
        try folder.write(path, edited)
    }

    private func valuation(_ account: AccountID, on date: CalendarDate, in folder: TemporaryFolder) throws
        -> Valuation? {
        try folder.library.load().library.valuations(for: account).first { $0.date == date }
    }

    @Test func aRecordAddedOnDiskSurvivesASaveOfTheSameMonth() throws {
        let folder = try TemporaryFolder.exampleLibrary()
        let previous = try folder.library.load().library
        // The other device adds a mid-month valuation, which syncs before the app reloads.
        try insert(#"{ "account": "tfr", "balance": "999", "date": "2026-09-15" }"#, into: "valuations",
                   of: september, in: folder)

        var library = previous
        library.upsert(Valuation(account: "conto-fineco", date: "2026-09-30", balance: 4300, flow: -215.2))
        let report = try folder.library.save(library, previous: previous)

        #expect(report.written == [september])
        #expect(report.reloadPaths == [september])
        #expect(report.issues.isEmpty)
        #expect(report.backups.isEmpty)
        #expect(try valuation("tfr", on: "2026-09-15", in: folder)?.balance == 999)
        #expect(try valuation("conto-fineco", on: "2026-09-30", in: folder)?.balance == 4300)
    }

    @Test func recordsChangedOnOneSideKeepThatSidesVersion() throws {
        let folder = try TemporaryFolder.exampleLibrary()
        let previous = try folder.library.load().library
        // On disk: conto-deposito changes and the mortgage is deleted.
        var text = try folder.text(september)
        text = text.replacingOccurrences(of: "\"17365.55\"", with: "\"17999\"")
        text = text.replacingOccurrences(
            of: ",\n    { \"account\": \"mutuo-casa\", \"balance\": \"-141050\", \"date\": \"2026-09-30\", \"flow\": \"650\" }",
            with: "")
        try folder.write(september, text)

        // In the app: conto-fineco changes and fondo-pensione is deleted.
        var library = previous
        library.upsert(Valuation(account: "conto-fineco", date: "2026-09-30", balance: 4300))
        library.removeValuation(ValuationKey(account: "fondo-pensione", date: "2026-09-30"))
        let report = try folder.library.save(library, previous: previous)

        #expect(report.issues.isEmpty)
        let month = try #require(folder.library.load().library.months["2026-09"])
        #expect(month.valuations.map(\.account) == ["conto-deposito", "conto-fineco", "directa"])
        #expect(month.valuations[0].balance == 17999)
        #expect(month.valuations[1].balance == 4300)
    }

    @Test func aRecordChangedOnBothSidesTakesOursAndIsReportedWithABackup() throws {
        let folder = try TemporaryFolder.exampleLibrary()
        let previous = try folder.library.load().library
        let remote = try folder.text(september).replacingOccurrences(of: "\"4210.55\"", with: "\"4000\"")
        try folder.write(september, remote)

        var library = previous
        library.upsert(Valuation(account: "conto-fineco", date: "2026-09-30", balance: 4300))
        let report = try folder.library.save(library, previous: previous)

        #expect(try valuation("conto-fineco", on: "2026-09-30", in: folder)?.balance == 4300)
        let issue = try #require(report.issues.first)
        #expect(issue.kind == .recordsReplaced)
        #expect(issue.path == september)
        #expect(issue.records == ["valuations: 2026-09-30 conto-fineco"])
        let backup = try #require(issue.backup)
        #expect(backup.label == "conflict")
        #expect(report.backups == [backup])
        #expect(try folder.text("\(backup.path)/\(september)") == remote)
        #expect(issue.summary.contains(backup.path))
    }

    @Test func aRecordDeletedHereButChangedOnDiskIsKept() throws {
        let folder = try TemporaryFolder.exampleLibrary()
        let previous = try folder.library.load().library
        try folder.write(september, try folder.text(september).replacingOccurrences(of: "\"4210.55\"", with: "\"4000\""))

        var library = previous
        library.removeValuation(ValuationKey(account: "conto-fineco", date: "2026-09-30"))
        library.removeValuation(ValuationKey(account: "directa", date: "2026-09-30"))
        let report = try folder.library.save(library, previous: previous)

        #expect(try valuation("conto-fineco", on: "2026-09-30", in: folder)?.balance == 4000)
        #expect(try valuation("directa", on: "2026-09-30", in: folder) == nil)
        #expect(report.issues.map(\.records) == [["valuations: 2026-09-30 conto-fineco"]])
        #expect(report.reloadPaths == [september])
    }

    @Test func deletingTheLastRecordOfAMonthKeepsTheOtherDevicesRecords() throws {
        let folder = try TemporaryFolder.exampleLibrary()
        try folder.write("history/2026/2026-10.json", """
            { "month": "2026-10", "valuations": [{ "account": "tfr", "balance": "9000", "date": "2026-10-31" }] }
            """)
        let previous = try folder.library.load().library
        try folder.write("history/2026/2026-10.json", """
            { "month": "2026-10", "valuations": [
              { "account": "casa", "balance": "320000", "date": "2026-10-31" },
              { "account": "tfr", "balance": "9000", "date": "2026-10-31" }
            ] }
            """)

        var library = previous
        library.removeValuation(ValuationKey(account: "tfr", date: "2026-10-31"))
        let report = try folder.library.save(library, previous: previous)

        #expect(report.deleted.isEmpty)
        #expect(report.reloadPaths == ["history/2026/2026-10.json"])
        let month = try folder.library.load().library.months["2026-10"]
        #expect(month?.valuations.map(\.account) == ["casa"])
    }

    @Test func unknownKeysAndUnreadableRecordsAddedOnDiskSurvive() throws {
        let folder = try TemporaryFolder.exampleLibrary()
        let previous = try folder.library.load().library
        var text = try folder.text(september)
        text = text.replacingOccurrences(of: "  \"month\": \"2026-09\",", with: "  \"checkedBy\": \"me\",\n  \"month\": \"2026-09\",")
        try folder.write(september, text)
        try insert(#"{ "account": "tfr", "balance": "9000,50", "date": "2026-09-30" }"#, into: "valuations",
                   of: september, in: folder)

        var library = previous
        library.upsert(Valuation(account: "conto-fineco", date: "2026-09-30", balance: 4300))
        try folder.library.save(library, previous: previous)

        let json = try folder.json(september)
        #expect(json["checkedBy"] == "me")
        #expect(json["valuations"]?.arrayValue?.contains { $0["balance"] == "9000,50" } == true)
        #expect(try valuation("conto-fineco", on: "2026-09-30", in: folder)?.balance == 4300)
    }

    @Test func headlinesAreMergedToo() throws {
        let folder = try TemporaryFolder.exampleLibrary()
        let path = "projections/base/headlines/2026.json"
        let previous = try folder.library.load().library
        let other = Headline(date: "2026-08-15", earliestAge: 57, engine: "0.1.0", planHash: "other")
        var onDisk = try #require(previous.projections["base"]?.headlines[2026])
        onDisk.headlines.append(other)
        try folder.library.save(onDisk, year: 2026, plan: "base")

        var library = previous
        library.projections["base"]?.headlines[2026]?.headlines.append(
            Headline(date: "2026-09-30", earliestAge: 56, engine: "0.1.0", planHash: "ours"))
        let report = try folder.library.save(library, previous: previous)

        #expect(report.reloadPaths == [path])
        let saved = try folder.library.load().library.projections["base"]?.headlines[2026]?.headlines ?? []
        #expect(saved.contains(other))
        #expect(saved.contains { $0.planHash == "ours" })
    }

    // MARK: Single-entity files

    @Test func anEntityChangedOnDiskAndHereIsBackedUpThenReplaced() throws {
        let folder = try TemporaryFolder.exampleLibrary()
        let path = "accounts/conto-fineco.json"
        let previous = try folder.library.load().library
        let remote = try folder.text(path).replacingOccurrences(of: "\"Conto Fineco\"", with: "\"Fineco (remote)\"")
        try folder.write(path, remote)

        var library = previous
        library.accounts["conto-fineco"]?.institution = "Local edit"
        let report = try folder.library.save(library, previous: previous)

        #expect(report.written == [path])
        #expect(try folder.library.load().library.accounts["conto-fineco"]?.institution == "Local edit")
        let issue = try #require(report.issues.first)
        #expect(issue.kind == .replaced)
        #expect(try folder.text("\(try #require(issue.backup).path)/\(path)") == remote)
    }

    @Test func theSameChangeOnBothSidesIsNotAConflict() throws {
        let folder = try TemporaryFolder.exampleLibrary()
        let previous = try folder.library.load().library
        var library = previous
        library.accounts["casa"]?.name = "Our home"
        try folder.library.save(try #require(library.accounts["casa"]))

        let report = try folder.library.save(library, previous: previous)
        #expect(report.issues.isEmpty)
        #expect(report.backups.isEmpty)
    }

    @Test func anEntityChangedOnDiskIsKeptInsteadOfDeleted() throws {
        let folder = try TemporaryFolder.exampleLibrary()
        let previous = try folder.library.load().library
        try folder.write("accounts/old-bank.json",
                         try folder.text("accounts/old-bank.json").replacingOccurrences(of: "\"Old bank\"", with: "\"Old\""))
        var library = previous
        library.accounts["old-bank"] = nil
        library.accounts["casa"] = nil

        let report = try folder.library.save(library, previous: previous)
        #expect(report.deleted == ["accounts/casa.json"])
        #expect(folder.exists("accounts/old-bank.json"))
        #expect(report.reloadPaths == ["accounts/old-bank.json"])
        #expect(report.issues == [SaveIssue(path: "accounts/old-bank.json", kind: .kept)])
    }

    // MARK: Files that didn't load

    @Test func settingsThatDoNotDecodeAreBackedUpBeforeTheyAreReplaced() throws {
        let folder = try TemporaryFolder.exampleLibrary()
        let broken = """
            {
              "baseCurrency": "CHF",
              "mainPlan": "base",
              "person": { "birthDate": "1988-4-12", "name": "Alex Example" },
              "schemaVersion": 2,
              "taxResidence": "CH"
            }

            """
        try folder.write("library.json", broken)
        let loaded = try folder.library.load()
        #expect(!loaded.report.issues(for: "library.json").isEmpty)
        var library = loaded.library
        library.settings.mainPlan = "part-time-from-50"

        let report = try folder.library.save(library, previous: loaded.library)
        let issue = try #require(report.issues.first)
        #expect(issue.kind == .unreadable)
        #expect(report.reloadPaths == ["library.json"])
        #expect(try folder.text("\(try #require(issue.backup).path)/library.json") == broken)
    }

    @Test func aFileThatDidNotLoadIsBackedUpWhenItsIDIsReused() throws {
        let folder = try TemporaryFolder.exampleLibrary()
        let broken = #"{ "currency": "EUR", "id": "ibkr", "kind": "brokerage", "name": "IBKR", "opened": "someday" }"#
        try folder.write("accounts/ibkr.json", broken)
        let loaded = try folder.library.load()
        #expect(loaded.library.accounts["ibkr"] == nil)
        var library = loaded.library
        library.accounts["ibkr"] = Account(id: "ibkr", name: "New", kind: .cash, currency: .eur, opened: "2026-01-01")

        let report = try folder.library.save(library, previous: loaded.library)
        #expect(report.written == ["accounts/ibkr.json"])
        #expect(report.backups.count == 1)
        #expect(try folder.text("\(report.backups[0].path)/accounts/ibkr.json") == broken)
    }

    @Test func aMonthThatIsNotJSONIsBackedUpBeforeACheckInReplacesIt() throws {
        let folder = try TemporaryFolder.exampleLibrary()
        let broken = try folder.text(september).replacingOccurrences(of: "\"flow\": \"650\" }", with: "\"flow\": \"650\" },")
        try folder.write(september, broken)
        let loaded = try folder.library.load()
        #expect(loaded.library.months["2026-09"] == nil)
        var library = loaded.library
        library.upsert(Valuation(account: "tfr", date: "2026-09-30", balance: 11100, flow: 0))

        let report = try folder.library.save(library, previous: loaded.library)
        let issue = try #require(report.issues.first)
        #expect(issue.kind == .unreadable)
        #expect(try folder.text("\(try #require(issue.backup).path)/\(september)") == broken)
    }

    // MARK: Changes between reading and writing

    @Test func aChangeThatArrivesWhileSavingIsMergedToo() throws {
        let folder = try TemporaryFolder.exampleLibrary()
        let previous = try folder.library.load().library
        let url = folder.url.appendingPathComponent(september)
        let remote = try folder.text(september).replacingOccurrences(
            of: "\"valuations\": [\n", with: "\"valuations\": [\n    { \"account\": \"tfr\", \"balance\": \"999\", \"date\": \"2026-09-15\" },\n")
        // The file changes right after the save reads it, once.
        let files = InterferingFileAccess(url: url, change: Data(remote.utf8))
        var library = previous
        library.upsert(Valuation(account: "conto-fineco", date: "2026-09-30", balance: 4300))

        let report = try LibraryFolder(root: folder.url, files: files).save(library, previous: previous)
        #expect(files.attempts == 2)
        #expect(report.written == [september])
        #expect(try valuation("tfr", on: "2026-09-15", in: folder)?.balance == 999)
        #expect(try valuation("conto-fineco", on: "2026-09-30", in: folder)?.balance == 4300)
    }

    @Test func changedFilesAreTheOnesTheSaveWrites() throws {
        let previous = try Fixtures.exampleLibrary()
        var library = previous
        library.accounts["casa"]?.name = "Our home"
        library.months["2025-10"] = MonthFile(month: "2025-10")
        library.months["2026-09"]?.valuations.reverse()
        #expect(library.files(changedFrom: previous) == [.account("casa"), .month("2025-10")])
    }
}

/// Local file access that changes one file on disk the first time a save
/// tries to replace it, as iCloud Drive might deliver a version meanwhile.
private final class InterferingFileAccess: FileAccessing, @unchecked Sendable {
    let base = LocalFileAccess()
    let url: URL
    let change: Data
    private(set) var attempts = 0

    init(url: URL, change: Data) {
        self.url = url
        self.change = change
    }

    func listFiles(in directory: URL) throws -> [String] { try base.listFiles(in: directory) }
    func fileExists(at url: URL) -> Bool { base.fileExists(at: url) }
    func readData(at url: URL) throws -> Data { try base.readData(at: url) }
    func writeData(_ data: Data, to url: URL) throws { try base.writeData(data, to: url) }
    func removeItem(at url: URL) throws { try base.removeItem(at: url) }
    func modificationDate(of url: URL) throws -> Date { try base.modificationDate(of: url) }
    func createDirectory(at url: URL) throws { try base.createDirectory(at: url) }

    func replaceData(at url: URL, ifContentsAre expected: Data?, with data: Data?) throws -> Bool {
        if url == self.url {
            attempts += 1
            if attempts == 1 { try base.writeData(change, to: url) }
        }
        return try base.replaceData(at: url, ifContentsAre: expected, with: data)
    }
}
