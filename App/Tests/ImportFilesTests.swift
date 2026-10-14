import Foundation
import Importer
import Model
import Testing
@testable import CanIRetireYet

/// The Files step of the import (UI.md, "Import"): each statement's bank,
/// what it covers, its balance and account, its menu, the notes between the
/// files, bank statements or a broker's transactions, and what *How It's
/// Read* says, on made-up September statements of the example library's
/// accounts.
struct ImportFilesTests {
    private let locale = Locale(identifier: "en_US")
    private let today: CalendarDate = "2026-10-14"

    /// The current account's September as its bank exports it, read with
    /// the example library's saved profile "Fineco, movimenti".
    private static let fineco = """
        Conto corrente;;;;
        Movimenti di settembre;;;;
        ;;;;
        Data operazione;Data valuta;Entrate;Uscite;Descrizione
        02/09/2026;02/09/2026;;1.200,00;Affitto settembre
        10/09/2026;10/09/2026;3.400,00;;Stipendio settembre
        25/09/2026;25/09/2026;;500,00;Giroconto conto deposito
        """

    /// The savings account's September, whose balance follows on from its
    /// August value, with the current account's transfer coming in.
    private static let deposito = """
        Data;Importo;Descrizione;Saldo
        26/09/2026;500,00;Bonifico in entrata;17.330,50
        """

    /// A statement nothing recognizes.
    private static let export = """
        Data;Importo;Descrizione
        02/09/2026;-1.200,00;Affitto settembre
        10/09/2026;3.400,00;Stipendio settembre
        14/09/2026;-62,10;Spesa 1234 supermercato
        21/09/2026;-48,30;Spesa 5678 mercato
        25/09/2026;-500,00;Giroconto conto deposito
        """

    private func threeStatements() -> ImportFlow {
        var flow = ImportFlow(library: PreviewLibrary.library)
        flow.open(files: [(name: "fineco-2026.csv", data: Data(Self.fineco.utf8)),
                          (name: "deposito-2026.csv", data: Data(Self.deposito.utf8)),
                          (name: "export (3).csv", data: Data(Self.export.utf8))])
        return flow
    }

    @Test func eachStatementSaysItsBankWhatItCoversAndItsAccount() throws {
        let rows = threeStatements().fileRows(today: today, locale: locale)
        #expect(rows.map(\.name) == ["deposito-2026.csv", "fineco-2026.csv", "export (3).csv"])

        let deposito = try #require(rows.first)
        #expect(deposito.bank == "Banca Esempio")
        #expect(deposito.detail == "Banca Esempio · 1 line")
        #expect(deposito.covers == "Sep 2026")
        #expect(deposito.balance == .addsUp)
        #expect(deposito.balance?.text == "Adds up")
        #expect(deposito.accountName == "Conto deposito")
        #expect(deposito.accountSource == "Its balance follows on from Aug 31, 2026")
        #expect(deposito.compactDetail == "Sep 2026 · follows on from Aug 31, 2026")

        let fineco = rows[1]
        #expect(fineco.bank == "Fineco")
        #expect(fineco.detail == "Fineco · 3 lines")
        #expect(fineco.balance == .noColumn)
        #expect(fineco.balance?.text == "No balance column")
        #expect(fineco.account == "conto-fineco")
        #expect(fineco.accountSource == "Remembered from last time")
        #expect(fineco.compactDetail == "Sep 2026 · remembered from last time")
        #expect(!fineco.showsReadingLink)

        // Before it has an account, a file still says what it covers.
        let export = rows[2]
        #expect(export.bank == nil)
        #expect(export.needsAccount)
        #expect(export.detail == "Bank not known · 5 lines")
        #expect(export.covers == "Sep 2026")
        #expect(export.balance == .noColumn)
        #expect(export.accountSource == nil)
        #expect(export.compactDetail == "Sep 2026 · bank not known · 5 lines")
        #expect(export.showsReadingLink)
        #expect(export.offersDays)
    }

