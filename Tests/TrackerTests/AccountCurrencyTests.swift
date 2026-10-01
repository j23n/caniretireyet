import Foundation
import Model
import Testing
import Tracker

private func d(_ string: String) -> Decimal { Decimal(fileString: string)! }

/// A made-up euro library with dollar accounts and no exchange rates before
/// October 2025, like history imported without filling in past prices:
///
/// - `brokerage`: dollar balances from 2018, emptied on 1 January 2022;
/// - `us-broker`: dollar cash, a euro ETF and a dollar stock;
/// - `usd-trades`: a dollar account that records trades, later emptied;
/// - `emptied`: holdings sold down to nothing;
/// - `bank`: euros.
func foreignAccountLibrary() -> Library {
    var library = Library(
        settings: LibrarySettings(baseCurrency: .eur),
        accounts: [
            Account(id: "brokerage", name: "Brokerage", kind: .brokerage, currency: .usd, opened: "2018-06-01"),
            Account(id: "us-broker", name: "US broker", kind: .brokerage, currency: .usd, opened: "2025-09-01"),
            Account(id: "usd-trades", name: "USD trades", kind: .brokerage, currency: .usd, opened: "2024-01-01",
                    valuation: .trades),
            Account(id: "emptied", name: "Emptied", kind: .brokerage, currency: .eur, opened: "2024-01-01"),
            Account(id: "bank", name: "Bank", kind: .cash, currency: .eur, opened: "2025-01-01"),
        ],
        instruments: [
            Instrument(id: "vwce", name: "VWCE", kind: .etf, currency: .eur, unit: .share,
                       assetClasses: .single(.equity)),
            Instrument(id: "aapl", name: "Apple", kind: .stock, currency: .usd, unit: .share,
                       assetClasses: .single(.equity)),
        ])
    for valuation in [
        Valuation(account: "brokerage", date: "2018-06-30", balance: 100_000, flow: 100_000),
        Valuation(account: "brokerage", date: "2020-12-31", balance: 110_000, flow: 0),
        Valuation(account: "brokerage", date: "2021-11-30", balance: 123_959),
        Valuation(account: "brokerage", date: "2022-01-01", balance: 0, flow: -123_959),
        Valuation(account: "brokerage", date: "2022-03-31", balance: 0, flow: 0),
        Valuation(account: "us-broker", date: "2025-09-30", cash: 100, positions: [
            Position(instrument: "vwce", quantity: 10),
            Position(instrument: "aapl", quantity: 5),
            Position(instrument: "nope", quantity: 1),
        ]),
        Valuation(account: "us-broker", date: "2025-10-31", cash: 100, positions: [
            Position(instrument: "vwce", quantity: 10),
            Position(instrument: "aapl", quantity: 5),
        ]),
        Valuation(account: "emptied", date: "2024-01-31", positions: [Position(instrument: "vwce", quantity: 5)]),
        Valuation(account: "emptied", date: "2024-02-29", cash: 0, positions: [Position(instrument: "vwce", quantity: 0)]),
        Valuation(account: "bank", date: "2025-09-30", balance: 2000),
        Valuation(account: "bank", date: "2025-10-31", balance: 2500, flow: 500),
    ] {
        library.upsert(valuation)
    }
    for trade in [
        Trade(account: "usd-trades", date: "2024-01-02", id: "dep1", type: .deposit, amount: 1000),
        Trade(account: "usd-trades", date: "2024-01-05", id: "buy1", type: .buy, instrument: "aapl", quantity: 5,
              price: 150, fees: 1),
        Trade(account: "usd-trades", date: "2024-02-10", id: "sel1", type: .sell, instrument: "aapl", quantity: 5,
              price: 160, fees: 1),
        Trade(account: "usd-trades", date: "2024-02-12", id: "wd1", type: .withdrawal, amount: -1048),
    ] {
        library.upsert(trade)
    }
    for price in [
        PriceRecord(instrument: "vwce", date: "2024-01-31", price: 100, currency: .eur),
        PriceRecord(instrument: "aapl", date: "2024-01-05", price: 150, currency: .usd),
        PriceRecord(instrument: "aapl", date: "2024-01-31", price: 155, currency: .usd),
        PriceRecord(instrument: "vwce", date: "2025-09-30", price: 125, currency: .eur),
        PriceRecord(instrument: "aapl", date: "2025-09-30", price: 190, currency: .usd),
        PriceRecord(instrument: "vwce", date: "2025-10-31", price: d("128.1"), currency: .eur),
        PriceRecord(instrument: "aapl", date: "2025-10-31", price: 200, currency: .usd),
    ] {
        library.upsert(price)
    }
    library.upsert(FXRecord(base: .eur, quote: .usd, date: "2025-10-31", rate: d("1.0852")))
    return library
}

