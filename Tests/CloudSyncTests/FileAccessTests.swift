import CloudSync
import Foundation
import Storage
import Testing

/// Coordinated file access, and files iCloud hasn't downloaded yet.
struct FileAccessTests {
    @Test func placeholderNamesMapToRealNames() {
        #expect(ICloudPlaceholder.placeholderName(for: "directa.json") == ".directa.json.icloud")
        #expect(ICloudPlaceholder.realName(forPlaceholder: ".directa.json.icloud") == "directa.json")
        #expect(ICloudPlaceholder.realName(forPlaceholder: "directa.json") == nil)
        #expect(ICloudPlaceholder.realName(forPlaceholder: ".DS_Store") == nil)
        #expect(ICloudPlaceholder.realName(forPlaceholder: "..icloud") == nil)
        #expect(ICloudPlaceholder.realPath(forPlaceholderPath: "accounts/.directa.json.icloud") == "accounts/directa.json")
        #expect(ICloudPlaceholder.realPath(forPlaceholderPath: ".hidden/.a.json.icloud") == nil)
    }

    @Test func listingIncludesFilesThatAreNotDownloaded() throws {
        let folder = try TemporaryFolder()
        try folder.write("accounts/casa.json", "{}")
        try folder.write("accounts/.directa.json.icloud", "placeholder")
        try folder.write("accounts/.DS_Store", "")
        try folder.write(".Trash/old.json", "{}")
        try folder.write("history/2026/.2026-09.json.icloud", "placeholder")

        let access = CoordinatedFileAccess()
        #expect(try access.listFiles(in: folder.url) == [
            "accounts/casa.json", "accounts/directa.json", "history/2026/2026-09.json",
        ])
        #expect(access.fileExists(at: folder.url("accounts/directa.json")))
        #expect(!access.fileExists(at: folder.url("accounts/tfr.json")))
        #expect(try access.modificationDate(of: folder.url("accounts/directa.json")) <= Date())
        #expect(try access.listFiles(in: folder.url("missing")) == [])
    }

    @Test func readsWritesAndDeletes() throws {
        let folder = try TemporaryFolder()
        let access = CoordinatedFileAccess()
        let url = folder.url("plans/base.json")

        try access.writeData(Data("one".utf8), to: url)
        #expect(try access.readData(at: url) == Data("one".utf8))
        try access.writeData(Data("two".utf8), to: url)
        #expect(try folder.text("plans/base.json") == "two")

        try access.removeItem(at: url)
        #expect(!folder.exists("plans/base.json"))
        try access.removeItem(at: url) // nothing to delete

        try folder.write("plans/.old.json.icloud", "placeholder")
        try access.removeItem(at: folder.url("plans/old.json"))
        #expect(!folder.exists("plans/.old.json.icloud"))

        try access.createDirectory(at: folder.url("imports"))
        #expect(folder.exists("imports"))
    }

    @Test func replacesOnlyWhatWasRead() throws {
        let folder = try TemporaryFolder()
        let access = CoordinatedFileAccess()
        let url = folder.url("accounts/casa.json")
        let one = Data("one".utf8)
        let two = Data("two".utf8)

        #expect(try access.replaceData(at: url, ifContentsAre: nil, with: one))
        #expect(try !access.replaceData(at: url, ifContentsAre: nil, with: two), "the file exists now")
        #expect(try !access.replaceData(at: url, ifContentsAre: two, with: two))
        #expect(try folder.text("accounts/casa.json") == "one")
        #expect(try access.replaceData(at: url, ifContentsAre: one, with: two))
        #expect(try folder.text("accounts/casa.json") == "two")
        #expect(try access.replaceData(at: url, ifContentsAre: two, with: nil))
        #expect(!folder.exists("accounts/casa.json"))

        // A file that is only a placeholder is read (downloaded) first.
        try folder.write("accounts/.tfr.json.icloud", "placeholder")
        #expect(try !access.replaceData(at: folder.url("accounts/tfr.json"), ifContentsAre: nil, with: one))
    }

    @Test func storageLoadsThroughCoordinatedAccess() throws {
        let folder = try TemporaryFolder.exampleLibrary()
        let loaded = try LibraryFolder(root: folder.url, files: CoordinatedFileAccess()).load()
        #expect(loaded.library.accounts.count == 10)
        #expect(loaded.report.errors.isEmpty)
    }
}
