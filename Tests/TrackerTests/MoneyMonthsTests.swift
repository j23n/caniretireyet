import Foundation
import Model
import Testing
import TestSupport
import Tracker

/// Your months (IMPORT.md, "Your months"): each cash or savings account's
/// money in and out up to each check-in, and where it stands. A made-up
/// current account with lines in January, a savings account with typed
/// totals, and February still to come.
struct MoneyMonthsTests {
    static func line(_ date: CalendarDate, _ id: BankLineID, _ amount: Decimal, _ statementClass: StatementClass,
                     confirmed: Bool = true) -> BankLine {
        BankLine(account: "conto", date: date, id: id, amount: amount, statementClass: statementClass,
                 confirmed: confirmed ? true : nil)
    }

    static func library() -> Library {
        var library = Library(accounts: [
            Account(id: "conto", name: "Conto", kind: .cash, currency: .eur, opened: "2020-01-01"),
            Account(id: "risparmio", name: "Risparmio", kind: .savings, currency: .eur, opened: "2020-01-01"),
            Account(id: "broker", name: "Broker", kind: .brokerage, currency: .eur, opened: "2020-01-01"),
        ])
        library.upsert(Valuation(account: "conto", date: "2025-12-31", balance: 1000))
        library.upsert(Valuation(account: "risparmio", date: "2025-12-31", balance: 5000))
        library.upsert(Valuation(account: "conto", date: "2026-01-31", balance: 1600, moneyIn: 3000,
                                 moneyOut: 900))
        library.upsert(Valuation(account: "risparmio", date: "2026-01-31", balance: 6500, moneyIn: 0,
                                 moneyOut: 0))
        library.upsert(Valuation(account: "broker", date: "2026-01-15", balance: 20000))
        for line in [
            line("2026-01-05", "rent", -900, .spending),
            line("2026-01-15", "save", -1500, .transfer),
            line("2026-01-27", "pay", 3000, .income, confirmed: false),
            line("2026-02-03", "shop", -40, .spending, confirmed: false),
        ] {
            library.upsert(line)
        }
        return library
    }

    @Test func eachCheckInHasEveryCashAccountsMonth() throws {
        let months = Self.library().moneyMonths(next: "2026-02-28")
        // The brokerage's own value isn't a check-in of these accounts.
        #expect(months.map(\.through) == ["2026-02-28", "2026-01-31", "2025-12-31"])
        #expect(months.map(\.isCheckedIn) == [false, true, true])

        let january = months[1]
        #expect(january.from == "2025-12-31")
        #expect(january.accounts.map(\.account) == ["conto", "risparmio"])
        let conto = january.accounts[0]
        #expect(conto.opening == 1000)
        #expect(conto.closing == 1600)
        #expect(conto.lines.count == 3)
        #expect(conto.status == .toCheck(1))
        #expect(january.accounts[1].status == .typed)
        #expect(january.toDo.map(\.account) == ["conto"])

        // February's lines wait for the bank's balance; savings has nothing yet.
        let february = months[0]
        #expect(february.accounts[0].status == .needsBalance)
        #expect(february.accounts[0].opening == 1600)
        #expect(february.accounts[1].status == .notDone)
        #expect(!AccountMonth.Status.needsBalance.isDone)

        // The first values have nothing before them.
        #expect(months[2].accounts.map(\.status) == [.balanceOnly, .balanceOnly])
    }

    @Test func aMonthOffByALineSaysByHowMuch() throws {
        var library = Self.library()
        library.upsert(Self.line("2026-01-20", "fee", d("-35.05"), .spending))
        let conto = try #require(library.accountMonth(of: "conto", through: "2026-01-31"))
        #expect(conto.status == .off(d("35.05")))
    }

    @Test func confirmingTheLastLineChecksTheMonth() throws {
        var library = Self.library()
        var pay = try #require(library.line(BankLineKey(account: "conto", date: "2026-01-27", id: "pay")))
        pay.confirmed = true
        library.save([pay])
        let conto = try #require(library.accountMonth(of: "conto", through: "2026-01-31"))
        #expect(conto.status == .checked)
        #expect(conto.status.isDone)
    }

    @Test func theBanksBalanceClosesTheMonthAndCountsItsLines() throws {
        var library = Self.library()
        library.setBankBalance(1560, of: "conto", on: "2026-02-28")
        let value = try #require(library.valuations(for: "conto").last)
        #expect(value.date == "2026-02-28")
        #expect(value.balance == 1560)
        #expect(value.moneyIn == 0)
        #expect(value.moneyOut == 40)
        let february = try #require(library.accountMonth(of: "conto", through: "2026-02-28"))
        #expect(february.status == .toCheck(1))
    }

    @Test func aChangeToAPastMonthShowsInTheMonthsAfter() throws {
        var library = Self.library()
        library.setBankBalance(1560, of: "conto", on: "2026-02-28")
        // January's balance typed wrong: February no longer adds up either.
        library.setBankBalance(1610, of: "conto", on: "2026-01-31")
        let after = library.accountMonths(of: "conto", after: "2026-01-31", next: "2026-03-31")
        #expect(after.map(\.through) == ["2026-02-28", "2026-03-31"])
        #expect(after[0].opening == 1610)
        #expect(after[0].status == .off(-10))
        #expect(after[1].status == .notDone)
    }

    @Test func typedTotalsAreTheValuesMoneyInAndOut() throws {
        var library = Self.library()
        library.saveTypedTotals(of: "risparmio", on: "2026-02-28", balance: 6520, cameIn: 20, spent: 0, tax: 5)
        let value = try #require(library.valuations(for: "risparmio").last)
        #expect(value.balance == 6520)
        #expect(value.moneyIn == 20)
        #expect(value.moneyOut == 5)
        #expect(value.tax == 5)
        let february = try #require(library.accountMonth(of: "risparmio", through: "2026-02-28"))
        #expect(february.status == .typed)
    }
}

extension MoneyMonthsTests {
    @Test func aLimitKeepsTheNewestMonths() {
        let library = Self.library()
        let all = library.moneyMonths(next: "2026-02-28")
        #expect(library.moneyMonths(next: "2026-02-28", limit: 2) == Array(all.prefix(2)))
        #expect(library.moneyMonths(next: "2026-02-28", limit: 9) == all)
        #expect(library.moneyMonthCount(next: "2026-02-28") == 3)
        #expect(library.moneyMonthCount() == 2)
    }

    /// Lines before an account's first value can't be checked against a
    /// balance: the month is done once they're all confirmed.
    @Test func theFirstMonthIsDoneOnceItsLinesAreChecked() throws {
        var library = Self.library()
        library.accounts["nuovo"] = Account(id: "nuovo", name: "Nuovo", kind: .cash, currency: .eur,
                                            opened: "2026-01-01")
        library.upsert(Valuation(account: "nuovo", date: "2026-01-31", balance: 200))
        var shop = BankLine(account: "nuovo", date: "2026-01-10", id: "shop", amount: -50,
                            statementClass: .spending)
        library.upsert(shop)
        let month = try #require(library.accountMonth(of: "nuovo", through: "2026-01-31"))
        #expect(month.status == .firstMonth(1))
        #expect(!month.status.isDone)

        shop.confirmed = true
        library.upsert(shop)
        #expect(library.accountMonth(of: "nuovo", through: "2026-01-31")?.status == .firstMonth(0))
        #expect(library.accountMonth(of: "nuovo", through: "2026-01-31")?.status.isDone == true)
    }
}
