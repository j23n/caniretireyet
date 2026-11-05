import Foundation
import Model
import Testing
import TestSupport
import Tracker

private extension ChangeReport {
    /// The change of one account, if it's in the report.
    func change(of account: AccountID) -> AccountChange? {
        accounts.first { $0.account == account }
    }
}

/// The waterfall of the example library, worked out by hand.
struct ExampleLibraryChangeTests {
    let valuator: Valuator

    init() throws {
        valuator = Valuator(library: try Fixtures.exampleLibrary())
    }

    @Test func sinceTheLastCheckIn() throws {
        let report = try #require(valuator.changeSinceLastCheckIn(asOf: "2026-10-10"))
        #expect(report.from == "2026-08-31")
        #expect(report.to == "2026-09-30")
        #expect(report.isComplete)
        #expect(report.unknownSavedAccounts.isEmpty)
        #expect(report.accounts.map(\.account) == [
            "casa", "conto-deposito", "conto-fineco", "directa", "fondo-pensione", "gold-coins", "ledger-wallet",
            "mutuo-casa", "tfr",
        ])

        let total = report.total
        #expect(total.start.rounded(10) == valuator.netWorth(on: "2026-08-31").total.rounded(10))
        #expect(total.end.rounded(10) == valuator.netWorth(on: "2026-09-30").total.rounded(10))
        // 500 − 304.65 + 11.3 + 1,325 + 650.
        #expect(total.saved == d("2181.65"))
        #expect(total.market.rounded(6) == d("3236.011765"))
        #expect(total.other == 0)
        #expect((total.start + total.market + total.saved + total.other).rounded(20) == total.end.rounded(20))

        let directa = try #require(report.change(of: "directa")?.change)
        #expect(directa.market == d("1307.625"))
        #expect(directa.saved == d("11.3"))
        // Contributions for the quarter, and the fund's return net of them.
        let fund = try #require(report.change(of: "fondo-pensione")?.change)
        #expect(fund.saved == 1325)
        #expect(fund.market == d("-865.23"))
        // Unchanged quantities follow prices.
        #expect(report.change(of: "gold-coins")?.change.market == d("-121.29"))
        #expect(report.change(of: "ledger-wallet")?.change.market.rounded(6) == d("2879.856765"))
        #expect(report.change(of: "tfr")?.change == ValueChange(start: d("10760.2"), market: 0, saved: 0,
                                                               other: 0, end: d("10760.2")))
        #expect(report.change(of: "mutuo-casa")?.change.saved == 650)
    }

    /// The Overview's *This year*: from 31 December of last year to the day.
    @Test func thisYear() throws {
        let report = try #require(valuator.changeThisYear(asOf: "2026-10-10"))
        #expect(report.from == "2025-12-31")
        #expect(report.to == "2026-10-10")
        // Net worth on those days, so a wrong start or a missing account shows.
        #expect(report.total.start.rounded(10) == valuator.total(on: "2025-12-31", in: .netWorth).total.rounded(10))
        #expect(report.total.end.rounded(10) == valuator.total(on: "2026-10-10", in: .netWorth).total.rounded(10))
    }

    /// The home's value went up 7.000 € without a saved: nothing says what
    /// was saved into it, so its change is other.
    @Test func aBalanceThatAsksForSavedWithoutIt() throws {
        let report = valuator.change(from: "2026-05-31", to: "2026-06-30")
        #expect(report.unknownSavedAccounts.isEmpty)
        let home = try #require(report.change(of: "casa"))
        #expect(home.saved == nil)
        #expect(home.change.market == 0)
        #expect(home.change.saved == 0)
        #expect(home.change.other == 7000)
        #expect(report.total.other == 7000)
        // Plan assets don't include the home.
        #expect(valuator.change(from: "2026-05-31", to: "2026-06-30", in: .planAssets).total.other == 0)
    }

    @Test func aClosedAccountEndsAtZeroAsSaved() throws {
        let report = valuator.change(from: "2025-10-31", to: "2025-11-30")
        let oldBank = try #require(report.change(of: "old-bank"))
        #expect(oldBank.change == ValueChange(start: 850, market: 0, saved: -850, other: 0, end: 0))
        // Its money arrived in the current account, so the two cancel out.
        #expect(report.change(of: "conto-fineco")?.change.saved == d("1285.45"))
        let directa = try #require(report.change(of: "directa")?.change)
        #expect(directa.market == d("439.4"))
        #expect(directa.saved == d("1267.5"))
        #expect(report.change(of: "conto-deposito")?.change.market == d("31.25"))
        // No valuation after the import: what the fund saved is zero, not unknown.
        #expect(report.change(of: "fondo-pensione")?.saved == 0)
        #expect(valuator.change(from: "2025-12-31", to: "2026-01-31").change(of: "old-bank") == nil)
    }

    @Test func relativeChange() {
        let change = ValueChange(start: 200, market: 10, saved: 20, other: -2, end: 228)
        #expect(change.change == 28)
        #expect(change.relativeChange == d("0.14"))
        #expect(ValueChange.zero.relativeChange == nil)
    }
}