/// Values of an account in its own currency (``ValueCurrency/account``).
struct AccountCurrencyTests {
    let valuator = Valuator(library: foreignAccountLibrary())

    @Test func anAccountInItsOwnCurrencyNeedsNoRate() throws {
        let own = try #require(valuator.value(of: "brokerage", on: "2021-11-30", in: .account))
        #expect(own.currency == .usd)
        #expect(own.value == 123_959)
        #expect(own.isComplete)

        let base = try #require(valuator.value(of: "brokerage", on: "2021-11-30", in: .base))
        #expect(base == valuator.value(of: "brokerage", on: "2021-11-30"))
        #expect(base.currency == .eur)
        #expect(base.knownValue == 0)
        #expect(base.problems == [.missingFX(account: "brokerage", from: .usd, to: .eur)])

        #expect(valuator.currencyCode(.account, of: "brokerage") == .usd)
        #expect(valuator.currencyCode(.base, of: "brokerage") == .eur)
        #expect(valuator.currencyCode(.account, of: "nope") == nil)
        #expect(valuator.value(of: "nope", on: "2021-11-30", in: .account) == nil)
    }

    @Test func seriesInTheAccountsCurrency() {
        let own = valuator.series(of: "brokerage", in: .account, through: "2022-03-31")
        let values = Dictionary(uniqueKeysWithValues: own.map { ($0.date, $0.value) })
        #expect(own.first?.date == "2018-06-30")
        #expect(own.count == 46)
        #expect(own.allSatisfy { $0.isComplete })
        #expect(values["2021-11-30"] == 123_959)
        #expect(values["2021-12-31"] == 123_959)
        #expect(values["2022-01-31"] == 0)

        // In euros, every value before 2022 lacks a rate and counts as zero; zero needs none.
        let base = valuator.series(of: "brokerage", in: .base, through: "2022-03-31")
        let incomplete = base.filter { !$0.isComplete }.map(\.date)
        let before2022 = own.map(\.date).filter { $0 < "2022-01-01" }
        #expect(base == valuator.series(of: "brokerage", through: "2022-03-31"))
        #expect(base.map(\.date) == own.map(\.date))
        #expect(incomplete == before2022)
        #expect(base.allSatisfy { $0.value == 0 })

        // An account in the base currency is the same either way.
        #expect(valuator.series(of: "bank", in: .account, through: "2025-10-31")
            == valuator.series(of: "bank", through: "2025-10-31"))
        #expect(valuator.series(of: "nope", in: .account, through: "2025-10-31").isEmpty)
    }

    @Test func positionsPricedInAnotherCurrencyAreConverted() throws {
        // 100 + 10 × 128,10 € × 1,0852 + 5 × 200.
        let october = try #require(valuator.value(of: "us-broker", on: "2025-10-31", in: .account))
        #expect(october.value == d("2490.1412"))
        let etf = try #require(october.components.first(where: { $0.kind == .position("vwce") }))
        #expect(etf.fx?.from == .eur)
        #expect(etf.fx?.to == .usd)

        // No rate yet in September: the euro ETF is missing, and so is the unpriced position.
        let september = try #require(valuator.value(of: "us-broker", on: "2025-09-30", in: .account))
        #expect(september.problems == [.missingFX(account: "us-broker", from: .eur, to: .usd),
                                       .missingPrice(account: "us-broker", instrument: "nope")])
        #expect(september.knownValue == 1050)
    }

    @Test func changeInTheAccountsCurrency() throws {
        let own = try #require(valuator.change(of: "brokerage", from: "2021-11-30", to: "2022-01-01", in: .account))
        #expect(own.change == ValueChange(start: 123_959, market: 0, newMoney: -123_959, other: 0, end: 0))
        #expect(own.flow == -123_959)
        #expect(own.problems.isEmpty)

        // In euros the start lacks a rate, and so does the flow: nothing to show.
        let base = try #require(valuator.change(of: "brokerage", from: "2021-11-30", to: "2022-01-01", in: .base))
        #expect(base == valuator.change(of: "brokerage", from: "2021-11-30", to: "2022-01-01"))
        #expect(base.change.change == 0)
        #expect(base.flow == nil)
        #expect(base.problems == [.missingFX(account: "brokerage", from: .usd, to: .eur)])
    }

    @Test func tradesAccountChangeInItsCurrency() throws {
        // Cash 1000 − 751, plus 5 × 155: the deposit is new money, the rest the market.
        let change = try #require(valuator.change(of: "usd-trades", from: "2024-01-01", to: "2024-01-31",
                                                  in: .account))
        #expect(change.change == ValueChange(start: 0, market: 24, newMoney: 1000, other: 0, end: 1024))
        #expect(change.problems.isEmpty)
        let base = try #require(valuator.change(of: "usd-trades", from: "2024-01-01", to: "2024-01-31"))
        #expect(!base.problems.isEmpty)
    }
}

