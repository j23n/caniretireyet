import Foundation
import Model
import Testing
import Tracker
@testable import CanIRetireYet

/// The months screens' logic (UI.md, "Your months" and "A month's lines"):
/// which lines a filter shows, what a line's editor saves, and typed
/// totals. A made-up September of a current account that opens at 1,000
/// and closes at 1,500: pay of 1,000 and two shop payments of 400 and 100.
struct MonthsDataTests {
    private static func line(_ date: CalendarDate, _ id: BankLineID, _ amount: Decimal, _ text: String,
                             _ statementClass: StatementClass) -> BankLine {
        BankLine(account: "conto", date: date, id: id, amount: amount, text: text, statementClass: statementClass,
                 source: .import)
    }

    private static func library() -> Library {
        var library = Library(accounts: [
            Account(id: "conto", name: "Conto", kind: .cash, currency: .eur, opened: "2020-01-01"),
            Account(id: "risparmio", name: "Risparmio", kind: .savings, currency: .eur, opened: "2020-01-01"),
        ])
        library.upsert(Valuation(account: "conto", date: "2026-08-31", balance: 1000))
        library.upsert(Valuation(account: "conto", date: "2026-09-30", balance: 1500, moneyIn: 0, moneyOut: 0))
        library.save([
            line("2026-09-10", "pay", 1000, "Stipendio ACME", .income),
            line("2026-09-12", "shop1", -400, "Esselunga Milano 1234", .spending),
            line("2026-09-20", "shop2", -100, "Esselunga Milano 5678", .spending),
        ])
        return library
    }

    private static func september(_ library: Library) throws -> AccountMonth {
        try #require(library.accountMonth(of: "conto", through: "2026-09-30"))
    }

    @Test func theMonthAddsUpWithLinesToCheck() throws {
        let month = try Self.september(Self.library())
        #expect(month.status == .toCheck(3))
        let totals = MonthTotals(month)
        #expect(totals.cameIn == 1000)
        #expect(totals.spent == 500)
        #expect(totals.saved == 500)
    }

    @Test func filtersShowTheirLines() throws {
        var library = Self.library()
        var shop = try #require(library.lines(for: "conto").first { $0.id == "shop2" })
        shop.removed = true
        library.save([shop])
        let lines = try Self.september(library).lines
        #expect(lines.filter(MonthLineFilter.toCheck.shows).map(\.id) == ["pay", "shop1"])
        #expect(lines.filter(MonthLineFilter.spending.shows).map(\.id) == ["shop1"])
        #expect(lines.filter(MonthLineFilter.removed.shows).map(\.id) == ["shop2"])
        #expect(lines.filter(MonthLineFilter.all.shows).count == 3)
    }

    /// Money moved to savings, given to the other line from the same shop
    /// too: both are confirmed, and only the first keeps the note.
    @Test func anEditGoesToTheSimilarLines() throws {
        var library = Self.library()
        let month = try Self.september(library)
        let shop = try #require(month.lines.first { $0.id == "shop1" })
        var edit = MonthLineEdit(shop)
        #expect(edit.phrase == "Esselunga Milano")
        edit.statementClass = .transfer
        edit.other = "risparmio"
        edit.note = "  saved  "
        edit.appliesToSimilar = true
        edit.apply(to: shop, in: month, library: &library)

        let lines = library.lines(for: "conto")
        let shops = lines.filter { $0.id != "pay" }
        let classes = shops.map(\.statementClass)
        let others = shops.map(\.otherAccount)
        let confirmed = shops.map(\.isConfirmed)
        let notes = shops.map(\.note)
        let pay = lines.first { $0.id == "pay" }
        let september = try Self.september(library)
        let risparmio: AccountID = "risparmio"
        #expect(classes == [StatementClass.transfer, StatementClass.transfer])
        #expect(others == [risparmio, risparmio])
        #expect(confirmed == [true, true])
        #expect(notes == ["saved", nil])
        #expect(pay?.isConfirmed == false)
        #expect(september.status == .toCheck(1))
    }

    @Test func aClassOtherThanMovedForgetsTheOtherAccount() throws {
        let library = Self.library()
        let month = try Self.september(library)
        var shop = try #require(month.lines.first { $0.id == "shop1" })
        shop.statementClass = .transfer
        shop.otherAccount = "risparmio"
        var edit = MonthLineEdit(shop)
        edit.statementClass = .oneOff
        let changed = edit.changedLines(shop, in: month, library: library)
        #expect(changed.count == 1)
        #expect(changed.first?.otherAccount == nil)
        #expect(changed.first?.statementClass == .oneOff)
    }

    /// Four typed numbers: what moved between your accounts is the rest.
    @Test func typedTotalsMoveTheRest() {
        let totals = MonthTypedTotals(opening: PreviewLibrary.d("412.30"), spent: PreviewLibrary.d("287.40"),
                                      closing: PreviewLibrary.d("424.90"))
        #expect(totals.expectedClosing == PreviewLibrary.d("124.90"))
        #expect(totals.moved == 300)
        #expect(MonthTypedTotals(opening: 1000, cameIn: 100, spent: 50, tax: 20, closing: 900).moved == -130)
        #expect(MonthTypedTotals(opening: nil, closing: 10).moved == nil)
        #expect(MonthTypedTotals(opening: 10, closing: nil).moved == nil)
    }

    @Test func monthWords() {
        let locale = Locale(identifier: "en_US")
        #expect(MonthText.title("2026-10-31", locale: locale) == "October 2026")
        #expect(MonthText.kind(.transfer, other: "Risparmio") == "Moved to Risparmio")
        #expect(MonthText.kind(.ignore, other: nil) == "Not counted")
        #expect(MonthText.classes(recordsInterest: false).contains(.interest) == false)
        #expect(MonthText.classes(recordsInterest: true).contains(.interest))
    }
}
