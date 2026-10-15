import Foundation
@testable import Importer
import Model
import Testing
import TestSupport

/// A spreadsheet's saved column (docs/IMPORT.md, "Saved"): what was saved
/// into an account since its value before, kept as the valuation's `saved` on
/// an account that asks for one.
struct SavedColumnTests {
    private let file = """
        Date;Pension;Pension saved;Cash;Cash saved
        2026-01-31;17000;1325;5210.85;100
        2026-02-28;17500;1325;5300;90
        2026-03-31;;400;;
        """

    private func session() throws -> ImportSession {
        var session = try ImportSession(data: Data(file.utf8))
        session.setMapping(ImportColumn(target: .balance, account: "fondo-pensione"), forColumn: 2)
        session.setMapping(ImportColumn(target: .saved, account: "fondo-pensione"), forColumn: 3)
        session.setMapping(ImportColumn(target: .balance, account: "conto-fineco"), forColumn: 4)
        session.setMapping(ImportColumn(target: .saved, account: "conto-fineco"), forColumn: 5)
        return session
    }

    @Test func isKeptWhereTheAccountAsksForIt() throws {
        let library = smallLibrary()
        let preview = try session().preview(against: library)
        // Saved on a date without a value of the account, in the file or the library.
        #expect(preview.cellErrors.map(\.problem) == [.savedWithoutValue])
        #expect(preview.cellErrors.map(\.cell) == [ImportCellRef(row: 4, column: 3)])

        let result = preview.apply(to: library)
        let pension = result.library.valuations(for: "fondo-pensione")
        #expect(pension.map(\.balance) == [17_000, 17_500])
        #expect(pension.map(\.saved) == [1_325, 1_325])
        // A cash account's saved amount is worked out from its values.
        #expect(result.library.valuations(for: "conto-fineco").map(\.saved) == [nil, nil])
    }

    @Test func aHeaderThatSaysSoIsProposed() throws {
        let file = "Data;Fondo pensione;Fondo pensione (versato)\n31/01/2026;17000;1325\n"
        let session = try ImportSession(data: Data(file.utf8))
        #expect(session.mapping(forColumn: 2)?.target == .balance)
        #expect(session.mapping(forColumn: 3)?.target == .saved)
    }
}
