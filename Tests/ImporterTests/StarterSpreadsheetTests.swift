import Foundation
@testable import Importer
import Model
import Testing
import TestSupport

/// The starter spreadsheet imports as new accounts of the right kinds.
struct StarterSpreadsheetTests {
    @Test func writesAHeaderAndTodaysRow() {
        let csv = StarterSpreadsheet.csv(on: "2026-10-15", amounts: ["Home": d("150000"), "Pension": d("31000.5")])
        #expect(csv == "Date,Home,Mortgage,Pension\n2026-10-15,150000,,31000.5\n")
    }

    /// Filled in: each column becomes a new account of its kind.
    @Test func importsAsAWideFileOfNewAccounts() throws {
        let csv = StarterSpreadsheet.csv(on: "2026-10-15", amounts: ["Home": d("250000"), "Mortgage": d("-100000"),
                                                                     "Pension": d("31000")])
        let session = try ImportSession(data: Data(csv.utf8))
        #expect(session.profile.layout == .wide)
        #expect(session.profile.dateColumn == "Date")
        #expect(session.profile.columns.map(\.target) == [.balance, .balance, .balance])
        let preview = session.preview(against: Library())
        let kinds = Dictionary(uniqueKeysWithValues: preview.newAccounts.map { ($0.account.id, $0.account.kind) })
        #expect(kinds == ["home": .property, "mortgage": .mortgage, "pension": .pensionFund])
        #expect(preview.record(.valuation("home", "2026-10-15"))?.imported.balance == d("250000"))
    }

    /// A column left empty, such as no mortgage, imports nothing.
    @Test func leavesOutAnEmptyColumn() throws {
        let csv = StarterSpreadsheet.csv(on: "2026-10-15", amounts: ["Home": d("150000"), "Pension": d("31000")])
        let preview = try ImportSession(data: Data(csv.utf8)).preview(against: Library())
        #expect(preview.newAccounts.map(\.account.id) == ["home", "pension"])
    }
}
