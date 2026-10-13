import Foundation
import Model
import Testing
import TestSupport

/// `retire import statements` with two made-up October 2026 statements
/// against the example library: Conto Fineco's, named in its file's name,
/// and Conto deposito's, whose balance follows on from its September value.
struct ImportStatementsTests {
    private static let today: CalendarDate = "2026-11-15"

    private static let fineco = """
        Data;Importo;Descrizione
        01/10/2026;-1.200,00;Affitto ottobre
        05/10/2026;-500,00;Bonifico a mio nome
        10/10/2026;3.400,00;Stipendio ottobre
        28/10/2026;-80,00;Spesa supermercato
        """

    private static let deposito = """
        Data;Importo;Descrizione;Saldo
        06/10/2026;500,00;Bonifico in entrata;17.865,55
        31/10/2026;12,40;Interessi;17.877,95
        """

    private func files() throws -> (folder: TemporaryFolder, paths: [String]) {
        let folder = try TemporaryFolder()
        try folder.write("fineco-ottobre.csv", Self.fineco)
        try folder.write("export.csv", Self.deposito)
        return (folder, [folder.url("fineco-ottobre.csv").path, folder.url("export.csv").path])
    }

    @Test func eachFilesAccountIsFoundAndTheTransferPaired() async throws {
        let library = try TemporaryFolder.exampleLibrary()
        let statements = try files()
        defer { withExtendedLifetime(statements.folder) {} }
        let arguments = ["import", "statements"] + statements.paths + ["--library", library.path, "--date-format", "dd/MM/yyyy"]
        let run = await retire(arguments, today: Self.today)
        #expect(run.status == 0, "\(run.all)")
        #expect(run.output.contains("""
              File                Account         Found by                    Days                      Lines  Paired
              fineco-ottobre.csv  conto-fineco    named in the file           2026-10-01 to 2026-10-31      4       1
              export.csv          conto-deposito  follows on from 2026-09-30  2026-10-01 to 2026-10-31      2       1
            """))
        #expect(run.output.contains("  2026-10-05    -500.00  transfer  paired: conto-deposito  Bonifico a mio nome\n"))

        let answered = await retire(arguments + ["--purchase", "fineco-ottobre.csv:5=belongings:Bici"],
                                    today: Self.today)
        #expect(answered.status == 0, "\(answered.all)")
        #expect(answered.output.contains("  2026-10-28     -80.00  transfer  purchase: bici"))
        let twice = await retire(arguments + ["--sale", "Bonifico=casa"], today: Self.today)
        #expect(twice.errors.contains("--sale: “Bonifico” is in 2 lines (fineco-ottobre.csv:3, export.csv:2)"))

        let json = try parseJSON(await retire(arguments + ["--json"], today: Self.today).output)
        let files = try #require(json["files"] as? [[String: Any]])
        #expect(files.map { $0["found"] as? String } == ["named", "balance"])

        let applied = await retire(arguments + ["--apply"], today: Self.today)
        #expect(applied.status == 0, "\(applied.all)")
        #expect(applied.output.contains("Imported: 2 added"))
        let written = try library.load()
        let fineco = try #require(written.valuations(for: "conto-fineco").last)
        #expect(fineco.date == "2026-10-31")
        #expect(fineco.balance == d("5830.55"))
        #expect(fineco.moneyIn == 3400)
        #expect(fineco.moneyOut == 1280)
        let deposito = try #require(written.valuations(for: "conto-deposito").last)
        #expect(deposito.balance == d("17877.95"))
        #expect(deposito.moneyIn == 0)
        #expect(deposito.interest == d("12.4"))

        // One undo takes both files back.
        let undo = await retire(["import", "--undo", "--library", library.path], today: Self.today)
        #expect(undo.status == 0, "\(undo.all)")
        #expect(try library.load().valuations(for: "conto-fineco").last?.date == "2026-09-30")
        #expect(try library.load().valuations(for: "conto-deposito").last?.date == "2026-09-30")
    }

    @Test func aFileWithoutAnAccountStopsTheImportUntilItsGiven() async throws {
        let library = try TemporaryFolder.exampleLibrary()
        let folder = try TemporaryFolder()
        try folder.write("export.csv", Self.fineco)
        let arguments = ["import", "statements", folder.url("export.csv").path, "--library", library.path,
                         "--date-format", "dd/MM/yyyy"]
        let blocked = await retire(arguments + ["--apply"], today: Self.today)
        #expect(blocked.status != 0)
        #expect(blocked.errors.contains("Nothing was imported: export.csv has no account."))
        #expect(try library.load().valuations(for: "conto-fineco").last?.date == "2026-09-30")

        let given = await retire(arguments + ["--account", "export.csv=conto-fineco", "--apply"], today: Self.today)
        #expect(given.status == 0, "\(given.all)")
        #expect(given.output.contains("  export.csv  conto-fineco  --account  "))
        #expect(try library.load().valuations(for: "conto-fineco").last?.date == "2026-10-31")

        let unknown = await retire(arguments + ["--account", "other.csv=conto-fineco"], today: Self.today)
        #expect(unknown.errors.contains("--account: no file is “other.csv”."))
    }
}
