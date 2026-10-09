import Foundation
import Model
@testable import Storage
import Testing
import TestSupport

/// A library written by a newer app opens read-only; older libraries are
/// migrated step by step after a backup.
struct SchemaGuardTests {
    private func newerLibrary() throws -> TemporaryFolder {
        let folder = try TemporaryFolder.exampleLibrary()
        let settings = try folder.text("library.json").replacingOccurrences(of: "\"schemaVersion\": 3",
                                                                           with: "\"schemaVersion\": 4")
        try folder.write("library.json", settings)
        return folder
    }

    @Test func aNewerLibraryLoadsReadOnly() throws {
        let folder = try newerLibrary()
        let result = try folder.library.load()
        #expect(result.report.isReadOnly)
        #expect(result.report.readOnlyReason == .newerSchema)
        #expect(result.report.schemaVersion == 4)
        #expect(result.report.errors.isEmpty)
        #expect(result.report.warnings.first?.message.contains("read-only") == true)
        #expect(result.library.settings.schemaVersion == 4)
        #expect(result.library.accounts.count == 10)
    }

    @Test func savingANewerLibraryThrows() throws {
        let folder = try newerLibrary()
        let loaded = try folder.library.load().library
        var library = loaded
        library.accounts["tfr"]?.name = "Changed"
        let error = StorageError.libraryIsNewer(version: 4, supported: 3)
        #expect(throws: error) { try folder.library.save(library, previous: loaded) }
        #expect(throws: error) { try folder.library.checkWritable() }
        #expect(error.description.contains("read-only"))
        #expect(try folder.library.load().library == loaded)
    }

    @Test func aLibraryInMemoryFromANewerAppCannotBeSavedElsewhere() throws {
        let folder = try TemporaryFolder()
        let library = Library(settings: LibrarySettings(schemaVersion: 4))
        #expect(throws: StorageError.libraryIsNewer(version: 4, supported: 3)) {
            try folder.library.save(library, previous: Library())
        }
        #expect(!folder.exists("library.json"))
    }

    @Test func theExampleLibraryIsCurrent() throws {
        let folder = try TemporaryFolder.exampleLibrary()
        #expect(LibrarySettings.currentSchemaVersion == 3)
        #expect(try folder.library.migrate() == nil)
        #expect(!folder.exists("backups"))
    }

    /// An app that knows only version 2 (plans with tax systems) opens a
    /// version 3 library read-only, so it never writes plans it would read
    /// without their tax rates.
    @Test func anAppBeforeSimplePlansOpensAVersion3LibraryReadOnly() throws {
        let folder = try TemporaryFolder.exampleLibrary()
        #expect(throws: StorageError.libraryIsNewer(version: 3, supported: 2)) {
            try folder.library.migrate(to: 2, steps: [])
        }
    }
}

/// A library.json that exists but can't be used leaves only default
/// settings in memory (EUR, no birth date). The library opens read-only, as
/// for a newer schema, so the next edit can't save those defaults over the
/// user's settings. A folder without library.json is unaffected.
struct UnreadableSettingsTests {
    private static let notJSON = "{ \"baseCurrency\": \"CHF\", \"schemaVersion\": 3,\n"
    private static let notSettings = #"{ "baseCurrency": ["CHF"], "schemaVersion": 3 }"#

    @Test(arguments: [notJSON, notSettings, "[]"])
    func anUnreadableSettingsFileOpensReadOnly(_ text: String) throws {
        let folder = try TemporaryFolder.exampleLibrary()
        try folder.write("library.json", text)
        let result = try folder.library.load()
        #expect(result.report.settingsUnreadable)
        #expect(result.report.isReadOnly)
        #expect(result.report.readOnlyReason == .unreadableSettings)
        #expect(!result.report.isNewerSchema)
        #expect(!result.report.needsMigration)
        // One error, on library.json, saying what's wrong and that the library is read-only.
        let issues = result.report.errors
        #expect(issues.map(\.path) == ["library.json"])
        #expect(issues.first?.message.contains("open read-only") == true)
        #expect(result.library.settings.baseCurrency == .eur)
        #expect(result.library.accounts.count == 10)
    }

