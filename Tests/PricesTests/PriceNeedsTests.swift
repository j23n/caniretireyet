import Foundation
import Model
@testable import Prices
import Testing
import TestSupport

/// What a check-in on a date, and filling in the past, need fetched.
struct PriceNeedsTests {
    private let today: CalendarDate = "2026-09-30"

    // MARK: A check-in

    @Test func theExampleLibrarysLatestCheckIn() throws {
        let needs = PriceNeeds(library: try PriceServiceTests.exampleLibrary(), checkInOn: "2026-09-30")
        #expect(needs.date == "2026-09-30")
        #expect(needs.baseCurrency == .eur)
        // vwce in Directa, btc in the Ledger wallet and gold in the coins.
        #expect(needs.instruments.map(\.instrument) == ["btc", "gold", "vwce"])
        #expect(needs.instruments.allSatisfy { $0.dates == ["2026-09-30"] })
        #expect(needs.manualInstruments.isEmpty)
        #expect(needs.unknownInstruments.isEmpty)
        // btc is priced in USD; every account is in EUR.
        #expect(needs.rates == [PriceNeeds.RateDates(quote: .usd, dates: ["2026-09-30"])])
        // hicp-it is recorded up to August.
        #expect(needs.indices == [PriceNeeds.IndexMonths(index: .hicpIT, months: ["2026-09"])])
    }

    @Test func aCheckInNeedsOnlyIndexMonthsThatHaveEnded() throws {
        let library = try Fixtures.exampleLibrary()
        #expect(PriceNeeds(library: library, checkInOn: "2026-09-15").indices.isEmpty)
        #expect(PriceNeeds(library: Library(), checkInOn: "2026-09-30").indices.first?.months == ["2026-09"])
        #expect(PriceNeeds(library: Library(), checkInOn: "2026-10-02").indices.isEmpty)
    }

    @Test func missingIndexMonthsAreFilledFromTheFirstCheckIn() throws {
        var library = try Fixtures.exampleLibrary()
        library.months["2025-11"]?.indices = []
        library.months["2026-08"]?.indices = []
        let needs = PriceNeeds(library: library, checkInOn: "2026-09-30")
        #expect(needs.indices.first?.months == ["2025-11", "2026-08", "2026-09"])

        let windowed = PriceNeeds(library: library, checkInOn: "2026-09-30", indexWindow: 3)
        #expect(windowed.indices.first?.months == ["2026-08", "2026-09"])
        #expect(PriceNeeds(library: library, checkInOn: "2026-09-30", indices: []).indices.isEmpty)
    }

    @Test func beforeTheFirstCheckInNothingIsHeld() throws {
        let needs = PriceNeeds(library: try Fixtures.exampleLibrary(), checkInOn: "2025-09-30")
        #expect(needs.instruments.isEmpty)
        #expect(needs.rates.isEmpty)
        #expect(needs.indices.isEmpty)
    }

    @Test func onlyOpenAccountsAndWhatTheirTradesHoldCount() {
        let needs = PriceNeeds(library: NeedsLibrary.make(), checkInOn: "2026-09-30")
        // vwce was sold again; gold is bought later.
        #expect(needs.instruments.map(\.instrument) == ["aapl"])
        #expect(needs.manualInstruments.map(\.instrument) == ["btc", "private-fund", "typed-in"])
        #expect(needs.unknownInstruments.map(\.instrument) == ["mystery"])
        // USD from the IBKR account and aapl; CHF from the Swiss account and
        // the private fund. Not GBP: that account opens later.
        #expect(needs.rates.map(\.quote) == [.chf, .usd])
    }

