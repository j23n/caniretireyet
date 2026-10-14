import Foundation
@testable import Importer
import Model
import Testing
import TestSupport

/// What statements move to or from the library's other accounts, from those
/// accounts' side (``StatementAccountMove``): money set aside in a tax pot
/// by a rule, a pension fund paid into, a mortgage's instalment, and a
/// transfer between two files. A check-in reads them for the accounts
/// without a statement. Made-up accounts and files.
struct StatementAccountMoveTests {
    static let today: CalendarDate = "2026-10-14"

    static func library() -> Library {
        var library = Library(accounts: [
            Account(id: "conto", name: "Conto corrente", kind: .cash, currency: .eur, opened: "2020-01-01"),
            Account(id: "giro", name: "Girokonto", kind: .cash, currency: .eur, opened: "2020-01-01"),
            Account(id: "pot", name: "Tax pot", kind: .taxPot, currency: .eur, opened: "2020-01-01"),
            Account(id: "fondo", name: "Fondo Esempio", kind: .pensionFund, currency: .eur, opened: "2020-01-01"),
            Account(id: "mutuo", name: "Mutuo Collina", kind: .mortgage, currency: .eur, opened: "2020-01-01"),
        ])
        for (id, balance) in [("conto", 4000), ("giro", 2000), ("pot", 4000), ("fondo", 18000),
                              ("mutuo", -180_000)] as [(AccountID, Decimal)] {
            library.upsert(Valuation(account: id, date: "2026-08-31", balance: balance))
        }
        return library
    }

    static let current = """
        Data;Importo;Descrizione
        01/09/2026;-1.000,00;Bonifico a mio nome
        10/09/2026;3.400,00;Stipendio settembre
        15/09/2026;-725,00;Rata Mutuo Collina settembre
        20/09/2026;-300,00;Versamento Fondo Esempio
        """

    static let giro = """
        Data;Importo;Descrizione
        02/09/2026;1.000,00;Bonifico da conto
        05/09/2026;-500,00;Steuer-Rücklage September
        """

    static func batch() -> StatementBatch {
        let library = library()
        var batch = StatementBatch(files: [(name: "a.csv", data: Data(current.utf8)),
                                           (name: "b.csv", data: Data(giro.utf8))],
                                   library: library, checkIn: "2026-09-30", today: today)
        batch.setAccount("conto", forFile: 0, library: library, today: today)
        batch.setAccount("giro", forFile: 1, library: library, today: today)
        batch.editSession(ofFile: 1, library: library, today: today) { session in
            session.setStatementRule(movingTo: "pot", for: "Steuer-Rücklage")
        }
        return batch
    }

    static func moves() -> [StatementAccountMove] {
        let batch = batch()
        return batch.accountMoves(in: batch.previews(against: library(), today: today))
    }

    @Test func aRulesMoveIntoATaxPotNamesItsPhrase() throws {
        let move = try #require(Self.moves().first { $0.account == "pot" })
        #expect(move.statement == "giro")
        #expect(move.amount == 500)
        #expect(move.rule == "Steuer-Rücklage")
        #expect(!move.isPayment)
        #expect(move.date == "2026-09-05")
    }

    @Test func aDebtsInstalmentIsAPayment() throws {
        let move = try #require(Self.moves().first { $0.account == "mutuo" })
        #expect(move.statement == "conto")
        #expect(move.amount == 725)
        #expect(move.isPayment)
        #expect(move.rule == nil)
    }

    @Test func moneyPaidIntoAnAccountNamedInTheLineIsMoved() throws {
        let move = try #require(Self.moves().first { $0.account == "fondo" })
        #expect(move.amount == 300)
        #expect(!move.isPayment)
    }

    /// Each side of a transfer between two files is a move: the caller
    /// leaves out the accounts whose own statement records it.
    @Test func aPairedTransferMovesBothWays() {
        let moves = Self.moves()
        #expect(moves.contains { $0.account == "giro" && $0.statement == "conto" && $0.amount == 1000 })
        #expect(moves.contains { $0.account == "conto" && $0.statement == "giro" && $0.amount == -1000 })
    }

    @Test func incomeAndSpendingMoveNothing() {
        let moves = Self.moves()
        #expect(moves.count == 5)
        #expect(!moves.contains { $0.row == 3 && $0.statement == "conto" })
    }
}