    @Test func theErrorSaysWhyTheFileCantBeRead() throws {
        let folder = try TemporaryFolder.exampleLibrary()
        try folder.write("library.json", Self.notJSON)
        let message = try #require(try folder.library.load().report.errors.first?.message)
        #expect(message.hasPrefix("This isn't valid JSON."))
        #expect(message.hasSuffix("Fix the file, or restore it from a backup in backups/, then open the library again."))

        try folder.write("library.json", Self.notSettings)
        let decoding = try #require(try folder.library.load().report.errors.first?.message)
        #expect(decoding.hasPrefix("baseCurrency:"))
        #expect(decoding.contains("open read-only"))
    }

    @Test func nothingIsSavedUntilItIsFixed() throws {
        let folder = try TemporaryFolder.exampleLibrary()
        let original = try folder.text("library.json")
        try folder.write("library.json", Self.notJSON)
        let loaded = try folder.library.load().library
        var library = loaded
        library.accounts["tfr"]?.name = "Changed"
        library.settings.person = Person(name: "Someone")
        let error = StorageError.unreadableFile(
            path: "library.json",
            message: "The file can't be read. The library is open read-only: saving would replace your settings "
                + "with defaults. Fix the file, or restore it from a backup in backups/, then open the library again.")
        #expect(throws: error) { try folder.library.save(library, previous: loaded) }
        #expect(throws: error) { try folder.library.checkWritable() }
        #expect(try folder.text("library.json") == Self.notJSON)
        #expect(try folder.library.load().library == loaded)

        // Fixed by hand, the library is writable again.
        try folder.write("library.json", original)
        let fixed = try folder.library.load()
        #expect(!fixed.report.isReadOnly)
        #expect(fixed.report.readOnlyReason == nil)
        try folder.library.checkWritable()
    }

    @Test func restoringACopyOfTheSettingsFixesThem() throws {
        let folder = try TemporaryFolder.exampleLibrary()
        let backup = try folder.library.backup(paths: ["library.json", "accounts/tfr.json"], label: "before")
        let copyOfAnAccount = try folder.library.backup(paths: ["accounts/tfr.json"], label: "account")
        try folder.write("library.json", Self.notJSON)

        #expect(throws: StorageError.self) { try folder.library.restore(backup: copyOfAnAccount) }
        try folder.library.restore(backup: backup)
        #expect(!(try folder.library.load().report.isReadOnly))
    }

    /// A library.json that breaks while the library is open says so when
    /// it's reloaded, as loading it would: the library turns read-only with
    /// default settings in memory, and writable again once the file is fixed.
    @Test func reloadingTheSettingsSaysWhetherTheLibraryIsReadOnly() throws {
        let folder = try TemporaryFolder.exampleLibrary()
        let original = try folder.text("library.json")
        let loaded = try folder.library.load().library
        var library = loaded

        try folder.write("library.json", Self.notJSON)
        let broken = folder.library.reload(.settings, into: &library)
        #expect(broken.settingsUnreadable)
        #expect(broken.readOnlyReason == .unreadableSettings)
        #expect(broken.errors.map(\.path) == ["library.json"])
        #expect(broken.errors.first?.message.contains("open read-only") == true)
        #expect(library.settings == LibrarySettings())
        #expect(library.accounts == loaded.accounts)

        try folder.write("library.json", original)
        let fixed = folder.library.reload(.settings, into: &library)
        #expect(fixed.readOnlyReason == nil)
        #expect(fixed.issues.isEmpty)
        #expect(library == loaded)

        try folder.write("library.json", original.replacingOccurrences(of: "\"schemaVersion\": 3",
                                                                       with: "\"schemaVersion\": 4"))
        let newer = folder.library.reload(.settings, into: &library)
        #expect(newer.readOnlyReason == .newerSchema)
    }

    @Test func aFolderWithoutSettingsIsNotReadOnly() throws {
        let folder = try TemporaryFolder.exampleLibrary()
        try FileManager.default.removeItem(at: folder.url.appendingPathComponent("library.json"))
        let result = try folder.library.load()
        #expect(!result.report.settingsUnreadable)
        #expect(!result.report.isReadOnly)
        #expect(result.report.readOnlyReason == nil)
        try folder.library.checkWritable()

        // Creating a new library is unaffected.
        let empty = try TemporaryFolder()
        try empty.library.createLibrary(settings: LibrarySettings(baseCurrency: .chf))
        let created = try empty.library.load()
        #expect(!created.report.isReadOnly)
        #expect(created.library.settings.baseCurrency == .chf)
    }