/// What a series couldn't value (``MissingValues``).
struct MissingValuesTests {
    let valuator = Valuator(library: foreignAccountLibrary())

    @Test func missingRatesOfAnAccountsHistory() throws {
        let dates = DateGrid.monthEnds(from: "2018-06-30", through: "2022-03-31")
        let missing = try #require(valuator.missingValues(of: "brokerage", on: dates))
        #expect(missing.gaps.count == 1)
        let gap = try #require(missing.gaps.first)
        #expect(gap.item == .rate(from: .usd, to: .eur))
        #expect(gap.accounts == ["brokerage"])
        #expect(gap.dates.first == "2018-06-30")
        #expect(gap.dates.last == "2021-12-31")
        #expect(gap.dates.count == 43)
        #expect(missing.dates == gap.dates)

        #expect(valuator.missingValues(of: "brokerage", on: dates, in: .account) == nil)
        #expect(valuator.missingValues(of: "bank", on: ["2025-10-31"]) == nil)
    }

    @Test func ratesComeBeforePrices() throws {
        let own = try #require(valuator.missingValues(of: "us-broker", on: ["2025-09-30", "2025-10-31"], in: .account))
        #expect(own.gaps.map(\.item) == [.rate(from: .eur, to: .usd), .price("nope")])
        #expect(own.gaps.map(\.dates) == [["2025-09-30"], ["2025-09-30"]])

        let prices = own.filter { gap in
            if case .price = gap.item { true } else { false }
        }
        let none = own.filter { _ in false }
        #expect(prices?.gaps.map(\.item) == [.price("nope")])
        #expect(none == nil)
    }

    @Test func missingValuesOfNetWorth() throws {
        let missing = try #require(valuator.missingValues(in: .netWorth, on: ["2025-09-30", "2025-10-31"]))
        #expect(missing.gaps.map(\.item) == [.rate(from: .usd, to: .eur), .price("nope")])
        let rate = try #require(missing.gaps.first)
        #expect(rate.accounts == ["us-broker"])
        #expect(rate.dates == ["2025-09-30"])
        #expect(valuator.missingValues(in: .netWorth, on: ["2025-10-31"]) == nil)
        #expect(MissingValues([]) == nil)
    }

    @Test func openAccountsWithoutAValueComeLast() throws {
        // The bank opened in January 2025 but has no value before September.
        let missing = try #require(valuator.missingValues(in: .netWorth, on: ["2025-08-31", "2025-09-30"]))
        #expect(missing.gaps.map(\.item) == [.rate(from: .usd, to: .eur), .price("nope"), .noValuation("bank")])
        #expect(missing.gaps.last?.dates == ["2025-08-31"])
        #expect(missing.gaps.map(\.item.isPriceOrRate) == [true, true, false])
        let fetchable = missing.filter { $0.item.isPriceOrRate }
        #expect(fetchable?.gaps.count == 2)
    }
}
