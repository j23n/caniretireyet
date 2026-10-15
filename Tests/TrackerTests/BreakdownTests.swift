import Foundation
import Model
import Testing
import TestSupport
import Tracker

/// Breakdowns of the example library on 2026-09-30, worked out by hand.
struct ExampleLibraryBreakdownTests {
    let valuator: Valuator
    /// 0.4515 BTC × 111,400 USD ÷ 1.1398.
    let wallet = d("44128.004913142656606422179329706966134")

    init() throws {
        valuator = Valuator(library: try Fixtures.exampleLibrary())
    }

    @Test func byAssetClass() throws {
        let breakdown = valuator.breakdown(by: .assetClass, on: "2026-09-30")
        #expect(breakdown.isComplete)
        #expect(breakdown.slices.map(\.key) == [
            .assetClass(.realEstate), .assetClass(.equity), .assetClass(.crypto), .assetClass(.cash),
            .assetClass(.other), .assetClass(.gold), .assetClass(.bonds), .debts,
        ])
        // Cash: savings, current account and the broker's cash.
        #expect(breakdown.value(of: .assetClass(.cash)) == d("21888.2"))
        // Equity: 412.5 × 138.42, plus 60% of the pension fund.
        #expect(breakdown.value(of: .assetClass(.equity)) == d("68168.322"))
        #expect(breakdown.value(of: .assetClass(.bonds)) == d("7380.048"))
        #expect(breakdown.value(of: .assetClass(.gold)) == d("9180.72"))
        #expect(breakdown.value(of: .assetClass(.crypto)).rounded(20) == wallet.rounded(20))
        #expect(breakdown.value(of: .assetClass(.realEstate)) == 312_000)
        // TFR has no asset mix.
        #expect(breakdown.value(of: .assetClass(.other)) == d("10760.2"))
        #expect(breakdown.value(of: .debts) == -141_050)
        #expect(breakdown.slice(for: .assetClass(.equity))?.accounts == ["directa", "fondo-pensione"])

        let shares = breakdown.slices.compactMap(\.share).reduce(0, +)
        #expect(shares.rounded(20) == 1)
        #expect(breakdown.assets.rounded(2) == d("473505.49"))
        let debts = try #require(breakdown.slice(for: .debts))
        #expect(try #require(debts.shareOfAssets) < 0)
        #expect(debts.shareOfAssets?.rounded(4) == d("-0.2979"))
    }

    /// Every dimension splits the whole net worth, leaving nothing out.
    @Test(arguments: BreakdownDimension.allCases)
    func slicesSumToNetWorth(dimension: BreakdownDimension) {
        let netWorth = valuator.netWorth(on: "2026-09-30").total
        let breakdown = valuator.breakdown(by: dimension, on: "2026-09-30")
        #expect(breakdown.total.rounded(10) == netWorth.rounded(10))
    }

    @Test func slicesFollowEachAccount() {
        // Bitcoin is priced in dollars; everything else is in euros.
        let currency = valuator.breakdown(by: .currency, on: "2026-09-30")
        #expect(currency.slices.map(\.key) == [.currency(.eur), .currency(.usd)])
        #expect(currency.value(of: .currency(.usd)).rounded(20) == wallet.rounded(20))
        // Accounts without an institution share one slice.
        let institution = valuator.breakdown(by: .institution, on: "2026-09-30")
        #expect(institution.slice(for: .institution(nil))?.accounts == ["casa", "gold-coins", "ledger-wallet"])
        // Locked: pension fund, TFR, the home and its mortgage.
        let liquidity = valuator.breakdown(by: .liquidity, on: "2026-09-30")
        #expect(liquidity.value(of: .liquidity(.locked)) == d("200160.32"))
    }

    @Test func planScopeLeavesOutTheHome() {
        let breakdown = valuator.breakdown(by: .assetClass, on: "2026-09-30", in: .planAssets)
        #expect(breakdown.slice(for: .assetClass(.realEstate)) == nil)
        #expect(breakdown.slice(for: .debts) == nil)
        #expect(breakdown.total.rounded(10) == valuator.total(on: "2026-09-30", in: .planAssets).total.rounded(10))
    }

    @Test func stackedSeriesByAssetClass() {
        let stacked = valuator.breakdownSeries(through: "2026-09-30")
        #expect(stacked.keys == [
            .assetClass(.cash), .assetClass(.bonds), .assetClass(.equity), .assetClass(.gold),
            .assetClass(.crypto), .assetClass(.realEstate), .assetClass(.other), .debts,
        ])
        let totals = valuator.series(through: "2026-09-30")
        #expect(stacked.points.map(\.date) == totals.map(\.date))
        #expect(stacked.points.map { $0.total.rounded(20) } == totals.map { $0.value.rounded(20) })
        let gold = stacked.series(for: .assetClass(.gold))
        #expect(gold.first?.value == d("5728.62"))
        #expect(gold.last?.value == d("9180.72"))
    }
}

