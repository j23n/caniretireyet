import Foundation
import Importer
import Model
import Testing
@testable import CanIRetireYet

/// The Import screen's steps for a bank statement (UI.md, "Import";
/// IMPORT.md, "Bank statements"): the account asked on the File step,
/// Review after it, several statements at once, and the days the file
/// covers, on a made-up September statement of the example library's
/// current account.
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

    @Test func aStatementGoesFromTheFileToReview() {
        let flow = flow()
        #expect(flow.layout == .statement)
        #expect(flow.steps == [.file, .preview, .done])
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
        #expect(!flow.canShow(.preview))
        #expect(flow.isBatch)
        #expect(flow.continueHint != nil)
        flow.setConstants { $0.account = "conto-fineco" }
        #expect(!flow.needsStatementAccount)
        #expect(flow.nextStep == .preview)
        #expect(flow.continueHint == nil)
    }

    @Test func anAccountThatCantBeTheStatementsWaitsToo() {
        var flow = flow()
        flow.setConstants { $0.account = "directa" }
        #expect(flow.needsStatementAccount)
        #expect(!flow.canShow(.preview))
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
        #expect(flow.steps == [.file, .accounts, .preview, .done])
        flow.show(.accounts)
        #expect(flow.step == .accounts)
        library.accounts["conto-fineco"]?.opened = opened
        flow.setLibrary(library)
        #expect(flow.steps == [.file, .preview, .done])
        #expect(flow.step == .file)
    }

    @Test func aStepTheLayoutTakesAwayGoesBackToTheFile() {
        var flow = flow()
        flow.setLayout(.wide)
        flow.show(.columns)
        #expect(flow.step == .columns)
        flow.setLayout(.statement)
        #expect(flow.step == .file)
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

    // MARK: Every statement on one page

    private static var withTaxPot: Library {
        var library = PreviewLibrary.library
        library.accounts["tasse"] = Account(id: "tasse", name: "Tax pot", kind: .taxPot, currency: .eur,
                                            opened: "2026-01-01")
        return library
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
        #expect(flow.steps == [.file, .preview, .done])
        #expect(flow.batchPairedTransfers == 1)
        #expect(flow.previews.count == 2)

        flow.showBatchFile(0)
        #expect(flow.fileName == "fineco-settembre.csv")
        let giroconto = try line(flow, "Giroconto")
        #expect(giroconto.source == .paired("conto-deposito"))
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
        #expect(!unknown.canShow(.preview))
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
        #expect(flow.barSteps == [.file, .preview])
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
        #expect(flow.steps == [.file, .accounts, .preview, .done])
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
