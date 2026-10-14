import Foundation
import Importer
import Model
import Testing
import Tracker
@testable import CanIRetireYet

/// A check-in that starts with its bank statements (UI.md, "Statements
/// first"): the start card's accounts, a line per file held, the rows the
/// files fill in (read-only, with where their value comes from), what the
/// rows without a file can expect from them, the grouping and the
/// progress, and saving them with the check-in. Made-up accounts and files.
@MainActor
struct CheckInStatementsTests {
    private let date: CalendarDate = "2026-09-30"
    private let locale = Locale(identifier: "en_GB")

    /// Two current accounts, a savings account, a tax pot, a pension fund
    /// and a mortgage, with August values; the savings account's came
    /// from a statement.
    private let library: Library = {
        var library = Library(accounts: [
            Account(id: "conto", name: "Conto corrente", kind: .cash, currency: .eur, opened: "2020-01-01"),
            Account(id: "giro", name: "Girokonto", kind: .cash, currency: .eur, opened: "2020-01-01"),
            Account(id: "deposito", name: "Conto Arancio", kind: .savings, currency: .eur, opened: "2020-01-01"),
            Account(id: "pot", name: "Tax pot", kind: .taxPot, currency: .eur, opened: "2020-01-01"),
            Account(id: "fondo", name: "Fondo Esempio", kind: .pensionFund, currency: .eur, opened: "2020-01-01"),
            Account(id: "mutuo", name: "Mutuo Collina", kind: .mortgage, currency: .eur, opened: "2020-01-01"),
        ])
        for (id, balance) in [("conto", 4000), ("giro", 2000), ("deposito", 12000), ("pot", 4000),
                              ("fondo", 18000), ("mutuo", -180_000)] as [(AccountID, Decimal)] {
            var value = Valuation(account: id, date: "2026-08-31", balance: balance)
            if id == "deposito" { value.source = .import }
            library.upsert(value)
        }
        return library
    }()

    private static let current = """
        Data;Importo;Descrizione
        01/09/2026;-1.000,00;Bonifico a Girokonto
        10/09/2026;3.400,00;Stipendio settembre
        15/09/2026;-725,00;Rata Mutuo Collina settembre
        20/09/2026;-300,00;Versamento Fondo Esempio
        25/09/2026;-500,00;Giroconto Conto Arancio
        28/09/2026;-18.000,00;Bonifico a Autosalone Neri
        """

    private static let giro = """
        Data;Importo;Descrizione
        02/09/2026;1.000,00;Bonifico da conto
        05/09/2026;-500,00;Steuer-Rücklage September
        """

    /// The check-in on 30 September holding both files, the Girokonto's
    /// money set aside by a rule into the tax pot (and a large payment not
    /// answered yet), and its draft following the library as it would be
    /// with them imported.
    private func held() throws -> (draft: CheckInDraft, flow: ImportFlow, statements: CheckInStatements) {
        var flow = ImportFlow(library: library, checkIn: date)
        flow.open(statements: [(name: "movimenti_settembre.csv", data: Data(Self.current.utf8)),
                               (name: "Umsaetze_092026.csv", data: Data(Self.giro.utf8))])
        flow.setBatchAccount("conto", forFile: 0)
        flow.setBatchAccount("giro", forFile: 1)
        flow.showBatchFile(1)
        flow.setStatementRule(movingTo: "pot", for: "Steuer-Rücklage")
        var draft = CheckInDraft(date: date, library: library)
        draft.rebase(onto: try #require(flow.checkInLibrary))
        return (draft, flow, CheckInStatements.make(draft: draft, library: library, flow: flow))
    }

    private func row(_ account: AccountID, in draft: CheckInDraft) throws -> CheckInRow {
        try #require(draft[account])
    }

    // MARK: The start card

    @Test func theStartCardListsTheAccountsAStatementCanBeOf() {
        let draft = CheckInDraft(date: date, library: library)
        let statements = CheckInStatements.make(draft: draft, library: library)
        // Tax pots follow from other statements; pensions, property and debts are typed.
        #expect(statements.accounts.map(\.id) == ["deposito", "conto", "giro"])
        #expect(statements.accounts.map { CheckInStatements.status(of: $0, locale: locale) }
            == ["last: 31 Aug", "typed by hand", "typed by hand"])
        #expect(statements.showsStart(dismissed: false))
        #expect(!statements.showsStart(dismissed: true))
        #expect(statements.groupsForStatements(dismissed: false))
        #expect(!statements.groupsForStatements(dismissed: true))
        #expect(statements.startTitle(locale: locale) == "Start with September's statements")
        #expect(statements.header(locale: locale) == "September's statements")
        #expect(statements.dropHint == "Drop statements here, or Add Statements…")
    }

