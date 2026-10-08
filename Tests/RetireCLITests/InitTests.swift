import Foundation
import Model
import Storage
import Testing
import TestSupport

struct InitTests {
    @Test func createsALibraryWithTheSettings() async throws {
        let folder = try TemporaryFolder()
        let path = folder.url("My Library").path
        let run = await retire(["init", path, "--birth-date", "1990-05-01", "--currency", "eur",
                                "--residence", "it", "--name", "Alex"])
        #expect(run.status == 0, "\(run.all)")
        #expect(run.output.hasPrefix("Created a new library in \(path)\n"))
        #expect(run.output.contains("  Base currency  EUR\n"))
        #expect(run.output.contains("  Country        IT\n"))
        #expect(run.output.contains("retire import <file> --library \"\(path)\""))

        let loaded = try LibraryFolder(root: URL(fileURLWithPath: path)).load()
        #expect(loaded.report.issues.isEmpty)
        #expect(loaded.library.settings == LibrarySettings(
            baseCurrency: .eur, person: Person(name: "Alex", birthDate: "1990-05-01"), taxResidence: .it))
        for folderName in ["accounts", "instruments", "history", "plans"] {
            #expect(folder.exists("My Library/\(folderName)"))
        }
        #expect(folder.exists("My Library/README.md"))

        // A fresh library validates cleanly.
        let validate = await retire(["validate", "--library", path])
        #expect(validate.status == 0)
        #expect(validate.output.contains("No problems found."))
    }

    @Test func takesTheFolderFromTheEnvironment() async throws {
        let folder = try TemporaryFolder()
        let run = await retire(["init", "--currency", "chf"], environment: ["RETIRE_LIBRARY": folder.url("lib").path])
        #expect(run.status == 0, "\(run.all)")
        #expect(folder.exists("lib/library.json"))
        let settings = try LibraryFolder(root: folder.url("lib")).load().library.settings
        #expect(settings.baseCurrency == .chf)
        #expect(settings.person == nil)
        #expect(settings.taxResidence == nil)
    }

    @Test func theCurrencyIsAskedForNotAssumed() async throws {
        let folder = try TemporaryFolder()
        let run = await retire(["init", folder.path])
        #expect(run.status == 64)
        #expect(run.errors.contains("--currency"))
        #expect(!folder.exists("library.json"))
    }

    @Test func refusesAnExistingLibraryOrAFolderWithFiles() async throws {
        let library = try TemporaryFolder.exampleLibrary()
        let existing = await retire(["init", library.path, "--currency", "EUR"])
        #expect(existing.status == 1)
        #expect(existing.errors.contains("There is already a library at \(library.path)."))

        let folder = try TemporaryFolder()
        try folder.write("notes.txt", "hello")
        let notEmpty = await retire(["init", folder.path, "--currency", "EUR"])
        #expect(notEmpty.status == 1)
        #expect(notEmpty.errors.contains("isn't empty"))
        #expect(!folder.exists("library.json"))
    }

    @Test func rejectsBadOptions() async throws {
        let folder = try TemporaryFolder()
        let date = await retire(["init", folder.path, "--currency", "EUR", "--birth-date", "12/04/1988"])
        #expect(date.status == 64)
        #expect(date.errors.contains("--birth-date must be a date written YYYY-MM-DD"))
        let currency = await retire(["init", folder.path, "--currency", "euro"])
        #expect(currency.status == 64)
        let nowhere = await retire(["init", "--currency", "EUR"])
        #expect(nowhere.status == 1)
        #expect(nowhere.errors.contains("retire init <path>"))
        #expect(!folder.exists("library.json"))
    }
}
