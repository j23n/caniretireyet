import Foundation
import Model
import Testing

/// A ledger import profile: `layout: "ledger"` with a `ledger` section.
struct LedgerImportSettingsTests {
    @Test func minimalLedgerProfileUsesTheDefaults() throws {
        let json = #"{ "id": "journal", "layout": "ledger", "name": "My journal" }"#
        let profile = try JSONDecoder().decode(ImportProfile.self, from: Data(json.utf8))
        #expect(profile.isLedger)
        #expect(profile.ledger == nil)
        let settings = profile.ledger ?? LedgerImportSettings()
        #expect(settings.effectiveRoots == LedgerImportSettings.defaultRoots)
        #expect(settings.effectiveRoots.contains("Attività"))
        #expect(settings.effectiveFrequency == .month)
        #expect(settings.effectiveTransactionPrices)
    }

    @Test func ledgerSectionRoundTrips() throws {
        let json = """
            {
              "id": "journal",
              "layout": "ledger",
              "ledger": {
                "frequency": "quarter",
                "ignore": ["Assets:Receivables"],
                "returns": ["Income:Dividends", "Expenses:Fees"],
                "transactionPrices": false
              },
              "matches": { "accounts": { "Assets:Broker:Directa": "directa" }, "instruments": { "VWCE.MI": "vwce" } },
              "name": "My journal"
            }
            """
        let profile = try JSONDecoder().decode(ImportProfile.self, from: Data(json.utf8))
        let settings = try #require(profile.ledger)
        #expect(settings.effectiveFrequency == .quarter)
        #expect(settings.ignore == ["Assets:Receivables"])
        #expect(settings.returns == ["Income:Dividends", "Expenses:Fees"])
        #expect(!settings.effectiveTransactionPrices)
        #expect(profile.matches.accounts["Assets:Broker:Directa"] == "directa")

        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let again = try JSONDecoder().decode(ImportProfile.self, from: encoder.encode(profile))
        #expect(again == profile)
        // Empty lists and absent options stay out of the file.
        let written = try JSONValue(encoding: LedgerImportSettings(frequency: .activity))
        #expect(written.objectValue?.keys.sorted() == ["frequency"])
    }

    @Test func newOpenEnumValuesAreKnown() {
        #expect(ImportLayout.ledger.isKnown)
        #expect(DataSource.ledger.isKnown)
        #expect(LedgerSnapshotFrequency.knownValues == [.month, .quarter, .activity])
        #expect(!LedgerSnapshotFrequency("weekly").isKnown)
    }
}
