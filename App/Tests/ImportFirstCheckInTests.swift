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

    @Test func quarterEndsAddFewerCheckIns() throws {
        var library = Library()
        library.accounts["conto"] = Account(id: "conto", name: "Conto", kind: .cash, currency: .eur,
                                            opened: "2025-01-01")
        var flow = ImportFlow(library: library)
        flow.open(Data(Self.csv.utf8), fileName: "conto.csv")
        flow.setBatchAccount("conto", forFile: 0)
        let months = try #require(flow.firstCheckIn)
        #expect(months.ends == .months)
        flow.setFirstCheckInEnds(.quarters)
        let quarters = try #require(flow.firstCheckIn)
        #expect(quarters.ends == .quarters)
        #expect(quarters.values.count < months.values.count)
        let checked = quarters.before.map(\.date)
        #expect(checked == quarters.values)
    }

    private static let csv = """
        Data;Importo;Descrizione;Saldo
        05/01/2026;-100,00;Spesa gennaio;900,00
        05/02/2026;-100,00;Spesa febbraio;800,00
        05/03/2026;-100,00;Spesa marzo;700,00
        05/04/2026;-100,00;Spesa aprile;600,00
        """
}
