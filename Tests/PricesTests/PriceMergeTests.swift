import Foundation
import Model
@testable import Prices
import Testing
import TestSupport

/// The one rule for saving fetched records: a value typed in by hand beats a
/// fetched one unless the policy replaces everything.
struct PriceMergeTests {
    private let date: CalendarDate = "2026-09-30"

    private func price(_ value: Decimal, _ source: DataSource?) -> PriceRecord {
        PriceRecord(instrument: "vwce", date: date, price: value, currency: .eur, source: source)
    }

    @Test(arguments: [MergePolicy.keepExisting, .replaceFetched, .replaceAll])
    func aNewRecordIsAddedAndTheSameOneLeftAlone(policy: MergePolicy) {
        var library = Library()
        #expect(library.mergeOutcome(of: price(138, .yahoo), policy: policy) == .added)
        library.upsert(price(138, .yahoo))
        #expect(library.mergeOutcome(of: price(138, .yahoo), policy: policy) == .identical)
    }

    @Test func eachPolicyDecidesWhatADifferentRecordDoes() {
        var library = Library()
        library.upsert(price(140, .manual))
        library.upsert(PriceRecord(instrument: "gold", date: date, price: 98, currency: .eur, source: .goldAPI))
        let fetchedOverTyped = price(138, .yahoo)
        let fetchedOverFetched = PriceRecord(instrument: "gold", date: date, price: d("98.4"), currency: .eur,
                                             source: .goldAPI)
        #expect(library.mergeOutcome(of: fetchedOverTyped, policy: .keepExisting) == .kept)
        #expect(library.mergeOutcome(of: fetchedOverFetched, policy: .keepExisting) == .kept)
        #expect(library.mergeOutcome(of: fetchedOverTyped, policy: .replaceFetched) == .kept)
        #expect(library.mergeOutcome(of: fetchedOverFetched, policy: .replaceFetched) == .replaced)
        #expect(library.mergeOutcome(of: fetchedOverTyped, policy: .replaceAll) == .replaced)
        #expect(library.mergeOutcome(of: fetchedOverFetched, policy: .replaceAll) == .replaced)
    }

    @Test func aRateRecordedTheOtherWayRoundIsADifferentOne() {
        var library = Library()
        library.upsert(FXRecord(base: .usd, quote: .eur, date: date, rate: d("0.88"), source: .manual))
        let fetched = FXRecord(base: .eur, quote: .usd, date: date, rate: d("1.1398"), source: .ecb)
        #expect(library.mergeOutcome(of: fetched, policy: .keepExisting) == .kept)
        #expect(library.mergeOutcome(of: fetched, policy: .replaceFetched) == .kept)
        #expect(library.mergeOutcome(of: fetched, policy: .replaceAll) == .replaced)
    }

    @Test func mergingCountsAndWritesEachKind() {
        var library = Library()
        library.upsert(price(140, .manual))
        library.upsert(FXRecord(base: .eur, quote: .usd, date: date, rate: d("1.14"), source: .ecb))
        library.upsert(IndexRecord(index: .hicpIT, date: "2026-08-31", value: d("128.41"), source: .eurostat))
        let fetched = FetchedPrices(
            date: date,
            prices: [price(138, .yahoo),
                     PriceRecord(instrument: "gold", date: date, price: d("98.4"), currency: .eur, source: .goldAPI)],
            fx: [FXRecord(base: .eur, quote: .usd, date: date, rate: d("1.1398"), source: .ecb)],
            indices: [IndexRecord(index: .hicpIT, date: "2026-08-31", value: d("128.41"), source: .eurostat)])

        var check = library
        let merge = fetched.merge(into: &check, policy: .replaceFetched)
        #expect(merge.added == 1 && merge.replaced == 1 && merge.kept == 1 && merge.identical == 1)
        #expect(merge.prices == 1 && merge.fx == 1 && merge.indices == 0)
        #expect(merge.written == 2)
        #expect(check.prices(for: "vwce").map(\.price) == [140])
        #expect(check.prices(for: "gold").map(\.price) == [d("98.4")])
        #expect(check.fxRates(base: .eur, quote: .usd).map(\.rate) == [d("1.1398")])

        var all = library
        #expect(fetched.merge(into: &all, policy: .replaceAll).written == 3)
        #expect(all.prices(for: "vwce").map(\.price) == [138])

        // Only the gold price is new.
        var none = library
        #expect(fetched.merge(into: &none, policy: .keepExisting).written == 1)
        #expect(none.prices(for: "vwce").map(\.price) == [140])
        #expect(none.fxRates(base: .eur, quote: .usd).map(\.rate) == [d("1.14")])
    }
}