    /// A newer app's settings may not decode here; that library is
    /// read-only because it's newer, and says so.
    @Test func aNewerLibraryWhoseSettingsDontDecodeSaysItIsNewer() throws {
        let folder = try TemporaryFolder.exampleLibrary()
        try folder.write("library.json", #"{ "baseCurrency": { "code": "CHF" }, "schemaVersion": 4 }"#)
        let report = try folder.library.load().report
        #expect(report.isReadOnly && report.isNewerSchema && !report.settingsUnreadable)
        #expect(report.readOnlyReason == .newerSchema)
        #expect(report.warnings.contains { $0.message.contains("newer version of the app") })
    }
}

/// The step from version 1 to 2: accounts can record trades, and nothing
/// but the version changes.
struct TradesMigrationTests {
    private let date = Date(timeIntervalSince1970: 1_790_000_000)  // 2026-09-21

    private func version1Library() throws -> TemporaryFolder {
        let folder = try TemporaryFolder.exampleLibrary()
        let settings = try folder.text("library.json").replacingOccurrences(of: "\"schemaVersion\": 3",
                                                                           with: "\"schemaVersion\": 1")
        try folder.write("library.json", settings)
        return folder
    }

    /// The example library's files are already in the newest form, so the
    /// step to 3 changes nothing either.
    @Test func aVersion1LibraryIsUpgradedWithOnlyItsVersionChanged() throws {
        let folder = try version1Library()
        let loaded = try folder.library.load()
        #expect(loaded.report.needsMigration)
        #expect(throws: StorageError.libraryNeedsMigration(version: 1, current: 3)) {
            try folder.library.checkWritable()
        }

        let report = try #require(try folder.library.migrate(date: date))
        #expect(report.fromVersion == 1)
        #expect(report.toVersion == 3)
        #expect(report.steps == [Migration.tradesAccounts.summary, Migration.simplePlans.summary])
        #expect(report.written == ["library.json"])
        #expect(report.deleted.isEmpty)
        #expect(report.backup.name == "\(CalendarDate(date, in: .current))-v1")
        // Every other file is byte for byte what it was.
        for path in Fixtures.allJSONFiles {
            #expect(try folder.data(path) == Fixtures.data(for: path), "\(path)")
        }
        let after = try folder.library.load()
        #expect(after.report.issues.isEmpty)
        #expect(after.library == (try Fixtures.exampleLibrary()))
    }

    /// Opening a library to work on it upgrades an older one first.
    @Test func loadingMigratesAnOlderLibraryFirst() throws {
        let folder = try version1Library()
        let (result, migration) = try folder.library.loadMigrating()
        #expect(migration?.fromVersion == 1)
        #expect(migration?.toVersion == 3)
        #expect(result.report.schemaVersion == 3)
        #expect(result.report.issues.isEmpty)
        #expect(try folder.library.loadMigrating().migration == nil)
    }
}

struct MigrationTests {
    private let date = Date(timeIntervalSince1970: 1_790_000_000)  // 2026-09-21

    /// A made-up step from version 3 to 4 that renames `notes` to `comment`
    /// in accounts and drops the import profiles.
    private let renameNotes = Migration(from: 3, summary: "Rename notes to comment") { files in
        for (path, json) in files where path.hasPrefix("accounts/") {
            guard case .object(var members) = json, let notes = members.removeValue(forKey: "notes") else { continue }
            members["comment"] = notes
            files[path] = .object(members)
        }
        for path in files.keys where path.hasPrefix("imports/") {
            files[path] = nil
        }
    }

