import Foundation
import Model
import Testing
import TestSupport
import Tracker

/// A current account's bank lines between its values (IMPORT.md, "Lines"):
/// whether they add up, and the money in and out they give. A made-up
/// January: 3,000 pay, 900 rent, 1,500 moved to savings, and a payment the
/// bank's export lists twice.
struct LineStretchTests {
    static func line(_ date: CalendarDate, _ id: BankLineID, _ amount: Decimal, _ statementClass: StatementClass,
                     to other: AccountID? = nil) -> BankLine {
        BankLine(account: "conto", date: date, id: id, amount: amount, statementClass: statementClass,
                 otherAccount: other)
    }

    static func library() -> Library {
        var library = Library(accounts: [
            Account(id: "conto", name: "Conto", kind: .cash, currency: .eur, opened: "2020-01-01"),
            Account(id: "risparmio", name: "Risparmio", kind: .savings, currency: .eur, opened: "2020-01-01"),
        ])
        library.upsert(Valuation(account: "conto", date: "2025-12-31", balance: 1000))
        library.upsert(Valuation(account: "conto", date: "2026-01-31", balance: 1540, moneyIn: 3000,
                                 moneyOut: 960))
        for line in [
            line("2026-01-05", "rent", -900, .spending),
            line("2026-01-12", "shop", -60, .spending),
            line("2026-01-12", "shop-2", -60, .spending),
            line("2026-01-15", "save", -1500, .transfer, to: "risparmio"),
            line("2026-01-27", "pay", 3000, .income),
            line("2026-02-03", "next", -40, .spending),
        ] {
            library.upsert(line)
        }
        return library
    }

    @Test func aStretchWithALineTwiceDoesntAddUp() throws {
        let stretches = Self.library().lineStretches(of: "conto")
        #expect(stretches.map(\.through) == ["2026-01-31", nil])
        let january = stretches[0]
        #expect(january.from == "2025-12-31")
        #expect(january.opening == 1000)
        #expect(january.closing == 1540)
        #expect(january.lines.count == 5)
        #expect(january.amounts.moneyIn == 3000)
        #expect(january.spent == 1020)
        #expect(january.moved == -1500)
        #expect(january.expectedClosing == 1480)
        #expect(january.difference == 60)
        #expect(!january.addsUp)
        // The lines after the last value wait for the next one.
        #expect(stretches[1].from == "2026-01-31")
        #expect(stretches[1].closing == nil)
        #expect(stretches[1].difference == nil)

        // A stretch that doesn't add up isn't counted again.
        var library = Self.library()
        library.countLines(of: "conto")
        #expect(library.valuations(for: "conto").last?.moneyOut == 960)
    }

    @Test func removingTheLineMakesItAddUpAndCountsAgain() throws {
        var library = Self.library()
        var twice = try #require(library.line(BankLineKey(account: "conto", date: "2026-01-12", id: "shop-2")))
        twice.removed = true
        library.upsert(twice)
        let january = try #require(library.lineStretches(of: "conto").first)
        #expect(january.addsUp)
        #expect(january.spent == 960)

        // Marking the rent as moved instead changes the value's money out.
        var rent = try #require(library.line(BankLineKey(account: "conto", date: "2026-01-05", id: "rent")))
        rent.statementClass = .transfer
        library.upsert(rent)
        library.countLines(of: "conto")
        let value = try #require(library.valuations(for: "conto").last)
        #expect(value.moneyIn == 3000)
        #expect(value.moneyOut == 60)
        #expect(value.tax == nil)
    }

    /// A balance typed wrong in January carries into February, which then
    /// doesn't add up either until it's fixed.
    @Test func aFixedBalanceCarriesForward() throws {
        var library = Self.library()
        library.removeLineRecord(BankLineKey(account: "conto", date: "2026-01-12", id: "shop-2"))
        library.upsert(Valuation(account: "conto", date: "2026-01-31", balance: 1600, moneyIn: 3000, moneyOut: 960))
        library.upsert(Valuation(account: "conto", date: "2026-02-28", balance: 1500, moneyIn: 0, moneyOut: 40))
        #expect(library.lineStretches(of: "conto").map(\.difference) == [60, -60])
        library.upsert(Valuation(account: "conto", date: "2026-01-31", balance: 1540, moneyIn: 3000, moneyOut: 960))
        #expect(library.lineStretches(of: "conto").map(\.difference) == [0, 0])
    }

    @Test func valuesWithoutMoneyInAndOutAreLeftAlone() throws {
        var library = Self.library()
        library.upsert(Valuation(account: "conto", date: "2026-01-31", balance: 1540))
        library.countLines(of: "conto")
        #expect(library.valuations(for: "conto").last?.moneyOut == nil)
        #expect(Library().lineStretches(of: "conto").isEmpty)
    }

    /// A savings account's interest is its own, and a tax pot's bill is
    /// only its money out.
    @Test func interestAndATaxPotsBillAreCounted() throws {
        var library = Library(accounts: [
            Account(id: "deposito", name: "Deposito", kind: .savings, currency: .eur, opened: "2020-01-01"),
            Account(id: "pot", name: "Tax pot", kind: .taxPot, currency: .eur, opened: "2020-01-01"),
        ])
        library.upsert(Valuation(account: "deposito", date: "2025-12-31", balance: 1000))
        library.upsert(Valuation(account: "deposito", date: "2026-01-31", balance: d("1012.5"), moneyIn: 0,
                                 moneyOut: 0))
        library.upsert(BankLine(account: "deposito", date: "2026-01-31", id: "i", amount: d("12.5"),
                                statementClass: .interest))
        library.upsert(Valuation(account: "pot", date: "2025-12-31", balance: 1000))
        library.upsert(Valuation(account: "pot", date: "2026-01-31", balance: 700, moneyIn: 0, moneyOut: 0))
        library.upsert(BankLine(account: "pot", date: "2026-01-20", id: "t", amount: -300, statementClass: .tax))
        library.upsert(BankLine(account: "pot", date: "2026-01-25", id: "g", amount: 50, statementClass: .oneOff))
        library.upsert(BankLine(account: "pot", date: "2026-01-26", id: "h", amount: -50, statementClass: .transfer))
        library.countLines(of: "deposito")
        library.countLines(of: "pot")
        let deposito = try #require(library.valuations(for: "deposito").last)
        #expect(deposito.interest == d("12.5"))
        #expect(deposito.moneyIn == 0)
        let pot = try #require(library.valuations(for: "pot").last)
        #expect(pot.moneyOut == 300)
        #expect(pot.tax == nil)
        #expect(pot.oneOff == 50)
    }

    @Test func theExampleLibrarysSeptemberAddsUp() throws {
        let library = try Fixtures.exampleLibrary()
        let stretches = library.lineStretches(of: "conto-fineco")
        #expect(stretches.count == 1)
        #expect(stretches.first?.addsUp == true)
        #expect(stretches.first?.spent == d("2554.65"))
        #expect(stretches.first?.moved == -1150)
        var counted = library
        counted.countLines(of: "conto-fineco")
        #expect(counted.valuations(for: "conto-fineco") == library.valuations(for: "conto-fineco"))
    }
}