/// Hand-made cases for each rule of the split.
struct ChangeRuleTests {
    private func library() -> Library {
        var library = Library(accounts: [
            Account(id: "dollars", name: "Dollars", kind: .cash, currency: .usd, opened: "2025-01-01"),
            Account(id: "fresh", name: "Fresh", kind: .savings, currency: .eur, opened: "2025-02-10"),
        ])
        library.upsert(Valuation(account: "dollars", date: "2025-01-31", balance: 1000))
        library.upsert(FXRecord(base: .eur, quote: .usd, date: "2025-01-31", rate: d("1.25")))
        library.upsert(FXRecord(base: .eur, quote: .usd, date: "2025-02-28", rate: 1))
        return library
    }

    @Test func foreignBalanceWithoutANewValuationIsMarket() throws {
        let change = try #require(Valuator(library: library()).change(of: "dollars", from: "2025-01-31",
                                                                      to: "2025-02-28"))
        #expect(change.saved == 0)
        #expect(change.change == ValueChange(start: 800, market: 200, saved: 0, other: 0, end: 1000))
    }

    /// What a cash value saved is worked out: the whole change, 100 $; the
    /// FX effect is market.
    @Test func foreignBalanceWithoutSavedSplitsOffTheFXEffect() throws {
        var library = library()
        library.upsert(Valuation(account: "dollars", date: "2025-02-28", balance: 1100))
        let change = try #require(Valuator(library: library).change(of: "dollars", from: "2025-01-31",
                                                                    to: "2025-02-28"))
        #expect(change.saved == 100)
        #expect(change.change == ValueChange(start: 800, market: 200, saved: 100, other: 0, end: 1100))

        library.upsert(Valuation(account: "dollars", date: "2025-02-28", balance: 1100, saved: 100))
        let known = try #require(Valuator(library: library).change(of: "dollars", from: "2025-01-31",
                                                                   to: "2025-02-28"))
        #expect(known.change == ValueChange(start: 800, market: 200, saved: 100, other: 0, end: 1100))
    }

    /// A current account's balances, without saved amounts: its first
    /// value is other, what it held when its records start, and each change
    /// after it is saved.
    @Test func importedBalancesCountTheirChangesAsSaved() throws {
        var library = Library(accounts: [
            Account(id: "imported", name: "Imported", kind: .cash, currency: .eur, opened: "2025-01-01"),
        ])
        library.upsert(Valuation(account: "imported", date: "2025-01-31", balance: 1000))
        library.upsert(Valuation(account: "imported", date: "2025-02-28", balance: 1200))
        library.upsert(Valuation(account: "imported", date: "2025-03-31", balance: 1150))
        let valuator = Valuator(library: library)

        let report = valuator.change(from: "2024-12-31", to: "2025-03-31")
        let change = try #require(report.change(of: "imported"))
        #expect(change.saved == nil)
        #expect(change.change == ValueChange(start: 0, market: 0, saved: 150, other: 1000, end: 1150))
        #expect(report.unknownSavedAccounts.isEmpty)

        let march = try #require(valuator.change(of: "imported", from: "2025-02-28", to: "2025-03-31"))
        #expect(march.change == ValueChange(start: 1200, market: 0, saved: -50, other: 0, end: 1150))
    }

    @Test func anAccountOpenedInThePeriodStartsAtZero() throws {
        var library = library()
        library.upsert(Valuation(account: "fresh", date: "2025-02-28", balance: 5000, saved: 5000))
        let report = Valuator(library: library).change(from: "2025-01-31", to: "2025-02-28")
        #expect(report.change(of: "fresh")?.change == ValueChange(start: 0, market: 0, saved: 5000, other: 0,
                                                                 end: 5000))
        #expect(report.total.start + report.total.market + report.total.saved + report.total.other
            == report.total.end)
    }

    /// A library whose first value is on 31 December has a change this year
    /// from the next day; one whose first value is in January has none.
    @Test func thisYearStartsAtTheEndOfLastYear() throws {
        var library = Library(accounts: [
            Account(id: "savings", name: "Savings", kind: .savings, currency: .eur, opened: "2025-01-01"),
        ])
        library.upsert(Valuation(account: "savings", date: "2025-12-31", balance: 1000))
        library.upsert(Valuation(account: "savings", date: "2026-01-31", balance: 1200, saved: 200))
        let valuator = Valuator(library: library)
        #expect(valuator.endOfLastYear(before: "2026-01-01") == "2025-12-31")
        let report = try #require(valuator.changeThisYear(asOf: "2026-01-31"))
        #expect(report.from == "2025-12-31")
        #expect(report.to == "2026-01-31")
        #expect(report.total == ValueChange(start: 1000, market: 0, saved: 200, other: 0, end: 1200))
        // On 31 December 2025 the year still started on 31 December 2024,
        // before the first value.
        #expect(valuator.endOfLastYear(before: "2025-12-31") == nil)

        var later = Library(accounts: [
            Account(id: "savings", name: "Savings", kind: .savings, currency: .eur, opened: "2026-01-01"),
        ])
        later.upsert(Valuation(account: "savings", date: "2026-01-01", balance: 1000))
        #expect(Valuator(library: later).changeThisYear(asOf: "2026-01-31") == nil)
    }
}

