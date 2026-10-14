import Foundation
import Importer
import Model
import Testing
@testable import CanIRetireYet

/// Bank statements' Review and Done (UI.md, "Import"): every file
/// together, the values they disagree with, the accounts they change, and
/// what Done says, on made-up September statements of the example
/// library's current and savings accounts.
struct ImportReviewTests {
    private static let locale = Locale(identifier: "en_GB")
    private static let today: CalendarDate = "2026-10-14"

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

    @Test func theSubtitleCountsWhatTheImportChanges() throws {
        var flow = flow()
        // Both September values are check-ins the files disagree with, kept until told otherwise.
        #expect(flow.reviewSubtitle(locale: Self.locale)
            == "Nothing changes yet, Sep 2026. Nothing is saved until you import.")
        for conflict in flow.reviewConflicts() {
            flow.setReviewResolution(usesFile: true, for: conflict.key)
        }
        #expect(flow.reviewSubtitle(locale: Self.locale)
            == "1 month for 2 accounts, Sep 2026. Nothing is saved until you import.")
        #expect(flow.reviewSubtitle(compact: true, locale: Self.locale)
            == "1 month for 2 accounts. Nothing is saved until you import.")
    }

    @Test func everyFilesConflictIsListedAndDecidedAlone() throws {
        var flow = flow()
        let conflicts = flow.reviewConflicts(locale: Self.locale)
        #expect(conflicts.map(\.title) == ["Conto deposito, 30 Sep 2026", "Conto Fineco, 30 Sep 2026"])
        let savings = try #require(conflicts.first)
        #expect(savings.headline(locale: Self.locale).text
            == "Conto deposito, 30 Sep 2026: the file says €17,330.50, your check-in says €17,365.55")
        #expect(savings.detail(locale: Self.locale)?.text == "Your check-in is €35.05 higher.")
        #expect(savings.compactSentence(locale: Self.locale).text
            == "The file says €17,330.50. Your check-in says €17,365.55.")
        #expect(savings.headline(locale: Self.locale).hasAmounts)
        #expect(conflicts.allSatisfy { !$0.usesFile })
        #expect(flow.planned?.hasChanges == false)

        // The current account's file isn't the one on screen.
        let current = try #require(conflicts.last)
        #expect(flow.batchFile != 0)
        flow.setReviewResolution(usesFile: true, for: current.key)
        #expect(flow.reviewConflicts().map(\.usesFile) == [false, true])
        #expect(flow.planned?.hasChanges == true)
        flow.setReviewResolution(usesFile: false, for: current.key)
        #expect(flow.reviewConflicts().map(\.usesFile) == [false, false])
        #expect(flow.reviewConflicts().last?.resolution == .keep)
    }

    @Test func aConflictSaysWhenEveryOtherMonthAgrees() throws {
        let conflict = ImportReviewConflict(
            key: .valuation(ValuationKey(account: "conto-fineco", date: "2026-09-30")),
            title: "Conto Fineco, 30 Sep 2026", incoming: 8420, existing: 8500, incomingText: "", existingText: "",
            currency: .eur, existingIsImported: false, othersAgree: true, resolution: .ask)
        #expect(conflict.detail(locale: Self.locale)?.text
            == "Your check-in is €80.00 higher. Every other month agrees with what you entered.")
        var imported = conflict
        imported.existingIsImported = true
        imported.existing = 8400
        #expect(imported.headline(locale: Self.locale).text
            == "Conto Fineco, 30 Sep 2026: the file says €8,420.00, an earlier import says €8,400.00")
        #expect(imported.detail(locale: Self.locale)?.text
            == "The earlier import is €20.00 lower. Every other month agrees with the library.")
    }

    @Test func accountsListEachAccountsMonthsBalanceAndChange() throws {
        var flow = flow()
        let savings = try #require(flow.reviewConflicts().first)
        flow.setReviewResolution(usesFile: true, for: savings.key)
        let accounts = flow.reviewAccounts
        #expect(accounts.map(\.name) == ["Conto deposito", "Conto Fineco"])
        #expect(accounts.map(\.monthsText) == ["1", "0 · 1 kept as yours"])
        #expect(accounts.map(\.isNew) == [false, false])
        #expect(accounts.map(\.balance) == [Decimal(string: "17330.5"), Decimal(string: "4210.55")])
        #expect(accounts.map(\.change) == [Decimal(string: "1768.4"), Decimal(string: "260.15")])
        #expect(flow.reviewBalanceHeader(today: Self.today, locale: Self.locale) == "Balance, 30 Sep")
        #expect(flow.reviewAccountsHeader(today: Self.today, locale: Self.locale) == "Accounts on 30 Sep")
        #expect(flow.reviewSinceHeader(locale: Self.locale) == "Since Jan 2026")
    }

    @Test func anAccountMoneyMovesToIsListedFromTransfers() throws {
        var library = PreviewLibrary.library
        library.accounts["tasse"] = Account(id: "tasse", name: "Tax pot", kind: .taxPot, currency: .eur,
                                            opened: "2026-01-01")
        var flow = ImportFlow(library: library)
        flow.open(Data((Self.current + "\n15/09/2026;-6.000,00;Accantonamento tasse").utf8), fileName: "settembre.csv")
        flow.setConstants { $0.account = "conto-fineco" }
        let question = try #require(flow.statementQuestions.first)
        flow.setStatementAsset(.moved("tasse"), forRow: question.row)
        let pot = try #require(flow.reviewAccounts.first { $0.account == "tasse" })
        #expect(pot.isNew)
        #expect(pot.fromTransfers)
        #expect(pot.monthsText == "1 · from transfers")
        #expect(pot.balance == 6000)
        #expect(pot.change == 6000)

        let conflict = try #require(flow.reviewConflicts().first)
        flow.setReviewResolution(usesFile: true, for: conflict.key)
        let result = try #require(flow.planned)
        #expect(ImportFlow.importedTitle(result, into: library) == "Imported 1 month for 2 accounts")
    }

    @Test func theChartsShowTheFirstAccountThatDisagreesOverTheYear() throws {
        let charts = try #require(flow().statementCharts)
        #expect(charts.year == 2026)
        #expect(charts.moneyTitle == "Came in and spent, 2026")
        #expect(charts.account == "conto-deposito")
        #expect(charts.balanceTitle == "Conto deposito, balance")
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
        #expect(asked.explanation.hasPrefix("fineco-settembre.csv has no balance column"))
        #expect(flow.blockers.contains("Give the balance before the first line of fineco-settembre.csv."))
        flow.setStatementOpeningBalance(Decimal(string: "4515.2"), forFile: asked.file)
        #expect(flow.batchFile == shown)
        let given = try #require(flow.reviewOpeningBalances.first)
        #expect(!given.isNeeded)
        #expect(given.balance == Decimal(string: "4515.2"))
        #expect(!flow.blockers.contains { $0.contains("balance before") })
    }

    @Test func doneRemembersHowEachFileIsReadAndTheRulesMade() throws {
        var flow = flow()
        flow.showBatchFile(0)
        flow.setStatementRule(.income, for: "Stipendio")
        let batch = try #require(flow.batch)
        let profiles = batch.rememberedProfiles(in: PreviewLibrary.library)
        let names = Dictionary(uniqueKeysWithValues: batch.files.map { ($0.id, $0.name) })
        let remembered = ImportRemembered.list(profiles, fileNames: names, before: PreviewLibrary.library,
                                               after: PreviewLibrary.library)
        #expect(remembered.map(\.title) == ["How fineco-settembre.csv is read", "How esempio-settembre.csv is read",
                                            "Stipendio is income"])
        #expect(remembered.map(\.scope) == ["its bank's next statement", "its bank's next statement", "every account"])

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
        let text = savings.sentence(locale: Self.locale).text
        #expect(text.hasPrefix("In 2026 so far you saved €"))
        #expect(text.contains(" that came in after tax: a savings rate of "))
        #expect(savings.sentence(locale: Self.locale).hasAmounts)
        var spentMore = savings
        spentMore.saved = -100
        spentMore.cameIn = 1000
        spentMore.isSoFar = false
        #expect(spentMore.sentence(locale: Self.locale).text
            == "In 2026 you spent €100 more than the €1,000 that came in after tax.")
    }

    @Test func doneHasNoBarsForStatements() {
        var flow = flow()
        #expect(flow.showsImportBars)
        flow.finish()
        #expect(!flow.showsImportBars)
    }
}