    @Test func aChosenAccountSaysNothingOfHowItWasFound() throws {
        var flow = threeStatements()
        flow.setBatchAccount("conto-deposito", forFile: 2)
        let row = try #require(flow.fileRow(2, today: today, locale: locale))
        #expect(row.accountName == "Conto deposito")
        #expect(row.accountSource == nil)
        // Its account's institution names the bank.
        #expect(row.bank == "Banca Esempio")
        #expect(!row.showsReadingLink)
    }

    @Test func aBanksNameIsItsProfilesUpToTheComma() throws {
        var library = PreviewLibrary.library
        library.importProfiles["fineco-movimenti"]?.name = "Fineco"
        var flow = ImportFlow(library: library)
        flow.open(files: [(name: "fineco-2026.csv", data: Data(Self.fineco.utf8))])
        #expect(flow.fileRows(today: today, locale: locale).first?.bank == "Fineco")
        library.accounts["conto-deposito"]?.institution = nil
        flow = ImportFlow(library: library)
        flow.open(files: [(name: "deposito-2026.csv", data: Data(Self.deposito.utf8))])
        #expect(flow.fileRows(today: today, locale: locale).first?.bank == nil)
    }

    @Test func daysOfTheFilesOwnShowInWhatItCovers() throws {
        var flow = threeStatements()
        flow.showBatchFile(2)
        #expect(flow.shownFilePeriod(today: today)?.from == "2026-09-01")
        #expect(flow.shownFilePeriod(today: today)?.through == "2026-09-30")
        #expect(flow.shownFileLastDay(today: today) == "2026-09-25")
        flow.setStatementFrom("2026-09-02")
        #expect(flow.fileRow(2, today: today, locale: locale)?.covers == "Sep 2 – Sep 30, 2026")
    }

    @Test func betweenTheFilesAreTheTransfersPairedAndNoGaps() throws {
        let flow = threeStatements()
        let notes = flow.betweenFilesNotes(locale: locale)
        #expect(notes.map(\.kind) == [.transfers(1), .noGaps])
        #expect(notes[0].text == "1 transfer found in both files and paired: neither spent nor came in.")
        #expect(notes[0].shortText == "1 transfer paired")
        #expect(notes[1].text == "No gaps or overlaps: each file's closing balance is the next one's opening balance.")
        #expect(notes[1].shortText == "No gaps or overlaps")

        let transfers = flow.pairedTransfers()
        #expect(transfers.count == 1)
        let transfer = try #require(transfers.first)
        #expect(transfer.date == "2026-09-25")
        #expect(transfer.amount == 500)
        #expect(transfer.from == "Conto Fineco")
        #expect(transfer.to == "Conto deposito")
    }

    @Test func oneFileHasNothingBetweenFiles() {
        var flow = ImportFlow(library: PreviewLibrary.library)
        flow.open(Data(Self.export.utf8), fileName: "export (3).csv")
        #expect(flow.isBatch)
        #expect(flow.fileRows(today: today, locale: locale).count == 1)
        #expect(flow.betweenFilesNotes(locale: locale).isEmpty)
    }

    @Test func filesAddedJoinTheOnesListed() {
        var flow = ImportFlow(library: PreviewLibrary.library)
        flow.open(files: [(name: "fineco-2026.csv", data: Data(Self.fineco.utf8))])
        flow.add(files: [(name: "export (3).csv", data: Data(Self.export.utf8))], as: .statements)
        #expect(flow.fileRows(today: today, locale: locale).map(\.name) == ["fineco-2026.csv", "export (3).csv"])
        flow.remove(file: 1)
        #expect(flow.fileRows(today: today, locale: locale).map(\.name) == ["fineco-2026.csv"])
    }

