import Foundation
import Model
import Testing
import TestSupport
@testable import Tracker

/// Chart values that use a price much older than their date.
struct OldPriceTests {
    @Test func theExampleLibraryHasAPriceForEveryMonthEnd() throws {
        let valuator = Valuator(library: try Fixtures.exampleLibrary())
        let dates = valuator.dates(.monthEnds, through: "2026-09-30")
        #expect(valuator.oldPrices(in: .netWorth, on: dates).isEmpty)
        #expect(valuator.oldPrices(of: "gold-coins", on: dates).isEmpty)
    }

    @Test func goldWithOnlyItsFirstPriceIsPointedOut() throws {
        var library = try Fixtures.exampleLibrary()
        for month in library.months.keys where month != "2025-10" {
            library.months[month]?.prices.removeAll { $0.instrument == "gold" }
        }
        let valuator = Valuator(library: library)
        let dates = valuator.dates(.monthEnds, through: "2026-09-30")
        let old = valuator.oldPrices(of: "gold-coins", on: dates)
        // 30 November uses 31 October's price: 30 days is not old yet.
        #expect(old.map(\.date).first == "2025-12-31")
        #expect(old.count == 10)
        #expect(Set(old.map(\.priceDate)) == ["2025-10-31"])
        #expect(old.last?.age == 334)

        let summary = try #require(OldPriceSummary(valuator.oldPrices(in: .netWorth, on: dates)))
        #expect(summary.instruments == ["gold"])
        #expect(summary.dates.count == 10)
        #expect(summary.oldestAge == 334)
        #expect(OldPriceSummary([]) == nil)
    }

    @Test func positionsWithoutAPriceOrQuantityArentOld() throws {
        var library = try Fixtures.exampleLibrary()
        for month in library.months.keys { library.months[month]?.prices.removeAll { $0.instrument == "gold" } }
        let valuator = Valuator(library: library)
        // No price at all is a missing price, reported elsewhere.
        #expect(valuator.oldPrices(of: "gold-coins", on: ["2026-09-30"]).isEmpty)
    }
}