/// A dollar fund recorded as cash and positions in a euro library, not as
/// trades, with a price missing at one value and then at the next: what
/// such a value saved is unknown, so only the FX movement of the old value
/// is market, saved is zero and the rest is other (docs/schema/README.md,
/// "Change since the last check-in", "Balance, saved unknown"). 1 € is
/// 1.25 $ on 31 January and 31 March, and 1 $ on 28 February.
struct MissingPriceChangeTests {
    private static func library(lateUnpriced: Bool = true) -> Library {
        var library = Library(
            settings: LibrarySettings(baseCurrency: .eur),
            accounts: [
                Account(id: "bank", name: "Bank", kind: .cash, currency: .eur, opened: "2026-01-01"),
                Account(id: "fund", name: "Fund", kind: .brokerage, currency: .usd, opened: "2026-01-01",
                        valuation: .balance),
            ],
            instruments: [
                Instrument(id: "us", name: "US", kind: .etf, currency: .usd, unit: .share,
                           assetClasses: .single(.equity)),
                Instrument(id: "nu", name: "New", kind: .etf, currency: .usd, unit: .share,
                           assetClasses: .single(.equity)),
                Instrument(id: "late", name: "Late", kind: .etf, currency: .usd, unit: .share,
                           assetClasses: .single(.equity)),
            ])
        library.upsert(FXRecord(base: .eur, quote: .usd, date: "2026-01-31", rate: d("1.25")))
        library.upsert(FXRecord(base: .eur, quote: .usd, date: "2026-02-28", rate: 1))
        library.upsert(FXRecord(base: .eur, quote: .usd, date: "2026-03-31", rate: d("1.25")))
        // `nu` has no price on 31 January; `late` never has one.
        for price in [
            PriceRecord(instrument: "us", date: "2026-01-31", price: 100, currency: .usd),
            PriceRecord(instrument: "us", date: "2026-02-28", price: 110, currency: .usd),
            PriceRecord(instrument: "us", date: "2026-03-31", price: 125, currency: .usd),
            PriceRecord(instrument: "nu", date: "2026-02-28", price: 50, currency: .usd),
            PriceRecord(instrument: "nu", date: "2026-03-31", price: 55, currency: .usd),
        ] {
            library.upsert(price)
        }
        var march = [Position(instrument: "us", quantity: 12), Position(instrument: "nu", quantity: 4)]
        if lateUnpriced { march.append(Position(instrument: "late", quantity: 3)) }
        for valuation in [
            Valuation(account: "fund", date: "2026-01-31", cash: 200, positions: [
                Position(instrument: "us", quantity: 10), Position(instrument: "nu", quantity: 4),
            ]),
            Valuation(account: "fund", date: "2026-02-28", cash: 100, positions: [
                Position(instrument: "us", quantity: 11), Position(instrument: "nu", quantity: 4),
            ]),
            Valuation(account: "fund", date: "2026-03-31", cash: 50, positions: march),
            Valuation(account: "bank", date: "2026-01-31", balance: 1000),
            Valuation(account: "bank", date: "2026-02-28", balance: 1500, moneyIn: 2000, moneyOut: 1500),
            Valuation(account: "bank", date: "2026-03-31", balance: 2000, moneyIn: 2000, moneyOut: 1500),
        ] {
            library.upsert(valuation)
        }
        return library
    }

