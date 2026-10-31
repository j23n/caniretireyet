import Foundation
import Importer
import Model
import Testing
@testable import CanIRetireYet

/// Past statements' check-ins (UI.md, "Add past statements"): whether each
/// adds up, and the sentences under them.
struct ImportFirstCheckInTests {
    private let locale = Locale(identifier: "en_US")

    private let checks = [
        ImportCheckInCheck(date: "2025-03-31", lines: 3),
        ImportCheckInCheck(date: "2025-06-30", lines: 1, off: Decimal(string: "-12.4"), currency: .eur),
        ImportCheckInCheck(date: "2025-09-30", lines: 2, off: 5, currency: .eur),
    ]

    @Test func aCheckInSaysItsLinesAndWhetherTheyAddUp() {
        #expect(checks[0].title(locale: locale) == "Mar 2025")
        #expect(checks[0].status(locale: locale).text == "3 lines · adds up")
        let off = checks[1].status(locale: locale)
        #expect(off.hasAmounts)
        #expect(off.parts.first == .words("1 line · off by "))
    }

    @Test func theSummaryNamesTheFirstThatsOff() throws {
        let summary = try #require(ImportCheckInCheck.summary(checks, locale: locale))
        #expect(summary.parts.first == .words("1 of 3 add up; Jun 2025 is off by "))
        #expect(summary.parts.last == .words(" and 1 more don't."))
        let all = Array(checks.prefix(1)) + [ImportCheckInCheck(date: "2025-06-30")]
        #expect(ImportCheckInCheck.summary(all, locale: locale)?.text == "All 2 add up.")
        #expect(ImportCheckInCheck.summary([], locale: locale) == nil)
    }

    /// A check-in with nothing to check its lines against, such as an
    /// account's first value, says so and isn't counted as adding up.
    @Test func aCheckInWithoutABalanceBeforeIsLeftOut() {
        var first = ImportCheckInCheck(date: "2025-03-31", lines: 3)
        first.unchecked = true
        #expect(first.status(locale: locale).text == "3 lines · no balance before to check")
        #expect(ImportCheckInCheck(date: "2025-03-31").status(locale: locale).text == "No lines")
        #expect(ImportCheckInCheck.summary([first], locale: locale) == nil)
        let summary = ImportCheckInCheck.summary([first, checks[0]], locale: locale)
        #expect(summary?.text == "It adds up.")
    }

    @Test func quarterEndsAddFewerCheckIns() throws {
        var library = Library()
        library.accounts["conto"] = Account(id: "conto", name: "Conto", kind: .cash, currency: .eur,
                                            opened: "2025-01-01")
        var flow = ImportFlow(library: library)
        flow.open(statements: [(name: "conto.csv", data: Data(Self.csv.utf8))])
        flow.setBatchAccount("conto", forFile: 0)
        let months = try #require(flow.firstCheckIn)
        #expect(months.ends == .months)
        flow.setFirstCheckInEnds(.quarters)
        let quarters = try #require(flow.firstCheckIn)
        #expect(quarters.ends == .quarters)
        #expect(quarters.values.count < months.values.count)
        #expect(quarters.note.contains("past check-in"))
        #expect(quarters.note.contains("one at each quarter end, and at the end of each file"))
        let checked = quarters.before.map(\.date)
        #expect(checked == quarters.values)
    }

    /// Month ends the files reach after the first check-in get check-ins
    /// too, and the card lists them apart from the library's own.
    @Test func checkInsAddedAfterTheFirstAreListed() throws {
        var library = Library()
        library.accounts["conto"] = Account(id: "conto", name: "Conto", kind: .cash, currency: .eur,
                                            opened: "2025-01-01")
        library.upsert(Valuation(account: "conto", date: "2026-01-31", balance: 900))
        var flow = ImportFlow(library: library)
        flow.open(statements: [(name: "conto.csv", data: Data(Self.csv.utf8))])
        flow.setBatchAccount("conto", forFile: 0)
        let first = try #require(flow.firstCheckIn)
        #expect(first.firstCheckIn == "2026-01-31")
        #expect(first.after.map(\.date) == ["2026-01-31"])
        #expect(!first.added.isEmpty)
        #expect(first.added.allSatisfy { $0.date > "2026-01-31" })
        #expect(first.added.map(\.date) == first.added.map(\.date).sorted())
        #expect(first.addedNote(locale: locale).contains("new check-in"))
        #expect(first.afterNote(locale: locale) == "Jan 2026: your check-in stays as it is. "
            + "The lines fill in what came in and went out up to it.")
    }

    @Test func theNotesAfterTheFirstNameTheirSpan() {
        var first = ImportFirstCheckIn(from: "2025-01-05", firstCheckIn: "2026-01-31", ends: .months, values: [])
        first.added = Array(checks.prefix(2))
        #expect(first.addedNote(locale: locale)
            == "Mar 2025 – Jun 2025: 2 new check-ins, with balances from the files.")
        first.added = Array(checks.prefix(1))
        #expect(first.addedNote(locale: locale) == "Mar 2025: 1 new check-in, with balances from the files.")
        first.added = [ImportCheckInCheck(date: "2025-03-15"), ImportCheckInCheck(date: "2025-03-31")]
        #expect(first.addedNote(locale: locale) == "Mar 2025: 2 new check-ins, with balances from the files.")
    }

    private static let csv = """
        Data;Importo;Descrizione;Saldo
        05/01/2026;-100,00;Spesa gennaio;900,00
        05/02/2026;-100,00;Spesa febbraio;800,00
        05/03/2026;-100,00;Spesa marzo;700,00
        05/04/2026;-100,00;Spesa aprile;600,00
        """
}
