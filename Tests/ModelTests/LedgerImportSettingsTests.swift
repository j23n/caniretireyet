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

/// A trades import profile: `layout: "trades"`, fields per column, and the
/// file's type words in `tradeTypes`.
struct TradesImportProfileTests {
    @Test func tradesProfileRoundTrips() throws {
        let json = """
            {
              "columns": [
                { "field": "date", "header": "Data operazione" },
                { "field": "type", "header": "Tipo operazione" },
                { "field": "instrument", "header": "ISIN" },
                { "field": "quantity", "header": "Quantità" },
                { "field": "price", "header": "Prezzo" },
                { "field": "amount", "format": { "amountSign": "asWritten" }, "header": "Importo euro" },
                { "field": "gross", "header": "Controvalore" },
                { "field": "fees", "header": "Commissioni" },
                { "field": "tax", "header": "Ritenuta" },
                { "field": "ratio", "header": "Rapporto" },
                { "field": "note", "header": "Descrizione" }
              ],
              "constants": { "account": "directa" },
              "defaults": { "amountSign": "fromType" },
              "id": "directa",
              "layout": "trades",
              "name": "Directa",
              "tradeTypes": { "Acquisto": "buy", "Rimborso": "ignore", "Vendita": "sell" }
            }
            """
        let profile = try JSONDecoder().decode(ImportProfile.self, from: Data(json.utf8))
        #expect(profile.layout == .trades)
        #expect(profile.layout.isKnown)
        #expect(profile.tradeTypes == ["Acquisto": .buy, "Rimborso": "ignore", "Vendita": .sell])
        #expect(profile.defaults.amountSign == .fromType)
        #expect(profile.columns.map(\.field) == [.date, .type, .instrument, .quantity, .price, .amount, .gross,
                                                 .fees, .tax, .ratio, .note])
        #expect(profile.columns.compactMap(\.field).allSatisfy { $0.isKnown })
        #expect(profile.columns[5].format?.amountSign == .asWritten)

        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let again = try JSONDecoder().decode(ImportProfile.self, from: encoder.encode(profile))
        #expect(again == profile)
        // Without trade types, the key stays out of the file.
        var plain = profile
        plain.tradeTypes = [:]
        #expect(try JSONValue(encoding: plain)["tradeTypes"] == nil)
    }

    @Test func cashChecksAreOffByDefault() throws {
        #expect(!LedgerImportSettings().effectiveCashChecks)
        let settings = LedgerImportSettings(cashChecks: true)
        #expect(settings.effectiveCashChecks)
        #expect(try JSONValue(encoding: settings) == ["cashChecks": true])
        #expect(TradeAmountSign.knownValues == [.auto, .fromType, .asWritten])
    }
}