    let valuator = Valuator(library: Self.library())

    /// 31 January counts `nu` as zero: 160 € of cash and 800 € of `us`.
    /// The 1,200 $ it held then are 240 € more at February's rate; the
    /// rest, `nu`'s 200 € among it, is other, not markets.
    @Test func aPriceMissingAtTheEarlierValue() throws {
        let change = try #require(valuator.change(of: "fund", from: "2026-01-31", to: "2026-02-28"))
        #expect(change.saved == nil)
        #expect(change.problems == [.missingPrice(account: "fund", instrument: "nu")])
        #expect(change.change == ValueChange(start: 960, market: 240, saved: 0, other: 310, end: 1510))
        let report = valuator.change(from: "2026-01-31", to: "2026-02-28")
        #expect(report.unknownSavedAccounts == ["fund"])
        #expect(report.total.saved == 500)
    }

    /// 31 March counts `late` as zero. The 1,510 $ held on 28 February are
    /// 302 € less at March's rate; the rest is other.
    @Test func aPriceMissingAtTheLaterValue() throws {
        let change = try #require(valuator.change(of: "fund", from: "2026-02-28", to: "2026-03-31"))
        #expect(change.saved == nil)
        #expect(change.problems == [.missingPrice(account: "fund", instrument: "late")])
        // 40 € of cash, 1,200 € of `us` and 176 € of `nu`.
        #expect(change.change == ValueChange(start: 1510, market: -302, saved: 0, other: 208, end: 1416))

        // Without `late`, what the value saved is known: its change, 260 $,
        // or 208 € at its date's rate, and markets are the same FX movement.
        let priced = Valuator(library: Self.library(lateUnpriced: false))
        let known = try #require(priced.change(of: "fund", from: "2026-02-28", to: "2026-03-31"))
        #expect(known.saved == 208)
        #expect(known.change == ValueChange(start: 1510, market: -302, saved: 208, other: 0, end: 1416))
    }