    @Test func brokerageTransactionsAreReadOneFileAtATime() {
        var flow = threeStatements()
        #expect(flow.filesKind == .statements)
        flow.setFilesKind(.brokerage)
        #expect(flow.filesKind == .brokerage)
        #expect(!flow.isBatch)
        #expect(flow.layout == .trades)
        #expect(flow.givenFileNames == ["fineco-2026.csv", "deposito-2026.csv", "export (3).csv"])
        let shown = flow.shownGivenFile
        #expect(shown != nil)
        flow.readGivenFile(2)
        #expect(flow.shownGivenFile == 2)
        #expect(flow.fileName == "export (3).csv")
        #expect(flow.layout == .trades)
        flow.setFilesKind(.statements)
        #expect(flow.fileRows(today: today, locale: locale).count == 3)

        // Added as a broker's transactions, the first new file is read.
        var one = ImportFlow(library: PreviewLibrary.library)
        one.open(files: [(name: "fineco-2026.csv", data: Data(Self.fineco.utf8))])
        one.setFilesKind(.brokerage)
        one.add(files: [(name: "export (3).csv", data: Data(Self.export.utf8))], as: .brokerage)
        #expect(one.filesKind == .brokerage)
        #expect(one.fileName == "export (3).csv")
        #expect(one.givenFileNames == ["fineco-2026.csv", "export (3).csv"])
    }

    @Test func howItsReadSaysTheLinesReadAndWhatTheBalanceFollows() {
        var flow = threeStatements()
        flow.showBatchFile(2)
        #expect(flow.readingTitle == "How export (3).csv is read")
        #expect(flow.readingSubtitle.hasPrefix("The bank isn't one it knows."))
        #expect(flow.readingStatus(today: today) == ImportReadingStatus(
            text: "All 5 lines read. With no balance column, the balance follows on from its account's last check-in.",
            isProblem: false))
        #expect(flow.sampleRows(limit: 2).map(\.cells) == [["02/09/2026", "-1.200,00", "Affitto settembre"],
                                                           ["10/09/2026", "3.400,00", "Stipendio settembre"]])

        #expect(flow.shownFileBank == nil)
        flow.showBatchFile(0)
        #expect(flow.shownFileBank == "Fineco")
        #expect(flow.readingSubtitle.hasPrefix("It's read as Fineco's statements are."))
        #expect(flow.readingStatus(today: today).text
            == "All 3 lines read. With no balance column, the balance follows on from Conto Fineco's last check-in.")
        flow.showBatchFile(1)
        #expect(flow.readingStatus(today: today).text == "1 line read. The balance column adds up.")
    }

    @Test func howItsReadShowsEachFormatByAnExample() {
        var flow = threeStatements()
        flow.showBatchFile(2)
        #expect(ImportChoices.dateExample(of: "dd.MM.yyyy") == "31.12.2025")
        #expect(ImportChoices.dateExample(of: "dd/MM/yyyy") == "31/12/2025")
        #expect(ImportChoices.numberExample(ImportNumberFormat(decimal: ",", thousands: ".")) == "1.234,56")
        #expect(ImportChoices.delimiterWord(";") == "Semicolon")

        #expect(flow.datePatternInUse == "dd/MM/yyyy")
        #expect(!flow.datePatternChoices.contains("dd/MM/yyyy"))
        #expect(flow.delimiterInUse == ";")
        #expect(!flow.delimiterChoices.contains(";"))
        #expect(flow.numberStyle == nil)
        #expect(!flow.numberStyleChoices.contains(flow.detectedNumberStyle))

        #expect(flow.dateDetectedTitle == "31/12/2025")
        #expect(flow.delimiterDetectedTitle == "Semicolon")
        #expect(flow.numberDetectedTitle == "1.234,56")

        let style = ImportNumberFormat(decimal: ",", thousands: "")
        flow.useNumberStyle(style)
        #expect(flow.numberStyle == style)
        #expect(flow.numberStyleChoices.contains(style))
        #expect(flow.numberDetectedTitle == "As detected")
        flow.useNumberStyle(nil)
        #expect(flow.numberStyle == nil)
    }
}
