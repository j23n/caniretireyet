import Foundation
import Importer
import Model
import Testing
@testable import CanIRetireYet

/// The Import screen's steps for a bank statement (UI.md, "Import";
/// IMPORT.md, "Bank statements"): the account asked on the File step,
/// Classify after it, a line's class
/// changed alone or by a rule, and the days the file covers, on a made-up
/// September statement of the example library's current account.
struct ImportStatementFlowTests {
    private static let csv = """
        Data;Importo;Descrizione
        02/09/2026;-1.200,00;Affitto settembre
        10/09/2026;3.400,00;Stipendio settembre
        14/09/2026;-62,10;Spesa 1234 supermercato
        21/09/2026;-48,30;Spesa 5678 mercato
        25/09/2026;-500,00;Giroconto conto deposito
        """

    private func flow() -> ImportFlow {
        var flow = ImportFlow(library: PreviewLibrary.library)
        flow.open(Data(Self.csv.utf8), fileName: "settembre.csv")
        flow.setConstants { $0.account = "conto-fineco" }
        return flow
    }

    private func line(_ flow: ImportFlow, _ text: String) throws -> StatementLine {
        try #require(flow.statementLines.first { $0.text.hasPrefix(text) })
    }

    @Test func aStatementHasAClassifyStepAfterTheFile() {
        let flow = flow()
        #expect(flow.layout == .statement)
        #expect(flow.steps == [.file, .classify, .preview, .done])
        #expect(ColumnUse.options(for: .statement).contains(.field(.credit)))
        #expect(ColumnUse.field(.amount).title(in: .statement) == "Amount (+ in, − out)")
        let choices = flow.statementAccountChoices.map(\.id)
        #expect(choices.contains("conto-fineco"))
        #expect(choices.contains("conto-deposito"))
        #expect(!choices.contains("directa"))
    }

    @Test func aStatementWaitsForItsAccountOnTheFileStep() {
        var flow = ImportFlow(library: PreviewLibrary.library)
        flow.open(Data(Self.csv.utf8), fileName: "settembre.csv")
        #expect(flow.needsStatementAccount)
        #expect(flow.nextStep == nil)
        #expect(!flow.canShow(.classify))
        #expect(!flow.canShow(.preview))
        #expect(flow.continueHint == "Choose the account this statement is of.")
        flow.setConstants { $0.account = "conto-fineco" }
        #expect(!flow.needsStatementAccount)
        #expect(flow.nextStep == .classify)
        #expect(flow.continueHint == nil)
    }

    @Test func anAccountThatCantBeTheStatementsWaitsToo() {
        var flow = flow()
        flow.setConstants { $0.account = "directa" }
        #expect(flow.needsStatementAccount)
        #expect(!flow.canShow(.classify))
        flow.setConstants { $0.account = "no-such-account" }
        #expect(flow.needsStatementAccount)
    }

    @Test func anAccountOpenedLaterAddsTheAccountsStepUntilItsGone() throws {
        var library = PreviewLibrary.library
        let opened = try #require(library.accounts["conto-fineco"]?.opened)
        library.accounts["conto-fineco"]?.opened = "2026-10-01"
        var flow = ImportFlow(library: library)
        flow.open(Data(Self.csv.utf8), fileName: "settembre.csv")
        flow.setConstants { $0.account = "conto-fineco" }
        #expect(flow.steps == [.file, .classify, .accounts, .preview, .done])
        flow.show(.accounts)
        #expect(flow.step == .accounts)
        library.accounts["conto-fineco"]?.opened = opened
        flow.setLibrary(library)
        #expect(flow.steps == [.file, .classify, .preview, .done])
        #expect(flow.step == .classify)
    }

    @Test func aStepTheLayoutTakesAwayGoesBackToTheFile() {
        var flow = flow()
        flow.setLayout(.wide)
        flow.show(.columns)
        #expect(flow.step == .columns)
        flow.setLayout(.statement)
        #expect(flow.step == .file)
    }

