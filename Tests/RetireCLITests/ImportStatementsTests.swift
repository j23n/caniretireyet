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
        /// The first file's statement lines.
        func finecoLines(_ extra: [String]) async throws -> [[String: Any]] {
            let json = try parseJSON(await retire(arguments + extra + ["--json"], today: Self.today).output)
            let files = try #require(json["files"] as? [[String: Any]])
            #expect(files.map { $0["account"] as? String } == ["conto-fineco", "conto-deposito"])
            #expect(files.map { $0["found"] as? String } == ["named", "balance"])
            let report = try #require(files.first?["report"] as? [String: Any])
            return try #require(report["statementLines"] as? [[String: Any]])
        }
        let lines = try await finecoLines([])
        let paired = try #require(lines.first { $0["text"] as? String == "Bonifico a mio nome" })
        #expect(paired["class"] as? String == "transfer")
        #expect(paired["source"] as? String == "paired")
        #expect(paired["sourceDetail"] as? String == "conto-deposito")

        let answered = try await finecoLines(["--purchase", "fineco-ottobre.csv:5=belongings:Bici"])
        let bike = try #require(answered.first { $0["text"] as? String == "Spesa supermercato" })
        #expect(bike["asset"] as? String == "purchase")
        #expect(bike["assetAccount"] as? String == "bici")
        let both = await retire(arguments + ["--purchase", "fineco-ottobre.csv:5=belongings:Bici",
                                             "--sale", "Spesa supermercato=casa"], today: Self.today)
        #expect(both.status == 1)
        let twice = await retire(arguments + ["--sale", "Bonifico=casa"], today: Self.today)
        #expect(twice.status == 1)

        let applied = await retire(arguments + ["--apply"], today: Self.today)
        #expect(applied.status == 0, "\(applied.all)")
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
        #expect(try library.load().valuations(for: "conto-fineco").last?.date == "2026-09-30")

        let given = await retire(arguments + ["--account", "export.csv=conto-fineco", "--apply"], today: Self.today)
        #expect(given.status == 0, "\(given.all)")
        #expect(try library.load().valuations(for: "conto-fineco").last?.date == "2026-10-31")

        let unknown = await retire(arguments + ["--account", "other.csv=conto-fineco"], today: Self.today)
        #expect(unknown.status == 1)
    }

    /// An account added after the files' first day opens on its first value,
    /// as a single statement's import does.
    @Test func anAccountOpensEarlierForItsStatements() async throws {
        let library = try TemporaryFolder.exampleLibrary()
        try library.write("accounts/conto-nuovo.json", """
            {"currency": "EUR", "id": "conto-nuovo", "kind": "cash", "name": "Conto nuovo", "opened": "2026-11-01"}
            """)
        let folder = try TemporaryFolder()
        try folder.write("export.csv", Self.deposito)
        let applied = await retire(["import", "statements", folder.url("export.csv").path, "--library", library.path,
                                    "--date-format", "dd/MM/yyyy", "--account", "export.csv=conto-nuovo", "--apply"],
                                   today: Self.today)
        #expect(applied.status == 0, "\(applied.all)")
        let written = try library.load()
        #expect(written.accounts["conto-nuovo"]?.opened == "2026-10-31")
        #expect(written.valuations(for: "conto-nuovo").last?.balance == d("17877.95"))
    }
}
