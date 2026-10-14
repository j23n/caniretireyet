import Foundation
@testable import Importer
import Model
import Testing
import TestSupport

/// Several statements imported at once (IMPORT.md, "Several statements at
/// once"): each file's account found, transfers between them paired, and
/// files of one account applied in order. Made-up accounts and files.
struct StatementBatchTests {
    static let today: CalendarDate = "2026-04-12"

    static func library() -> Library {
        var library = Library(accounts: [
            Account(id: "conto", name: "Conto corrente", kind: .cash, currency: .eur, opened: "2020-01-01",
                    institution: "Fineco"),
            Account(id: "risparmio", name: "Risparmio", kind: .savings, currency: .eur, opened: "2020-01-01",
                    institution: "Banca Esempio"),
        ])
        library.upsert(Valuation(account: "conto", date: "2025-12-31", balance: 5000))
        library.upsert(Valuation(account: "risparmio", date: "2025-12-31", balance: 10000))
        return library
    }

    /// The current account's January, without a balance column; its bank is in the file's name.
    static let current = """
        Data;Importo;Descrizione
        05/01/2026;-900,00;Affitto gennaio
        15/01/2026;-1.000,00;Bonifico a mio nome
        27/01/2026;3.000,00;Stipendio ACME
        """

    /// The savings account's January, with a balance column that follows on from its value.
    static let savings = """
        Data;Importo;Descrizione;Saldo
        16/01/2026;1.000,00;Bonifico da Mario Rossi;11.000,00
        31/01/2026;2,50;Interessi;11.002,50
        """

    static func batch(_ files: [(String, String)], library: Library = library()) -> StatementBatch {
        StatementBatch(files: files.map { (name: $0.0, data: Data($0.1.utf8)) }, library: library, today: today)
    }

    static func lines(_ batch: StatementBatch, _ file: Int) -> [StatementLine] {
        batch.files[file].session.preview(against: library(), today: today).statementLines
    }

    @Test func eachFilesAccountIsFound() {
        let batch = Self.batch([("fineco-gennaio.csv", Self.current), ("export.csv", Self.savings)])
        #expect(batch.files.map(\.account) == ["conto", "risparmio"])
        #expect(batch.files.map(\.accountSource) == [.named, .balance("2025-12-31")])
        // Nothing says which account a file is: it waits for a choice.
        let unknown = Self.batch([("export.csv", Self.current)])
        #expect(unknown.files.first?.account == nil)
        #expect(unknown.files.first?.accountSource == nil)
    }

    @Test func eachFileOfACheckInCoversThroughItsDate() {
        let batch = StatementBatch(files: [(name: "fineco-gennaio.csv", data: Data(Self.current.utf8))],
                                   library: Self.library(), checkIn: "2026-01-29", today: Self.today)
        #expect(batch.files.first?.session.statementCheckIn == "2026-01-29")
        let preview = batch.files[0].session.preview(against: Self.library(), today: Self.today)
        #expect(preview.issues.contains { $0.kind == .statementPeriod(from: "2026-01-01", through: "2026-01-29") })
    }

    /// In a month that isn't over the file makes no value yet, and its
    /// balance still says which account it follows on from. An account's
    /// own word names it: "Conto Arancio" is "arancio".
    @Test func anUnfinishedMonthsFileFollowsOnByItsBalance() {
        var library = Self.library()
        library.accounts["arancio"] = Account(id: "arancio", name: "Conto Arancio", kind: .cash, currency: .eur,
                                              opened: "2020-01-01")
        for (id, balance) in [("conto", 5000), ("risparmio", 10000), ("arancio", 300)] as [(AccountID, Decimal)] {
            library.upsert(Valuation(account: id, date: "2026-03-31", balance: balance))
        }
        let april = """
            Data;Importo;Descrizione;Saldo
            02/04/2026;-200,00;Bonifico a Mario Rossi;9.800,00
            02/04/2026;50,00;Rimborso;9.850,00
            """
        let batch = Self.batch([("export.csv", april), ("arancio.csv", Self.current)], library: library)
        #expect(batch.files.map(\.account) == ["risparmio", "arancio"])
        #expect(batch.files.first?.accountSource == .balance("2026-03-31"))
    }

    /// A saved profile's account is the file's, while a statement can be
    /// of it. A closed account's file waits for a choice.
    @Test func aSavedProfileNamesItsAccount() throws {
        var session = try ImportSession(data: Data(Self.current.utf8))
        session.proposeMapping(layout: .statement)
        session.profile.constants.account = "conto"
        var library = Self.library()
        library.importProfiles["fineco"] = session.makeProfile(id: "fineco", name: "Fineco", library: library)
        let batch = Self.batch([("export.csv", Self.current)], library: library)
        #expect(batch.files.first?.account == "conto")
        #expect(batch.files.first?.accountSource == .profile)

        library.accounts["conto"]?.closed = "2026-01-31"
        let closed = Self.batch([("export.csv", Self.current)], library: library)
        #expect(closed.files.first?.account == nil)
        #expect(closed.files.first?.accountSource == nil)
        #expect(closed.previews(against: library, today: Self.today).isEmpty)
    }

