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
        #expect(result.report.schemaVersion == 3)
        #expect(!result.report.isReadOnly)
        #expect(result.report.filesRead == Fixtures.allJSONFiles.count)
        #expect(result.library == (try Fixtures.exampleLibrary()))
    }

    @Test func savingTheExampleLibraryReproducesEveryFile() throws {
        let library = try LibraryFolder(root: Fixtures.exampleLibraryURL).load().library
        let output = try TemporaryFolder()
        let report = try output.library.save(library)

        #expect(report.written == Fixtures.allJSONFiles.sorted())
        #expect(report.deleted.isEmpty)
        #expect(try output.allFiles() == Fixtures.allJSONFiles)
        for path in Fixtures.allJSONFiles {
            let expected = String(decoding: try Fixtures.data(for: path), as: UTF8.self)
            let actual = try output.text(path)
            #expect(actual == expected, "\(path) differs from the fixture")
        }
    }

    @Test func savingAgainChangesNothing() throws {
        let folder = try TemporaryFolder.exampleLibrary()
        let library = try folder.library.load().library
        #expect(try folder.library.save(library).isEmpty)
        #expect(try folder.library.save(library, previous: library).isEmpty)
    }
}
