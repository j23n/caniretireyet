import Foundation
import Model
import Testing
import TestSupport

/// Which inflation index a library uses (docs/schema,
/// library.schema.json: `inflationIndex`), and which one goes with a currency. All made up.
struct InflationIndicesTests {
    private func library(currency: CurrencyCode, residence: CountryCode? = nil, index: IndexID? = nil) -> Library {
        var library = Library()
        library.settings = LibrarySettings(baseCurrency: currency, taxResidence: residence, inflationIndex: index)
        return library
    }

    @Test func everyCountryWithAnHICPHasAnIndex() {
        #expect(IndexID.hicp(.de) == "hicp-de")
        #expect(IndexID.hicp("ch") == "hicp-ch")
        #expect(IndexID.hicp(.it) == .hicpIT)
        #expect(IndexID.hicp("GR") == "hicp-gr")
        #expect(IndexID.hicp(.us) == nil)
        #expect(IndexID.hicp(.gb) == nil)
        #expect(IndexID.hicpCountries.count == 35)
        #expect(IndexID.hicpCountries == IndexID.hicpCountries.sorted())
        #expect(Set(IndexID.hicpCountries).isSuperset(of: [.it, .de, .fr, .es, .pt, .nl, .ie, .ch, "NO", "IS", "SE"]))
    }

    @Test func anIndexKnowsItsAreaAndCurrency() {
        #expect(IndexID.hicpIT.hicpArea == "IT" && IndexID.hicpIT.hicpCurrency == .eur)
        #expect(IndexID.hicpEA.hicpArea == "EA" && IndexID.hicpEA.hicpCurrency == .eur)
        #expect(IndexID("hicp-ch").hicpCurrency == .chf)
        #expect(IndexID("hicp-se").hicpCurrency == "SEK")
        #expect(IndexID("hicp-bg").hicpCurrency == .eur)
        #expect(IndexID("hicp-us").hicpArea == nil)
        #expect(IndexID("cpi-us").hicpCurrency == nil)
    }

    @Test func aCurrencyHasTheHICPOfItsArea() {
        #expect(IndexID.hicp(currency: .eur) == .hicpEA)
        #expect(IndexID.hicp(currency: .chf) == "hicp-ch")
        #expect(IndexID.hicp(currency: "nok") == "hicp-no")
        #expect(IndexID.hicp(currency: "PLN") == "hicp-pl")
        #expect(IndexID.hicp(currency: .usd) == nil)
        #expect(IndexID.hicp(currency: .gbp) == nil)
    }

    @Test func theUSAndTheUKHaveANationalCPI() {
        #expect(IndexID.cpi(.us) == .cpiUS && IndexID.cpi("gb") == .cpiGB)
        #expect(IndexID.cpi(.de) == nil)
        #expect(IndexID.cpiCountries == [.gb, .us])
        #expect(IndexID.cpiUS.rawValue == "cpi-us" && IndexID.cpiGB.rawValue == "cpi-gb")
        #expect(IndexID.cpiUS.cpiArea == "US" && IndexID.cpiGB.cpiArea == "GB")
        #expect(IndexID.cpiUS.hicpArea == nil && IndexID.hicpIT.cpiArea == nil)
    }

    @Test func everyCountryWithAnIndex() {
        #expect(IndexID.consumerPrices(.it) == .hicpIT)
        #expect(IndexID.consumerPrices("us") == .cpiUS)
        #expect(IndexID.consumerPrices(.gb) == .cpiGB)
        #expect(IndexID.consumerPrices("JP") == nil)
        #expect(IndexID.consumerPriceCountries.count == 37)
        #expect(IndexID.consumerPriceCountries == IndexID.consumerPriceCountries.sorted())
        #expect(Set(IndexID.consumerPriceCountries).isSuperset(of: [.it, .ch, .gb, .us]))
    }

    @Test func everyIndexKnowsItsAreaAndCurrency() {
        #expect(IndexID.cpiUS.priceArea == "US" && IndexID.cpiUS.priceCurrency == .usd)
        #expect(IndexID.cpiGB.priceArea == "GB" && IndexID.cpiGB.priceCurrency == .gbp)
        #expect(IndexID.hicpIT.priceArea == "IT" && IndexID.hicpIT.priceCurrency == .eur)
        #expect(IndexID.hicpEA.priceArea == "EA" && IndexID("hicp-ch").priceCurrency == .chf)
        #expect(IndexID("cpi-jp").priceArea == nil && IndexID("cpi-jp").priceCurrency == nil)
    }

    @Test func aCurrencyHasTheIndexOfItsCountry() {
        #expect(IndexID.consumerPrices(currency: .eur) == .hicpEA)
        #expect(IndexID.consumerPrices(currency: .chf) == "hicp-ch")
        #expect(IndexID.consumerPrices(currency: .usd) == .cpiUS)
        #expect(IndexID.consumerPrices(currency: "gbp") == .cpiGB)
        #expect(IndexID.consumerPrices(currency: "JPY") == nil)
    }

    @Test func aLibraryInDollarsCountsOnlyIndicesInDollars() {
        var library = self.library(currency: .usd)
        library.upsert(IndexRecord(index: .cpiUS, date: "2026-08-31", value: 320))
        library.upsert(IndexRecord(index: .hicpEA, date: "2026-08-31", value: 100))
        library.upsert(IndexRecord(index: .hicpEA, date: "2026-07-31", value: 100))
        // The euro area's index isn't in dollars, so it doesn't count.
        #expect(library.effectiveInflationIndex == .cpiUS)
    }

