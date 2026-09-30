import Foundation
import Model
import Testing
import TestSupport

struct LibraryTests {
    @Test func loadsTheExampleLibrary() throws {
        let library = try Fixtures.exampleLibrary()
        #expect(library.settings.baseCurrency == .eur)
        #expect(library.settings.person?.birthDate == "1988-04-12")
        #expect(library.accounts.count == 10)
        #expect(library.instruments.count == 3)
        #expect(library.months.count == 12)
        #expect(library.plans.keys.sorted() == ["base", "part-time-from-50"])
        #expect(library.importProfiles["net-worth-sheet"]?.columns.count == 5)
        #expect(library.baselines(for: "base").count == 1)
        #expect(library.headlines(for: "base").count == 9)
        #expect(library.headlines(for: "base").map(\.date) == library.headlines(for: "base").map(\.date).sorted())
        #expect(library.baselines(for: "missing").isEmpty)
    }

    @Test func queriesAreSortedByDate() throws {
        let library = try Fixtures.exampleLibrary()
        let gold = library.valuations(for: "gold-coins")
        #expect(gold.map(\.date) == ["2025-10-31", "2026-03-31"])
        #expect(gold[1].positions.first?.quantity == Decimal(fileString: "93.3"))

        let prices = library.prices(for: "vwce")
        #expect(prices.count == 12)
        #expect(prices.first?.date == "2025-10-31")
        #expect(prices.last?.price == Decimal(fileString: "138.42"))

        #expect(library.fxRates(base: .eur, quote: .usd).count == 12)
        #expect(library.fxRates(base: .usd, quote: .eur).isEmpty)
        #expect(library.indexValues(for: .hicpIT).count == 11)
        #expect(library.checkInDates.count == 12)
        #expect(library.latestCheckInDate == "2026-09-30")
        #expect(library.allValuations == library.allValuations.sortedByKey())
    }

    @Test func accountsOpenOnADate() throws {
        let library = try Fixtures.exampleLibrary()
        let before = library.accounts(openOn: "2025-11-15").map(\.id)
        let after = library.accounts(openOn: "2025-11-16").map(\.id)
        #expect(before.contains("old-bank"))
        #expect(!after.contains("old-bank"))
        #expect(library.accounts["old-bank"]?.successor == "conto-fineco")
        #expect(!library.accounts(openOn: "2025-05-31").map(\.id).contains("conto-deposito"))
    }

    @Test func upsertPlacesRecordsInTheirMonthInOrder() {
        var library = Library()
        library.upsert(Valuation(account: "b", date: "2026-09-30", balance: 2))
        library.upsert(Valuation(account: "a", date: "2026-09-30", balance: 1))
        library.upsert(Valuation(account: "a", date: "2026-09-15", balance: 5))
        library.upsert(Valuation(account: "a", date: "2026-10-01", balance: 7))
        #expect(library.months.keys.sorted() == ["2026-09", "2026-10"])
        #expect(library.months["2026-09"]?.valuations.map(\.key) == [
            ValuationKey(account: "a", date: "2026-09-15"),
            ValuationKey(account: "a", date: "2026-09-30"),
            ValuationKey(account: "b", date: "2026-09-30"),
        ])

        library.upsert(Valuation(account: "a", date: "2026-09-30", balance: 10))
        #expect(library.months["2026-09"]?.valuations.count == 3)
        #expect(library.valuations(for: "a").map(\.balance) == [5, 10, 7])

        #expect(library.removeValuation(ValuationKey(account: "a", date: "2026-09-15"))?.balance == 5)
        #expect(library.removeValuation(ValuationKey(account: "a", date: "2026-09-15")) == nil)

        library.upsert(PriceRecord(instrument: "x", date: "2026-09-30", price: 1, currency: .eur))
        library.upsert(FXRecord(base: .eur, quote: .usd, date: "2026-09-30", rate: 1))
        library.upsert(IndexRecord(index: .hicpIT, date: "2026-09-30", value: 1))
        library.upsert(PriceRecord(instrument: "x", date: "2026-09-30", price: 2, currency: .eur))
        #expect(library.prices(for: "x").map(\.price) == [2])
        #expect(library.months["2026-09"]?.fx.count == 1)
        #expect(library.months["2026-09"]?.indices.count == 1)
    }

    @Test func recordKeysSortByDateThenID() {
        let keys = [
            FXKey(base: .eur, quote: .usd, date: "2026-09-30"),
            FXKey(base: .eur, quote: .chf, date: "2026-09-30"),
            FXKey(base: .usd, quote: .jpy, date: "2026-08-31"),
        ]
        #expect(keys.sorted().map(\.quote) == [.jpy, .chf, .usd])
        #expect(PriceKey(instrument: "a", date: "2026-09-30") > PriceKey(instrument: "z", date: "2026-09-29"))
        #expect(Headline(date: "2026-09-30", engine: "1", planHash: "h").key == "2026-09-30")
    }
}