    /// Accounts in different currencies don't pair: a transfer between
    /// them moves different amounts.
    @Test func aTransferPairsOnlyInOneCurrency() throws {
        var library = Self.library()
        library.accounts["risparmio"]?.currency = .usd
        let batch = Self.batch([("fineco-gennaio.csv", Self.current), ("export.csv", Self.savings)],
                               library: library)
        let lines = batch.files[0].session.preview(against: library, today: Self.today).statementLines
        #expect(lines.first { $0.amount == -1000 }?.source == .sign)
    }

    @Test func aTransferBetweenTheFilesIsPaired() throws {
        let batch = Self.batch([("fineco-gennaio.csv", Self.current), ("export.csv", Self.savings)])
        let out = try #require(Self.lines(batch, 0).first { $0.amount == -1000 })
        #expect(out.statementClass == .transfer)
        #expect(out.source == .paired("risparmio"))
        let incoming = try #require(Self.lines(batch, 1).first { $0.amount == 1000 })
        #expect(incoming.statementClass == .transfer)
        #expect(incoming.source == .paired("conto"))
        // Rent has no line the other way.
        #expect(Self.lines(batch, 0).first?.source == .sign)

        let previews = batch.previews(against: Self.library(), today: Self.today)
        #expect(previews.map(\.file) == [0, 1])
        let result = ImportPreview.apply(previews.map(\.preview), to: Self.library())
        let conto = try #require(result.library.valuations(for: "conto").last)
        #expect(conto.date == "2026-01-31")
        #expect(conto.moneyIn == 3000)
        #expect(conto.moneyOut == 900)
        let risparmio = try #require(result.library.valuations(for: "risparmio").last)
        #expect(risparmio.balance == Decimal(string: "11002.5"))
        #expect(risparmio.moneyIn == 0)
        #expect(result.added == 2)
    }

    /// A rule made for every file classifies each file's lines, and a line
    /// a rule classifies isn't paired.
    @Test func everyFileIsEditedAtOnce() throws {
        var batch = Self.batch([("fineco-gennaio.csv", Self.current), ("export.csv", Self.savings)])
        var edited: [Int] = []
        batch.editSessions(library: Self.library(), today: Self.today) { id, session in
            edited.append(id)
            session.setStatementRule(.spending, for: "Bonifico")
        }
        #expect(edited == [0, 1])
        #expect(batch.files.map { $0.session.profile.rules.map(\.match) } == [["Bonifico"], ["Bonifico"]])
        let out = try #require(Self.lines(batch, 0).first { $0.amount == -1000 })
        #expect(out.source == .rule("Bonifico"))
        let incoming = try #require(Self.lines(batch, 1).first { $0.amount == 1000 })
        #expect(incoming.source == .rule("Bonifico"))
    }

    @Test func aChosenAccountPairsAgain() throws {
        var batch = Self.batch([("export.csv", Self.current), ("export (2).csv", Self.savings)])
        #expect(batch.files[0].account == nil)
        #expect(Self.lines(batch, 1).first?.source != .paired("conto"))
        batch.setAccount("conto", forFile: 0, library: Self.library(), today: Self.today)
        #expect(batch.files[0].accountSource == .chosen)
        #expect(Self.lines(batch, 1).first?.source == .paired("conto"))
    }

