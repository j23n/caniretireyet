import Foundation
import Model
import Testing
import TestSupport

struct LibraryTests {
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

        #expect(library.price(PriceKey(instrument: "x", date: "2026-09-30"))?.price == 2)
        #expect(library.price(PriceKey(instrument: "x", date: "2026-09-29")) == nil)
        #expect(library.fxRate(FXKey(base: .eur, quote: .usd, date: "2026-09-30"))?.rate == 1)
        #expect(library.fxRate(FXKey(base: .usd, quote: .eur, date: "2026-09-30")) == nil)
        #expect(library.indexValue(IndexKey(index: .hicpIT, date: "2026-09-30"))?.value == 1)
        #expect(library.indexValue(IndexKey(index: .hicpIT, date: "2026-10-31")) == nil)
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