    @Test func stepsRunAfterABackupOfTheWholeLibrary() throws {
        let folder = try TemporaryFolder.exampleLibrary()
        try folder.write("README.md", "Readme")
        let report = try #require(try folder.library.migrate(to: 4, steps: [renameNotes], date: date))

        let day = CalendarDate(date, in: .current)
        #expect(report.backup.name == "\(day)-v3")
        #expect(report.backup.files.count == Fixtures.allJSONFiles.count + 1)
        for path in Fixtures.allJSONFiles {
            #expect(try folder.data("backups/\(day)-v3/\(path)") == Fixtures.data(for: path))
        }
        #expect(report.fromVersion == 3)
        #expect(report.toVersion == 4)
        #expect(report.steps == ["Rename notes to comment"])
        #expect(report.written == [
            "accounts/casa.json", "accounts/gold-coins.json", "accounts/mutuo-casa.json", "library.json",
        ])
        #expect(report.deleted == ["imports/directa-movimenti.json", "imports/net-worth-sheet.json"])
        #expect(try folder.json("library.json")["schemaVersion"] == 4)
        #expect(try folder.json("accounts/casa.json")["comment"] == "Made-up estimate of the home's market value.")
        #expect(!folder.exists("imports/net-worth-sheet.json"))
        #expect(try folder.library.backups().map(\.name) == ["\(day)-v3"])
    }

    @Test func aMissingStepThrowsAndChangesNothing() throws {
        let folder = try TemporaryFolder.exampleLibrary()
        #expect(throws: StorageError.missingMigration(from: 4)) {
            try folder.library.migrate(to: 5, steps: [renameNotes], date: date)
        }
        #expect(try folder.json("library.json")["schemaVersion"] == 3)
        #expect(!folder.exists("backups"))
    }

    @Test func aFailingStepChangesNothing() throws {
        struct Failure: Error {}
        let folder = try TemporaryFolder.exampleLibrary()
        let failing = Migration(from: 3, summary: "Fails") { _ in throw Failure() }
        #expect(throws: Failure.self) { try folder.library.migrate(to: 4, steps: [failing], date: date) }
        #expect(try folder.json("library.json")["schemaVersion"] == 3)
    }

    @Test func aNewerLibraryIsNotMigrated() throws {
        let folder = try TemporaryFolder.exampleLibrary()
        try folder.write("library.json", #"{ "baseCurrency": "EUR", "schemaVersion": 5 }"#)
        #expect(throws: StorageError.libraryIsNewer(version: 5, supported: 3)) { try folder.library.migrate() }
    }

    @Test func anOlderLibraryMustBeMigratedBeforeSaving() throws {
        let folder = try TemporaryFolder.exampleLibrary()
        try folder.write("library.json", #"{ "baseCurrency": "EUR", "schemaVersion": 0 }"#)
        let result = try folder.library.load()
        #expect(result.report.needsMigration)
        #expect(throws: StorageError.libraryNeedsMigration(version: 0, current: 3)) {
            try folder.library.checkWritable()
        }

        let step = Migration(from: 0, summary: "Nothing to change") { _ in }
        let report = try #require(try folder.library.migrate(steps: [step] + Migration.all, date: date))
        #expect(report.steps == ["Nothing to change", Migration.tradesAccounts.summary, Migration.simplePlans.summary])
        #expect(report.written == ["library.json"])
        #expect(try folder.library.load().report.issues.isEmpty)
        try folder.library.checkWritable()
    }
}

/// The step from version 2 to 3: plans lose their tax systems (PLANNER.md),
/// accounts their tax wrappers, instruments their tax overrides.
struct SimplePlansMigrationTests {
    private let date = Date(timeIntervalSince1970: 1_790_000_000)  // 2026-09-21

