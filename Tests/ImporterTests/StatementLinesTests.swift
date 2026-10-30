import Foundation
@testable import Importer
import Model
import Testing
import TestSupport

/// A statement's lines kept in the library (IMPORT.md, "Lines"): each with
/// a stable ID, so importing the file again finds it, keeps what was
/// removed or confirmed since, and counts it that way. A made-up January:
/// rent of 900, a payment of 60 the bank's export lists twice, and pay of
/// 3,000.
struct StatementLinesTests {
    static let today: CalendarDate = "2026-02-10"

    static let statement = """
        Data;Importo;Descrizione
        05/01/2026;-900,00;Affitto gennaio
        12/01/2026;-60,00;Esselunga
        12/01/2026;-60,00;Esselunga
        27/01/2026;3.000,00;Bonifico SEPA da ACME GmbH rif 0126
        """

    static func library() -> Library {
        var library = Library(accounts: [
            Account(id: "conto", name: "Conto corrente", kind: .cash, currency: .eur, opened: "2020-01-01"),
            Account(id: "risparmio", name: "Risparmio", kind: .savings, currency: .eur, opened: "2020-01-01"),
        ])
        library.upsert(Valuation(account: "conto", date: "2025-12-31", balance: 10000))
        return library
    }

    /// The statement's preview with the pay chosen as income.
    static func preview(against library: Library) throws -> ImportPreview {
        var session = try ImportSession(data: Data(statement.utf8))
        session.proposeMapping(layout: .statement)
        session.profile.constants.account = "conto"
        let lines = session.preview(against: library, today: today).statementLines
        let pay = try #require(lines.first { $0.text.hasPrefix("Bonifico SEPA") })
        session.setStatementClass(.income, forRow: pay.row)
        return session.preview(against: library, today: today)
    }

    static func key(_ date: CalendarDate, _ amount: Decimal, _ text: String, ordinal: Int = 0) -> BankLineKey {
        BankLineKey(account: "conto", date: date,
                    id: BankLineID.stable(account: "conto", date: date, amount: amount, text: text, ordinal: ordinal))
    }

    static let rent = key("2026-01-05", -900, "Affitto gennaio")
    static let twice = key("2026-01-12", -60, "Esselunga", ordinal: 1)

    static func january(_ preview: ImportPreview) -> ImportedRecord? {
        preview.record(.valuation("conto", "2026-01-31"))?.imported
    }

    @Test func importingAStatementKeepsItsLines() throws {
        let preview = try Self.preview(against: Self.library())
        #expect(preview.lines.map(\.key) == [Self.rent, Self.key("2026-01-12", -60, "Esselunga"), Self.twice,
                                              Self.key("2026-01-27", 3000, "Bonifico SEPA da ACME GmbH rif 0126")])
        #expect(preview.lines.map(\.statementClass) == [.spending, .spending, .spending, .income])
        // The pay was chosen; the rest is the import's suggestion.
        #expect(preview.lines.map(\.isConfirmed) == [false, false, false, true])
        #expect(preview.lines.allSatisfy { $0.source == .import })

        let result = preview.apply(to: Self.library())
        #expect(result.linesWritten == 4)
        #expect(result.library.lines(for: "conto") == preview.lines.sorted { $0.key < $1.key })
        #expect(result.library.valuations(for: "conto").last?.moneyOut == 1020)

        // Importing it again writes nothing.
        let again = try Self.preview(against: result.library).apply(to: result.library)
        #expect(again.linesWritten == 0)
        #expect(again.library == result.library)
    }

    @Test func aRemovedLineStaysRemovedAndCountsInNothing() throws {
        var library = try Self.preview(against: Self.library()).apply(to: Self.library()).library
        var twice = try #require(library.line(Self.twice))
        twice.removed = true
        library.upsert(twice)

        let preview = try Self.preview(against: library)
        let line = try #require(preview.statementLines.first { $0.lineID == Self.twice.id })
        #expect(line.isRemoved)
        #expect(Self.january(preview)?.moneyOut == 960)
        #expect(Self.january(preview)?.balance == 12040)
        let result = preview.apply(to: library)
        #expect(result.library.line(Self.twice)?.isRemoved == true)

        // A class chosen for it in the import doesn't count it either.
        var session = try ImportSession(data: Data(Self.statement.utf8))
        session.proposeMapping(layout: .statement)
        session.profile.constants.account = "conto"
        let rows = session.preview(against: library, today: Self.today).statementLines
        let pay = try #require(rows.first { $0.text.hasPrefix("Bonifico SEPA") })
        session.setStatementClass(.income, forRow: pay.row)
        session.setStatementClass(.spending, forRow: line.row)
        let chosen = session.preview(against: library, today: Self.today)
        #expect(Self.january(chosen)?.moneyOut == 960)
        #expect(Self.january(chosen)?.balance == 12040)
    }

    @Test func aConfirmedLineKeepsWhatItIs() throws {
        var library = try Self.preview(against: Self.library()).apply(to: Self.library()).library
        var rent = try #require(library.line(Self.rent))
        rent.statementClass = .transfer
        rent.otherAccount = "risparmio"
        rent.confirmed = true
        rent.note = "moved to savings"
        library.upsert(rent)

        let preview = try Self.preview(against: library)
        let line = try #require(preview.statementLines.first { $0.lineID == Self.rent.id })
        #expect(line.statementClass == .transfer)
        #expect(line.otherAccount == "risparmio")
        #expect(Self.january(preview)?.moneyOut == 120)
        let kept = try #require(preview.apply(to: library).library.line(Self.rent))
        #expect(kept.statementClass == .transfer)
        #expect(kept.note == "moved to savings")
        #expect(kept.isConfirmed)
    }

    /// A line moved to an account the import doesn't create, such as a
    /// purchase's whose new account was turned off, names no account.
    @Test func aLineKeepsOnlyAnAccountThatExists() throws {
        var preview = ImportPreview()
        preview.lines = [BankLine(account: "conto", date: "2026-01-05", id: "a", amount: -900,
                                  statementClass: .transfer, otherAccount: "auto-nuova", confirmed: true)]
        let line = try #require(preview.apply(to: Self.library()).library.line(BankLineKey(account: "conto",
                                                                                          date: "2026-01-05",
                                                                                          id: "a")))
        #expect(line.otherAccount == nil)
        #expect(line.statementClass == .transfer)
    }

    /// A line no one confirmed is the import's suggestion, which a new
    /// import replaces; its note stays.
    @Test func anUnconfirmedLineTakesTheNewSuggestion() throws {
        var library = try Self.preview(against: Self.library()).apply(to: Self.library()).library
        var rent = try #require(library.line(Self.rent))
        rent.statementClass = .oneOff
        rent.note = "January"
        library.upsert(rent)

        let written = try #require(try Self.preview(against: library).apply(to: library).library.line(Self.rent))
        #expect(written.statementClass == .spending)
        #expect(written.note == "January")
    }
}
