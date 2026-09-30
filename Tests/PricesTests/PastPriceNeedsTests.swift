import Foundation
import Model
@testable import Prices
import Testing
import TestSupport

private func d(_ string: String) -> Decimal { Decimal(fileString: string)! }

/// What filling in past prices needs, worked out from a library.
struct PastPriceNeedsTests {
    private let today: CalendarDate = "2026-09-30"

    @Test func theExampleLibraryOnlyMissesSeptembersInflation() throws {
        let needs = PastPriceNeeds(library: try Fixtures.exampleLibrary(), today: today)
        #expect(needs.instruments.isEmpty)
        #expect(needs.manualInstruments.isEmpty)
        #expect(needs.rates.isEmpty)
        #expect(needs.indices == [CheckInPriceNeeds.IndexMonths(index: .hicpIT, months: ["2026-09"])])
    }

    @Test func withoutGoldPricesEveryValuationOfTheCoinsNeedsOne() throws {
        var library = try Fixtures.exampleLibrary()
        for month in library.months.keys { library.months[month]?.prices.removeAll { $0.instrument == "gold" } }
        let needs = PastPriceNeeds(library: library, today: today, indices: [])
        let gold = try #require(needs.instruments.first)
        #expect(needs.instruments.map(\.instrument) == ["gold"])
        #expect(gold.details?.priceSource == PriceSource(provider: .goldAPI, symbol: "XAU"))
        #expect(gold.dates == [
            "2025-10-31", "2025-11-30", "2025-12-31", "2026-01-31", "2026-02-28", "2026-03-31", "2026-04-30",
            "2026-05-31", "2026-06-30", "2026-07-31", "2026-08-31", "2026-09-30",
        ])
        #expect(needs.priceCount == 12)
        // Gold is priced in euros, the base currency: no rates needed.
        #expect(needs.rates.isEmpty)
        #expect(needs.isEmpty == false && needs.hasFetchable)
    }

    @Test func monthEndsBetweenSparseValuationsAreNeededToo() {
        var library = Self.library()
        library.upsert(Valuation(account: "broker", date: "2026-01-15",
                                 positions: [Position(instrument: "vwce", quantity: 10)]))
        library.upsert(Valuation(account: "broker", date: "2026-05-10",
                                 positions: [Position(instrument: "vwce", quantity: 12)]))
        let needs = PastPriceNeeds(library: library, today: "2026-06-30", indices: [])
        // January and May have values of their own; the month ends between are
        // valued with the quantities carried forward, up to today.
        #expect(needs.dates(for: "vwce") == [
            "2026-01-15", "2026-02-28", "2026-03-31", "2026-04-30", "2026-05-10", "2026-06-30",
        ])
    }

    @Test func recordedPricesAreNotNeededWhereverTheyCameFrom() {
        var library = Self.library()
        for date: CalendarDate in ["2026-06-30", "2026-07-31", "2026-08-31", "2026-09-30"] {
            library.upsert(Valuation(account: "broker", date: date, positions: [Position(instrument: "vwce", quantity: 10)]))
        }
        library.upsert(PriceRecord(instrument: "vwce", date: "2026-06-30", price: 120, currency: .eur, source: .manual))
        library.upsert(PriceRecord(instrument: "vwce", date: "2026-07-31", price: 121, currency: .eur, source: .ledger))
        library.upsert(PriceRecord(instrument: "vwce", date: "2026-08-31", price: 122, currency: .eur, source: .yahoo))
        let needs = PastPriceNeeds(library: library, today: today, indices: [])
        #expect(needs.dates(for: "vwce") == ["2026-09-30"])
    }

    @Test func foreignAmountsNeedARateUnlessOneIsRecordedEitherWay() {
        var library = Self.library()
        library.upsert(Valuation(account: "usd-cash", date: "2026-08-31", balance: 1000))
        library.upsert(Valuation(account: "usd-cash", date: "2026-09-30", balance: 1100))
        library.upsert(Valuation(account: "broker", date: "2026-09-30", positions: [Position(instrument: "aapl", quantity: 5)]))
        // 1 USD = 0.88 EUR, recorded the other way round, on 31 August.
        library.upsert(FXRecord(base: .usd, quote: .eur, date: "2026-08-31", rate: d("0.88")))
        let needs = PastPriceNeeds(library: library, today: today, indices: [])
        #expect(needs.rates == [PastPriceNeeds.RateDates(quote: .usd, dates: ["2026-09-30"])])
        #expect(needs.dates(for: "aapl") == ["2026-09-30"])
    }

    @Test func onlyDatesAnAccountCountsOnAreNeeded() {
        var library = Self.library()
        library.accounts["broker"]?.opened = "2026-07-01"
        library.accounts["broker"]?.closed = "2026-08-15"
        for date: CalendarDate in ["2026-06-30", "2026-07-31"] {
            library.upsert(Valuation(account: "broker", date: date, positions: [Position(instrument: "vwce", quantity: 1)]))
        }
        // Not before it opened, and no month ends after it closed.
        let needs = PastPriceNeeds(library: library, today: today, indices: [])
        #expect(needs.dates(for: "vwce") == ["2026-07-31"])
    }

    @Test func instrumentsWithoutASourceOrMissingAreListedApart() {
        var library = Self.library()
        library.upsert(Valuation(account: "broker", date: "2026-09-30", positions: [
            Position(instrument: "vwce", quantity: 1), Position(instrument: "fund", quantity: 2),
            Position(instrument: "mystery", quantity: 3), Position(instrument: "sold", quantity: 0),
        ]))
        let needs = PastPriceNeeds(library: library, today: today, indices: [])
        #expect(needs.instruments.map(\.instrument) == ["vwce"])
        #expect(needs.manualInstruments.map(\.instrument) == ["fund"])
        #expect(needs.unknownInstruments.map(\.instrument) == ["mystery"])
        #expect(needs.manualPriceCount == 2)
    }

    @Test func indexMonthsGoBackToTheFirstValuation() {
        var library = Self.library()
        library.upsert(Valuation(account: "usd-cash", date: "2026-05-20", balance: 1))
        library.upsert(IndexRecord(index: .hicpIT, date: "2026-06-30", value: 127))
        let needs = PastPriceNeeds(library: library, today: "2026-09-15")
        #expect(needs.indices == [CheckInPriceNeeds.IndexMonths(index: .hicpIT, months: ["2026-05", "2026-07", "2026-08"])])
        #expect(needs.indexMonthCount == 3)
    }

    /// A euro library with a brokerage account, a US-dollar cash account, and
    /// instruments with and without a price source.
    static func library() -> Library {
        Library(
            accounts: [
                Account(id: "broker", name: "Broker", kind: .brokerage, currency: .eur, opened: "2020-01-01"),
                Account(id: "usd-cash", name: "Dollars", kind: .cash, currency: .usd, opened: "2020-01-01"),
            ],
            instruments: [
                Instrument(id: "vwce", name: "VWCE", kind: .etf, currency: .eur, unit: .share,
                           assetClasses: .single(.equity), priceSource: PriceSource(provider: .yahoo, symbol: "VWCE.DE")),
                Instrument(id: "aapl", name: "Apple", kind: .stock, currency: .usd, unit: .share,
                           assetClasses: .single(.equity), priceSource: PriceSource(provider: .yahoo, symbol: "AAPL")),
                Instrument(id: "fund", name: "Private fund", kind: .fund, currency: .eur, unit: .share,
                           assetClasses: .single(.equity)),
                Instrument(id: "sold", name: "Sold", kind: .stock, currency: .eur, unit: .share,
                           assetClasses: .single(.equity), priceSource: PriceSource(provider: .yahoo, symbol: "SOLD")),
            ])
    }
}
