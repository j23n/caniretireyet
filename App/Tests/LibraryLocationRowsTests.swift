import CloudSync
import Foundation
import Testing
@testable import CanIRetireYet

/// *Show in Files* and *Show in Finder* (UI.md, "Settings"): the Files app's
/// URL for the library folder, and where the rows say the library is.
@MainActor
struct LibraryLocationRowsTests {
    @Test func theFilesURLIsTheFoldersPathPercentEncoded() throws {
        let container = "iCloud~com~j23n~caniretireyet"
        let folder = URL(
            fileURLWithPath: "/private/var/mobile/Library/Mobile Documents/\(container)/Documents", isDirectory: true)
        let url = try #require(LibraryLocationRows.filesAppURL(for: folder))
        #expect(url.absoluteString
            == "shareddocuments:///private/var/mobile/Library/Mobile%20Documents/\(container)/Documents/")
        #expect(LibraryLocationRows.filesAppURL(for: try #require(URL(string: "https://example.com"))) == nil)
    }

    @Test func anICloudLibraryIsInTheFolderNamedAfterTheApp() {
        let location = LibraryLocation(kind: .iCloud, url: URL(fileURLWithPath: "/tmp/Documents", isDirectory: true))
        #expect(LibraryLocationRows.canShow(location))
        #expect(LibraryLocationRows.whereText(location) == "In Files and Finder: iCloud Drive › Last Monday.")
    }

    /// Finder can show a library on this Mac; Files can't show one on an
    /// iPhone or iPad, in Application Support.
    @Test func aLibraryOnTheMacCanBeShown() {
        let location = LibraryLocation(kind: .local, url: URL(fileURLWithPath: "/tmp/Library", isDirectory: true))
        #if os(macOS)
        #expect(LibraryLocationRows.canShow(location))
        #expect(LibraryLocationRows.whereText(location) == nil)
        #else
        #expect(!LibraryLocationRows.canShow(location))
        #expect(LibraryLocationRows.whereText(location) != nil)
        #endif
    }
}
