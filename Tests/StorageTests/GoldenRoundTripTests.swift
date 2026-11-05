import Foundation
import Model
import Storage
import Testing
import TestSupport

/// Load the example library, save it into an empty folder, and every file
/// must come out byte for byte the same as the fixture.
struct GoldenRoundTripTests {
    @Test func exampleLibraryLoadsWithoutIssues() throws {
        let result = try LibraryFolder(root: Fixtures.exampleLibraryURL).load()
        #expect(result.report.issues.isEmpty, "\(result.report.issues)")
        #expect(result.report.schemaVersion == LibrarySettings.currentSchemaVersion)
        #expect(result.report.readOnlyReason == nil)
        #expect(result.report.filesRead == Fixtures.allJSONFiles.count)
        #expect(result.library == (try Fixtures.exampleLibrary()))
    }

    @Test func savingTheExampleLibraryReproducesEveryFile() throws {
        let library = try LibraryFolder(root: Fixtures.exampleLibraryURL).load().library
        let output = try TemporaryFolder()
        let report = try output.library.save(library, previous: Library())

        #expect(report.written == Fixtures.allJSONFiles.sorted())
        #expect(report.deleted.isEmpty)
        #expect(try output.allFiles() == Fixtures.allJSONFiles)
        for path in Fixtures.allJSONFiles {
            let expected = String(decoding: try Fixtures.data(for: path), as: UTF8.self)
            let actual = try output.text(path)
            #expect(actual == expected, "\(path) differs from the fixture")
        }
    }

    /// Each reference ledger is a library as the app writes it: it loads
    /// without issues, as the tests read it, and saving it gives its files
    /// back byte for byte.
    @Test(arguments: ReferenceLedger.allCases)
    func referenceLedgersRoundTrip(_ ledger: ReferenceLedger) throws {
        let result = try LibraryFolder(root: ledger.url).load()
        #expect(result.report.issues.isEmpty, "\(result.report.issues)")
        #expect(result.report.filesRead == ledger.allJSONFiles.count)
        #expect(result.library == (try ledger.library()))

        let output = try TemporaryFolder()
        _ = try output.library.save(result.library, previous: Library())
        let written = try output.allFiles()
        // library.json with the default settings isn't written again.
        #expect(written == ledger.allJSONFiles.filter { $0 != "library.json" })
        for path in written {
            let expected = String(decoding: try ledger.data(for: path), as: UTF8.self)
            #expect(try output.text(path) == expected, "\(ledger.rawValue)/\(path) differs from the ledger")
        }
    }

    @Test func savingAgainChangesNothing() throws {
        let folder = try TemporaryFolder.exampleLibrary()
        let library = try folder.library.load().library
        #expect(try folder.library.save(library, previous: Library()).isEmpty)
        #expect(try folder.library.save(library, previous: library).isEmpty)
    }
}
