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
        #expect(report.unknownFlowAccounts.isEmpty)
        #expect(report.accounts.map(\.account) == [
            "casa", "conto-deposito", "conto-fineco", "directa", "fondo-pensione", "gold-coins", "ledger-wallet",
            "mutuo-casa", "tfr",
        ])

        let total = report.total
        #expect(total.start.rounded(2) == d("327037.83"))
        #expect(total.end.rounded(2) == d("332455.49"))
        // 500 − 304.65 + 11.3 + 1,325 + 650.
        #expect(total.newMoney == d("2181.65"))
        #expect(total.market.rounded(6) == d("3236.011765"))
        #expect(total.other == 0)
        #expect((total.start + total.market + total.newMoney + total.other).rounded(20) == total.end.rounded(20))

        let directa = try #require(report.change(of: "directa")?.change)
        #expect(directa.market == d("1307.625"))
        #expect(directa.newMoney == d("11.3"))
        // Contributions for the quarter, and the fund's return net of them.
        let fund = try #require(report.change(of: "fondo-pensione")?.change)
        #expect(fund.newMoney == 1325)
        #expect(fund.market == d("-865.23"))
        // Unchanged quantities follow prices.
        #expect(report.change(of: "gold-coins")?.change.market == d("-121.29"))
        #expect(report.change(of: "ledger-wallet")?.change.market.rounded(6) == d("2879.856765"))
        #expect(report.change(of: "tfr")?.change == ValueChange(start: d("10760.2"), market: 0, newMoney: 0,
                                                               other: 0, end: d("10760.2")))
        #expect(report.change(of: "mutuo-casa")?.change.newMoney == 650)
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

    /// The home's value went up 7.000 € without a flow: nothing says what
    /// was saved into it, so its change is other.
    @Test func aBalanceThatAsksForAFlowWithoutOne() throws {
        let report = valuator.change(from: "2026-05-31", to: "2026-06-30")
        #expect(report.unknownFlowAccounts.isEmpty)
        let home = try #require(report.change(of: "casa"))
        #expect(home.flow == nil)
        #expect(home.change.market == 0)
        #expect(home.change.newMoney == 0)
        #expect(home.change.other == 7000)
        #expect(report.total.other == 7000)
        // Plan assets don't include the home.
        #expect(valuator.change(from: "2026-05-31", to: "2026-06-30", in: .planAssets).total.other == 0)
    }

    @Test func aClosedAccountEndsAtZeroAsNewMoney() throws {
        let report = valuator.change(from: "2025-10-31", to: "2025-11-30")
        let oldBank = try #require(report.change(of: "old-bank"))
        #expect(oldBank.change == ValueChange(start: 850, market: 0, newMoney: -850, other: 0, end: 0))
        // Its money arrived in the current account, so the two cancel out.
        #expect(report.change(of: "conto-fineco")?.change.newMoney == d("1285.45"))
        let directa = try #require(report.change(of: "directa")?.change)
        #expect(directa.market == d("439.4"))
        #expect(directa.newMoney == d("1267.5"))
        #expect(report.change(of: "conto-deposito")?.change.market == d("31.25"))
        // No valuation after the import: the fund's flow is zero, not unknown.
        #expect(report.change(of: "fondo-pensione")?.flow == 0)
        #expect(valuator.change(from: "2025-12-31", to: "2026-01-31").change(of: "old-bank") == nil)
    }

    @Test func relativeChange() {
        let change = ValueChange(start: 200, market: 10, newMoney: 20, other: -2, end: 228)
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
        #expect(change.flow == 0)
        #expect(change.change == ValueChange(start: 800, market: 200, newMoney: 0, other: 0, end: 1000))
    }

    /// A cash value's new money is worked out: the whole change, 100 $; the
    /// FX effect is market.
    @Test func foreignBalanceWithoutAFlowSplitsOffTheFXEffect() throws {
        var library = library()
        library.upsert(Valuation(account: "dollars", date: "2025-02-28", balance: 1100))
        let change = try #require(Valuator(library: library).change(of: "dollars", from: "2025-01-31",
                                                                    to: "2025-02-28"))
        #expect(change.flow == 100)
        #expect(change.change == ValueChange(start: 800, market: 200, newMoney: 100, other: 0, end: 1100))

        library.upsert(Valuation(account: "dollars", date: "2025-02-28", balance: 1100, flow: 100))
        let known = try #require(Valuator(library: library).change(of: "dollars", from: "2025-01-31",
                                                                   to: "2025-02-28"))
        #expect(known.change == ValueChange(start: 800, market: 200, newMoney: 100, other: 0, end: 1100))
    }

    /// A current account's balances, without flows: its first
    /// value is other, what it held when its records start, and each change
    /// after it new money.
    @Test func importedBalancesCountTheirChangesAsNewMoney() throws {
        var library = Library(accounts: [
            Account(id: "imported", name: "Imported", kind: .cash, currency: .eur, opened: "2025-01-01"),
        ])
        library.upsert(Valuation(account: "imported", date: "2025-01-31", balance: 1000))
        library.upsert(Valuation(account: "imported", date: "2025-02-28", balance: 1200))
        library.upsert(Valuation(account: "imported", date: "2025-03-31", balance: 1150))
        let valuator = Valuator(library: library)

        let report = valuator.change(from: "2024-12-31", to: "2025-03-31")
        let change = try #require(report.change(of: "imported"))
        #expect(change.flow == nil)
        #expect(change.change == ValueChange(start: 0, market: 0, newMoney: 150, other: 1000, end: 1150))
        #expect(report.unknownFlowAccounts.isEmpty)

        let march = try #require(valuator.change(of: "imported", from: "2025-02-28", to: "2025-03-31"))
        #expect(march.change == ValueChange(start: 1200, market: 0, newMoney: -50, other: 0, end: 1150))
    }

    @Test func anAccountOpenedInThePeriodStartsAtZero() throws {
        var library = library()
        library.upsert(Valuation(account: "fresh", date: "2025-02-28", balance: 5000, flow: 5000))
        let report = Valuator(library: library).change(from: "2025-01-31", to: "2025-02-28")
        #expect(report.change(of: "fresh")?.change == ValueChange(start: 0, market: 0, newMoney: 5000, other: 0,
                                                                 end: 5000))
        #expect(report.total.start + report.total.market + report.total.newMoney + report.total.other
            == report.total.end)
    }

    /// A library whose first value is on 31 December has a change this year
    /// from the next day; one whose first value is in January has none.
    @Test func thisYearStartsAtTheEndOfLastYear() throws {
        var library = Library(accounts: [
            Account(id: "savings", name: "Savings", kind: .savings, currency: .eur, opened: "2025-01-01"),
        ])
        library.upsert(Valuation(account: "savings", date: "2025-12-31", balance: 1000))
        library.upsert(Valuation(account: "savings", date: "2026-01-31", balance: 1200, flow: 200))
        let valuator = Valuator(library: library)
        #expect(valuator.endOfLastYear(before: "2026-01-01") == "2025-12-31")
        let report = try #require(valuator.changeThisYear(asOf: "2026-01-31"))
        #expect(report.from == "2025-12-31")
        #expect(report.to == "2026-01-31")
        #expect(report.total == ValueChange(start: 1000, market: 0, newMoney: 200, other: 0, end: 1200))
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
