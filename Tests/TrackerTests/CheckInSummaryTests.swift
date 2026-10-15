import Foundation
import Model
import Testing
import TestSupport
import Tracker

/// The check-in's read-only summary on the example library, whose latest
/// check-in is 30 September 2026.
struct CheckInSummaryTests {
    let library: Library

    init() throws {
        library = try Fixtures.exampleLibrary()
    }

    @Test func theMonthsImportedValuesMarkTheirAccountsUpdated() {
        let summary = CheckInSummary(date: "2026-09-30", library: library)
        #expect(Set(summary.updated) == ["conto-deposito", "conto-fineco", "directa", "fondo-pensione", "mutuo-casa"])
        #expect(Set(summary.notUpdated) == ["casa", "gold-coins", "ledger-wallet", "tfr"])
        // A closed account is in neither list.
        #expect(!summary.updated.contains("old-bank") && !summary.notUpdated.contains("old-bank"))
        #expect(summary.change?.from == "2026-08-31")
    }

    @Test func aNewMonthStartsWithNothingUpdated() throws {
        let summary = CheckInSummary(date: "2026-10-31", library: library)
        #expect(summary.updated.isEmpty)
        #expect(summary.notUpdated.contains("conto-fineco"))
        let change = try #require(summary.change)
        #expect(change.from == "2026-09-30")
        #expect(change.to == "2026-10-31")
    }

    @Test func anImportedValueOrTradeUpdatesItsAccount() {
        var imported = library
        imported.upsert(Valuation(account: "conto-fineco", date: "2026-10-31", balance: 5000))
        imported.upsert(Trade(account: "directa", date: "2026-10-15", type: .deposit, amount: 100))
        let summary = CheckInSummary(date: "2026-10-31", library: imported)
        #expect(Set(summary.updated) == ["conto-fineco", "directa"])
        #expect(!summary.notUpdated.contains("conto-fineco"))
    }

    @Test func theFetchedPricesValueTheHoldings() {
        let before = CheckInSummary(date: "2026-10-31", library: library)
        let price = PriceRecord(instrument: "vwce", date: "2026-10-31", price: 1000, currency: .eur, source: .yahoo)
        let after = CheckInSummary(date: "2026-10-31", library: library, prices: [price])
        #expect(after.netWorth.total > before.netWorth.total)
    }
}