    /// One instrument's price, as *Update Prices* fetches it: with its
    /// currency's rate, unless that's the base currency or its price is
    /// typed in.
    @Test func oneInstrumentBringsItsCurrencyUnlessItsTheBase() {
        var instrument = Instrument(id: "aapl", name: "Apple", kind: .stock, currency: .usd, unit: .share,
                                    assetClasses: .single(.equity),
                                    priceSource: PriceSource(provider: .yahoo, symbol: "AAPL"))
        let needs = PriceNeeds(instrument: instrument, date: "2026-09-30", baseCurrency: .eur)
        #expect(needs.date == "2026-09-30")
        #expect(needs.instruments == [.init(instrument: "aapl", details: instrument, dates: ["2026-09-30"])])
        #expect(needs.rates == [.init(quote: .usd, dates: ["2026-09-30"])])
        #expect(needs.indices.isEmpty)
        instrument.currency = .eur
        #expect(PriceNeeds(instrument: instrument, date: "2026-09-30", baseCurrency: .eur).rates.isEmpty)
        instrument.priceSource = nil
        let typed = PriceNeeds(instrument: instrument, date: "2026-09-30", baseCurrency: .eur)
        #expect(typed.instruments.isEmpty)
        #expect(typed.manualInstruments.map(\.instrument) == ["aapl"])
    }

