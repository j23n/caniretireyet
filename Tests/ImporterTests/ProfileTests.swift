import Foundation
@testable import Importer
import Model
import Testing
import TestSupport

struct ProfileTests {
    /// Building the example library's `net-worth-sheet` profile from its file, step by step.
    private func italianSession() throws -> ImportSession {
        var session = try Samples.session("italian-excel-1252.csv")
        try session.reread(with: ImportFileSettings(excludeRows: ["Totale"]))
        session.setMapping(ImportColumn(target: .quantity, account: "ledger-wallet", instrument: "btc"), forColumn: 4)
        session.setMapping(ImportColumn(target: .balance, account: "gold-coins"), forColumn: 5)
        session.match(account: "Fineco", to: "conto-fineco")
        session.profile.defaults.empty = .skip
        session.profile.onConflict = .ask
        return session
    }

    @Test func buildsAProfileFromAFinishedSession() throws {
        let library = try Fixtures.exampleLibrary()
        let profile = try italianSession().makeProfile(id: "net-worth-sheet", name: "My net worth spreadsheet",
                                                       library: library)
        #expect(profile == library.importProfiles["net-worth-sheet"])
    }

    @Test func profileRoundTripsThroughJSONAndImportsTheSameRecords() throws {
        let library = try Fixtures.exampleLibrary()
        let session = try italianSession()
        var preview = session.preview(against: library)
        preview.resolveConflicts(.overwrite)
        let result = preview.apply(to: library)

        let profile = session.makeProfile(id: "sheet", name: "Sheet", library: result.library)
        let json = try JSONEncoder().encode(profile)
        let decoded = try JSONDecoder().decode(ImportProfile.self, from: json)
        #expect(decoded == profile)

        let again = try Importer.preview(Samples.data("italian-excel-1252.csv"), profile: decoded,
                                         library: result.library)
        #expect(again.records.map(\.imported) == preview.records.map(\.imported))
        #expect(again.records.allSatisfy { $0.status == .identical })
        #expect(again.issues.isEmpty)
        #expect(again.ambiguities.isEmpty)
    }