    @Test func aLineChangedAloneGoesBackWhenUndone() throws {
        var flow = flow()
        let pay = try line(flow, "Stipendio")
        #expect(pay.statementClass == .income)
        #expect(pay.source == .words)
        flow.setStatementClass(.transfer, forRow: pay.row)
        #expect(try line(flow, "Stipendio").statementClass == .transfer)
        #expect(try line(flow, "Stipendio").source == .chosen)
        flow.setStatementClass(nil, forRow: pay.row)
        #expect(try line(flow, "Stipendio").source == .words)
    }

    @Test func aRuleClassifiesEveryLineWithItsWords() throws {
        var flow = flow()
        #expect(ImportFlow.suggestedRulePhrase(for: try line(flow, "Spesa 1234")) == "Spesa")
        #expect(flow.linesMatching(rule: "spesa") == 2)
        #expect(flow.linesMatching(rule: " – ") == nil)
        flow.setStatementClass(.spending, forRow: try line(flow, "Spesa 5678").row)
        #expect(flow.linesMatching(rule: "spesa") == 1)
        flow.setStatementClass(nil, forRow: try line(flow, "Spesa 5678").row)
        flow.setStatementRule(.ignore, for: "Spesa")
        #expect(flow.statementRules.map(\.match) == ["Spesa"])
        #expect(try line(flow, "Spesa 1234").statementClass == .ignore)
        #expect(try line(flow, "Spesa 5678").source == .rule("Spesa"))
        let ignored = try #require(flow.statementClassTotals.first { $0.statementClass == .ignore })
        #expect(ignored.lines == 2)
        #expect(ignored.moneyOut == Decimal(string: "110.4"))
        flow.setStatementRule(nil, for: "Spesa")
        #expect(flow.statementRules.isEmpty)
    }

    @Test func theDaysTheFileCoversCanBeGiven() throws {
        var flow = flow()
        let period = try #require(flow.statementPeriod)
        #expect(period.from == "2026-09-01")
        #expect(period.through == "2026-09-30")
        flow.setStatementThrough("2026-09-26")
        #expect(flow.statementPeriod?.through == "2026-09-26")
        let value = try #require(flow.preview?.records.first { $0.imported.key.date == "2026-09-26" })
        let text = flow.describe(value.incoming, locale: Locale(identifier: "en_US"))
        #expect(text.contains("in "))
        #expect(text.contains("out "))
        flow.setStatementFrom("2026-09-03")
        #expect(flow.statementNotes.contains { $0.isProblem })
    }

    @Test func aFileThatDoesNotFollowOnNeedsTheBalanceBeforeIt() throws {
        var library = PreviewLibrary.library
        library.months["2026-08"]?.valuations.removeAll { $0.account == "conto-fineco" }
        var flow = ImportFlow(library: library)
        flow.open(Data(Self.csv.utf8), fileName: "settembre.csv")
        flow.setConstants { $0.account = "conto-fineco" }
        #expect(flow.needsOpeningBalance)
        #expect(flow.statementNotes.contains { $0.isProblem })
        let problem = try #require(flow.openingBalanceProblem)
        #expect(problem.hasPrefix("Conto Fineco's balances can't be worked out"))
        #expect(!problem.contains("conto-fineco"))
        #expect(flow.mappingIssues.contains(problem))
        #expect(!flow.previewIssues.contains(problem))
        #expect(flow.blockers.contains("Give the balance before the file's first line."))
        flow.setStatementOpeningBalance(Decimal(string: "4515.2"))
        #expect(!flow.needsOpeningBalance)
        #expect(flow.statementOpeningBalance == Decimal(string: "4515.2"))
        #expect(flow.openingBalanceProblem == nil)
        #expect(flow.statementNotes.contains { $0.text.contains("not the day before the file") })
    }

    @Test func anOpeningBalanceThatDisagreesWithTheValueBeforeIsSaidSo() {
        var flow = flow()
        flow.setStatementOpeningBalance(4000)
        let notes = flow.statementNotes.map(\.text)
        #expect(notes.contains { $0.contains("isn't the balance before the file's first line") })
        #expect(!notes.contains { $0.contains("not the day before the file") })
    }
}