    @Test func theLibrarysIndexFollowsItsSettings() {
        // The tax residence's HICP first, then the base currency's.
        #expect(library(currency: .eur, residence: .it).effectiveInflationIndex == .hicpIT)
        #expect(library(currency: .eur, residence: .de).effectiveInflationIndex == "hicp-de")
        #expect(library(currency: .chf, residence: .ch).effectiveInflationIndex == "hicp-ch")
        #expect(library(currency: .eur).effectiveInflationIndex == .hicpEA)
        #expect(library(currency: .chf).effectiveInflationIndex == "hicp-ch")
        #expect(library(currency: .eur, residence: "JP").effectiveInflationIndex == .hicpEA)
        #expect(library(currency: .eur, residence: .us).effectiveInflationIndex == .cpiUS)
        #expect(library(currency: .usd, residence: .us).effectiveInflationIndex == .cpiUS)
        #expect(library(currency: .gbp, residence: .gb).effectiveInflationIndex == .cpiGB)
        #expect(library(currency: .usd).effectiveInflationIndex == .cpiUS)
        #expect(library(currency: .gbp, residence: "JP").effectiveInflationIndex == .cpiGB)
        #expect(library(currency: "JPY", residence: "JP").effectiveInflationIndex == nil)
        // The setting wins, whatever it is.
        #expect(library(currency: .eur, residence: .it, index: .hicpEA).effectiveInflationIndex == .hicpEA)
        #expect(library(currency: .usd, residence: .us, index: .hicpEA).effectiveInflationIndex == .hicpEA)
    }

    @Test func aLibraryWithoutAResidenceKeepsTheIndexItRecorded() {
        var library = self.library(currency: .eur)
        for month in ["2026-07-31", "2026-08-31"] {
            library.upsert(IndexRecord(index: .hicpIT, date: CalendarDate(month)!, value: 100))
        }
        library.upsert(IndexRecord(index: .hicpEA, date: "2026-08-31", value: 100))
        // A franc index recorded for a plan doesn't count for a library in euros.
        for month in ["2026-06-30", "2026-07-31", "2026-08-31"] {
            library.upsert(IndexRecord(index: "hicp-ch", date: CalendarDate(month)!, value: 100))
        }
        #expect(library.effectiveInflationIndex == .hicpIT)
        library.settings.taxResidence = .de
        #expect(library.effectiveInflationIndex == "hicp-de")
    }

    @Test func theExampleLibraryUsesItalysIndex() throws {
        let library = try Fixtures.exampleLibrary()
        #expect(library.settings.inflationIndex == nil)
        #expect(library.effectiveInflationIndex == .hicpIT)
        #expect(library.inflationIndices == [.hicpIT])
    }

    @Test func aCurrencyGetsTheIndexOfItsArea() {
        let italy = library(currency: .eur, residence: .it)
        #expect(italy.inflationIndex(for: .eur) == .hicpIT)
        #expect(italy.inflationIndex(for: .chf) == "hicp-ch")
        #expect(italy.inflationIndex(for: .usd) == .cpiUS)
        #expect(italy.inflationIndex(for: .gbp) == .cpiGB)
        #expect(italy.inflationIndex(for: "JPY") == nil)

        let switzerland = library(currency: .chf, residence: .ch)
        #expect(switzerland.inflationIndex(for: .chf) == "hicp-ch")
        #expect(switzerland.inflationIndex(for: .eur) == .hicpEA)

        // Living in Germany with a library in francs: euros use Germany's index.
        let border = library(currency: .chf, residence: .de)
        #expect(border.inflationIndex(for: .chf) == "hicp-de")
        #expect(border.inflationIndex(for: .eur) == "hicp-de")

        let us = library(currency: .usd, residence: .us)
        #expect(us.inflationIndex(for: .usd) == .cpiUS)
        #expect(us.inflationIndex(for: .eur) == .hicpEA)
        #expect(us.inflationIndex(for: .gbp) == .cpiGB)

        // Living in the UK with a library in euros: pounds use the UK's index.
        let britain = library(currency: .eur, residence: .gb)
        #expect(britain.inflationIndex(for: .eur) == .cpiGB)
        #expect(britain.inflationIndex(for: .gbp) == .cpiGB)
        #expect(britain.inflationIndex(for: .usd) == .cpiUS)
    }

    @Test func theLibraryNeedsItsOwnIndex() {
        var library = self.library(currency: .eur, residence: .it)
        #expect(library.inflationIndices == [.hicpIT])
        library.settings.inflationIndex = .hicpEA
        #expect(library.inflationIndices == [.hicpEA])
        #expect(self.library(currency: .usd).inflationIndices == [.cpiUS])
        #expect(self.library(currency: "JPY").inflationIndices.isEmpty)
    }

    @Test func theSettingIsOptionalInTheFile() throws {
        let decoder = JSONDecoder()
        let text = #"{ "baseCurrency": "CHF", "inflationIndex": "hicp-ch", "schemaVersion": 2 }"#
        let settings = try decoder.decode(LibrarySettings.self, from: Data(text.utf8))
        #expect(settings.inflationIndex == "hicp-ch")
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let written = String(decoding: try encoder.encode(settings), as: UTF8.self)
        #expect(written == #"{"baseCurrency":"CHF","inflationIndex":"hicp-ch","schemaVersion":2}"#)
        let without = try decoder.decode(LibrarySettings.self, from: Data(#"{ "baseCurrency": "EUR", "schemaVersion": 2 }"#.utf8))
        #expect(without.inflationIndex == nil)
        #expect(!String(decoding: try encoder.encode(without), as: UTF8.self).contains("inflationIndex"))
    }
}
