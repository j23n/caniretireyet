import Foundation
import Importer
import Model
import Testing
@testable import CanIRetireYet

/// The Import screen's steps for a bank statement (UI.md, "Import";
/// IMPORT.md, "Bank statements"): the account asked on the File step,
/// Income after it, money in by sender, a line's class changed alone or by
/// a rule, and the days the file covers, on a made-up September statement
/// of the example library's current account.
struct ImportStatementFlowTests {
    private static let csv = """
        Data;Importo;Descrizione
        02/09/2026;-1.200,00;Affitto settembre
        10/09/2026;3.400,00;Stipendio settembre
        14/09/2026;-62,10;Spesa 1234 supermercato
        21/09/2026;-48,30;Spesa 5678 mercato
        25/09/2026;-500,00;Giroconto conto deposito
        """

    private func flow(adding lines: String = "") -> ImportFlow {
        var flow = ImportFlow(library: PreviewLibrary.library)
        flow.open(Data((Self.csv + lines).utf8), fileName: "settembre.csv")
        flow.setConstants { $0.account = "conto-fineco" }
        return flow
    }

    private func line(_ flow: ImportFlow, _ text: String) throws -> StatementLine {
        try #require(flow.statementLines.first { $0.text.hasPrefix(text) })
    }

    @Test func aStatementHasAnIncomeStepAfterTheFile() {
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

    @Test func incomeIsListedBySenderAndChangedForAllItsLines() throws {
        var flow = flow()
        let income = flow.incomingGroups(.income)
        #expect(income.map(\.sender) == ["Stipendio"])
        #expect(income.first?.total == 3400)
        #expect(flow.statementQuestions.isEmpty)
        flow.setStatementClass(.paidBack, for: try #require(income.first))
        #expect(flow.incomingGroups(.income).isEmpty)
        #expect(flow.statementRules.map(\.match) == ["Stipendio"])
        #expect(flow.incomingGroups(.paidBack).map(\.sender) == ["Stipendio"])
    }

    @Test func aSenderBehindALongerRuleIsChangedLineByLine() throws {
        var flow = flow()
        flow.setStatementRule(.paidBack, for: "Stipendio settembre")
        let group = try #require(flow.incomingGroups(.paidBack).first { $0.sender == "Stipendio" })
        flow.setStatementClass(.income, for: group)
        #expect(flow.incomingGroups(.income).map(\.sender) == ["Stipendio"])
        #expect(flow.statementRules.map(\.match) == ["Stipendio settembre"])
    }

    @Test func noRuleIsMadeWhenItWouldTakeMoneyOut() throws {
        var flow = flow(adding: "\n20/09/2026;-80,00;Stipendio trattenuta")
        let group = try #require(flow.incomingGroups(.income).first)
        flow.setStatementClass(.paidBack, for: group)
        #expect(flow.incomingGroups(.paidBack).map(\.sender) == ["Stipendio"])
        #expect(flow.statementRules.isEmpty)
        #expect(try line(flow, "Stipendio trattenuta").statementClass == .spending)
    }

    @Test func theSumsSayWhatCameInAndWhatWasSpent() {
        let sums = flow().statementSums
        #expect(sums.cameIn == 3400)
        #expect(sums.wentOut == Decimal(string: "1310.4"))
        #expect(sums.paidBack == 0)
        #expect(sums.spent == Decimal(string: "1310.4"))
        #expect(sums.moved == -500)
    }

    @Test func aLargeLineIsAnsweredAloneAndChangedBackWithItsGroup() throws {
        var flow = flow(adding: "\n15/09/2026;5.000,00;Bonifico da Notaio Bianchi")
        let question = try #require(flow.statementQuestions.first)
        #expect(flow.statementQuestions.count == 1)
        #expect(question.sender == "Notaio Bianchi")
        #expect(flow.incomingGroups(.paidBack).isEmpty)
        flow.setStatementClass(.oneOff, forRow: question.row)
        #expect(flow.statementQuestions.isEmpty)
        let oneOff = try #require(flow.incomingGroups(.oneOff).first)
        #expect(oneOff.total == 5000)
        #expect(flow.statementSums.oneOffs == 5000)
        // Its class was chosen alone, so it changes alone: no rule.
        flow.setStatementClass(.paidBack, for: oneOff)
        #expect(flow.incomingGroups(.oneOff).isEmpty)
        #expect(flow.statementRules.isEmpty)
        #expect(flow.statementSums.paidBack == 5000)
    }

    @Test func aLargeLineOutIsAnsweredAsAPurchaseYouKeep() throws {
        var flow = flow(adding: "\n18/09/2026;-18.000,00;Bonifico a Autosalone Neri")
        let question = try #require(flow.statementQuestions.first)
        #expect(flow.statementQuestions.count == 1)
        #expect(question.amount == -18000)
        flow.setStatementAsset(.purchase(name: "Car", kind: .belongings), forRow: question.row)
        #expect(flow.statementQuestions.isEmpty)
        let bought = try #require(flow.statementAssetLines.first)
        #expect(flow.statementAssetText(bought) == "A purchase you keep: Car")
        #expect(flow.statementSums.bought == 18000)
        #expect(flow.statementSums.spent == Decimal(string: "1310.4"))
        #expect(flow.statementSums.moved == -500)
        #expect(flow.preview?.newAccounts.map(\.account.name) == ["Car"])
        #expect(flow.steps == [.file, .classify, .preview, .done])
        // Undone, it's asked again.
        flow.setStatementAsset(nil, forRow: question.row)
        #expect(flow.statementAssetLines.isEmpty)
        #expect(flow.statementQuestions.count == 1)
        #expect(flow.preview?.newAccounts.isEmpty == true)
    }

    @Test func aLargeLineInIsAnsweredAsTheSaleOfAnAccount() throws {
        var flow = flow(adding: "\n22/09/2026;250.000,00;Rogito notaio vendita")
        let question = try #require(flow.statementQuestions.first)
        #expect(flow.saleChoices(for: question).map(\.id) == ["casa"])
        flow.setStatementAsset(.sale("casa"), forRow: question.row)
        let sold = try #require(flow.statementAssetLines.first)
        #expect(flow.statementAssetText(sold) == "The sale of Home")
        #expect(flow.statementSums.sold == 250_000)
        #expect(flow.statementSums.paidBack == 0)
        #expect(flow.preview?.accountChanges.map(\.account) == ["casa"])
        // The Income step answered it: no Accounts step.
        #expect(flow.steps == [.file, .classify, .preview, .done])
    }

    /// Importing the file again with the same answer finds the same sale:
    /// the account it closed is still offered.
    @Test func aSaleImportedBeforeIsOfferedAgain() throws {
        var flow = flow(adding: "\n22/09/2026;250.000,00;Rogito notaio vendita")
        let question = try #require(flow.statementQuestions.first)
        flow.setStatementAsset(.sale("casa"), forRow: question.row)
        let library = try #require(flow.preview).apply(to: PreviewLibrary.library).library
        #expect(library.accounts["casa"]?.isClosed == true)

        var again = ImportFlow(library: library)
        again.open(Data((Self.csv + "\n22/09/2026;250.000,00;Rogito notaio vendita").utf8), fileName: "settembre.csv")
        again.setConstants { $0.account = "conto-fineco" }
        let asked = try #require(again.statementQuestions.first)
        #expect(again.saleChoices(for: asked).map(\.id) == ["casa"])
        again.setStatementAsset(.sale("casa"), forRow: asked.row)
        #expect(again.preview?.records.allSatisfy { $0.status == .identical } == true)
        #expect(again.preview?.accountChanges.isEmpty == true)
    }

    /// An answer the import can't record, here on the first statement of an
    /// account without values, stays listed with why, and Undo takes it back.
    @Test func anAnswerThatIsntRecordedCanBeUndone() throws {
        var library = PreviewLibrary.library
        library.accounts["nuovo"] = Account(id: "nuovo", name: "Conto nuovo", kind: .cash, currency: .eur,
                                            opened: "2026-01-01")
        var flow = ImportFlow(library: library)
        flow.open(Data((Self.csv + "\n18/09/2026;-18.000,00;Bonifico a Autosalone Neri").utf8),
                  fileName: "settembre.csv")
        flow.setConstants { $0.account = "nuovo" }
        flow.setStatementOpeningBalance(25000)
        let question = try #require(flow.statementQuestions.first)
        flow.setStatementAsset(.purchase(name: "Car", kind: .belongings), forRow: question.row)
        let answered = try #require(flow.statementAssetLines.first)
        #expect(answered.asset == nil)
        #expect(flow.statementAssetText(answered) == "Not recorded: the file doesn't cover the value it counts in")
        #expect(flow.statementQuestions.isEmpty)
        #expect(flow.preview?.newAccounts.isEmpty == true)
        flow.setStatementAsset(nil, forRow: question.row)
        #expect(flow.statementAssetLines.isEmpty)
        #expect(flow.statementAnswer(answered) == nil)
    }

    /// Several statements at once (IMPORT.md, "Several statements at
    /// once"): each file's account found, the transfer between them paired,
    /// one file shown at a time, and the import waiting for a file's
    /// account until it's chosen.
    @Test func severalStatementsAreImportedTogether() throws {
        let deposito = """
            Data;Importo;Descrizione;Saldo
            26/09/2026;500,00;Bonifico in entrata;17.330,50
            """
        var flow = ImportFlow(library: PreviewLibrary.library)
        flow.open(files: [(name: "fineco-settembre.csv", data: Data(Self.csv.utf8)),
                          (name: "esempio-settembre.csv", data: Data(deposito.utf8))])
        #expect(flow.isBatch)
        #expect(flow.displayName == "2 statements")
        #expect(flow.batchFiles.map(\.account) == ["conto-deposito", "conto-fineco"])
        #expect(!flow.needsStatementAccount)
        #expect(flow.steps == [.file, .classify, .preview, .done])
        #expect(flow.batchPairedTransfers == 1)
        #expect(flow.batchPreviews.count == 2)

        flow.showBatchFile(0)
        #expect(flow.fileName == "fineco-settembre.csv")
        let giroconto = try line(flow, "Giroconto")
        #expect(giroconto.source == .paired("conto-deposito"))
        #expect(flow.statementSourceText(giroconto.source) == "Matches a line of Conto deposito's statement")
        // A change to one file's lines keeps the pair.
        flow.setStatementClass(.spending, forRow: try line(flow, "Affitto").row)
        #expect(try line(flow, "Giroconto").source == .paired("conto-deposito"))
        #expect(flow.planned?.hasChanges == true)

        // A file nothing recognizes waits for its account.
        var unknown = ImportFlow(library: PreviewLibrary.library)
        unknown.open(files: [(name: "fineco-settembre.csv", data: Data(Self.csv.utf8)),
                             (name: "export.csv", data: Data(Self.csv.utf8))])
        #expect(unknown.needsStatementAccount)
        #expect(unknown.continueHint == "Choose the account of export.csv to continue.")
        #expect(!unknown.canShow(.classify))
        unknown.setBatchAccount("conto-deposito", forFile: 1)
        #expect(!unknown.needsStatementAccount)
        #expect(unknown.batchFiles.first { $0.id == 1 }?.accountSource == .chosen)
    }

    @Test func previewChartsTheFilesBalanceAgainstTheAccountsValues() throws {
        let charts = try #require(flow().statementCharts)
        #expect(!charts.money.counted.isEmpty)
        #expect(charts.file.first == .init(date: "2026-09-01", balance: Decimal(string: "4515.2") ?? 0))
        #expect(charts.fileBalance(on: "2026-09-12") == Decimal(string: "6715.2"))
        #expect(charts.file.last == .init(date: "2026-09-30", balance: Decimal(string: "6104.8") ?? 0))
        #expect(charts.before.map(\.date) == ["2026-09-30"])
        #expect(!charts.agrees(try #require(charts.before.first)))
        #expect(charts.balanceCaption.hasSuffix("0 of 1 agree."))
    }

    @Test func moneyInAndOutEndsWithTheMonthWhenTheLibraryGoesOn() throws {
        var library = PreviewLibrary.library
        for var valuation in library.months["2026-09"]?.valuations ?? [] {
            _ = library.removeValuation(valuation.key)
            valuation.date = "2026-10-01"
            library.upsert(valuation)
        }
        var flow = ImportFlow(library: library)
        flow.open(Data(Self.csv.utf8), fileName: "settembre.csv")
        flow.setConstants { $0.account = "conto-fineco" }
        flow.setStatementThrough("2026-09-26")
        let charts = try #require(flow.statementCharts)
        let last = try #require(charts.money.periods.last)
        #expect(last.through == "2026-09-30")
        #expect(!charts.money.isSoFar(last))
    }

    @Test func theBalanceLineLeavesOutLinesAfterTheLastValue() {
        let lines: [(date: CalendarDate, amount: Decimal)] = [("2026-09-02", -100), ("2026-10-02", 50)]
        let days = ImportStatementCharts.dayEnds(lines: lines, values: [.init(date: "2026-09-30", balance: 900)])
        #expect(days == [.init(date: "2026-09-01", balance: 1000), .init(date: "2026-09-02", balance: 900),
                         .init(date: "2026-09-30", balance: 900)])
    }