    @Test func writesDetectedFormatsAndOverrides() throws {
        var session = try ImportSession(data: Data(
            "Date,Balance EUR,Rate,Qty\n2026-01-31,\"1,234.50\",\"12,5%\",\"1.234,5\"\n".utf8))
        session.setMapping(ImportColumn(target: .balance, account: "cash"), forColumn: 2)
        session.setMapping(ImportColumn(target: .price, instrument: "etf"), forColumn: 3)
        session.setMapping(ImportColumn(target: .quantity, account: "broker", instrument: "etf"), forColumn: 4)
        let profile = session.makeProfile(id: "p", name: "P", library: Library())
        #expect(profile.file == ImportFileSettings(encoding: .utf8, delimiter: ",", headerRow: 1,
                                                   excludeRows: ["Totale", "Total"]))
        #expect(profile.defaults.date == ImportDateFormat(pattern: "yyyy-MM-dd"))
        // The most common format becomes the default; the others are overrides.
        #expect(profile.defaults.number == ImportNumberFormat(decimal: ",", thousands: "."))
        #expect(profile.columns.map(\.format) == [
            ImportFormat(number: ImportNumberFormat(decimal: ".", thousands: ",")),
            ImportFormat(number: ImportNumberFormat(percent: true)),
            nil,
        ])
    }

    @Test func savedProfileRunsOnANewFile() throws {
        let library = try Fixtures.exampleLibrary()
        let profile = try #require(library.importProfiles["net-worth-sheet"])
        // Columns reordered, "Oro" gone, a new column.
        let file = "Data;Directa;Conto Fineco;BTC (qtà);Conto nuovo;Note\n30/04/2026;41.000,00;5.600,00;0,23;1.000,00;\n"
        let session = try ImportSession(data: Data(file.utf8), profile: profile)
        #expect(session.columnRoles == [.date, .mapped(profileColumn: 1), .mapped(profileColumn: 0),
                                        .mapped(profileColumn: 2), .unknown, .mapped(profileColumn: 4)])
        let preview = session.preview(against: library)
        #expect(preview.issues == [
            ImportIssue(kind: .missingColumn, header: "Oro"),
            ImportIssue(kind: .unknownColumn, column: 5, header: "Conto nuovo"),
        ])
        #expect(preview.issues.map(\.description) == [
            "“Oro” from the profile isn't in the file.",
            "“Conto nuovo” isn't in the profile, so it isn't imported until you map it.",
        ])
        #expect(preview.newAccounts.isEmpty)
        #expect(preview.records.map(\.imported.key) == [
            .valuation("conto-fineco", "2026-04-30"), .valuation("directa", "2026-04-30"),
            .valuation("ledger-wallet", "2026-04-30"),
        ])
        #expect(preview.record(.valuation("directa", "2026-04-30"))?.imported.balance == 41000)
        #expect(preview.record(.valuation("conto-fineco", "2026-04-30"))?.imported.balance == 5600)
    }

    @Test func headersMatchIgnoringCaseAndAccents() throws {
        let profile = ImportProfile(id: "p", name: "P", layout: .wide, dateColumn: "Data",
                                    columns: [ImportColumn(header: "Qtà BTC", target: .balance, account: "x")])
        let session = try ImportSession(data: Data("DATA;qta btc\n2026-01-31;1\n".utf8), profile: profile)
        #expect(session.issues.isEmpty)
        #expect(session.preview(against: Library()).records.count == 1)
    }

    @Test func columnsByPositionWhenThereIsNoHeader() throws {
        let profile = ImportProfile(
            id: "p", name: "P", file: ImportFileSettings(delimiter: ";", headerRow: 0), layout: .wide,
            columns: [ImportColumn(index: 2, target: .balance, account: "cash"), ImportColumn(index: 1, field: .date)])
        let session = try ImportSession(data: Data("31/01/2026;100\n28/02/2026;200\n".utf8), profile: profile)
        let preview = session.preview(against: Library())
        #expect(preview.records.map(\.imported.balance) == [100, 200])
        #expect(preview.newAccounts.map(\.account.id) == ["cash"])

        let rebuilt = session.makeProfile(id: "p", name: "P", library: Library())
        #expect(rebuilt.columns == [ImportColumn(index: 1, field: .date),
                                    ImportColumn(index: 2, target: .balance, account: "cash")])
        #expect(rebuilt.dateColumn == nil)
    }

    @Test func longProfileRemembersEveryName() throws {
        var session = try Samples.session("long-format.csv")
        session.match(account: "Fineco", to: "conto-fineco")
        var preview = session.preview(against: smallLibrary())
        preview.resolveConflicts(.overwrite)
        let result = preview.apply(to: smallLibrary())
        let profile = session.makeProfile(id: "bank", name: "Bank", library: result.library)
        #expect(profile.layout == .long)
        #expect(profile.target == .balance)
        #expect(profile.columns == [
            ImportColumn(header: "date", field: .date), ImportColumn(header: "account", field: .account),
            ImportColumn(header: "value", target: .balance, field: .value),
            ImportColumn(header: "currency", field: .currency),
        ])
        #expect(profile.matches.accounts == [
            "Conto Fineco": "conto-fineco", "conto fineco": "conto-fineco", "Fineco": "conto-fineco",
            "FONDO PENSIONE": "fondo-pensione", "Fondo pensione": "fondo-pensione",
            "Crédit Agricole": "credit-agricole", "Credit Agricole": "credit-agricole",
        ])
        #expect(profile.defaults.date == ImportDateFormat(pattern: "yyyy-MM-dd"))

        // Renaming an account doesn't break the next import.
        var renamed = result.library
        renamed.accounts["credit-agricole"]?.name = "CA risparmio"
        let again = try Importer.preview(Samples.data("long-format.csv"), profile: profile, library: renamed)
        #expect(again.newAccounts.isEmpty)
        #expect(again.records.allSatisfy { $0.status == .identical })
    }

    @Test func choosingAnOptionSettlesAnAmbiguity() throws {
        var session = try ImportSession(data: Data("Data;Saldo\n01/02/2026;1\n01/03/2026;2\n".utf8))
        let dates = try #require(session.ambiguities.first)
        try session.choose(1, for: dates)
        #expect(session.ambiguities.isEmpty)
        #expect(session.profile.defaults.date?.pattern == "MM/dd/yyyy")
        #expect(session.preview(against: Library()).records.map(\.imported.key.date) == [date("2026-01-02"),
                                                                                           date("2026-01-03")])

        session = try ImportSession(data: Data("Date,Qty\n2026-01-31,\"1,500\"\n".utf8))
        let numbers = try #require(session.ambiguities.first)
        #expect(numbers.kind == .numberFormat)
        #expect(session.preview(against: Library()).records.first?.imported.balance == 1500)
        try session.choose(1, for: numbers)
        #expect(session.ambiguities.isEmpty)
        #expect(session.preview(against: Library()).records.first?.imported.balance == dec("1.5"))

        session = try ImportSession(data: Data("a;b|c\n1;2|3\n".utf8))
        let delimiter = try #require(session.ambiguities.first)
        #expect(delimiter.delimiters == [";", "|"])
        try session.choose(1, for: delimiter)
        #expect(session.table.delimiter == "|")
        #expect(session.ambiguities.isEmpty)
    }

    @Test func changingTheDateColumn() throws {
        var session = try ImportSession(data: Data(
            "Inserito;Data;Conto\n01/03/2026;31/01/2026;100\n01/04/2026;28/02/2026;200\n".utf8))
        #expect(session.profile.dateColumn == "Inserito")
        session.setDateColumn(2)
        #expect(session.profile.dateColumn == "Data")
        #expect(session.issues.isEmpty)
        #expect(session.columnRoles == [.mapped(profileColumn: 1), .date, .mapped(profileColumn: 0)])
        #expect(session.preview(against: Library()).records.map(\.imported.key.date) == [date("2026-01-31"),
                                                                                           date("2026-02-28")])
    }

    @Test func rereadingProposesAgainUntilTheMappingIsEdited() throws {
        var session = try Samples.session("titles-totals-utf16.tsv")
        try session.reread(with: ImportFileSettings(headerRow: 5))
        #expect(session.profile.dateColumn == "31/01/2026")
        try session.reread(with: ImportFileSettings())
        #expect(session.profile.dateColumn == "Data")
        session.setMapping(ImportColumn(target: .ignore), forColumn: 4)
        try session.reread(with: ImportFileSettings(excludeRows: ["Totale"]))
        #expect(session.mapping(forColumn: 4)?.target == .ignore)
        // "TOTAL GENERALE" no longer matches the footer rule.
        #expect(session.table.rows.last?.number == 10)
    }
}
