import Foundation
import Model
import Storage
import Testing

struct NewLibraryTests {
    @Test func createsAnEmptyLibraryWithAReadme() throws {
        let parent = try TemporaryFolder()
        let folder = LibraryFolder(root: parent.url.appendingPathComponent("Can I Retire Yet"))
        let settings = LibrarySettings(person: Person(name: "Sam Sample"), taxResidence: .it)
        try folder.createLibrary(settings: settings)

        #expect(try parent.allFiles() == ["Can I Retire Yet/README.md", "Can I Retire Yet/library.json"])
        for name in LibraryFolder.initialFolders {
            #expect(parent.exists("Can I Retire Yet/\(name)"))
        }
        #expect(try parent.text("Can I Retire Yet/library.json") == """
            {
              "baseCurrency": "EUR",
              "person": { "name": "Sam Sample" },
              "schemaVersion": 1,
              "taxResidence": "IT"
            }

            """)
        #expect(try parent.text("Can I Retire Yet/README.md") == LibraryFolder.readme)

        let result = try folder.load()
        #expect(result.report.issues.isEmpty)
        #expect(result.library == Library(settings: settings))
        #expect(folder.containsLibrary)
    }

    @Test func doesNotOverwriteAnExistingLibrary() throws {
        let folder = try TemporaryFolder()
        try folder.library.createLibrary()
        #expect(throws: StorageError.libraryAlreadyExists(path: folder.url.path)) { try folder.library.createLibrary() }
    }

    @Test func theReadmeExplainsTheFolder() throws {
        let readme = LibraryFolder.readme
        for topic in ["library.json", "accounts/", "instruments/", "history/YYYY/YYYY-MM.json", "plans/", "projections/",
                      "imports/", "backups/", "schemaVersion"] {
            #expect(readme.contains(topic), "\(topic)")
        }
        #expect(readme.hasSuffix("\n"))
        #expect(!readme.contains("\\"))
    }

    @Test func updateReadmeWritesOnlyWhenItDiffers() throws {
        let folder = try TemporaryFolder()
        try folder.library.createLibrary()
        #expect(try folder.library.updateReadme() == false)
        try folder.write("README.md", "old text")
        #expect(try folder.library.updateReadme() == true)
        #expect(try folder.text("README.md") == LibraryFolder.readme)
    }
}
