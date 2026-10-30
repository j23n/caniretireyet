import Foundation
@testable import Importer
import Model
import Testing
import TestSupport
import Tracker

/// A bank statement's purchases you keep and sales (IMPORT.md, "Purchases
/// and sales"): a large line out asks whether it's spending, and answered
/// as a purchase starts an account; a line in answered as a sale closes one.
/// On a made-up current account's first quarter.
struct StatementPurchaseTests {
    static let today: CalendarDate = "2026-04-12"

    static let csv = """
        Data;Importo;Descrizione
        05/01/2026;-900,00;Affitto gennaio
        12/01/2026;-400,00;Pagamento POS Supermercato Rossi
        27/01/2026;3.000,00;Stipendio ACME
        05/02/2026;-900,00;Affitto febbraio
        12/02/2026;-400,00;Pagamento POS Supermercato Rossi
        20/02/2026;-15.000,00;Bonifico a Autosalone Neri
        27/02/2026;3.000,00;Stipendio ACME
        05/03/2026;-900,00;Affitto marzo
        12/03/2026;-400,00;Pagamento POS Supermercato Rossi
        18/03/2026;12.000,00;Bonifico da Mario Verdi
        27/03/2026;3.000,00;Stipendio ACME
        """

    static func library() -> Library {
        var library = Library(accounts: [
            Account(id: "conto", name: "Conto corrente", kind: .cash, currency: .eur, opened: "2020-01-01"),
            Account(id: "moto", name: "Moto", kind: .belongings, currency: .eur, opened: "2022-05-01"),
            Account(id: "broker", name: "Broker", kind: .brokerage, currency: .eur, opened: "2022-05-01"),
        ])
        library.upsert(Valuation(account: "conto", date: "2025-12-31", balance: 20000))
        library.upsert(Valuation(account: "moto", date: "2025-12-31", balance: 13000))
        return library
    }

    static func session() throws -> ImportSession {
        var session = try ImportSession(data: Data(csv.utf8))
        session.proposeMapping(layout: .statement)
        session.profile.constants.account = "conto"
        return session
    }

    static func line(_ preview: ImportPreview, _ text: String) throws -> StatementLine {
        try #require(preview.statementLines.first { $0.text.hasPrefix(text) })
    }

    static func value(_ preview: ImportPreview, _ account: AccountID, _ date: CalendarDate) throws -> ImportedRecord {
        try #require(preview.records.first { $0.id == .valuation(ValuationKey(account: account, date: date)) })
            .imported
    }

    @Test func aLargeLineOutNeedsAnAnswer() throws {
        let preview = try Self.session().preview(against: Self.library(), today: Self.today)
        let car = try Self.line(preview, "Bonifico a Autosalone Neri")
        #expect(car.statementClass == .spending)
        #expect(car.needsAnswer)
        // Rent is less than a typical month's spending, which leaves the car out.
        #expect(try !Self.line(preview, "Affitto febbraio").needsAnswer)
        #expect(preview.statementLines.filter { $0.amount < 0 && $0.needsAnswer }.count == 1)
    }

    /// The account's months before the file count toward a typical month.
    @Test func theMonthsBeforeTheFileCount() throws {
        var library = Self.library()
        for date: CalendarDate in ["2025-10-31", "2025-11-30", "2025-12-31"] {
            library.upsert(Valuation(account: "conto", date: date, balance: 20000, moneyIn: 20000, moneyOut: 20000))
        }
        let preview = try Self.session().preview(against: library, today: Self.today)
        #expect(try !Self.line(preview, "Bonifico a Autosalone Neri").needsAnswer)
    }