    @Test func eachStretchOfTheLineIsWorkedBackFromItsOwnValue() {
        let lines: [(date: CalendarDate, amount: Decimal)] = [("2026-09-02", -100), ("2026-09-20", 300)]
        let days = ImportStatementCharts.dayEnds(lines: lines, values: [
            .init(date: "2026-09-15", balance: 900), .init(date: "2026-09-30", balance: 1250),
        ])
        #expect(days == [.init(date: "2026-09-01", balance: 1000), .init(date: "2026-09-02", balance: 900),
                         .init(date: "2026-09-15", balance: 900), .init(date: "2026-09-20", balance: 1250),
                         .init(date: "2026-09-30", balance: 1250)])
    }

    @Test func theCaptionCountsTheValuesThatAgree() throws {
        var charts = try #require(flow().statementCharts)
        let agreeing = ImportStatementCharts.Balance(date: "2026-09-12", balance: Decimal(string: "6715.2") ?? 0)
        #expect(charts.agrees(agreeing))
        charts.before = [agreeing]
        #expect(charts.balanceCaption.hasSuffix(": it agrees."))
        charts.before = [agreeing, .init(date: "2026-09-30", balance: Decimal(string: "6104.8") ?? 0)]
        #expect(charts.balanceCaption.hasSuffix(": all 2 agree."))
    }
}
