import Foundation
@testable import Importer
import Model
import Testing
import TestSupport
import Tracker

/// A bank statement's tax (IMPORT.md, "Classes") and money moved to or from
/// an account (IMPORT.md, "Moved to or from an account"): a tax bill and a
/// refund, and money put in a tax pot every month, on a made-up current
/// account's first quarter.
struct StatementTaxTests {
    static let today: CalendarDate = "2026-04-12"

    static let csv = """
        Data;Importo;Descrizione
        05/01/2026;-900,00;Affitto gennaio
        10/01/2026;-500,00;Accantonamento tasse gennaio
        27/01/2026;3.000,00;Bonifico SEPA da ACME GmbH rif 0126
        05/02/2026;-900,00;Affitto febbraio
        10/02/2026;-500,00;Accantonamento tasse febbraio
        16/02/2026;-3.200,00;Pagamento F24 Agenzia delle Entrate
        27/02/2026;3.050,00;Bonifico SEPA da ACME GmbH rif 0226
        05/03/2026;-900,00;Affitto marzo
        10/03/2026;-500,00;Accantonamento tasse marzo
        20/03/2026;410,00;Rimborso Agenzia delle Entrate
        27/03/2026;2.980,00;Bonifico SEPA da ACME GmbH rif 0326
        """

    static func library() -> Library {
        var library = Library(accounts: [
            Account(id: "conto", name: "Conto corrente", kind: .cash, currency: .eur, opened: "2020-01-01"),
            Account(id: "tax-pot", name: "Tasse", kind: .taxPot, currency: .eur, opened: "2026-01-01"),
            Account(id: "risparmio", name: "Conto deposito", kind: .savings, currency: .eur, opened: "2020-01-01"),
        ])
        library.upsert(Valuation(account: "conto", date: "2025-12-31", balance: 10000))
        return library
    }

    static func session() throws -> ImportSession {
        var session = try ImportSession(data: Data(csv.utf8))
        session.proposeMapping(layout: .statement)
        session.profile.constants.account = "conto"
        session.setStatementRule(movingTo: "tax-pot", for: "Accantonamento tasse")
        return session
    }

    static func line(_ preview: ImportPreview, _ text: String) throws -> StatementLine {
        try #require(preview.statementLines.first { $0.text.hasPrefix(text) })
    }

    @Test func taxIsMoneyOutAndTheValuesTax() throws {
        let preview = try Self.session().preview(against: Self.library(), today: Self.today)
        #expect(preview.issues.filter { !$0.isNote }.isEmpty, "\(preview.issues)")
        let bill = try Self.line(preview, "Pagamento F24")
        #expect(bill.statementClass == .tax)
        #expect(bill.source == .words)
        #expect(!bill.needsAnswer)
        #expect(try Self.line(preview, "Rimborso Agenzia").statementClass == .tax)

        let february = try #require(preview.record(.valuation("conto", "2026-02-28"))?.imported)
        #expect(february.moneyIn == 3050)
        #expect(february.moneyOut == 4100)
        #expect(february.tax == 3200)
        // A refund lowers money out and tax.
        let march = try #require(preview.record(.valuation("conto", "2026-03-31"))?.imported)
        #expect(march.moneyOut == 490)
        #expect(march.tax == -410)
        let january = try #require(preview.record(.valuation("conto", "2026-01-31"))?.imported)
        #expect(january.tax == nil)

        let library = preview.apply(to: Self.library()).library
        let written = try #require(library.valuations(for: "conto").first { $0.date == "2026-02-28" })
        #expect(written.tax == 3200)
    }