/// Asset mixes: instrument mixes, account mixes that don't sum to 1, unknown instruments.
struct AssetMixBreakdownTests {
    @Test func splitsHoldingsAndBalancesByTheirMix() {
        var library = Library(
            accounts: [
                Account(id: "broker", name: "Broker", kind: .brokerage, currency: .eur, opened: "2026-01-01",
                        valuation: .balance),
                Account(id: "fund", name: "Fund", kind: .pensionFund, currency: .eur, opened: "2026-01-01"),
                Account(id: "card", name: "Card", kind: .creditCard, currency: .eur, opened: "2026-01-01"),
                Account(id: "mixed", name: "Mixed", kind: .savings, currency: .eur, opened: "2026-01-01",
                        assetClasses: [.cash: d("0.5"), .bonds: d("0.3")]),
            ],
            instruments: [
                Instrument(id: "balanced", name: "Balanced", kind: .fund, currency: .eur, unit: .share,
                           assetClasses: [.equity: d("0.6"), .bonds: d("0.4")]),
            ])
        library.upsert(Valuation(account: "broker", date: "2026-01-31", cash: 100, positions: [
            Position(instrument: "balanced", quantity: 10), Position(instrument: "mystery", quantity: 2),
        ]))
        library.upsert(Valuation(account: "fund", date: "2026-01-31", balance: 1000))
        library.upsert(Valuation(account: "card", date: "2026-01-31", balance: -200))
        library.upsert(Valuation(account: "mixed", date: "2026-01-31", balance: 800))
        library.upsert(PriceRecord(instrument: "balanced", date: "2026-01-31", price: 50, currency: .eur))
        library.upsert(PriceRecord(instrument: "mystery", date: "2026-01-31", price: 10, currency: .eur))

        let breakdown = Valuator(library: library).breakdown(by: .assetClass, on: "2026-01-31")
        // Cash: the broker's 100 plus 0.5 / 0.8 of the savings account.
        #expect(breakdown.value(of: .assetClass(.cash)) == 600)
        #expect(breakdown.value(of: .assetClass(.equity)) == 300)
        #expect(breakdown.value(of: .assetClass(.bonds)) == 500)
        // An instrument not in the library, and a pension fund without a mix.
        #expect(breakdown.value(of: .assetClass(.other)) == 1020)
        #expect(breakdown.value(of: .debts) == -200)
        #expect(breakdown.total == 2220)
        #expect(breakdown.assets == 2420)
    }
}

/// Stale accounts (docs/schema/README.md, "How values are computed").
struct StalenessTests {
    @Test func exampleLibraryOnTheLatestCheckIn() throws {
        let valuator = Valuator(library: try Fixtures.exampleLibrary())
        let stale = valuator.staleAccounts(on: "2026-09-30")
        #expect(stale.map(\.account) == ["gold-coins", "ledger-wallet", "casa", "tfr"])
        #expect(stale.first?.lastValuation == "2026-03-31")
        #expect(stale.first?.age == 183)
        #expect(stale.last?.age == 92)
        #expect(valuator.staleAccounts(on: "2026-09-30", threshold: 100).map(\.account)
            == ["gold-coins", "ledger-wallet"])
        #expect(valuator.staleAccounts(on: "2026-09-30", in: .planAssets).map(\.account)
            == ["gold-coins", "ledger-wallet", "tfr"])
    }

    @Test func thresholdIsExclusiveAndNeverValuedIsStale() throws {
        var library = try Fixtures.exampleLibrary()
        library.accounts["new"] = Account(id: "new", name: "New", kind: .cash, currency: .eur, opened: "2026-10-01")
        let valuator = Valuator(library: library)
        #expect(valuator.staleness(of: "fondo-pensione", on: "2026-11-14") == nil)
        #expect(valuator.staleness(of: "fondo-pensione", on: "2026-11-15")?.age == 46)
        let never = try #require(valuator.staleness(of: "new", on: "2026-10-02"))
        #expect(never.lastValuation == nil)
        #expect(never.age == nil)
        #expect(valuator.staleAccounts(on: "2026-10-02").first?.account == "new")
        // Closed and not-yet-open accounts are never stale.
        #expect(valuator.staleness(of: "old-bank", on: "2026-10-02") == nil)
        #expect(valuator.staleness(of: "new", on: "2026-09-30") == nil)
    }
}
