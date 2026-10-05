import Foundation
@testable import Importer
import Model
import Testing
import TestSupport

/// A row dated before 1900 or more than a week after today is a cell
/// problem: most likely a typo (31/01/2204), which would otherwise import
/// silently and become the file's last date.
struct DateRangeTests {
    private static let today: CalendarDate = "2026-10-04"

    private func preview(_ csv: String, _ edit: (inout ImportSession) -> Void = { _ in }) throws -> ImportPreview {
        var session = try ImportSession(data: Data(csv.utf8))
        edit(&session)
        return session.preview(against: Library(), today: Self.today)
    }

    @Test func aDateTypoIsACellProblem() throws {
        let preview = try preview("""
            Data;Conto Fineco
            31/07/2026;4.100,00
            31/08/2026;4.200,00
            31/01/2204;4.300,00
            30/09/2026;4.400,00
            """)
        #expect(preview.cellErrors.map(\.description) == [
            "Row 4, “Data”: “31/01/2204”: after 2026-10-11, more than a week from today",
        ])
        #expect(preview.lastDate == "2026-09-30")
        #expect(preview.records.map(\.imported.key.date) == ["2026-07-31", "2026-08-31", "2026-09-30"])
        // The account's values don't stop early, so it isn't proposed as closed.
        #expect(preview.accountChanges.isEmpty)
    }

    @Test func datesBefore1900AreCellProblems() throws {
        let preview = try preview("""
            Date,Cash
            1899-12-31,90
            1900-01-01,100
            2026-01-31,110
            """)
        #expect(preview.cellErrors.map(\.description) == ["Row 2, “Date”: “1899-12-31”: before 1900"])
        #expect(preview.firstDate == "1900-01-01")
    }

    @Test func aWeekAfterTodayIsTheLatestDate() throws {
        let preview = try preview("""
            Date,Cash
            2026-09-30,100
            2026-10-11,110
            2026-10-12,120
            """)
        #expect(preview.cellErrors.map(\.problem) == [.dateInTheFuture(latest: "2026-10-11")])
        #expect(preview.cellErrors.map(\.row) == [4])
        #expect(preview.lastDate == "2026-10-11")
    }

    @Test func longAndTradesLayoutsCheckDatesToo() throws {
        let long = try preview("""
            date,account,value
            2026-09-30,Cash,100
            2062-09-30,Cash,110
            """) { $0.proposeMapping(layout: .long) }
        #expect(long.cellErrors.map(\.problem) == [.dateInTheFuture(latest: "2026-10-11")])
        let trades = try preview("""
            Tipo;Data;Importo
            Versamento;02/09/2026;1000
            Versamento;02/09/2062;500
            """) { session in
            if session.profile.layout != .trades { session.proposeMapping(layout: .trades) }
            session.profile.constants.account = "broker"
        }
        #expect(trades.cellErrors.map(\.problem) == [.dateInTheFuture(latest: "2026-10-11")])
        #expect(trades.cellErrors.map(\.row) == [3])
    }
}
