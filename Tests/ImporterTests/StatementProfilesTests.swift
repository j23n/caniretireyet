import Foundation
@testable import Importer
import Model
import Testing
import TestSupport

/// The profiles saved with a batch of statements (IMPORT.md, "Remembering
/// banks and senders"): one per account, a saved profile updated, and
/// every file's rules in each. Made-up accounts and files.
struct StatementProfilesTests {
    private typealias Batch = StatementBatchTests

    /// The current account's February, read like its January.
    private static let february = """
        Data;Importo;Descrizione
        05/02/2026;-900,00;Affitto febbraio
        27/02/2026;3.000,00;Stipendio ACME
        """

    @Test func eachAccountGetsANewProfileWithEveryFilesRules() throws {
        var batch = Batch.batch([("fineco-gennaio.csv", Batch.current), ("export.csv", Batch.savings)])
        batch.editSession(ofFile: 0, library: Batch.library(), today: Batch.today) {
            $0.setStatementRule(.income, for: "Stipendio ACME")
            $0.setStatementRule(movingTo: "risparmio", for: "Bonifico a mio nome")
        }
        batch.editSession(ofFile: 1, library: Batch.library(), today: Batch.today) {
            $0.setStatementRule(movingTo: "conto", for: "Bonifico da Mario Rossi")
        }
        let remembered = batch.rememberedProfiles(in: Batch.library())
        #expect(remembered.map(\.profile.id) == ["fineco-conto-corrente", "banca-esempio-risparmio"])
        #expect(remembered.map(\.profile.name) == ["Fineco, Conto corrente", "Banca Esempio, Risparmio"])
        #expect(remembered.map(\.isNew) == [true, true])
        #expect(remembered.map(\.files) == [[0], [1]])
        #expect(remembered.map(\.profile.constants.account) == ["conto", "risparmio"])
        #expect(remembered.allSatisfy { $0.profile.layout == .statement })
        // Its own rules first, then the others', without moves to or from its own account.
        #expect(remembered[0].profile.rules.map(\.match) == ["Stipendio ACME", "Bonifico a mio nome"])
        #expect(remembered[1].profile.rules.map(\.match) == ["Bonifico da Mario Rossi", "Stipendio ACME"])

        // Read again with the profiles saved, each file finds its account by its profile.
        var library = Batch.library()
        for profile in remembered.map(\.profile) { library.importProfiles[profile.id] = profile }
        let again = Batch.batch([("export.csv", Batch.current), ("export (2).csv", Batch.savings)], library: library)
        #expect(again.files.map(\.account) == ["conto", "risparmio"])
        #expect(again.files.map(\.accountSource) == [.profile, .profile])
        #expect(again.rememberedProfiles(in: library).map(\.isNew) == [false, false])
    }

    @Test func aSavedProfileIsUpdatedByTheFilesOfItsAccount() throws {
        var session = try ImportSession(data: Data(Batch.current.utf8))
        session.proposeMapping(layout: .statement)
        session.profile.constants.account = "conto"
        var library = Batch.library()
        library.importProfiles["fineco"] = session.makeProfile(id: "fineco", name: "Fineco", library: library)

        var batch = Batch.batch([("gennaio.csv", Batch.current), ("febbraio.csv", Self.february),
                                 ("altro.csv", Self.february)], library: library)
        // The third file is read the same way, but it's another account's.
        batch.setAccount("risparmio", forFile: 2, library: library, today: Batch.today)
        let remembered = batch.rememberedProfiles(in: library)
        #expect(remembered.map(\.profile.id) == ["fineco", "banca-esempio-risparmio"])
        #expect(remembered.map(\.profile.name) == ["Fineco", "Banca Esempio, Risparmio"])
        #expect(remembered.map(\.isNew) == [false, true])
        #expect(remembered.map(\.files) == [[0, 1], [2]])
        #expect(remembered.map(\.profile.constants.account) == ["conto", "risparmio"])
    }

    @Test func aClassChosenForALineIsRememberedForTheSameLine() throws {
        var batch = Batch.batch([("fineco-gennaio.csv", Batch.current)])
        // Row 3: "Bonifico a mio nome", 15 January, −1,000.
        batch.editSession(ofFile: 0, library: Batch.library(), today: Batch.today) {
            $0.setStatementClass(.oneOff, forRow: 3)
        }
        let remembered = batch.rememberedProfiles(in: Batch.library(), today: Batch.today)
        let answer = StatementAnswer(date: "2026-01-15", amount: -1000, match: "Bonifico a mio nome",
                                     statementClass: .oneOff)
        #expect(remembered.first?.profile.answers == [answer])

        // The next export covers the same days: the line keeps its class, and nothing else changes.
        var library = Batch.library()
        for profile in remembered.map(\.profile) { library.importProfiles[profile.id] = profile }
        var again = Batch.batch([("export.csv", Batch.current)], library: library)
        let line = try #require(Batch.lines(again, 0).first { $0.text == "Bonifico a mio nome" })
        #expect(line.statementClass == .oneOff)
        #expect(line.source == .chosen)
        #expect(Batch.lines(again, 0).first { $0.text == "Affitto gennaio" }?.statementClass == .spending)

        // A new class for the line replaces the one remembered.
        again.editSession(ofFile: 0, library: library, today: Batch.today) {
            $0.setStatementClass(.tax, forRow: 3)
        }
        let updated = again.rememberedProfiles(in: library, today: Batch.today)
        #expect(updated.first?.isNew == false)
        #expect(updated.first?.profile.answers.map(\.statementClass) == [.tax])
    }

    @Test func aFileOfAnAccountWithoutABankIsNamedAfterItself() {
        var library = Batch.library()
        library.accounts["risparmio"]?.institution = nil
        let batch = Batch.batch([("export (3).csv", Batch.savings)], library: library)
        let remembered = batch.rememberedProfiles(in: library)
        #expect(remembered.map(\.profile.name) == ["export (3)"])
        #expect(remembered.map(\.profile.id) == ["export-3"])
    }
}
