import Foundation
import Model
import Prices
import Testing
import TestSupport

struct CheckInPriceNeedsTests {
    @Test func theExampleLibrarysLatestCheckIn() throws {
        let needs = CheckInPriceNeeds(library: try Fixtures.exampleLibrary(), date: "2026-09-30")
        #expect(needs.baseCurrency == .eur)
        // vwce in Directa, btc in the Ledger wallet and gold in the coins,
        // the last two carried forward from March.
        #expect(needs.instruments.map(\.id) == ["btc", "gold", "vwce"])
        #expect(needs.manualInstruments.isEmpty)
        #expect(needs.unknownInstruments.isEmpty)
        // btc is priced in USD; every account is in EUR.
        #expect(needs.currencies == [.usd])
        // hicp-it is recorded up to August.
        #expect(needs.indices == [.init(index: .hicpIT, months: ["2026-09"])])
    }

    @Test func midMonthNeedsOnlyMonthsThatHaveEnded() throws {
        let needs = CheckInPriceNeeds(library: try Fixtures.exampleLibrary(), date: "2026-09-15")
        #expect(needs.indices == [.init(index: .hicpIT, months: [])])
    }

    @Test func missingIndexMonthsAreFilledFromTheFirstCheckIn() throws {
        var library = try Fixtures.exampleLibrary()
        library.months["2025-11"]?.indices = []
        library.months["2026-08"]?.indices = []
        let needs = CheckInPriceNeeds(library: library, date: "2026-09-30")
        #expect(needs.indices.first?.months == ["2025-11", "2026-08", "2026-09"])

        let windowed = CheckInPriceNeeds(library: library, date: "2026-09-30", indexWindow: 3)
        #expect(windowed.indices.first?.months == ["2026-08", "2026-09"])
        #expect(CheckInPriceNeeds(library: library, date: "2026-09-30", indices: []).indices.isEmpty)
    }

    @Test func beforeTheFirstCheckInNothingIsHeld() throws {
        let needs = CheckInPriceNeeds(library: try Fixtures.exampleLibrary(), date: "2025-09-30")
        #expect(needs.instruments.isEmpty)
        #expect(needs.currencies.isEmpty)
        #expect(needs.indices.first?.months == [])
    }

    @Test func aNewLibraryDoesntBackfillIndexValues() {
        let needs = CheckInPriceNeeds(library: Library(), date: "2026-09-30")
        #expect(needs.indices.first?.months == ["2026-09"])
        #expect(CheckInPriceNeeds(library: Library(), date: "2026-10-02").indices.first?.months == [])
    }

    /// The library's own index: the tax residence's HICP, else the base
    /// currency's; and the rate of each account's currency.
    @Test func theIndicesAndCurrenciesFollowTheLibrary() throws {
        var library = try Fixtures.exampleLibrary()
        library.settings.taxResidence = .de
        let germany = CheckInPriceNeeds(library: library, date: "2026-09-30")
        let months: [YearMonth] = ["2025-10", "2025-11", "2025-12", "2026-01", "2026-02", "2026-03", "2026-04",
                                   "2026-05", "2026-06", "2026-07", "2026-08", "2026-09"]
        #expect(germany.indices == [.init(index: "hicp-de", months: months)])

        library.settings.taxResidence = .it
        let italy = CheckInPriceNeeds(library: library, date: "2026-09-30")
        #expect(italy.currencies == [.usd])
        #expect(italy.indices.map(\.index) == [.hicpIT])

        // Asked for no indices, there are none; the currencies stay.
        #expect(CheckInPriceNeeds(library: library, date: "2026-09-30", indices: []).indices.isEmpty)
    }

    @Test func aTradesAccountNeedsWhatItsTradesHold() {
        var library = NeedsLibrary.make()
        library.accounts["ibkr"]?.valuation = .trades
        library.upsert(Trade(account: "ibkr", date: "2026-09-01", id: "a", type: .opening, instrument: "typed-in",
                             quantity: 3))
        library.upsert(Trade(account: "ibkr", date: "2026-09-10", id: "b", type: .buy, instrument: "private-fund",
                             quantity: 1, amount: -100))
        library.upsert(Trade(account: "ibkr", date: "2026-09-20", id: "c", type: .sell, instrument: "private-fund",
                             quantity: 1, amount: 101))
        let needs = CheckInPriceNeeds(library: library, date: "2026-09-30")
        // Its valuations' positions don't count; the fund was sold again.
        #expect(needs.instruments.isEmpty)
        #expect(needs.manualInstruments.contains("typed-in"))
    }

    @Test func onlyOpenAccountsAndHeldPositionsCount() {
        let needs = CheckInPriceNeeds(library: NeedsLibrary.make(), date: "2026-09-30")
        #expect(needs.instruments.map(\.id) == ["aapl"])
        #expect(needs.manualInstruments == ["private-fund", "typed-in"])
        #expect(needs.unknownInstruments == ["mystery"])
        // USD from the IBKR account and aapl; CHF from the Swiss account and
        // the private fund. Not GBP: that account opens later.
        #expect(needs.currencies == [.chf, .usd])
    }

