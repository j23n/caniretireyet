import Foundation
import Importer
import Model
import Storage
import Testing
@testable import CanIRetireYet

/// Bank statements' Review and Done (UI.md, "Import"): every file
/// together, the values they disagree with, the accounts they change, and
/// what Done says, on made-up September statements of the example
/// library's current and savings accounts.
struct ImportReviewTests {
    private static let locale = Locale(identifier: "en_GB")

    /// The current account's September.
    private static let current = """
        Data;Importo;Descrizione
        02/09/2026;-1.200,00;Affitto settembre
        10/09/2026;3.400,00;Stipendio settembre
        14/09/2026;-62,10;Spesa 1234 supermercato
        21/09/2026;-48,30;Spesa 5678 mercato
        25/09/2026;-500,00;Giroconto conto deposito
        """

    /// The savings account's September, whose balance follows on from its
    /// August value, with the current account's transfer coming in.
    private static let savings = """
        Data;Importo;Descrizione;Saldo
        26/09/2026;500,00;Bonifico in entrata;17.330,50
        """

    private static let files = [(name: "fineco-settembre.csv", data: Data(current.utf8)),
                                (name: "esempio-settembre.csv", data: Data(savings.utf8))]

    private func flow(library: Library = PreviewLibrary.library) -> ImportFlow {
        var flow = ImportFlow(library: library)
        flow.open(files: Self.files)
        return flow
    }