    @Test func moneyMovedToATaxPotIsItsValues() throws {
        let preview = try Self.session().preview(against: Self.library(), today: Self.today)
        let moved = preview.statementLines.filter { $0.text.hasPrefix("Accantonamento") }
        #expect(moved.count == 3)
        #expect(moved.allSatisfy { line in
            line.statementClass == .transfer && line.source == .rule("Accantonamento tasse")
                && line.asset == .moved("tax-pot") && line.assetAccount == "tax-pot"
        })
        // Moved, not spent.
        let january = try #require(preview.record(.valuation("conto", "2026-01-31"))?.imported)
        #expect(january.moneyOut == 900)

        let start = try #require(preview.record(.valuation("tax-pot", "2026-01-09"))?.imported)
        #expect(start.balance == 0)
        #expect(start.flow == nil)
        let values: [(CalendarDate, Decimal)] = [("2026-01-31", 500), ("2026-02-28", 1000), ("2026-03-31", 1500)]
        for (date, balance) in values {
            let value = try #require(preview.record(.valuation("tax-pot", date))?.imported)
            #expect(value.balance == balance)
            #expect(value.flow == nil)
            #expect(value.moneyIn == 0)
            #expect(value.moneyOut == 0)
        }

        let library = preview.apply(to: Self.library()).library
        let pot = library.valuations(for: "tax-pot")
        #expect(pot.map(\.date) == ["2026-01-09", "2026-01-31", "2026-02-28", "2026-03-31"])
        let valuator = Valuator(library: library)
        #expect(zip(pot, pot.dropFirst()).allSatisfy { valuator.moved($1, previous: $0) == 500 })
        // Importing the file again changes nothing.
        let again = try Self.session().preview(against: library, today: Self.today).apply(to: library).library
        #expect(again.valuations(for: "tax-pot") == pot)
    }

    @Test func aPotsValueBetweenMovesCountsTheMovesBefore() throws {
        var library = Self.library()
        library.upsert(Valuation(account: "tax-pot", date: "2026-02-15", balance: 1000))
        let preview = try Self.session().preview(against: library, today: Self.today)
        #expect(preview.record(.valuation("tax-pot", "2026-01-31"))?.imported.balance == 500)
        // February's move is in the value of 15 February already.
        #expect(preview.record(.valuation("tax-pot", "2026-02-28")) == nil)
        let march = try #require(preview.record(.valuation("tax-pot", "2026-03-31"))?.imported)
        #expect(march.balance == 1500)
    }

    @Test func moneyMovedToAnotherAccountIsATransfer() throws {
        var session = try Self.session()
        let row = try Self.line(session.preview(against: Self.library(), today: Self.today), "Affitto marzo").row
        session.setStatementAsset(.moved("risparmio"), forRow: row)
        let preview = session.preview(against: Self.library(), today: Self.today)
        let line = try Self.line(preview, "Affitto marzo")
        #expect(line.statementClass == .transfer)
        #expect(line.source == .chosen)
        #expect(line.assetAccount == "risparmio")
        // A savings account's own check-in or statement records its side.
        #expect(!preview.records.contains { $0.imported.key.account == "risparmio" })
        #expect(preview.record(.valuation("conto", "2026-03-31"))?.imported.moneyOut == 0)
    }

    /// A savings account with a value before the move follows from it:
    /// its balance moves by the amount, and what else came in or went out
    /// (its interest) stays unknown.
    @Test func aSavingsAccountWithAValueFollowsFromTheMove() throws {
        var library = Self.library()
        library.upsert(Valuation(account: "risparmio", date: "2025-12-31", balance: 2000))
        var session = try Self.session()
        let row = try Self.line(session.preview(against: library, today: Self.today), "Affitto marzo").row
        session.setStatementAsset(.moved("risparmio"), forRow: row)
        let preview = session.preview(against: library, today: Self.today)
        let march = try #require(preview.record(.valuation("risparmio", "2026-03-31"))?.imported)
        #expect(march.balance == 2900)
        #expect(march.moneyIn == nil)
        #expect(march.moneyOut == nil)
        // In another currency it doesn't.
        library.accounts["risparmio"]?.currency = .usd
        #expect(session.preview(against: library, today: Self.today)
            .record(.valuation("risparmio", "2026-03-31")) == nil)
    }

    @Test func aClassChosenForALineTakesThePlaceOfARulesMove() throws {
        var session = try Self.session()
        let row = try Self.line(session.preview(against: Self.library(), today: Self.today),
                                "Accantonamento tasse marzo").row
        session.setStatementClass(.spending, forRow: row)
        let preview = session.preview(against: Self.library(), today: Self.today)
        let line = try Self.line(preview, "Accantonamento tasse marzo")
        #expect(line.statementClass == .spending)
        #expect(line.asset == nil)
        #expect(preview.record(.valuation("tax-pot", "2026-03-31")) == nil)
    }

    @Test func aPotWithAStatementOfItsOwnRecordsItsSide() throws {
        let session = try Self.session()
        let preview = session.preview(against: Self.library(), today: Self.today,
                                      batch: StatementBatchContext(accounts: ["tax-pot"]))
        #expect(try Self.line(preview, "Accantonamento tasse gennaio").statementClass == .transfer)
        #expect(!preview.records.contains { $0.imported.key.account == "tax-pot" })
    }

    @Test func aMoveToAnAccountItCantMoveToIsLeftOut() throws {
        var session = try Self.session()
        let row = try Self.line(session.preview(against: Self.library(), today: Self.today), "Affitto marzo").row
        session.setStatementAsset(.moved("conto"), forRow: row)
        let preview = session.preview(against: Self.library(), today: Self.today)
        #expect(try Self.line(preview, "Affitto marzo").statementClass == .spending)
        #expect(try Self.line(preview, "Affitto marzo").assetLeftOut == .accountCantTakeMoves)
        #expect(preview.issues.contains { $0.kind == .statementMoveLeftOut(row: row, account: "conto") })
    }

    @Test func aRulesMoveItCantTakeIsLeftOutAndStaysATransfer() throws {
        var library = Self.library()
        library.accounts["tax-pot"]?.closed = "2026-01-31"
        for (pot, lines) in [("tasse", 3), ("tax-pot", 2)] as [(AccountID, Int)] {
            var session = try Self.session()
            session.setStatementRule(movingTo: pot, for: "Accantonamento tasse")
            let preview = session.preview(against: library, today: Self.today)
            let moves = preview.statementLines.filter { $0.text.hasPrefix("Accantonamento") }
            // A pot closed at the end of January still takes January's.
            #expect(moves.allSatisfy { $0.statementClass == .transfer })
            #expect(moves.count { $0.asset == nil } == lines)
            let leftOut = preview.issues.filter { issue in
                if case .statementMoveLeftOut(_, let account) = issue.kind { account == pot } else { false }
            }
            #expect(leftOut.count == lines, "\(pot)")
        }
    }

    @Test func aTaxPotsOwnStatementRecordsNoTax() throws {
        var library = Self.library()
        library.upsert(Valuation(account: "tax-pot", date: "2026-01-31", balance: 4000))
        var session = try ImportSession(data: Data("""
            Data;Importo;Descrizione
            16/02/2026;-3.200,00;Pagamento F24 Agenzia delle Entrate
            """.utf8))
        session.proposeMapping(layout: .statement)
        session.profile.constants.account = "tax-pot"
        let preview = session.preview(against: library, today: Self.today)
        #expect(try Self.line(preview, "Pagamento F24").statementClass == .tax)
        let february = try #require(preview.record(.valuation("tax-pot", "2026-02-28"))?.imported)
        #expect(february.balance == 800)
        #expect(february.moneyOut == 3200)
        #expect(february.tax == nil)
    }
}
