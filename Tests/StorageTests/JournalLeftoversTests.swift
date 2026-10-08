import Foundation
import Model
import Storage
import Testing
import TestSupport

/// A library written by an earlier version, which imported ledger journals:
/// a profile with `"layout": "ledger"` and a `ledger` section, and records
/// with `"source": "ledger"`. This version doesn't import journals, but the
/// library still loads, and rewriting it keeps every byte.
struct JournalLeftoversTests {
    /// The journal's profile, as the earlier version wrote it.
    private static let profile = canonical("""
        {
          "id": "journal",
          "layout": "ledger",
          "ledger": {
            "cashChecks": true,
            "frequency": "quarter",
            "ignore": ["Assets:Receivables"],
            "returns": ["Expenses:Fees", "Income:Dividends"]
          },
          "matches": {
            "accounts": { "Assets:Bank:Fineco": "conto-fineco", "Assets:Broker:Directa": "directa" },
            "instruments": { "VWCE.MI": "vwce" }
          },
          "name": "My journal",
          "onConflict": "keep"
        }
        """)

    /// A month the journal wrote, as the earlier version wrote it.
    private static let month = """
        {
          "fx": [],
          "indices": [],
          "month": "2025-09",
          "prices": [
            { "currency": "EUR", "date": "2025-09-30", "instrument": "vwce", "price": "125.4", "source": "ledger" }
          ],
          "valuations": [
            { "account": "conto-fineco", "balance": "4700", "date": "2025-09-30", "source": "ledger" }
          ]
        }

        """

    private static func canonical(_ text: String) -> String {
        CanonicalJSON.string(for: try! CanonicalJSON.parse(Data(text.utf8)))
    }

    private func library() throws -> TemporaryFolder {
        let folder = try TemporaryFolder.exampleLibrary()
        try folder.write("imports/journal.json", Self.profile)
        try folder.write("history/2025/2025-09.json", Self.month)
        return folder
    }

    @Test func loadsWithoutIssues() throws {
        let folder = try library()
        let loaded = try folder.library.load()
        #expect(loaded.report.issues.isEmpty, "\(loaded.report.issues)")
        let profile = try #require(loaded.library.importProfiles["journal"])
        #expect(profile.layout.rawValue == "ledger")
        #expect(!profile.layout.isKnown)
        #expect(profile.matches.accounts["Assets:Bank:Fineco"] == "conto-fineco")
        #expect(profile.onConflict == .keep)
        #expect(loaded.library.prices(for: "vwce").first?.source == "ledger")
        #expect(loaded.library.valuations(for: "conto-fineco").first?.source == "ledger")
    }

    @Test func savingRewritesNothing() throws {
        let folder = try library()
        let library = try folder.library.load().library
        #expect(try folder.library.save(library).isEmpty)
        #expect(try folder.text("imports/journal.json") == Self.profile)
        #expect(try folder.text("history/2025/2025-09.json") == Self.month)
    }

    @Test func anEditKeepsTheLedgerSection() throws {
        let folder = try library()
        let loaded = try folder.library.load().library
        var renamed = loaded
        renamed.importProfiles["journal"]?.name = "Old journal"
        renamed.months["2025-09"]?.valuations[0].balance = 4710
        let report = try folder.library.save(renamed, previous: loaded)
        #expect(report.written == ["history/2025/2025-09.json", "imports/journal.json"])
        let written = try folder.json("imports/journal.json")
        #expect(written["name"] == "Old journal")
        #expect(written["layout"] == "ledger")
        #expect(written["ledger"] == (try CanonicalJSON.parse(Data(Self.profile.utf8)))["ledger"])
        #expect(try folder.json("history/2025/2025-09.json")["valuations"]?[0]?["source"] == "ledger")

        // Named back, the profile is the earlier version's file byte for byte.
        var restored = renamed
        restored.importProfiles["journal"]?.name = "My journal"
        restored.months["2025-09"]?.valuations[0].balance = 4700
        try folder.library.save(restored, previous: renamed)
        #expect(try folder.text("imports/journal.json") == Self.profile)
        #expect(try folder.text("history/2025/2025-09.json") == Self.month)
    }
}
