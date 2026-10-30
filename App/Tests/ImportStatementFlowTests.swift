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
        #expect(flow.isBatch)
        #expect(flow.continueHint != nil)
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
        #expect(flow.allStatementLines.filter { $0.line.statementClass == .ignore }.count == 2)
        #expect(flow.statementRuleTarget(matching: "spesa") == .statementClass(.ignore))
        flow.setStatementRule(nil, for: "Spesa")
        #expect(flow.statementRules.isEmpty)
        #expect(flow.statementRuleTarget(matching: "Spesa") == nil)
    }

    @Test func theDaysTheFileCoversCanBeGiven() throws {
        var flow = flow()
        let period = try #require(flow.statementPeriod)
        #expect(period.from == "2026-09-01")
        #expect(period.through == "2026-09-30")
        flow.setStatementThrough("2026-09-26")
        #expect(flow.statementPeriod?.through == "2026-09-26")
        #expect(flow.preview?.records.contains { $0.imported.key.date == "2026-09-26" } == true)
        // The rent on 2 September is before the first day given.
        flow.setStatementFrom("2026-09-03")
        #expect(flow.statementPeriod == nil)
        #expect(flow.preview?.issues.contains {
            $0.kind == .linesOutsidePeriod(count: 1, from: "2026-09-03", through: "2026-09-26")
        } == true)
    }

    @Test func aCheckInsStatementsCoverThroughItsDate() throws {
        var flow = ImportFlow(library: PreviewLibrary.library, checkIn: "2026-09-27")
        flow.open(Data(Self.csv.utf8), fileName: "settembre.csv")
        flow.setConstants { $0.account = "conto-fineco" }
        #expect(flow.statementPeriod?.through == "2026-09-27")
        #expect(flow.preview?.records.contains { $0.imported.key.date == "2026-09-27" } == true)
        // Several statements too, and a file read with another profile.
        var batch = ImportFlow(library: PreviewLibrary.library, checkIn: "2026-09-27")
        batch.open(files: Self.twoStatements)
        batch.showBatchFile(0)
        #expect(batch.statementPeriod?.through == "2026-09-27")
        flow.useProfile(nil)
        flow.setConstants { $0.account = "conto-fineco" }
        #expect(flow.statementPeriod?.through == "2026-09-27")
    }

    @Test func aFileThatDoesNotFollowOnNeedsTheBalanceBeforeIt() throws {
        var library = PreviewLibrary.library
        library.months["2026-08"]?.valuations.removeAll { $0.account == "conto-fineco" }
        var flow = ImportFlow(library: library)
        flow.open(Data(Self.csv.utf8), fileName: "settembre.csv")
        flow.setConstants { $0.account = "conto-fineco" }
        #expect(flow.needsOpeningBalance)
        #expect(!flow.blockers.isEmpty)
        flow.setStatementOpeningBalance(Decimal(string: "4515.2"), forFile: 0)
        #expect(!flow.needsOpeningBalance)
        // The file's closing balance, 4.515,20 + 1.589,60, isn't the library's on 30 September, so that value is a
        // conflict the library's balance is kept for until it's overwritten. The lines are written either way, so
        // nothing blocks the import: the month then shows the difference.
        let closing = flow.preview?.records.first { $0.imported.key.date == "2026-09-30" }
        #expect(closing?.imported.balance == Decimal(string: "6104.8"))
        #expect(flow.planned?.kept == 1)
        #expect(flow.planned?.overwritten == 0)
        #expect(flow.blockers.isEmpty)
    }

    @Test func incomeIsListedBySender() throws {
        let flow = flow()
        let income = flow.incomeGroups
        #expect(income.map(\.sender) == ["Stipendio"])
        #expect(income.first?.total == 3400)
        #expect(ImportFlow.filter(for: try #require(income.first)) == StatementLinesFilter(search: "Stipendio",
                                                                                            show: .income))
        #expect(flow.statementQuestions.isEmpty)
    }

    /// A question stays listed once it's answered, with its answer, and
    /// "N of M left" counts those still waiting.
    @Test func aLargeLineIsAnsweredAloneAndStaysListed() throws {
        var flow = flow(adding: "\n15/09/2026;5.000,00;Bonifico da Notaio Bianchi")
        let question = try #require(flow.statementQuestions.first)
        #expect(flow.statementQuestions.count == 1)
        #expect(flow.unansweredQuestions == 1)
        #expect(question.line.sender == "Notaio Bianchi")
        #expect(flow.answerChoice(question) == nil)
        flow.setStatementClass(.oneOff, for: question)
        let answered = try #require(flow.statementQuestions.first)
        #expect(flow.statementQuestions.count == 1)
        #expect(flow.unansweredQuestions == 0)
        #expect(flow.answerChoice(answered) == .statementClass(.oneOff))
        #expect(answered.line.source == .chosen)
        // An answered question isn't a sender's income too.
        flow.setStatementClass(.income, for: answered)
        #expect(flow.incomeGroups.map(\.sender) == ["Stipendio"])
        // Undone, it's asked again.
        flow.setStatementClass(nil, for: answered)
        #expect(flow.unansweredQuestions == 1)
    }

    @Test func aLargeLineOutIsAnsweredAsAPurchaseYouKeep() throws {
        var flow = flow(adding: "\n18/09/2026;-18.000,00;Bonifico a Autosalone Neri")
        let question = try #require(flow.statementQuestions.first)
        #expect(flow.statementQuestions.count == 1)
        #expect(question.amount == -18000)
        #expect(flow.saleChoices(for: question).isEmpty)
        flow.setStatementAsset(.purchase(name: "Car", kind: .belongings), for: question)
        let bought = try #require(flow.statementQuestions.first)
        #expect(flow.unansweredQuestions == 0)
        #expect(flow.answerChoice(bought) == .moved)
        #expect(flow.answerDetail(bought)?.isProblem == false)
        #expect(flow.preview?.newAccounts.map(\.account.name) == ["Car"])
        #expect(flow.steps == [.file, .classify, .preview, .done])
        // An answered question isn't one of the moves found for you.
        #expect(!flow.moveGroups.contains { $0.lines.contains { $0.id == bought.id } })
        // Undone, it's asked again.
        flow.setStatementAsset(nil, for: bought)
        #expect(flow.unansweredQuestions == 1)
        #expect(flow.preview?.newAccounts.isEmpty == true)
    }

    @Test func aLargeLineOutIsAnsweredAsMovedToATaxPot() throws {
        var flow = ImportFlow(library: Self.withTaxPot)
        flow.open(Data((Self.csv + "\n15/09/2026;-6.000,00;Accantonamento tasse").utf8), fileName: "settembre.csv")
        flow.setConstants { $0.account = "conto-fineco" }
        let question = try #require(flow.statementQuestions.first)
        #expect(flow.moveChoices(for: question).first?.id == "tasse")
        flow.setStatementAsset(.moved("tasse"), for: question)
        let moved = try #require(flow.statementQuestions.first)
        #expect(flow.statementAnswer(moved) == .moved("tasse"))
        #expect(flow.preview?.records.contains { $0.imported.key.account == "tasse" } == true)
    }

    @Test func taxIsTakenOffWhatCameIn() throws {
        var flow = flow(adding: "\n16/09/2026;-800,00;Pagamento F24 Agenzia delle Entrate")
        #expect(try line(flow, "Pagamento F24").statementClass == .tax)
        let tax = try #require(flow.allStatementLines.first { $0.line.text.hasPrefix("Pagamento F24") })
        #expect(flow.answerDetail(tax) == nil)
        flow.setStatementClass(.tax, for: tax)
        let chosen = try #require(flow.allStatementLines.first { $0.id == tax.id })
        #expect(flow.answerDetail(chosen) != nil)
    }

    @Test func aLargeLineInIsAnsweredAsTheSaleOfAnAccount() throws {
        var flow = flow(adding: "\n22/09/2026;250.000,00;Rogito notaio vendita")
        let question = try #require(flow.statementQuestions.first)
        #expect(flow.saleChoices(for: question).map(\.id) == ["casa", "tfr"])
        flow.setStatementAsset(.sale("casa"), for: question)
        let sold = try #require(flow.statementQuestions.first)
        #expect(flow.statementAnswer(sold) == .sale("casa"))
        #expect(flow.preview?.accountChanges.map(\.account) == ["casa"])
        // The Income step answered it: no Accounts step.
        #expect(flow.steps == [.file, .classify, .preview, .done])
    }

    /// A line in can sell what a purchase earlier in the import starts.
    @Test func aSaleCanSellWhatAPurchaseStarts() throws {
        var flow = flow(adding: "\n18/09/2026;-18.000,00;Bonifico a Autosalone Neri"
            + "\n22/09/2026;15.000,00;Bonifico da Mario Verdi")
        let car = try #require(flow.allStatementLines.first { $0.line.text.hasPrefix("Bonifico a Autosalone") })
        flow.setStatementAsset(.purchase(name: "Car", kind: .belongings), for: car)
        let sale = try #require(flow.allStatementLines.first { $0.line.text.hasPrefix("Bonifico da Mario") })
        #expect(flow.saleChoices(for: sale).map(\.id).contains("car"))
        // A line before the purchase can't sell it.
        let earlier = try #require(flow.allStatementLines.first { $0.amount > 0 && $0.date < car.date })
        #expect(!flow.saleChoices(for: earlier).map(\.id).contains("car"))
        flow.setStatementAsset(.sale("car"), for: sale)
        let sold = try #require(flow.allStatementLines.first { $0.id == sale.id })
        #expect(flow.statementAnswer(sold) == .sale("car"))
        #expect(flow.preview?.accountChanges.map(\.account) == ["car"])
        // Sold, it isn't offered to another line.
        #expect(!flow.saleChoices(for: earlier).map(\.id).contains("car"))
    }

    /// A month's statement can sell what the month before's purchase starts.
    @Test func aSaleCanSellWhatAnEarlierFilesPurchaseStarts() throws {
        var library = Library(accounts: [
            Account(id: "conto", name: "Conto corrente", kind: .cash, currency: .eur, opened: "2020-01-01"),
        ])
        library.upsert(Valuation(account: "conto", date: "2026-07-31", balance: 30000))
        let august = """
            Data;Importo;Descrizione
            10/08/2026;3.400,00;Stipendio agosto
            18/08/2026;-18.000,00;Bonifico a Autosalone Neri
            """
        let september = """
            Data;Importo;Descrizione
            10/09/2026;3.400,00;Stipendio settembre
            22/09/2026;15.000,00;Bonifico da Mario Verdi
            """
        var flow = ImportFlow(library: library)
        flow.open(statements: [(name: "agosto.csv", data: Data(august.utf8)),
                               (name: "settembre.csv", data: Data(september.utf8))])
        flow.setBatchAccount("conto", forFile: 0)
        flow.setBatchAccount("conto", forFile: 1)
        let car = try #require(flow.allStatementLines.first { $0.line.text.hasPrefix("Bonifico a Autosalone") })
        flow.setStatementAsset(.purchase(name: "Car", kind: .belongings), for: car)
        let sale = try #require(flow.allStatementLines.first { $0.line.text.hasPrefix("Bonifico da Mario") })
        #expect(flow.saleChoices(for: sale).map(\.id) == ["car"])
        flow.setStatementAsset(.sale("car"), for: sale)
        let sold = try #require(flow.allStatementLines.first { $0.id == sale.id })
        #expect(flow.statementAnswer(sold) == .sale("car"))
        let planned = try #require(flow.planned)
        #expect(planned.library.accounts["car"]?.closed == "2026-09-23")
    }

    /// Another account's statement can sell what a purchase starts, even
    /// when its file is read before the purchase's.
    @Test func aSaleCanSellWhatAnotherAccountsPurchaseStarts() throws {
        var library = Library(accounts: [
            Account(id: "conto", name: "Conto corrente", kind: .cash, currency: .eur, opened: "2020-01-01"),
            Account(id: "risparmio", name: "Risparmio", kind: .savings, currency: .eur, opened: "2020-01-01"),
        ])
        library.upsert(Valuation(account: "conto", date: "2026-07-31", balance: 5000))
        library.upsert(Valuation(account: "risparmio", date: "2026-07-31", balance: 30000))
        let current = """
            Data;Importo;Descrizione
            10/08/2026;3.400,00;Stipendio agosto
            25/08/2026;15.000,00;Bonifico da Mario Verdi
            """
        let savings = """
            Data;Importo;Descrizione
            18/08/2026;-18.000,00;Bonifico a Autosalone Neri
            """
        var flow = ImportFlow(library: library)
        flow.open(statements: [(name: "conto.csv", data: Data(current.utf8)),
                               (name: "risparmio.csv", data: Data(savings.utf8))])
        flow.setBatchAccount("conto", forFile: 0)
        flow.setBatchAccount("risparmio", forFile: 1)
        let car = try #require(flow.allStatementLines.first { $0.line.text.hasPrefix("Bonifico a Autosalone") })
        flow.setStatementAsset(.purchase(name: "Car", kind: .belongings), for: car)
        let sale = try #require(flow.allStatementLines.first { $0.line.text.hasPrefix("Bonifico da Mario") })
        #expect(flow.saleChoices(for: sale).map(\.id) == ["car"])
        flow.setStatementAsset(.sale("car"), for: sale)
        let sold = try #require(flow.allStatementLines.first { $0.id == sale.id })
        #expect(flow.statementAnswer(sold) == .sale("car"))
        let planned = try #require(flow.planned)
        #expect(planned.library.accounts["car"]?.closed == "2026-08-26")
        #expect(planned.library.valuations(for: "car").last?.balance == 0)
    }

    /// Importing the file again with the same answer finds the same sale:
    /// the account it closed is still offered.
    @Test func aSaleImportedBeforeIsOfferedAgain() throws {
        var flow = flow(adding: "\n22/09/2026;250.000,00;Rogito notaio vendita")
        let question = try #require(flow.statementQuestions.first)
        flow.setStatementAsset(.sale("casa"), for: question)
        let library = try #require(flow.preview).apply(to: PreviewLibrary.library).library
        #expect(library.accounts["casa"]?.isClosed == true)

        var again = ImportFlow(library: library)
        again.open(Data((Self.csv + "\n22/09/2026;250.000,00;Rogito notaio vendita").utf8), fileName: "settembre.csv")
        again.setConstants { $0.account = "conto-fineco" }
        let asked = try #require(again.statementQuestions.first)
        #expect(again.saleChoices(for: asked).map(\.id) == ["casa", "tfr"])
        again.setStatementAsset(.sale("casa"), for: asked)
        // The sale's value is found again. The current account's September
        // differs from the example library's own value either way.
        let sale = again.preview?.records.first { $0.imported.key.account == "casa" }
        #expect(sale?.status == .identical)
        #expect(again.preview?.accountChanges.isEmpty == true)
    }

    /// An answer the import can't record, here money moved into a tax pot
    /// on the first statement of an account without values, says why, and
    /// opens its sheet to change it. A purchase there is recorded: it needs
    /// no value of the file.
    @Test func anAnswerThatIsntRecordedSaysWhy() throws {
        var library = Self.withTaxPot
        library.accounts["nuovo"] = Account(id: "nuovo", name: "Conto nuovo", kind: .cash, currency: .eur,
                                            opened: "2026-01-01")
        var flow = ImportFlow(library: library)
        flow.open(Data((Self.csv + "\n18/09/2026;-18.000,00;Bonifico a Autosalone Neri").utf8),
                  fileName: "settembre.csv")
        flow.setConstants { $0.account = "nuovo" }
        flow.setStatementOpeningBalance(25000, forFile: 0)
        let question = try #require(flow.statementQuestions.first)
        flow.setStatementAsset(.moved("tasse"), for: question)
        let answered = try #require(flow.statementQuestions.first)
        #expect(answered.line.asset == nil)
        #expect(flow.answerDetail(answered)?.isProblem == true)
        #expect(flow.answerDetail(answered)?.opensSheet == true)
        flow.setStatementAsset(.purchase(name: "Car", kind: .belongings), for: answered)
        let bought = try #require(flow.statementQuestions.first)
        #expect(flow.answerDetail(bought)?.isProblem == false)
        #expect(flow.preview?.newAccounts.map(\.account.id) == ["car"])
        flow.setStatementAsset(nil, for: bought)
        #expect(flow.statementAnswer(bought) == nil)
    }

    // MARK: Every statement on one page

    private static var withTaxPot: Library {
        var library = PreviewLibrary.library
        library.accounts["tasse"] = Account(id: "tasse", name: "Tax pot", kind: .taxPot, currency: .eur,
                                            opened: "2026-01-01")
        return library
    }

    /// Income and All Lines show every file's lines, and a line of a file
    /// that isn't on screen changes in its own file.
    @Test func everyStatementsLinesAreOnOnePage() throws {
        var flow = ImportFlow(library: PreviewLibrary.library)
        flow.open(files: Self.twoStatements)
        #expect(flow.allStatementLines.count == 6)
        #expect(flow.statementAccountsOpen.map(\.name) == ["Conto deposito", "Conto Fineco"])
        let shown = try #require(flow.batchFile)
        let rent = try #require(flow.allStatementLines.first { $0.line.text.hasPrefix("Affitto") })
        #expect(rent.file != shown)
        flow.setStatementClass(.oneOff, for: rent)
        #expect(flow.batchFile == shown)
        let changed = try #require(flow.allStatementLines.first { $0.id == rent.id })
        #expect(changed.line.source == .chosen)
        #expect(changed.line.statementClass == .oneOff)
        #expect(flow.answerChoice(changed) == .statementClass(.oneOff))
        // The transfer between the files is still paired.
        let out = try #require(flow.allStatementLines.first { $0.line.text.hasPrefix("Giroconto") })
        #expect(out.line.source == .paired("conto-deposito"))
        #expect(flow.answerChoice(out, current: true) == .moved)
        let incoming = try #require(flow.allStatementLines.first { $0.line.text.hasPrefix("Bonifico in entrata") })
        #expect(incoming.line.source == .paired("conto-fineco"))
        let paired = try #require(flow.moveGroups.first { $0.kind == .paired })
        #expect(paired.total == 500)
        #expect(flow.foundForYou.map(\.filter) == [StatementLinesFilter(show: .income),
                                                    StatementLinesFilter(show: .moved)])
    }

    /// A rule made from a line is made in every statement open.
    @Test func aRuleIsMadeInEveryStatement() throws {
        var flow = ImportFlow(library: PreviewLibrary.library)
        flow.open(files: Self.twoStatements)
        flow.setStatementRule(.spending, for: "Bonifico")
        #expect(flow.batchFiles.allSatisfy { $0.session.profile.rules.map(\.match) == ["Bonifico"] })
        let incoming = try #require(flow.allStatementLines.first { $0.line.text.hasPrefix("Bonifico in entrata") })
        #expect(incoming.line.source == .rule("Bonifico"))
        #expect(flow.linesMatching(rule: "bonifico") == 1)
        #expect(flow.linesMatching(rule: "Giroconto") == 1)
        flow.setStatementRule(to: nil, for: "bonifico")
        #expect(flow.statementRules.isEmpty)
    }

    /// A rule's moves to a tax pot are one row of *Moved between your
    /// accounts*, and the rule can be removed.
    @Test func aRulesMovesAreOneRow() throws {
        var flow = ImportFlow(library: Self.withTaxPot)
        flow.open(Data((Self.csv + "\n15/09/2026;-600,00;Accantonamento tasse").utf8), fileName: "settembre.csv")
        flow.setConstants { $0.account = "conto-fineco" }
        let line = try #require(flow.allStatementLines.first { $0.line.text.hasPrefix("Accantonamento") })
        #expect(flow.statementRuleTargets(for: line).contains(.moved("tasse")))
        flow.setStatementRule(to: .moved("tasse"), for: "Accantonamento")
        #expect(flow.statementRuleTarget(matching: "accantonamento") == .moved("tasse"))
        let group = try #require(flow.moveGroups.first)
        #expect(group.kind == .rule("Accantonamento", "tasse"))
        #expect(group.total == -600)
        #expect(group.filter == StatementLinesFilter(search: "Accantonamento", show: .moved))
        #expect(flow.foundForYou.contains { $0.filter == group.filter && $0.amount == 600 })
        flow.setStatementRule(to: nil, for: "Accantonamento")
        #expect(flow.statementRuleTarget(matching: "Accantonamento") == nil)
    }

    /// Money that came in and went out again within days passed through
    /// the account.
    @Test func moneyThatPassedThroughIsOneRow() throws {
        let flow = flow(adding: "\n12/09/2026;20.000,00;Bonifico da Luca Bianchi\n13/09/2026;-20.000,00;Bonifico a Sara Neri")
        let group = try #require(flow.moveGroups.first { $0.kind == .passThrough("conto-fineco") })
        #expect(group.lines.count == 2)
        #expect(group.total == 20000)
        #expect(group.filter == StatementLinesFilter(show: .moved, account: "conto-fineco"))
    }

    /// All Lines: newest first, by month on iPhone, searched and filtered.
    @Test func allLinesAreSearchedAndFiltered() throws {
        var flow = flow(adding: "\n04/08/2026;-35,00;Spesa 9999 mercato")
        flow.setStatementFrom("2026-08-01")
        let all = flow.statementLines(matching: StatementLinesFilter())
        #expect(all.first?.line.text == "Giroconto conto deposito")
        #expect(all.map(\.date) == all.map(\.date).sorted(by: >))
        let spesa = flow.statementLines(matching: StatementLinesFilter(search: "SPESA mercato"))
        #expect(spesa.map(\.line.text) == ["Spesa 5678 mercato", "Spesa 1234 supermercato", "Spesa 9999 mercato"])
        #expect(flow.statementLines(matching: StatementLinesFilter(search: " spésa 9999 ")).map(\.line.text)
            == ["Spesa 9999 mercato"])
        #expect(flow.statementLines(matching: StatementLinesFilter(show: .income)).map(\.line.text)
            == ["Stipendio settembre"])
        #expect(flow.statementLines(matching: StatementLinesFilter(show: .moved)).count == 1)
        #expect(flow.statementLines(matching: StatementLinesFilter(account: "conto-deposito")).isEmpty)
        let months = flow.statementLineMonths(matching: StatementLinesFilter())
        #expect(months.map(\.month) == ["2026-09", "2026-08"])
        let english = Locale(identifier: "en_US")
        #expect(ImportFlow.lineAmount(3400, locale: english) == "+3,400.00")
        #expect(ImportFlow.lineAmount(Decimal(string: "-74") ?? 0, locale: english) == "\u{2212}74.00")
        #expect(ImportFlow.lineAmount(0, locale: english) == "0.00")
        let rent = try #require(all.first { $0.line.text.hasPrefix("Affitto") })
        #expect(rent.line.source == .sign)
        #expect(flow.answerChoice(rent) == nil)
        #expect(flow.answerChoice(rent, current: true) == .statementClass(.spending))
    }

    /// The summary: what came in, tax, after tax, spent and saved, from the
    /// library as importing would leave it.
    @Test func theSummarySaysWhatWasSaved() throws {
        let summary = try #require(flow().incomeSummary)
        #expect(summary.afterTax == summary.cameIn - summary.tax)
        #expect(summary.spent + summary.saved == summary.afterTax)
        #expect(summary.rate != nil)
    }

    /// Several statements at once (IMPORT.md, "Several statements at
    /// once"): each file's account found, the transfer between them paired,
    /// one file shown at a time, and the import waiting for a file's
    /// account until it's chosen.
    @Test func severalStatementsAreImportedTogether() throws {
        var flow = ImportFlow(library: PreviewLibrary.library)
        flow.open(files: Self.twoStatements)
        #expect(flow.isBatch)
        #expect(flow.batchFiles.map(\.account) == ["conto-deposito", "conto-fineco"])
        #expect(!flow.needsStatementAccount)
        #expect(flow.steps == [.file, .classify, .preview, .done])
        #expect(flow.batchPairedTransfers == 1)
        #expect(flow.previews.count == 2)

        flow.showBatchFile(0)
        #expect(flow.fileName == "fineco-settembre.csv")
        let giroconto = try line(flow, "Giroconto")
        #expect(giroconto.source == .paired("conto-deposito"))
        // A change to one file's lines keeps the pair.
        flow.setStatementClass(.spending, forRow: try line(flow, "Affitto").row)
        #expect(try line(flow, "Giroconto").source == .paired("conto-deposito"))
        // The example library has both accounts' September values: kept until they're overwritten.
        #expect(flow.planned?.overwritten == 0)
        flow.setConflictPolicy(.overwrite)
        #expect((flow.planned?.overwritten ?? 0) > 0)

        // A file nothing recognizes waits for its account.
        var unknown = ImportFlow(library: PreviewLibrary.library)
        unknown.open(files: [(name: "fineco-settembre.csv", data: Data(Self.csv.utf8)),
                             (name: "export.csv", data: Data(Self.csv.utf8))])
        #expect(unknown.needsStatementAccount)
        #expect(unknown.continueHint != nil)
        #expect(!unknown.canShow(.classify))
        unknown.setBatchAccount("conto-deposito", forFile: 1)
        #expect(!unknown.needsStatementAccount)
        #expect(unknown.batchFiles.first { $0.id == 1 }?.accountSource == .chosen)
    }

    /// Files added later join the statements open, which keep their
    /// accounts; taking one out pairs the rest again, and the last starts over.
    @Test func statementsAreAddedAndTakenOut() throws {
        var flow = ImportFlow(library: PreviewLibrary.library)
        flow.open(Data(Self.csv.utf8), fileName: "export.csv")
        flow.setBatchAccount("conto-fineco", forFile: 0)
        #expect(flow.barSteps == [.file, .classify, .preview])
        flow.add(files: [(name: "esempio-settembre.csv", data: Data(Self.deposito.utf8))])
        #expect(flow.batchFiles.count == 2)
        #expect(flow.batchFiles.first { $0.id == 0 }?.accountSource == .chosen)
        #expect(flow.batchPairedTransfers == 1)
        flow.remove(file: 1)
        #expect(flow.batchFiles.map(\.id) == [0])
        #expect(flow.batchPairedTransfers == 0)
        flow.remove(file: 0)
        #expect(!flow.hasFile)
    }

    /// A statement read as another layout is one file again, and back as
    /// a statement it's every file given.
    @Test func aStatementReadAsAnotherLayoutLeavesTheBatch() {
        var flow = ImportFlow(library: PreviewLibrary.library)
        flow.open(files: Self.twoStatements)
        flow.setLayout(.trades)
        #expect(!flow.isBatch)
        #expect(flow.layout == .trades)
        flow.setLayout(.statement)
        #expect(flow.batchFiles.count == 2)
    }

    /// The savings account's September, whose balance follows on from its
    /// August value, with the current account's transfer coming in.
    private static let deposito = """
        Data;Importo;Descrizione;Saldo
        26/09/2026;500,00;Bonifico in entrata;17.330,50
        """

    /// The current account's September and the savings account's.
    private static let twoStatements = [(name: "fineco-settembre.csv", data: Data(csv.utf8)),
                                        (name: "esempio-settembre.csv", data: Data(deposito.utf8))]

    /// Accounts answers one statement's opening or closing at a time, so it
    /// opens on the first file that proposes one.
    @Test func accountsOpenOnTheStatementThatProposesAChange() {
        var library = PreviewLibrary.library
        library.accounts["conto-fineco"]?.opened = "2026-10-01"
        var flow = ImportFlow(library: library)
        flow.open(files: Self.twoStatements)
        #expect(flow.batchFile == 1)
        #expect(flow.steps == [.file, .classify, .accounts, .preview, .done])
        flow.show(.accounts)
        #expect(flow.step == .accounts)
        #expect(flow.batchFile == 0)
        #expect(flow.preview?.accountChanges.contains { $0.account == "conto-fineco" } == true)
    }

    /// An account chosen in How It's Read… is chosen, as on the File step.
    @Test func anAccountChangedInHowItsReadIsChosen() {
        var flow = ImportFlow(library: PreviewLibrary.library)
        flow.open(files: Self.twoStatements)
        flow.showBatchFile(0)
        flow.setConstants { $0.account = "conto-deposito" }
        #expect(flow.batchFiles.first { $0.id == 0 }?.accountSource == .chosen)
    }

    /// Two statements of one account's same days wait to be told which
    /// to leave out.
    @Test func twoStatementsOfTheSameDaysWait() {
        var flow = ImportFlow(library: PreviewLibrary.library)
        flow.open(files: [(name: "settembre.csv", data: Data(Self.csv.utf8)),
                          (name: "settembre-copia.csv", data: Data(Self.csv.utf8))])
        flow.setBatchAccount("conto-fineco", forFile: 0)
        flow.setBatchAccount("conto-fineco", forFile: 1)
        #expect(flow.batchGaps.map(\.isOverlap) == [true])
        #expect(!flow.blockers.isEmpty)
    }

    @Test func previewChartsTheFilesBalanceAgainstTheAccountsValues() throws {
        let charts = try #require(flow().statementCharts)
        #expect(!charts.money.counted.isEmpty)
        #expect(charts.file.first == .init(date: "2026-09-01", balance: Decimal(string: "4515.2") ?? 0))
        #expect(charts.fileBalance(on: "2026-09-12") == Decimal(string: "6715.2"))
        #expect(charts.file.last == .init(date: "2026-09-30", balance: Decimal(string: "6104.8") ?? 0))
        #expect(charts.before.map(\.date) == ["2026-09-30"])
        #expect(!charts.agrees(try #require(charts.before.first)))
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

    @Test func aValueAgreesWhenTheFileHasItsBalanceThatDay() throws {
        let charts = try #require(flow().statementCharts)
        #expect(charts.agrees(.init(date: "2026-09-12", balance: Decimal(string: "6715.2") ?? 0)))
        #expect(charts.agrees(.init(date: "2026-09-30", balance: Decimal(string: "6104.8") ?? 0)))
        #expect(!charts.agrees(.init(date: "2026-09-30", balance: 6000)))
    }
}