    /// Only Yahoo Finance and gold-api.com are fetched from. A source naming
    /// another provider, such as CoinGecko, which crypto was once priced
    /// from, decodes as it is and counts as typed in.
    @Test func otherProvidersAreTypedIn() throws {
        #expect(PriceNeeds.isFetched(PriceSource(provider: .yahoo, symbol: "BTC-EUR")))
        #expect(PriceNeeds.isFetched(PriceSource(provider: .goldAPI, symbol: "XAU")))
        #expect(!PriceNeeds.isFetched(PriceSource(provider: .yahoo, symbol: "")))
        #expect(!PriceNeeds.isFetched(PriceSource(provider: "coingecko", symbol: "bitcoin")))
        #expect(!PriceNeeds.isFetched(PriceSource(provider: .eodhd, symbol: "AAPL.US")))
        #expect(!PriceNeeds.isFetched(nil))
        let source = try JSONDecoder().decode(PriceSource.self,
                                              from: Data(#"{"provider":"coingecko","symbol":"bitcoin"}"#.utf8))
        #expect(source.provider.rawValue == "coingecko")
        #expect(!source.provider.isKnown)
    }

    // MARK: Filling in the past

    @Test func theExampleLibraryOnlyMissesSeptembersInflation() throws {
        let needs = PriceNeeds(library: try Fixtures.exampleLibrary(), through: today)
        #expect(needs.date == today)
        #expect(needs.instruments.isEmpty)
        #expect(needs.manualInstruments.isEmpty)
        #expect(needs.rates.isEmpty)
        #expect(needs.indices == [PriceNeeds.IndexMonths(index: .hicpIT, months: ["2026-09"])])
    }

    @Test func withoutGoldPricesEveryMonthEndOfTheCoinsNeedsOne() throws {
        var library = try Fixtures.exampleLibrary()
        for month in library.months.keys { library.months[month]?.prices.removeAll { $0.instrument == "gold" } }
        let needs = PriceNeeds(library: library, through: today, indices: [])
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

    @Test func aTradesAccountNeedsPricesForWhatItsTradesHold() {
        var library = Self.library()
        library.upsert(Trade(account: "broker", date: "2026-01-15", id: "a", type: .buy, instrument: "vwce",
                             quantity: 10, price: 100))
        library.upsert(Trade(account: "broker", date: "2026-02-10", id: "b", type: .transferIn, instrument: "aapl",
                             quantity: 2, cost: 300))
        library.upsert(Trade(account: "broker", date: "2026-03-20", id: "c", type: .sell, instrument: "vwce",
                             quantity: 10, price: 110))
        library.upsert(Trade(account: "broker", date: "2026-04-02", id: "d", type: .buy, instrument: "aapl",
                             quantity: 1, price: 170))
        library.upsert(Valuation(account: "broker", date: "2026-04-15", cash: 10))
        let needs = PriceNeeds(library: library, through: "2026-04-30", indices: [])
        // Month ends from the first trade while it's held; the transfer is valued on its date.
        #expect(needs.dates(for: "vwce") == ["2026-01-31", "2026-02-10", "2026-02-28"])
        #expect(needs.dates(for: "aapl") == ["2026-02-10", "2026-02-28", "2026-03-31", "2026-04-15", "2026-04-30"])
        // The USD price of the buy without an amount is converted on its date.
        #expect(needs.rates.first?.dates.contains("2026-04-02") == true)
    }

    @Test func aBalanceIsConvertedOnEachMonthEndItsCarriedTo() {
        var library = Self.library()
        library.upsert(Valuation(account: "usd-cash", date: "2026-01-15", balance: 1000))
        library.upsert(Valuation(account: "usd-cash", date: "2026-05-10", balance: 1200))
        let needs = PriceNeeds(library: library, through: "2026-06-30", indices: [])
        // January and May have values of their own; the month ends between are
        // valued with the balance carried forward, up to today.
        #expect(needs.rates == [PriceNeeds.RateDates(quote: .usd, dates: [
            "2026-01-15", "2026-02-28", "2026-03-31", "2026-04-30", "2026-05-10", "2026-06-30",
        ])])
    }

    @Test func recordedPricesAreNotNeededWhereverTheyCameFrom() {
        var library = Self.library()
        library.upsert(Trade(account: "broker", date: "2026-06-30", id: "a", type: .buy, instrument: "vwce",
                             quantity: 10, price: 120))
        library.upsert(PriceRecord(instrument: "vwce", date: "2026-06-30", price: 120, currency: .eur, source: .manual))
        library.upsert(PriceRecord(instrument: "vwce", date: "2026-07-31", price: 121, currency: .eur, source: "ledger"))
        library.upsert(PriceRecord(instrument: "vwce", date: "2026-08-31", price: 122, currency: .eur, source: .yahoo))
        let needs = PriceNeeds(library: library, through: today, indices: [])
        #expect(needs.dates(for: "vwce") == ["2026-09-30"])
    }

    @Test func foreignAmountsNeedARateUnlessOneIsRecordedEitherWay() {
        var library = Self.library()
        library.upsert(Valuation(account: "usd-cash", date: "2026-08-31", balance: 1000))
        library.upsert(Valuation(account: "usd-cash", date: "2026-09-30", balance: 1100))
        library.upsert(Trade(account: "broker", date: "2026-09-30", id: "a", type: .opening, instrument: "aapl",
                             quantity: 5))
        // 1 USD = 0.88 EUR, recorded the other way round, on 31 August.
        library.upsert(FXRecord(base: .usd, quote: .eur, date: "2026-08-31", rate: d("0.88")))
        let needs = PriceNeeds(library: library, through: today, indices: [])
        #expect(needs.rates == [PriceNeeds.RateDates(quote: .usd, dates: ["2026-09-30"])])
        #expect(needs.dates(for: "aapl") == ["2026-09-30"])
    }

    @Test func onlyDatesAnAccountCountsOnAreNeeded() {
        var library = Self.library()
        library.accounts["broker"]?.opened = "2026-07-01"
        library.accounts["broker"]?.closed = "2026-08-15"
        library.upsert(Trade(account: "broker", date: "2026-07-10", id: "a", type: .buy, instrument: "vwce",
                             quantity: 1, price: 100))
        // No month ends after it closed.
        let needs = PriceNeeds(library: library, through: today, indices: [])
        #expect(needs.dates(for: "vwce") == ["2026-07-31"])
    }

    @Test func instrumentsWithoutASourceOrMissingAreListedApart() {
        var library = Self.library()
        for (id, instrument) in [("a", "vwce"), ("b", "fund"), ("c", "mystery")] {
            library.upsert(Trade(account: "broker", date: "2026-09-30", id: TradeID(id), type: .opening,
                                 instrument: InstrumentID(instrument), quantity: 1))
        }
        let needs = PriceNeeds(library: library, through: today, indices: [])
        #expect(needs.instruments.map(\.instrument) == ["vwce"])
        #expect(needs.manualInstruments.map(\.instrument) == ["fund"])
        #expect(needs.unknownInstruments.map(\.instrument) == ["mystery"])
        #expect(needs.manualPriceCount == 2)
    }

    @Test func indexMonthsGoBackToTheFirstValuation() {
        var library = Self.library()
        library.upsert(Valuation(account: "usd-cash", date: "2026-05-20", balance: 1))
        library.upsert(IndexRecord(index: .hicpIT, date: "2026-06-30", value: 127))
        let needs = PriceNeeds(library: library, through: "2026-09-15")
        #expect(needs.indices == [PriceNeeds.IndexMonths(index: .hicpIT, months: ["2026-05", "2026-07", "2026-08"])])
        #expect(needs.indexMonthCount == 3)
    }

    /// A euro library with a brokerage account that records trades, a
    /// US-dollar cash account, and instruments with and without a price
    /// source.
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
            ])
    }
}

