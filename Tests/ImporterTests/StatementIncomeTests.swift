import Foundation
@testable import Importer
import Model
import Testing
import TestSupport

/// A bank statement's money in (IMPORT.md, "Classes"): income marked once
/// per sender, a sender who pays every month, money paid back, a large
/// line that needs an answer, and a one-off, on a made-up current account's
/// first quarter.
struct StatementIncomeTests {
    static let today: CalendarDate = "2026-04-12"

    static let csv = """
        Data;Importo;Descrizione
        05/01/2026;-900,00;Affitto gennaio
        12/01/2026;-400,00;Pagamento POS Supermercato Rossi
        15/01/2026;25,00;Bonifico da Mario Neri
        27/01/2026;3.000,00;Bonifico SEPA da ACME GmbH rif 0126
        05/02/2026;-900,00;Affitto febbraio
        05/02/2026;-120,00;Pagamento POS Ristorante Verdi
        12/02/2026;-400,00;Pagamento POS Supermercato Rossi
        20/02/2026;40,00;Bonifico SEPA da Ristorante Verdi
        27/02/2026;3.050,00;Bonifico SEPA da ACME GmbH rif 0226
        04/03/2026;18.000,00;Bonifico da Notaio Bianchi
        05/03/2026;-900,00;Affitto marzo
        12/03/2026;-400,00;Pagamento POS Supermercato Rossi
        27/03/2026;2.980,00;Bonifico SEPA da ACME GmbH rif 0326
        """

    static func library() -> Library {
        var library = Library(accounts: [
            Account(id: "conto", name: "Conto corrente", kind: .cash, currency: .eur, opened: "2020-01-01"),
        ])
        library.upsert(Valuation(account: "conto", date: "2025-12-31", balance: 1000))
        return library
    }

    static func session() throws -> ImportSession {
        var session = try ImportSession(data: Data(csv.utf8))
        session.proposeMapping(layout: .statement)
        session.profile.constants.account = "conto"
        return session
    }

    static func line(_ preview: ImportPreview, _ text: String) throws -> StatementLine {
        try #require(preview.statementLines.first { $0.text.hasPrefix(text) })
    }

    @Test func aSenderIsTheFirstWordsThatNameSomeone() {
        #expect(StatementWords.sender(of: "Bonifico SEPA da ACME GmbH Stipendio settembre") == "ACME")
        #expect(StatementWords.sender(of: "Pagamento POS SUPERMERCATO ROSSI 12/03") == "SUPERMERCATO ROSSI")
        #expect(StatementWords.sender(of: "Überweisung von Müller Anna Kundenreferenz 123")
            == "Müller Anna")
        #expect(StatementWords.sender(of: "SEPA 0126 EUR").isEmpty)
    }

    @Test func moneyInIsPaidBackUnlessASenderPaysEveryMonth() throws {
        let preview = try Self.session().preview(against: Self.library(), today: Self.today)
        #expect(preview.issues.filter { !$0.isNote }.isEmpty, "\(preview.issues)")
        let pay = preview.statementLines.filter { $0.sender == "ACME" }
        #expect(pay.count == 3)
        #expect(pay.allSatisfy { $0.statementClass == .income && $0.source == .recurring })
        let share = try Self.line(preview, "Bonifico SEPA da Ristorante Verdi")
        #expect(share.statementClass == .paidBack)
        #expect(share.source == .paidBefore)
        let small = try Self.line(preview, "Bonifico da Mario Neri")
        #expect(small.statementClass == .paidBack)
        #expect(small.source == .sign)
        #expect(!small.needsAnswer)
        // More than a typical month's spending, 1.300: asked about, paid back until it's answered.
        let large = try Self.line(preview, "Bonifico da Notaio Bianchi")
        #expect(large.statementClass == .paidBack)
        #expect(large.needsAnswer)
        #expect(preview.statementLines.filter(\.needsAnswer).count == 1)

        let january = try #require(preview.record(.valuation("conto", "2026-01-31"))?.imported)
        #expect(january.moneyIn == 3000)
        #expect(january.moneyOut == 1275)
        #expect(january.oneOff == nil)
        let february = try #require(preview.record(.valuation("conto", "2026-02-28"))?.imported)
        #expect(february.moneyIn == 3050)
        #expect(february.moneyOut == 1380)
        // Paid back more than spent: no money out, and the rest is moved.
        let march = try #require(preview.record(.valuation("conto", "2026-03-31"))?.imported)
        #expect(march.moneyIn == 2980)
        #expect(march.moneyOut == 0)
    }

    @Test func aOneOffIsNeitherIncomeNorSpending() throws {
        var session = try Self.session()
        let row = try Self.line(session.preview(against: Self.library(), today: Self.today),
                                "Bonifico da Notaio Bianchi").row
        session.setStatementClass(.oneOff, forRow: row)
        let preview = session.preview(against: Self.library(), today: Self.today)
        #expect(!(try Self.line(preview, "Bonifico da Notaio Bianchi").needsAnswer))
        let march = try #require(preview.record(.valuation("conto", "2026-03-31"))?.imported)
        #expect(march.moneyIn == 2980)
        #expect(march.moneyOut == 1300)
        #expect(march.oneOff == 18000)

        let library = preview.apply(to: Self.library()).library
        let written = try #require(library.valuations(for: "conto").first { $0.date == "2026-03-31" })
        #expect(written.oneOff == 18000)
        #expect(written.moved == 0)
        // Paid back after all: the one-off the library has goes.
        session.setStatementClass(.paidBack, forRow: row)
        let again = session.preview(against: library, today: Self.today).apply(to: library).library
        let corrected = try #require(again.valuations(for: "conto").first { $0.date == "2026-03-31" })
        #expect(corrected.oneOff == nil)
        #expect(corrected.moneyOut == 0)
    }

    @Test func incomeIsMarkedOncePerSender() throws {
        var session = try Self.session()
        let preview = session.preview(against: Self.library(), today: Self.today)
        let sender = try Self.line(preview, "Bonifico da Mario Neri").sender
        #expect(sender == "Mario Neri")
        session.setStatementRule(.income, for: sender)
        let marked = try Self.line(session.preview(against: Self.library(), today: Self.today),
                                   "Bonifico da Mario Neri")
        #expect(marked.statementClass == .income)
        #expect(marked.source == .rule("Mario Neri"))
    }
}
