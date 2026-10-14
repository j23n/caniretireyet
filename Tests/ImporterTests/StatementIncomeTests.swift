import Foundation
@testable import Importer
import Model
import Testing
import TestSupport
import Tracker

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
        #expect(StatementWords.sender(of: "Bonifico a vostro favore disposto da: Mario Rossi") == "Mario Rossi")
    }

    /// A payment processor writes the merchant after a `*`.
    @Test func aProcessorsLineIsItsMerchants() {
        #expect(StatementWords.sender(of: "PayPal Europe *Kleinanzeigen Fahrrad") == "Kleinanzeigen")
        #expect(StatementWords.sender(of: "SUMUP *BarCentrale 0412") == "BarCentrale")
        #expect(StatementWords.sender(of: "PayPal *") == "PayPal")
        #expect(StatementWords.sender(of: "Libreria *Rossi") == "Libreria Rossi")
    }

    @Test func aPensionAndARefundAreKnownByTheirWords() {
        #expect(StatementWords.suggestion(for: "Accredito pensione INPS", amount: 1200) == .income)
        #expect(StatementWords.suggestion(for: "Rimborso Amazon", amount: 30) == .spending)
        #expect(StatementWords.suggestion(for: "Rimborso Amazon", amount: -30) == nil)
    }

    @Test func aLargerLineFromASenderWhoPaysEveryMonthNeedsAnAnswer() throws {
        let csv = Self.csv + "\n30/03/2026;15.000,00;Bonifico SEPA da ACME GmbH rif TFR"
            + "\n15/01/2026;1.500,00;Bonifico SEPA da ACME GmbH rif anticipo"
        var session = try ImportSession(data: Data(csv.utf8))
        session.proposeMapping(layout: .statement)
        session.profile.constants.account = "conto"
        let preview = session.preview(against: Self.library(), today: Self.today)
        let salary = try Self.line(preview, "Bonifico SEPA da ACME GmbH rif 0326")
        #expect(salary.statementClass == .income)
        #expect(salary.source == .recurring)
        let severance = try Self.line(preview, "Bonifico SEPA da ACME GmbH rif TFR")
        #expect(severance.source == .sign)
        #expect(severance.needsAnswer)
        let advance = try Self.line(preview, "Bonifico SEPA da ACME GmbH rif anticipo")
        #expect(advance.statementClass == .income)
        #expect(advance.source == .recurring)
    }

    /// An answered question stays a question: the line was asked.
    @Test func anAnsweredLineWasAsked() throws {
        let csv = Self.csv + "\n30/03/2026;15.000,00;Bonifico SEPA da ACME GmbH rif TFR"
        var session = try ImportSession(data: Data(csv.utf8))
        session.proposeMapping(layout: .statement)
        session.profile.constants.account = "conto"
        let before = session.preview(against: Self.library(), today: Self.today)
        let asked = try Self.line(before, "Bonifico SEPA da ACME GmbH rif TFR")
        #expect(asked.needsAnswer)
        #expect(asked.wasAsked)
        session.setStatementClass(.oneOff, forRow: asked.row)
        let preview = session.preview(against: Self.library(), today: Self.today)
        let answered = try Self.line(preview, "Bonifico SEPA da ACME GmbH rif TFR")
        #expect(!answered.needsAnswer)
        #expect(answered.wasAsked)
        #expect(answered.statementClass == .oneOff)
        #expect(preview.statementLines.filter(\.wasAsked).map(\.row)
            == before.statementLines.filter(\.needsAnswer).map(\.row))
    }

    @Test func aRegularPayersLargerLineNeedsAnAnswerWhateverItsSize() throws {
        let csv = Self.csv + "\n10/01/2026;500,00;Bonifico da Affitti Bianchi rif 0126"
            + "\n10/02/2026;500,00;Bonifico da Affitti Bianchi rif 0226"
            + "\n10/03/2026;500,00;Bonifico da Affitti Bianchi rif 0326"
            + "\n20/03/2026;700,00;Bonifico da Affitti Bianchi rif 9999"
        var session = try ImportSession(data: Data(csv.utf8))
        session.proposeMapping(layout: .statement)
        session.profile.constants.account = "conto"
        let preview = session.preview(against: Self.library(), today: Self.today)
        let rent = try Self.line(preview, "Bonifico da Affitti Bianchi rif 0326")
        #expect(rent.statementClass == .income)
        #expect(rent.source == .recurring)
        let larger = try Self.line(preview, "Bonifico da Affitti Bianchi rif 9999")
        #expect(larger.source == .sign)
        #expect(larger.needsAnswer)
    }

    @Test func moneyInIsPaidBackUnlessASenderPaysEveryMonth() throws {
        let preview = try Self.session().preview(against: Self.library(), today: Self.today)
        #expect(preview.issues.filter { !$0.isNote }.isEmpty, "\(preview.issues)")
        let pay = preview.statementLines.filter { $0.sender == "ACME" }
        #expect(pay.count == 3)
        #expect(pay.allSatisfy { $0.statementClass == .income && $0.source == .recurring })
        let share = try Self.line(preview, "Bonifico SEPA da Ristorante Verdi")
        #expect(share.statementClass == .spending)
        #expect(share.source == .paidBefore)
        let small = try Self.line(preview, "Bonifico da Mario Neri")
        #expect(small.statementClass == .spending)
        #expect(small.source == .sign)
        #expect(!small.needsAnswer)
        // More than a typical month's spending, 1.300: asked about, paid back until it's answered.
        let large = try Self.line(preview, "Bonifico da Notaio Bianchi")
        #expect(large.statementClass == .spending)
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
        let valuator = Valuator(library: library)
        #expect(valuator.moved(written, previous: valuator.previousValuation(for: "conto", before: written.date)) == 0)
        // Paid back after all: the one-off the library has goes.
        session.setStatementClass(.spending, forRow: row)
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

    static func passThroughSession() throws -> ImportSession {
        let csv = Self.csv + "\n10/02/2026;6.000,00;Bonifico da Risparmio Esempio"
            + "\n12/02/2026;-6.000,00;Bonifico a Broker Esempio rif 1"
            + "\n20/02/2026;-6.000,00;Bonifico a Broker Esempio rif 2"
            + "\n16/01/2026;-25,00;Pagamento POS Bar Centrale"
        var session = try ImportSession(data: Data(csv.utf8))
        session.proposeMapping(layout: .statement)
        session.profile.constants.account = "conto"
        return session
    }

    @Test func moneyThatPassesThroughIsATransfer() throws {
        let preview = try Self.passThroughSession().preview(against: Self.library(), today: Self.today)
        let incoming = try Self.line(preview, "Bonifico da Risparmio Esempio")
        let out = try Self.line(preview, "Bonifico a Broker Esempio rif 1")
        #expect(incoming.statementClass == .transfer)
        #expect(incoming.source == .passThrough(row: out.row))
        #expect(!incoming.needsAnswer)
        #expect(out.statementClass == .transfer)
        #expect(out.source == .passThrough(row: incoming.row))
        #expect(!out.needsAnswer)
        // The same amount further away is left to its sign, and asked about.
        let later = try Self.line(preview, "Bonifico a Broker Esempio rif 2")
        #expect(later.statementClass == .spending)
        #expect(later.needsAnswer)
        let february = try #require(preview.record(.valuation("conto", "2026-02-28"))?.imported)
        #expect(february.moneyIn == 3050)
        #expect(february.moneyOut == 7380)
    }

    @Test func smallLinesDontPassThrough() throws {
        let preview = try Self.passThroughSession().preview(against: Self.library(), today: Self.today)
        let share = try Self.line(preview, "Bonifico da Mario Neri")
        #expect(share.statementClass == .spending)
        #expect(share.source == .sign)
        let bar = try Self.line(preview, "Pagamento POS Bar Centrale")
        #expect(bar.statementClass == .spending)
        #expect(bar.source == .sign)
    }

    @Test func aClassChosenForOneSideAsksAboutTheOther() throws {
        var session = try Self.passThroughSession()
        let row = try Self.line(session.preview(against: Self.library(), today: Self.today),
                                "Bonifico da Risparmio Esempio").row
        session.setStatementClass(.oneOff, forRow: row)
        let preview = session.preview(against: Self.library(), today: Self.today)
        #expect(try Self.line(preview, "Bonifico da Risparmio Esempio").source == .chosen)
        let out = try Self.line(preview, "Bonifico a Broker Esempio rif 1")
        #expect(out.statementClass == .spending)
        #expect(out.needsAnswer)
    }
}