    /// A purchase's line is kept as a suggestion that names the account it
    /// starts, so importing the file again asks for it again.
    @Test func aPurchaseLineStaysASuggestion() throws {
        var session = try Self.session()
        let row = try Self.line(session.preview(against: Self.library(), today: Self.today), "Bonifico a Autosalone")
            .row
        session.setStatementAsset(.purchase(name: "Auto", kind: .belongings), forRow: row)
        let preview = session.preview(against: Self.library(), today: Self.today)
        let car = try #require(preview.lines.first { $0.text.hasPrefix("Bonifico a Autosalone") })
        #expect(car.statementClass == .transfer)
        #expect(car.otherAccount == "auto")
        #expect(!car.isConfirmed)
        // The other lines' classes chosen in the import are confirmed.
        let gift = try Self.line(preview, "Bonifico da Mario Verdi")
        session.setStatementClass(.income, forRow: gift.row)
        let chosen = session.preview(against: Self.library(), today: Self.today)
        #expect(chosen.lines.first { $0.text.hasPrefix("Bonifico da Mario Verdi") }?.isConfirmed == true)
    }

    @Test func aPurchaseStartsAnAccountWorthTheAmount() throws {
        var session = try Self.session()
        let row = try Self.line(session.preview(against: Self.library(), today: Self.today), "Bonifico a Autosalone")
            .row
        session.setStatementAsset(.purchase(name: "Auto", kind: .belongings), forRow: row)
        let preview = session.preview(against: Self.library(), today: Self.today)
        let car = try Self.line(preview, "Bonifico a Autosalone Neri")
        #expect(car.statementClass == .transfer)
        #expect(car.source == .chosen)
        #expect(!car.needsAnswer)
        #expect(car.asset == .purchase(name: "Auto", kind: .belongings))
        #expect(car.assetAccount == "auto")
        let proposal = try #require(preview.newAccounts.first)
        #expect(preview.newAccounts.count == 1)
        #expect(proposal.account == Account(id: "auto", name: "Auto", kind: .belongings, currency: .eur,
                                            opened: "2026-02-19"))
        #expect(proposal.statementRow == row)
        // Worth nothing the day before, then the amount on the line's day.
        #expect(try Self.value(preview, "auto", "2026-02-19").balance == 0)
        let value = try Self.value(preview, "auto", "2026-02-20")
        #expect(value.balance == 15000)
        // What belongings saved is worked out from the balances, not stored.
        #expect(value.saved == nil)
        // Moved, not spent.
        let february = try Self.value(preview, "conto", "2026-02-28")
        #expect(february.moneyOut == 1300)

        let library = preview.apply(to: Self.library()).library
        #expect(library.accounts["auto"]?.opened == "2026-02-19")
        // Pay of 3,000 covers part of it, but it's all saved: 3,000 − 1,300 spent.
        let saved = Valuator(library: library).saved(after: "2026-01-31", through: "2026-02-28")
        #expect(saved.byAccount["auto"] == 15000)
        #expect(saved.byAccount.values.reduce(Decimal(0), +) == 1700)

        // Importing the file again with the same answer finds the account it started.
        let again = session.preview(against: library, today: Self.today)
        #expect(again.newAccounts.isEmpty)
        #expect(again.records.allSatisfy { $0.status == .identical })
    }

    /// A property asks for what it saved, so its purchase stores it.
    @Test func aPropertysPurchaseStoresWhatWasSaved() throws {
        var session = try Self.session()
        let row = try Self.line(session.preview(against: Self.library(), today: Self.today), "Bonifico a Autosalone")
            .row
        session.setStatementAsset(.purchase(name: "Box", kind: .property), forRow: row)
        let preview = session.preview(against: Self.library(), today: Self.today)
        #expect(try Self.value(preview, "box", "2026-02-20").saved == 15000)
        let library = preview.apply(to: Self.library()).library
        #expect(library.valuations(for: "box").map(\.saved) == [nil, 15000])
    }

    @Test func aSaleValuesTheAccountAtNothingAndClosesIt() throws {
        var session = try Self.session()
        let row = try Self.line(session.preview(against: Self.library(), today: Self.today), "Bonifico da Mario")
            .row
        session.setStatementAsset(.sale("moto"), forRow: row)
        let preview = session.preview(against: Self.library(), today: Self.today)
        let sale = try Self.line(preview, "Bonifico da Mario Verdi")
        #expect(sale.statementClass == .transfer)
        #expect(sale.assetAccount == "moto")
        let value = try Self.value(preview, "moto", "2026-03-18")
        #expect(value.balance == 0)
        #expect(value.saved == nil)
        #expect(preview.accountChanges == [AccountChangeProposal(account: "moto", change: .close(on: "2026-03-19"),
                                                                 statementRow: row)])
        #expect(preview.summary.closedAccounts == 1)
        #expect(try Self.value(preview, "conto", "2026-03-31").moneyIn == 3000)

        let library = preview.apply(to: Self.library()).library
        #expect(library.accounts["moto"]?.closed == "2026-03-19")
        // Importing the file again with the same answer finds the same sale.
        let again = session.preview(against: library, today: Self.today)
        #expect(again.records.allSatisfy { $0.status == .identical })
        #expect(again.accountChanges.isEmpty)
        #expect(!again.issues.contains { !$0.isNote })
        // What it sold for comes back into the current account: only the change since its last value is spent.
        let saved = Valuator(library: library).saved(after: "2026-02-28", through: "2026-03-31")
        #expect(saved.byAccount["conto"] == 13700)
        #expect(saved.byAccount.values.reduce(Decimal(0), +) == 700)
    }

    /// A sale is found again whatever the current account's values are: a
    /// value checked in after it, which the line now counts in, changes
    /// nothing.
    @Test func aSaleIsFoundAgainAfterAValueOfTheStatementsAccount() throws {
        var session = try Self.session()
        let row = try Self.line(session.preview(against: Self.library(), today: Self.today), "Bonifico da Mario").row
        session.setStatementAsset(.sale("moto"), forRow: row)
        var library = session.preview(against: Self.library(), today: Self.today).apply(to: Self.library()).library
        #expect(library.accounts["moto"]?.closed == "2026-03-19")
        library.upsert(Valuation(account: "conto", date: "2026-03-20", balance: 18000))
        let again = session.preview(against: library, today: Self.today)
        #expect(try Self.line(again, "Bonifico da Mario").asset == .sale("moto"))
        #expect(try Self.value(again, "moto", "2026-03-18").balance == 0)
        #expect(again.records.filter { $0.imported.key.account == "moto" }.allSatisfy { $0.status == .identical })
        #expect(again.accountChanges.isEmpty)
        #expect(!again.issues.contains { if case .statementAssetLeftOut = $0.kind { true } else { false } })
    }

    /// A line in can sell what a purchase earlier in the same file starts.
    @Test func aSaleCanSellWhatThePurchaseStarts() throws {
        var session = try Self.session()
        let first = session.preview(against: Self.library(), today: Self.today)
        let car = try Self.line(first, "Bonifico a Autosalone Neri").row
        let sale = try Self.line(first, "Bonifico da Mario Verdi").row
        session.setStatementAsset(.purchase(name: "Auto", kind: .belongings), forRow: car)
        session.setStatementAsset(.sale("auto"), forRow: sale)
        let preview = session.preview(against: Self.library(), today: Self.today)
        #expect(try Self.line(preview, "Bonifico da Mario Verdi").assetAccount == "auto")
        #expect(preview.newAccounts.map(\.account.id) == ["auto"])
        #expect(try Self.value(preview, "auto", "2026-02-20").balance == 15000)
        let sold = try Self.value(preview, "auto", "2026-03-18")
        #expect(sold.balance == 0)
        #expect(sold.saved == nil)
        #expect(preview.accountChanges == [AccountChangeProposal(account: "auto", change: .close(on: "2026-03-19"),
                                                                 statementRow: sale)])
        #expect(!preview.issues.contains { !$0.isNote })

        let library = preview.apply(to: Self.library()).library
        #expect(library.accounts["auto"]?.closed == "2026-03-19")
        // Importing the file again with the same answers finds the account and its sale.
        let again = session.preview(against: library, today: Self.today)
        #expect(again.newAccounts.isEmpty)
        #expect(again.accountChanges.isEmpty)
        #expect(again.records.allSatisfy { $0.status == .identical })
        #expect(!again.issues.contains { !$0.isNote })
    }

    /// Bought and sold in one month, the account is worth the amount
    /// between the two days and 0 from the sale, in either order of rows.
    @Test func aPurchaseSoldInTheSameMonth() throws {
        var session = try Self.session()
        let first = session.preview(against: Self.library(), today: Self.today)
        let car = try Self.line(first, "Bonifico a Autosalone Neri").row
        let pay = try #require(first.statementLines.first { $0.text.hasPrefix("Stipendio") && $0.date == "2026-02-27" })
        session.setStatementAsset(.purchase(name: "Auto", kind: .belongings), forRow: car)
        session.setStatementAsset(.sale("auto"), forRow: pay.row)
        let preview = session.preview(against: Self.library(), today: Self.today)
        #expect(try Self.value(preview, "auto", "2026-02-20").balance == 15000)
        let value = try Self.value(preview, "auto", "2026-02-27")
        #expect(value.balance == 0)
        #expect(value.saved == nil)
        #expect(preview.accountChanges.map(\.change) == [.close(on: "2026-02-28")])

        // Newest first, as many banks export, importing again finds the same values.
        let lines = Self.csv.split(separator: "\n")
        let reversed = ([lines[0]] + lines.dropFirst().reversed()).joined(separator: "\n")
        var newestFirst = try ImportSession(data: Data(reversed.utf8))
        newestFirst.proposeMapping(layout: .statement)
        newestFirst.profile.constants.account = "conto"
        let rows = newestFirst.preview(against: Self.library(), today: Self.today).statementLines
        let bought = try #require(rows.first { $0.text.hasPrefix("Bonifico a Autosalone") })
        let paid = try #require(rows.first { $0.text.hasPrefix("Stipendio") && $0.date == "2026-02-27" })
        #expect(paid.row < bought.row)
        newestFirst.setStatementAsset(.purchase(name: "Auto", kind: .belongings), forRow: bought.row)
        newestFirst.setStatementAsset(.sale("auto"), forRow: paid.row)
        let library = newestFirst.preview(against: Self.library(), today: Self.today).apply(to: Self.library()).library
        #expect(library.valuations(for: "auto").map(\.balance) == [0, 15000, 0])
        let again = newestFirst.preview(against: library, today: Self.today)
        #expect(try Self.value(again, "auto", "2026-02-27").balance == 0)
        #expect(again.records.allSatisfy { $0.status == .identical })
        #expect(again.accountChanges.isEmpty)
    }

    /// A sale before the purchase, or of an account no purchase starts, is
    /// left out and names the account.
    @Test func aSaleBeforeThePurchaseIsLeftOut() throws {
        var session = try Self.session()
        let first = session.preview(against: Self.library(), today: Self.today)
        let car = try Self.line(first, "Bonifico a Autosalone Neri").row
        let pay = try #require(first.statementLines.first { $0.text.hasPrefix("Stipendio") && $0.date == "2026-01-27" })
        let sale = try Self.line(first, "Bonifico da Mario Verdi").row
        session.setStatementAsset(.purchase(name: "Auto", kind: .belongings), forRow: car)
        session.setStatementAsset(.sale("auto"), forRow: pay.row)
        session.setStatementAsset(.sale("barca"), forRow: sale)
        let preview = session.preview(against: Self.library(), today: Self.today)
        #expect(preview.issues.contains { $0.kind == .statementAssetLeftOut(row: pay.row, account: "auto") })
        #expect(preview.issues.contains { $0.kind == .statementAssetLeftOut(row: sale, account: "barca") })
        #expect(preview.accountChanges.isEmpty)
        #expect(try Self.value(preview, "auto", "2026-02-20").balance == 15000)
    }

    /// An older account with the purchase's name, such as the car before,
    /// isn't the one it starts.
    @Test func aPurchaseDoesntTakeAnOlderAccountsName() throws {
        var library = Self.library()
        library.accounts["auto"] = Account(id: "auto", name: "Auto", kind: .belongings, currency: .eur,
                                           opened: "2018-03-01", closed: "2025-06-01")
        var session = try Self.session()
        let row = try Self.line(session.preview(against: library, today: Self.today), "Bonifico a Autosalone").row
        session.setStatementAsset(.purchase(name: "Auto", kind: .belongings), forRow: row)
        let preview = session.preview(against: library, today: Self.today)
        #expect(preview.newAccounts.map(\.account.id) == ["auto-2"])
        #expect(try Self.line(preview, "Bonifico a Autosalone").assetAccount == "auto-2")
    }

    /// A purchase and a sale don't need the file's values: on the first
    /// statement of an account without values, with no balances and no
    /// opening balance, so the file makes no values at all, both are
    /// recorded on their days.
    @Test func aPurchaseAndASaleNeedNoValues() throws {
        var library = Self.library()
        library.months = [:]
        var session = try Self.session()
        let first = session.preview(against: library, today: Self.today)
        #expect(first.issues.contains { $0.kind == .needsOpeningBalance("conto") })
        let car = try Self.line(first, "Bonifico a Autosalone Neri").row
        let sale = try Self.line(first, "Bonifico da Mario Verdi").row
        session.setStatementAsset(.purchase(name: "Auto", kind: .belongings), forRow: car)
        session.setStatementAsset(.sale("auto"), forRow: sale)
        let preview = session.preview(against: library, today: Self.today)
        #expect(preview.newAccounts.map(\.account.id) == ["auto"])
        #expect(try Self.value(preview, "auto", "2026-02-20").balance == 15000)
        #expect(try Self.value(preview, "auto", "2026-03-18").balance == 0)
        #expect(preview.accountChanges.map(\.change) == [.close(on: "2026-03-19")])
        #expect(!preview.issues.contains { if case .statementAssetLeftOut = $0.kind { true } else { false } })
    }

    @Test func anAnswerThatDoesntFitIsLeftOut() throws {
        var session = try Self.session()
        let first = session.preview(against: Self.library(), today: Self.today)
        let sale = try Self.line(first, "Bonifico da Mario Verdi").row
        let car = try Self.line(first, "Bonifico a Autosalone Neri").row
        let rent = try Self.line(first, "Affitto marzo").row
        session.setStatementAsset(.purchase(name: "Quadro", kind: .belongings), forRow: sale)
        session.setStatementAsset(.purchase(name: "Auto", kind: .cash), forRow: car)
        session.setStatementAsset(.sale("broker"), forRow: rent)
        let preview = session.preview(against: Self.library(), today: Self.today)
        #expect(try Self.line(preview, "Bonifico da Mario Verdi").statementClass == .spending)
        #expect(try Self.line(preview, "Bonifico a Autosalone Neri").statementClass == .spending)
        #expect(try Self.line(preview, "Affitto marzo").asset == nil)
        #expect(try Self.line(preview, "Affitto marzo").assetLeftOut == .doesntFit)
        // A sale of money out is left out for its sign, not for the account.
        #expect(preview.issues.contains { $0.kind == .statementAssetLeftOut(row: rent, account: nil) })
        #expect(preview.newAccounts.isEmpty)
        #expect(preview.issues.filter {
            if case .statementAssetLeftOut = $0.kind { true } else { false }
        }.count == 3)

        // A sale of an account that can't be sold names it.
        var selling = try Self.session()
        selling.setStatementAsset(.sale("broker"), forRow: sale)
        let broker = selling.preview(against: Self.library(), today: Self.today)
        #expect(broker.issues.contains { $0.kind == .statementAssetLeftOut(row: sale, account: "broker") })
        #expect(broker.accountChanges.isEmpty)
    }

    @Test func aClassAndAnAnswerReplaceEachOther() throws {
        var session = try Self.session()
        session.setStatementClass(.spending, forRow: 7)
        session.setStatementAsset(.purchase(name: "Auto", kind: .belongings), forRow: 7)
        #expect(session.statementLineClasses[7] == nil)
        session.setStatementClass(.spending, forRow: 7)
        #expect(session.statementAssets[7] == nil)
    }
}