    /// February's file follows on from January's, applied before it.
    @Test func filesOfOneAccountFollowOnInOrder() throws {
        let february = """
            Data;Importo;Descrizione
            05/02/2026;-900,00;Affitto febbraio
            27/02/2026;3.000,00;Stipendio ACME
            """
        let april = """
            Data;Importo;Descrizione
            05/04/2026;-900,00;Affitto aprile
            """
        let batch = Self.batch([("fineco-febbraio.csv", february), ("fineco-gennaio.csv", Self.current)])
        let previews = batch.previews(against: Self.library(), today: Self.today)
        #expect(previews.map(\.file) == [1, 0])
        let result = ImportPreview.apply(previews.map(\.preview), to: Self.library())
        let values = result.library.valuations(for: "conto")
        #expect(values.map(\.date) == ["2025-12-31", "2026-01-31", "2026-02-28"])
        #expect(values.last?.moneyOut == 900)
        #expect(values.last?.balance == 8200)
        #expect(StatementBatch.gaps(in: previews, batch: batch).isEmpty)

        let gap = Self.batch([("fineco-gennaio.csv", Self.current), ("fineco-aprile.csv", april)])
        let gaps = StatementBatch.gaps(in: gap.previews(against: Self.library(), today: Self.today), batch: gap)
        #expect(gaps == [StatementGap(account: "conto", before: 0, after: 1, from: "2026-02-01", through: "2026-03-31",
                                      isOverlap: false)])
        let twice = Self.batch([("fineco-gennaio.csv", Self.current), ("fineco-copia.csv", Self.current)])
        let overlaps = StatementBatch.gaps(in: twice.previews(against: Self.library(), today: Self.today),
                                           batch: twice)
        #expect(overlaps.map(\.isOverlap) == [true])
    }

    @Test func aFileThatCantBeReadIsSaidSo() {
        let batch = Self.batch([("empty.csv", ""), ("fineco-gennaio.csv", Self.current)])
        #expect(batch.unreadable.map(\.name) == ["empty.csv"])
        #expect(batch.files.map(\.id) == [1])
    }

    /// Files added later keep the ones read before as they are, and pair
    /// with them.
    @Test func addedFilesFollowOnAndPair() throws {
        var batch = Self.batch([("export.csv", Self.current)])
        batch.setAccount("conto", forFile: 0, library: Self.library(), today: Self.today)
        batch.add(files: [(name: "empty.csv", data: Data()), (name: "export (2).csv", data: Data(Self.savings.utf8))],
                  library: Self.library(), today: Self.today)
        #expect(batch.files.map(\.id) == [0, 2])
        #expect(batch.files.map(\.account) == ["conto", "risparmio"])
        #expect(batch.files[0].accountSource == .chosen)
        #expect(Self.lines(batch, 0).first { $0.amount == -1000 }?.source == .paired("risparmio"))

        batch.remove(file: 2, library: Self.library(), today: Self.today)
        #expect(batch.files.map(\.id) == [0])
        #expect(Self.lines(batch, 0).first { $0.amount == -1000 }?.source == .sign)
    }

    @Test func aFileSaysWhatItCoversBeforeItHasAnAccount() throws {
        let files = Self.batch([("export.csv", Self.current), ("export (2).csv", Self.savings)]).files
        let current = try #require(files[0].session.statementSummary(today: Self.today))
        #expect(current.lines == 3)
        #expect(current.first == "2026-01-05")
        #expect(current.last == "2026-01-27")
        #expect(current.from == "2026-01-01")
        #expect(current.through == "2026-01-31")
        #expect(!current.hasBalance)
        #expect(!current.addsUp)
        let savings = try #require(files[1].session.statementSummary(today: Self.today))
        #expect(savings.addsUp)
        #expect(savings.closingBalance == Decimal(string: "11002.5"))
    }

    // MARK: Sales across files

    /// A purchase in one account's statement and its sale in another's,
    /// whichever account's name comes first: the sale's file is applied
    /// after the purchase's and records the sale on its day, and importing
    /// them again finds the same values.
    @Test(arguments: [false, true])
    func aSaleInAnotherFileSellsThePurchase(boughtFromSavings: Bool) throws {
        let current = """
            Data;Importo;Descrizione
            05/01/2026;-900,00;Affitto gennaio
            20/01/2026;\(boughtFromSavings ? "3.000,00;Bonifico da Mario Verdi" : "-4.000,00;Bonifico a Autosalone Neri")
            27/01/2026;3.000,00;Stipendio ACME
            """
        let savings = """
            Data;Importo;Descrizione;Saldo
            16/01/2026;1.000,00;Bonifico da Mario Rossi;11.000,00
            \(boughtFromSavings ? "18/01/2026;-4.000,00;Bonifico a Autosalone Neri;7.000,00"
                                 : "25/01/2026;3.000,00;Bonifico da Mario Verdi;14.000,00")
            31/01/2026;2,50;Interessi;\(boughtFromSavings ? "7.002,50" : "14.002,50")
            """
        var batch = Self.batch([("fineco-gennaio.csv", current), ("export.csv", savings)])
        let library = Self.library()
        let purchaseFile = boughtFromSavings ? 1 : 0
        let saleFile = 1 - purchaseFile
        let purchaseRow = try #require(Self.lines(batch, purchaseFile).first { $0.text.hasPrefix("Bonifico a Auto") }).row
        let saleLine = try #require(Self.lines(batch, saleFile).first { $0.text.hasPrefix("Bonifico da Mario V") })
        batch.editSession(ofFile: purchaseFile, library: library, today: Self.today) {
            $0.setStatementAsset(.purchase(name: "Auto", kind: .belongings), forRow: purchaseRow)
        }
        batch.editSession(ofFile: saleFile, library: library, today: Self.today) {
            $0.setStatementAsset(.sale("auto"), forRow: saleLine.row)
        }
        #expect(batch.order(against: library, today: Self.today) == [purchaseFile, saleFile])
        let previews = batch.previews(against: library, today: Self.today)
        let sold = try #require(previews.first { $0.file == saleFile }?.preview)
        let sale = try #require(sold.statementLines.first { $0.row == saleLine.row })
        #expect(sale.asset == .sale("auto"))
        #expect(sale.statementClass == .transfer)
        let value = try #require(sold.records.first {
            $0.id == .valuation(ValuationKey(account: "auto", date: saleLine.date))
        }).imported
        #expect(value.balance == 0)
        #expect(value.flow == nil)
        #expect(sold.accountChanges == [AccountChangeProposal(account: "auto",
                                                              change: .close(on: saleLine.date.adding(days: 1)),
                                                              statementRow: saleLine.row)])
        #expect(!previews.contains { $0.preview.issues.contains { !$0.isNote } })

        let imported = ImportPreview.apply(previews.map(\.preview), to: library).library
        #expect(imported.accounts["auto"]?.closed == saleLine.date.adding(days: 1))
        let again = batch.previews(against: imported, today: Self.today)
        #expect(again.allSatisfy { $0.preview.records.allSatisfy { $0.status == .identical } })
        #expect(again.allSatisfy { $0.preview.accountChanges.isEmpty && $0.preview.newAccounts.isEmpty })
        #expect(!again.contains { $0.preview.issues.contains { !$0.isNote } })
    }

    /// Two fresh accounts without values, whose statements have no balances
    /// and no opening balance, so neither file makes values: a purchase in
    /// one and its sale months later in the other are still recorded on
    /// their days, and an answered line is never paired as a transfer.
    @Test(arguments: [false, true])
    func aPurchaseAndASaleAcrossFilesNeedNoValues(boughtFromSavings: Bool) throws {
        let library = Library(accounts: [
            Account(id: "conto", name: "Conto corrente", kind: .cash, currency: .eur, opened: "2024-01-01",
                    institution: "Fineco"),
            Account(id: "risparmio", name: "Risparmio", kind: .savings, currency: .eur, opened: "2024-01-01",
                    institution: "Banca Esempio"),
        ])
        let purchase = "20/12/2024;-4.000,00;Bonifico a Autosalone Neri"
        let sale = "10/09/2025;3.000,00;Bonifico da Mario Verdi"
        // A payment of the sale's amount out of the other account, within days of it, isn't its transfer.
        let current = """
            Data;Importo;Descrizione
            05/12/2024;-900,00;Affitto dicembre
            \(boughtFromSavings ? sale : purchase)
            12/09/2025;-3.000,00;Bonifico a mio nome
            27/09/2025;3.000,00;Stipendio ACME
            """
        let savings = """
            Data;Importo;Descrizione
            16/12/2024;1.000,00;Bonifico da Mario Rossi
            \(boughtFromSavings ? purchase : sale)
            12/09/2025;-3.000,00;Bonifico a mio nome
            30/09/2025;2,50;Interessi
            """
        var batch = Self.batch([("fineco.csv", current), ("export.csv", savings)], library: library)
        batch.setAccount("risparmio", forFile: 1, library: library, today: Self.today)
        let purchaseFile = boughtFromSavings ? 1 : 0
        let saleFile = 1 - purchaseFile
        func lines(_ file: Int) -> [StatementLine] {
            batch.files[file].session.preview(against: library, today: Self.today).statementLines
        }
        let purchaseRow = try #require(lines(purchaseFile).first { $0.text.hasPrefix("Bonifico a Auto") }).row
        let saleRow = try #require(lines(saleFile).first { $0.text.hasPrefix("Bonifico da Mario V") }).row
        batch.editSession(ofFile: purchaseFile, library: library, today: Self.today) {
            $0.setStatementAsset(.purchase(name: "Auto", kind: .belongings), forRow: purchaseRow)
        }
        batch.editSession(ofFile: saleFile, library: library, today: Self.today) {
            $0.setStatementAsset(.sale("auto"), forRow: saleRow)
        }
        let previews = batch.previews(against: library, today: Self.today)
        for (file, preview) in previews {
            let account = try #require(batch.files.first { $0.id == file }?.account)
            #expect(preview.issues.contains { $0.kind == .needsOpeningBalance(account) })
        }
        #expect(!previews.contains { $0.preview.issues.contains {
            if case .statementAssetLeftOut = $0.kind { true } else { false }
        } })
        let imported = ImportPreview.apply(previews.map(\.preview), to: library).library
        #expect(imported.valuations(for: "auto").map { "\($0.date) \($0.balance ?? -1)" }
            == ["2024-12-19 0", "2024-12-20 4000", "2025-09-10 0"])
        #expect(imported.accounts["auto"]?.closed == "2025-09-11")
        #expect(batch.files.allSatisfy { $0.session.statementPairs.isEmpty })
    }
}