    // MARK: The files held

    @Test func eachFileHeldHasALine() throws {
        let (_, _, statements) = try held()
        #expect(!statements.showsStart(dismissed: false))
        #expect(statements.files.map(\.accountName) == ["Conto corrente", "Girokonto"])
        #expect(statements.files.map(\.name) == ["movimenti_settembre.csv", "Umsaetze_092026.csv"])
        #expect(statements.files.map(\.lines) == [6, 2])
        #expect(statements.header(locale: locale) == "September's statements · 2")
        let giro = try #require(statements.files.last)
        #expect(CheckInStatements.detail(of: giro, locale: locale).hasPrefix("1–30 Sep"))
        #expect(CheckInStatements.lineCount(of: giro) == "2 lines")
        // The savings account's last value came from a statement, and it has none this time.
        #expect(statements.alsoLastTime == ["Conto Arancio"])
        #expect(statements.dropHint
            == "Drop more statements here, or Add Statements… · last time also: Conto Arancio")
    }

    /// A large payment needs an answer: its file says so, and its row's
    /// From opens that file's Income. It's a hint: the check-in saves without.
    @Test func aFilesLinesToAnswerAreCounted() throws {
        let (draft, _, statements) = try held()
        #expect(statements.files.map(\.toAnswer) == [1, 0])
        #expect(statements.linesToAnswer == 1)
        #expect(statements.files.map { CheckInStatements.subtitle(of: $0, locale: locale) }
            == ["Conto corrente · 1–30 Sep", "1–30 Sep · 2 lines · all answered"])
        let from = statements.from(for: try row("conto", in: draft), locale: locale)
        #expect(from.text.text == "Statement · 1 line to answer")
        #expect(from.opensFile == 0)
        #expect(statements.from(for: try row("giro", in: draft), locale: locale).text.text == "Statement")
    }

    // MARK: Rows

    @Test func theRowsAFileFillsInAreReadOnly() throws {
        let (draft, _, statements) = try held()
        for account: AccountID in ["conto", "giro", "pot"] {
            let row = try row(account, in: draft)
            #expect(statements.isFromStatement(row), "\(account)")
            #expect(row.state == .updated)
        }
        #expect(statements.filled == ["conto", "giro", "pot"])
        let review = draft.review(in: try #require(try held().flow.checkInLibrary))
        let conto = try row("conto", in: draft)
        let line = try #require(statements.statementLine(for: conto, review: review.row(for: "conto"),
                                                         locale: locale))
        #expect(line.text.hasPrefix("From statement · in 3,400.00 · out "))
        let figures = try #require(statements.statementFigures(for: conto, review: review.row(for: "conto"),
                                                               locale: locale))
        #expect(figures.text.hasPrefix("In 3,400.00 · Out "))
        #expect(statements.from(for: conto, locale: locale).text.text.hasPrefix("Statement"))

        // The tax pot's value is the money set aside in it.
        let pot = try row("pot", in: draft)
        #expect(pot.balance == 4500)
        #expect(statements.statementLine(for: pot, review: nil, locale: locale)?.text
            == "+500.00 from Girokonto · counts as tax")
        #expect(statements.from(for: pot, locale: locale).text.text == "Girokonto's \u{201C}Steuer-Rücklage\u{201D} · tax")
        #expect(statements.from(for: pot, locale: locale).opensFile == nil)
    }

    @Test func aRowWithoutAFileSaysWhatItCanExpect() throws {
        let (draft, _, statements) = try held()
        let deposito = try row("deposito", in: draft)
        #expect(deposito.state == .notReviewed)
        #expect(!statements.isFromStatement(deposito))
        #expect(statements.expectedAmount(for: deposito) == 500)
        #expect(statements.suggestedBalance(for: deposito) == 12500)
        #expect(statements.expectation(for: deposito, compact: true, locale: locale)?.text
            == "No statement · expects +500.00 from Conto corrente")
        #expect(statements.from(for: deposito, locale: locale).text.text
            == "Type it, or drop its statement · expects +500.00 from Conto corrente")

        let mutuo = try row("mutuo", in: draft)
        #expect(statements.expectation(for: mutuo, compact: true, locale: locale)?.text
            == "Conto corrente paid 725.00 to it")
        #expect(statements.from(for: mutuo, locale: locale).text.text == "Type it · Conto corrente paid 725.00 to it")
        #expect(statements.suggestedBalance(for: mutuo) == -179_275)

        // Mark Rest Unchanged still keeps the last value.
        var unchanged = draft
        unchanged.markRestUnchanged()
        #expect(unchanged["deposito"]?.balance == 12000)
    }

    @Test func aStatementsValueTypedOverIsNoLongerFromIt() throws {
        let (draft, flow, statements) = try held()
        var typed = draft
        typed["conto"]?.setBalance(4300)
        let row = try row("conto", in: typed)
        #expect(!statements.isFromStatement(row))
        #expect(statements.from(for: row, locale: locale).text.text == "Typed over the statement")
        // *Use the Statement's Value* fills it in again.
        typed.refill("conto", from: try #require(flow.checkInLibrary))
        #expect(statements.isFromStatement(try self.row("conto", in: typed)))
    }

    // MARK: Grouping and progress

    @Test func theAccountsTypedByHandAreGroupedTogether() throws {
        let (draft, flow, statements) = try held()
        let held = try #require(flow.checkInLibrary)
        let sections = CheckInSection.sections(of: draft, in: held, forStatements: true)
        #expect(sections.map(\.title) == ["Cash", "Pension · Debts"])
        #expect(sections.map(\.compactTitle) == ["Cash", "To type"])
        #expect(CheckInSection.sections(of: draft, in: held).map(\.title) == ["Cash", "Pension", "Debts"])

        // The rows a file fills in have no field: the first is the first row to type.
        let rows = sections.flatMap(\.rows)
        let readOnly = Set(rows.filter { statements.isFromStatement($0) }.map(\.account))
        let order = CheckInFieldOrder.nowColumn(rows: rows, readOnly: readOnly)
        #expect(order.fields.first == .balance("deposito"))
    }

    @Test func theProgressSaysWhereTheValuesCameFrom() throws {
        let (draft, _, statements) = try held()
        let mac = CheckInWording.progress(draft, statements: statements, compact: false)
        #expect(mac.lead == "3 of 6 done")
        #expect(mac.detail == "3 from statements · 1 line to answer first")
        #expect(CheckInWording.progress(draft, statements: statements, compact: true).detail == "3 from statements")
        let none = CheckInWording.progress(CheckInDraft(date: date, library: library), statements: nil, compact: false)
        #expect(none.lead == "0 of 6 done")
        #expect(none.detail == nil)
    }

    @Test func aRowNotReviewedAsksForMoneyInAndOutOnceTyped() throws {
        let (draft, _, _) = try held()
        var deposito = try row("deposito", in: draft)
        #expect(!CheckInRowDisplay.showsMoneyInOut(deposito, forStatements: true))
        #expect(CheckInRowDisplay.showsMoneyInOut(deposito))
        deposito.setBalance(12500)
        #expect(CheckInRowDisplay.showsMoneyInOut(deposito, forStatements: true))
    }

    // MARK: Saving and moving

    /// Saving applies the statements, then the check-in's values, in one
    /// edit (``CheckInStore/save()``): a row left as the statement filled
    /// it in writes its value back as it was.
    @Test func savingWritesTheStatementsWithTheCheckIn() throws {
        let (draft, flow, _) = try held()
        let held = try #require(flow.checkInLibrary)
        var saved = StatementBatch.apply(flow.checkInPreviews, to: library) { $0.applyFollowingFlows(to: $1) }.library
        var typed = draft
        typed["deposito"]?.setBalance(12500)
        typed.apply(to: &saved)
        for account: AccountID in ["conto", "giro", "pot"] {
            #expect(saved.valuations(for: account).last { $0.date == date }
                == held.valuations(for: account).last { $0.date == date }, "\(account)")
        }
        #expect(saved.valuations(for: "deposito").last?.balance == 12500)
        #expect(saved.valuations(for: "fondo").last?.date == "2026-08-31")
    }

    @Test func movingTheCheckInReadsItsStatementsAgainKeepingTheirAnswers() throws {
        let (_, flow, _) = try held()
        let moved = flow.movingCheckIn(to: "2026-09-28")
        #expect(moved.checkIn == "2026-09-28")
        #expect(moved.batchFiles.map(\.account) == ["conto", "giro"])
        let pot = try #require(moved.checkInLibrary).valuations(for: "pot").last
        #expect(pot?.date == "2026-09-28")
        #expect(pot?.balance == 4500)
        #expect(flow.movingCheckIn(to: date).checkIn == date)
    }

    // MARK: Wording

    @Test func aFilesDaysAreShort() {
        #expect(CheckInStatements.period(from: "2026-09-01", through: "2026-09-30", locale: locale) == "1–30 Sep")
        #expect(CheckInStatements.period(from: "2026-08-28", through: "2026-09-30", locale: locale)
            == "28 Aug – 30 Sep")
        #expect(CheckInStatements.period(from: "2026-09-30", through: "2026-09-30", locale: locale) == "30 Sep")
        #expect(CheckInStatements.period(from: "2026-09-01", through: "2026-09-30", locale: Locale(identifier: "en_US"))
            == "Sep 1–30")
    }
}