    @Test func everyFilesConflictIsListedAndDecidedAlone() throws {
        var flow = flow()
        let conflicts = flow.reviewConflicts(locale: Self.locale)
        #expect(conflicts.map(\.key) == [.valuation(ValuationKey(account: "conto-deposito", date: "2026-09-30")),
                                          .valuation(ValuationKey(account: "conto-fineco", date: "2026-09-30"))])
        let savings = try #require(conflicts.first)
        #expect(savings.incoming == Decimal(string: "17330.5"))
        #expect(savings.existing == Decimal(string: "17365.55"))
        #expect(savings.headline(locale: Self.locale).hasAmounts)
        #expect(conflicts.allSatisfy { !$0.usesFile })
        // Only the files' lines are written; the library's values are kept.
        #expect(flow.planned?.overwritten == 0)

        // The current account's file isn't the one on screen.
        let current = try #require(conflicts.last)
        #expect(flow.batchFile != 0)
        flow.setReviewResolution(usesFile: true, for: current.key)
        #expect(flow.reviewConflicts().map(\.usesFile) == [false, true])
        #expect((flow.planned?.overwritten ?? 0) > 0)
        flow.setReviewResolution(usesFile: false, for: current.key)
        #expect(flow.reviewConflicts().map(\.usesFile) == [false, false])
        #expect(flow.reviewConflicts().last?.resolution == .keep)
    }

    /// Replacing starting estimates on Done is an edit of its own that
    /// undoing the import would leave behind, so Undo import goes.
    @Test func undoIsNoLongerOfferedOnceEstimatesWereReplaced() throws {
        var flow = flow()
        let current = try #require(flow.reviewConflicts().last)
        flow.setReviewResolution(usesFile: true, for: current.key)
        let planned = try #require(flow.planned)
        var receipt = ImportReceipt(fileName: "fineco-settembre.csv", result: planned)
        receipt.backup = Backup(name: "2026-10-15-120000-import", label: "import", created: Date(), files: [])
        #expect(receipt.canUndo)
        receipt.replacedEstimates = true
        #expect(!receipt.canUndo)
    }

    @Test func accountsListEachAccountsMonthsBalanceAndChange() throws {
        var flow = flow()
        let savings = try #require(flow.reviewConflicts().first)
        flow.setReviewResolution(usesFile: true, for: savings.key)
        let accounts = flow.reviewAccounts
        #expect(accounts.map(\.name) == ["Conto deposito", "Conto Fineco"])
        #expect(accounts.map(\.months) == [1, 0])
        #expect(accounts.map(\.kept) == [0, 1])
        #expect(accounts.map(\.isNew) == [false, false])
        #expect(accounts.map(\.balance) == [Decimal(string: "17330.5"), Decimal(string: "4210.55")])
        #expect(accounts.map(\.change) == [Decimal(string: "1768.4"), Decimal(string: "260.15")])
    }

    /// An account money moves to by a saved rule, such as one
    /// `retire import --move` remembers, is listed from the transfers.
    @Test func anAccountMoneyMovesToIsListedFromTransfers() throws {
        var library = PreviewLibrary.library
        library.accounts["tasse"] = Account(id: "tasse", name: "Tax pot", kind: .taxPot, currency: .eur,
                                            opened: "2026-01-01")
        var flow = ImportFlow(library: library)
        flow.open(Data((Self.current + "\n15/09/2026;-6.000,00;Accantonamento tasse").utf8), fileName: "settembre.csv")
        flow.setConstants { $0.account = "conto-fineco" }
        let rule = StatementRule(match: "Accantonamento tasse", statementClass: .transfer, account: "tasse")
        flow.editSession { $0.profile.rules.append(rule) }
        let pot = try #require(flow.reviewAccounts.first { $0.account == "tasse" })
        #expect(pot.isNew)
        #expect(pot.fromTransfers)
        #expect(pot.months == 1)
        #expect(pot.balance == 6000)
        #expect(pot.change == 6000)

        let conflict = try #require(flow.reviewConflicts().first)
        flow.setReviewResolution(usesFile: true, for: conflict.key)
        #expect(flow.planned?.hasChanges == true)
    }

    @Test func theChartsShowTheFirstAccountThatDisagreesOverTheYear() throws {
        let charts = try #require(flow().statementCharts)
        #expect(charts.year == 2026)
        #expect(charts.account == "conto-deposito")
        #expect(charts.months.first?.month == "2026-01")
        #expect(charts.months.last?.month == "2026-09")
        #expect(charts.before.map(\.date) == ["2026-09-30"])
        #expect(!charts.agrees(try #require(charts.before.first)))
    }

    @Test func reviewAsksForAnotherFilesBalanceBeforeItsFirstLine() throws {
        var library = PreviewLibrary.library
        library.months["2026-08"]?.valuations.removeAll { $0.account == "conto-fineco" }
        var flow = flow(library: library)
        let shown = flow.batchFile
        let asked = try #require(flow.reviewOpeningBalances.first)
        #expect(flow.reviewOpeningBalances.count == 1)
        #expect(asked.fileName == "fineco-settembre.csv")
        #expect(asked.isNeeded)
        let blockers = flow.blockers.count
        flow.setStatementOpeningBalance(Decimal(string: "4515.2"), forFile: asked.file)
        #expect(flow.batchFile == shown)
        let given = try #require(flow.reviewOpeningBalances.first)
        #expect(!given.isNeeded)
        #expect(given.balance == Decimal(string: "4515.2"))
        #expect(flow.blockers.count == blockers - 1)
    }

    @Test func doneRemembersHowEachFileIsRead() throws {
        var flow = flow()
        flow.showBatchFile(0)
        let batch = try #require(flow.batch)
        let profiles = batch.rememberedProfiles(in: PreviewLibrary.library)
        let names = Dictionary(uniqueKeysWithValues: batch.files.map { ($0.id, $0.name) })
        let remembered = ImportRemembered.list(profiles, fileNames: names, before: PreviewLibrary.library,
                                               after: PreviewLibrary.library)
        #expect(remembered.map(\.title) == ["How fineco-settembre.csv is read", "How esempio-settembre.csv is read"])
        #expect(remembered.map(\.scope) == ["its bank's next statement", "its bank's next statement"])

        // Saved, they're known: nothing new to remember.
        var library = PreviewLibrary.library
        for remembered in profiles { library.importProfiles[remembered.profile.id] = remembered.profile }
        #expect(ImportRemembered.list([], fileNames: names, before: library, after: library).isEmpty)
        let again = ImportRemembered.list(profiles.map { var profile = $0; profile.isNew = false; return profile },
                                          fileNames: names, before: library, after: library)
        #expect(again.isEmpty)
    }

    @Test func aMoveRuleIsRememberedForEveryMonth() {
        var library = PreviewLibrary.library
        library.accounts["tasse"] = Account(id: "tasse", name: "Tax pot", kind: .taxPot, currency: .eur,
                                            opened: "2026-01-01")
        var profile = ImportProfile(id: "x", name: "X", layout: .statement)
        profile.rules = [StatementRule(match: "Steuer-Rücklage", statementClass: .transfer, account: "tasse"),
                         StatementRule(match: "Notaio Bianchi", statementClass: .oneOff)]
        let remembered = ImportRemembered.list([StatementBatch.RememberedProfile(profile: profile, files: [0],
                                                                                 isNew: false)],
                                               fileNames: [:], before: PreviewLibrary.library, after: library)
        #expect(remembered == [
            ImportRemembered(title: "Steuer-Rücklage moves to Tax pot", scope: "every month"),
            ImportRemembered(title: "Notaio Bianchi is a one-off", scope: "every account"),
        ])
    }

    @Test func aLinesAnswerIsRememberedForItsMonth() {
        var profile = ImportProfile(id: "fineco-movimenti", name: "Fineco", layout: .statement)
        let had = PreviewLibrary.library.importProfiles["fineco-movimenti"]?.answers ?? []
        profile.answers = had + [StatementAnswer(date: "2025-03-14", amount: 18000,
                                                 match: "Bonifico da Notaio Bianchi", statementClass: .oneOff)]
        let remembered = ImportRemembered.list([StatementBatch.RememberedProfile(profile: profile, files: [0],
                                                                                 isNew: false)],
                                               fileNames: [:], before: PreviewLibrary.library,
                                               after: PreviewLibrary.library, locale: Self.locale)
        // The answers the profile had are known already.
        #expect(remembered.map(\.title) == ["Notaio Bianchi was a one-off"])
        #expect(remembered.map(\.scope) == ["Mar 2025"])
    }

    @Test func doneSaysWhatWasSavedThisYear() throws {
        let savings = try #require(ImportSavings(library: PreviewLibrary.library, through: "2026-09-30"))
        #expect(savings.year == 2026)
        #expect(savings.isSoFar)
        #expect(savings.sentence(locale: Self.locale).hasAmounts)
    }

    @Test func doneHasNoBarsForStatements() {
        var flow = flow()
        #expect(flow.showsImportBars)
        flow.finish()
        #expect(!flow.showsImportBars)
    }
}