    /// The example library as version 2 wrote it, in part: a plan on the
    /// Italian system then the generic one, accounts with wrappers.
    private func version2Library() throws -> TemporaryFolder {
        let folder = try TemporaryFolder.exampleLibrary()
        try folder.write("library.json", """
            {
              "baseCurrency": "EUR",
              "mainPlan": "base",
              "person": { "birthDate": "1988-04-12", "citizenships": ["IT"], "name": "Alex Example" },
              "schemaVersion": 2,
              "taxResidence": "IT"
            }
            """)
        try folder.write("plans/base.json", """
            {
              "contributions": [
                { "account": "fondo-pensione", "perYear": "5000", "until": "retirement" },
                { "amount": "20000", "pension": "ch.bvg", "year": 2030 }
              ],
              "currency": "CHF",
              "events": [{ "age": 62, "amount": "150000", "kind": "inheritance", "name": "Inheritance" }],
              "id": "base",
              "name": "Base case",
              "pensions": [
                { "claim": 67, "options": { "montante": "92000" }, "scheme": "it.inps" },
                { "fromAge": 67, "name": "Abroad", "perYear": "4800", "scheme": "fixed", "taxedIn": "source" }
              ],
              "retirement": { "age": 55 },
              "spending": { "retired": "36000", "working": "36000" },
              "tax": {
                "indexThresholds": true,
                "residence": [
                  { "from": 2020, "system": "it" },
                  { "from": 2048, "options": { "capitalGainsRate": "0.28" }, "system": "generic" }
                ]
              },
              "withdrawals": { "cashBuffer": "10000", "strategy": "fixed-real" },
              "work": [
                { "from": "2026-01-01", "grossSalary": "65000", "kind": "employee", "regime": "it.employee", "until": "2028-12-31" },
                { "from": "2029-01-01", "kind": "net", "netIncome": "18000", "until": "retirement" }
              ]
            }
            """)
        try folder.write("accounts/fondo-pensione.json", """
            {
              "currency": "EUR",
              "id": "fondo-pensione",
              "kind": "pensionFund",
              "name": "Fondo pensione",
              "opened": "2022-01-01",
              "tax": { "joined": "2022-01-01", "wrapper": "it.pensionFund" }
            }
            """)
        try folder.write("instruments/vwce.json", """
            {
              "assetClasses": { "equity": "1" },
              "currency": "EUR",
              "id": "vwce",
              "kind": "etf",
              "name": "Vanguard FTSE All-World UCITS ETF (Acc)",
              "tax": { "fundType": "equity" },
              "unit": "share"
            }
            """)
        return folder
    }

    @Test func plansAccountsAndInstrumentsLoseTheirTaxSystems() throws {
        let folder = try version2Library()
        let report = try #require(try folder.library.migrate(date: date))
        #expect(report.steps == [Migration.simplePlans.summary])
        #expect(report.written == ["accounts/fondo-pensione.json", "instruments/vwce.json", "library.json",
                                   "plans/base.json"])

        let plan = try folder.json("plans/base.json")
        // Italy, in force this year: 26% on investments, the 0.2% stamp duty as a wealth tax.
        #expect(plan["tax"] == ["investmentRate": "0.26", "wealthRate": "0.002"])
        #expect(plan["withdrawals"] == nil && plan["currency"] == nil)
        #expect(plan["name"] == "Base case (amounts in CHF)")
        // A gross phase keeps its dates and says what it was; a net one stays.
        #expect(plan["work"] == [
            ["from": "2026-01-01", "name": "Employee, gross 65000 a year", "until": "2028-12-31"],
            ["from": "2029-01-01", "netIncome": "18000", "until": "retirement"],
        ])
        #expect(plan["pensions"] == [["fromAge": 67, "name": "Pension (it.inps)"],
                                     ["fromAge": 67, "name": "Abroad", "perYear": "4800"]])
        #expect(plan["contributions"] == [["account": "fondo-pensione", "perYear": "5000", "until": "retirement"]])
        #expect(plan["events"]?[0]?["kind"] == nil)

        let fund = try folder.json("accounts/fondo-pensione.json")
        #expect(fund["tax"] == nil && fund["availableFromAge"] == 67)
        #expect(try folder.json("instruments/vwce.json")["tax"] == nil)
        #expect(try folder.json("library.json")["person"] == ["birthDate": "1988-04-12", "name": "Alex Example"])

        // It opens cleanly, and the plan says what's missing.
        let loaded = try folder.library.load()
        #expect(loaded.report.issues.isEmpty)
        #expect(loaded.library.plans["base"]?.work[0].netIncome == nil)
    }

    @Test func genericRatesAreKeptAsWritten() throws {
        var tax: [String: JSONValue] = [:]
        (tax["investmentRate"], tax["wealthRate"]) = Migration.rates(
            system: "generic", options: ["capitalGainsRate": "0.28", "wealthTaxRate": "0.001"])
        #expect(tax == ["investmentRate": "0.28", "wealthRate": "0.001"])
        #expect(Migration.rates(system: "ch", options: [:]) == (nil, nil))
        #expect(Migration.availableFromAge(wrapper: "ch.pillar3a") == 60)
        #expect(Migration.availableFromAge(wrapper: "it.tfr") == nil)
    }
}