    /// Instruments the library doesn't hold on the date (a check-in's new
    /// positions) are sorted in with the others; only a fetched one brings
    /// its currency.
    @Test func instrumentsNotHeldCanBeIncluded() {
        var library = NeedsLibrary.make()
        library.instruments["toyota"] = Instrument(
            id: "toyota", name: "Toyota", kind: .stock, currency: CurrencyCode("JPY"), unit: .share,
            assetClasses: .single(.equity), priceSource: PriceSource(provider: .yahoo, symbol: "7203.T"))
        library.instruments["art"] = Instrument(id: "art", name: "Art", kind: .other, currency: .gbp, unit: .share,
                                                assetClasses: .single(.equity))
        let needs = CheckInPriceNeeds(library: library, date: "2026-09-30",
                                      including: ["toyota", "art", "vwce", "aapl", "nowhere"])
        #expect(needs.instruments.map(\.id) == ["aapl", "toyota", "vwce"])
        #expect(needs.manualInstruments == ["art", "private-fund", "typed-in"])
        #expect(needs.unknownInstruments == ["mystery", "nowhere"])
        // The yen for Toyota; not the pound: the art's price is typed in.
        #expect(needs.currencies == [.chf, CurrencyCode("JPY"), .usd])
    }

    /// One instrument's price, as *Update Prices* fetches it: with its
    /// currency's rate, unless that's the base currency.
    @Test func oneInstrumentBringsItsCurrencyUnlessItsTheBase() {
        var instrument = Instrument(id: "aapl", name: "Apple", kind: .stock, currency: .usd, unit: .share,
                                    assetClasses: .single(.equity),
                                    priceSource: PriceSource(provider: .yahoo, symbol: "AAPL"))
        let needs = CheckInPriceNeeds(instrument: instrument, date: "2026-09-30", baseCurrency: .eur)
        #expect(needs.date == "2026-09-30")
        #expect(needs.baseCurrency == .eur)
        #expect(needs.instruments == [instrument])
        #expect(needs.currencies == [.usd])
        #expect(needs.indices.isEmpty)
        instrument.currency = .eur
        #expect(CheckInPriceNeeds(instrument: instrument, date: "2026-09-30", baseCurrency: .eur).currencies.isEmpty)
    }
}

/// A made-up library that exercises every rule of the work-out.
enum NeedsLibrary {
    static func make() -> Library {
        func instrument(_ id: InstrumentID, _ currency: CurrencyCode, _ source: PriceSource?) -> Instrument {
            Instrument(id: id, name: id.rawValue, kind: .stock, currency: currency, unit: .share,
                       assetClasses: .single(.equity), priceSource: source)
        }
        func holding(_ account: AccountID, _ date: CalendarDate, _ positions: [(InstrumentID, String)]) -> Valuation {
            Valuation(account: account, date: date,
                      positions: positions.map { Position(instrument: $0.0, quantity: d($0.1)) })
        }
        var library = Library(
            accounts: [
                Account(id: "ibkr", name: "IBKR", kind: .brokerage, currency: .usd, opened: "2024-01-01"),
                Account(id: "swiss-cash", name: "Swiss cash", kind: .cash, currency: .chf, opened: "2024-01-01"),
                Account(id: "closed-broker", name: "Closed broker", kind: .brokerage, currency: .eur,
                        opened: "2020-01-01", closed: "2026-01-31"),
                Account(id: "future", name: "Opens later", kind: .brokerage, currency: .gbp, opened: "2026-10-15"),
                Account(id: "switched", name: "Switched to a balance", kind: .brokerage, currency: .eur,
                        opened: "2024-01-01"),
            ],
            instruments: [
                instrument("aapl", .usd, PriceSource(provider: .yahoo, symbol: "AAPL")),
                instrument("vwce", .eur, PriceSource(provider: .yahoo, symbol: "VWCE.DE")),
                instrument("btc", .usd, PriceSource(provider: .coingecko, symbol: "bitcoin")),
                instrument("gold", .eur, PriceSource(provider: .goldAPI, symbol: "XAU")),
                instrument("private-fund", .chf, nil),
                instrument("typed-in", .eur, PriceSource(provider: "manual", symbol: "")),
            ])
        library.upsert(holding("ibkr", "2026-09-30", [
            ("aapl", "10"), ("vwce", "0"), ("mystery", "5"), ("private-fund", "3"), ("typed-in", "1"),
        ]))
        library.upsert(holding("ibkr", "2026-10-31", [("gold", "1")]))
        library.upsert(Valuation(account: "swiss-cash", date: "2026-09-30", balance: d("1200")))
        library.upsert(holding("closed-broker", "2025-12-31", [("btc", "0.5")]))
        library.upsert(holding("future", "2026-10-15", [("vwce", "3")]))
        library.upsert(holding("switched", "2026-06-30", [("gold", "10")]))
        library.upsert(Valuation(account: "switched", date: "2026-08-31", balance: d("950")))
        return library
    }
}