    /// A euro fund held in the dollar account has no FX movement in a euro
    /// library: each part of the old value moves with its own currency.
    /// On 31 January the fund holds 500 € of `eu` and 1,000 $ of `us`
    /// (800 €), 1,300 € in all. At February's rate the dollars are 1,000 €,
    /// so market is 200 €; counting all of it in dollars would make it
    /// 325 €. `eu`'s rise to 110 € is other, with `late` unpriced.
    @Test func eachPartMovesWithItsOwnCurrency() throws {
        var library = Library(
            settings: LibrarySettings(baseCurrency: .eur),
            accounts: [
                Account(id: "fund", name: "Fund", kind: .brokerage, currency: .usd, opened: "2026-01-01",
                        valuation: .balance),
            ],
            instruments: [
                Instrument(id: "eu", name: "EU", kind: .etf, currency: .eur, unit: .share,
                           assetClasses: .single(.equity)),
                Instrument(id: "us", name: "US", kind: .etf, currency: .usd, unit: .share,
                           assetClasses: .single(.equity)),
                Instrument(id: "late", name: "Late", kind: .etf, currency: .usd, unit: .share,
                           assetClasses: .single(.equity)),
            ])
        library.upsert(FXRecord(base: .eur, quote: .usd, date: "2026-01-31", rate: d("1.25")))
        library.upsert(FXRecord(base: .eur, quote: .usd, date: "2026-02-28", rate: 1))
        for price in [
            PriceRecord(instrument: "eu", date: "2026-01-31", price: 100, currency: .eur),
            PriceRecord(instrument: "eu", date: "2026-02-28", price: 110, currency: .eur),
            PriceRecord(instrument: "us", date: "2026-01-31", price: 100, currency: .usd),
            PriceRecord(instrument: "us", date: "2026-02-28", price: 100, currency: .usd),
        ] {
            library.upsert(price)
        }
        library.upsert(Valuation(account: "fund", date: "2026-01-31", cash: 0, positions: [
            Position(instrument: "eu", quantity: 5), Position(instrument: "us", quantity: 10),
        ]))
        library.upsert(Valuation(account: "fund", date: "2026-02-28", cash: 0, positions: [
            Position(instrument: "eu", quantity: 5), Position(instrument: "us", quantity: 10),
            Position(instrument: "late", quantity: 2),
        ]))
        let change = try #require(Valuator(library: library).change(of: "fund", from: "2026-01-31",
                                                                    to: "2026-02-28"))
        #expect(change.saved == nil)
        #expect(change.problems == [.missingPrice(account: "fund", instrument: "late")])
        #expect(change.change == ValueChange(start: 1300, market: 200, saved: 0, other: 50, end: 1550))
    }

    /// The fund's first value, what it held when its records start, is
    /// other, as a balance's is; with February's, whose saved is unknown,
    /// all of it is.
    @Test func theFirstValueIsOther() throws {
        let january = try #require(valuator.change(of: "fund", from: "2025-12-31", to: "2026-01-31"))
        #expect(january.saved == nil)
        #expect(january.change == ValueChange(start: 0, market: 0, saved: 0, other: 960, end: 960))
        let both = try #require(valuator.change(of: "fund", from: "2025-12-31", to: "2026-02-28"))
        #expect(both.change == ValueChange(start: 0, market: 0, saved: 0, other: 1510, end: 1510))
    }

    /// What wasn't known to be saved isn't saved anywhere: each stretch
    /// and the savings rate count the fund's as zero, and the bank's 500 €
    /// a month alone.
    @Test func theSavingsRateDoesntCountItAsSaved() throws {
        let stretches = valuator.savedStretches(between: ["2026-01-31", "2026-02-28", "2026-03-31"], in: .netWorth)
        #expect(stretches.map { $0.saved["fund"] } == [0, 0])
        #expect(stretches.map(\.total) == [500, 500])

        let rate = try #require(valuator.savingsRate(from: "2026-02-01", through: "2026-03-31"))
        #expect(rate.savedByAccount == ["bank": 1000, "fund": 0])
        #expect(rate.saved == 1000)
        #expect(rate.spent == 3000)
        #expect(!rate.isPriced)
    }
}