/// A made-up library that exercises every rule of a check-in's needs.
enum NeedsLibrary {
    static func make() -> Library {
        func instrument(_ id: InstrumentID, _ currency: CurrencyCode, _ source: PriceSource?) -> Instrument {
            Instrument(id: id, name: id.rawValue, kind: .stock, currency: currency, unit: .share,
                       assetClasses: .single(.equity), priceSource: source)
        }
        var library = Library(
            accounts: [
                Account(id: "ibkr", name: "IBKR", kind: .brokerage, currency: .usd, opened: "2024-01-01"),
                Account(id: "swiss-cash", name: "Swiss cash", kind: .cash, currency: .chf, opened: "2024-01-01"),
                Account(id: "closed-broker", name: "Closed broker", kind: .brokerage, currency: .eur,
                        opened: "2020-01-01", closed: "2026-01-31"),
                Account(id: "future", name: "Opens later", kind: .brokerage, currency: .gbp, opened: "2026-10-15"),
            ],
            instruments: [
                instrument("aapl", .usd, PriceSource(provider: .yahoo, symbol: "AAPL")),
                instrument("vwce", .eur, PriceSource(provider: .yahoo, symbol: "VWCE.DE")),
                // A source the app no longer fetches from: typed in.
                instrument("btc", .usd, PriceSource(provider: "coingecko", symbol: "bitcoin")),
                instrument("gold", .eur, PriceSource(provider: .goldAPI, symbol: "XAU")),
                instrument("private-fund", .chf, nil),
                instrument("typed-in", .eur, PriceSource(provider: "manual", symbol: "")),
            ])
        var count = 0
        func trade(_ account: AccountID, _ date: CalendarDate, _ type: TradeType, _ instrument: InstrumentID,
                   _ quantity: Decimal) {
            count += 1
            library.upsert(Trade(account: account, date: date, id: TradeID("t\(count)"), type: type,
                                 instrument: instrument, quantity: quantity))
        }
        for (instrument, quantity) in [("aapl", 10), ("mystery", 5), ("private-fund", 3), ("typed-in", 1), ("btc", 1),
                                       ("vwce", 2)] as [(InstrumentID, Decimal)] {
            trade("ibkr", "2026-09-01", .opening, instrument, quantity)
        }
        trade("ibkr", "2026-09-20", .transferOut, "vwce", 2)
        trade("ibkr", "2026-10-31", .transferIn, "gold", 1)
        trade("closed-broker", "2025-12-31", .opening, "btc", d("0.5"))
        trade("future", "2026-10-15", .opening, "vwce", 3)
        library.upsert(Valuation(account: "swiss-cash", date: "2026-09-30", balance: d("1200")))
        return library
    }
}

extension PriceNeeds {
    /// The dates `instrument` needs a price on, whichever list it's in.
    func dates(for instrument: InstrumentID) -> [CalendarDate] {
        (instruments + manualInstruments + unknownInstruments).first { $0.instrument == instrument }?.dates ?? []
    }
}
