import Foundation
@testable import Importer
import Model
import Testing
import TestSupport

/// The statement layout: a bank statement of one cash or savings account,
/// its lines classified into money in and out (IMPORT.md, "Bank
/// statements"), with the made-up exports in `Samples/statements/`.
struct StatementImportTests {
    static let today: CalendarDate = "2026-04-12"

    /// A current account with a value on 31 January, a savings account, a
    /// broker that records trades, and a credit card.
    static func library(deposit: Bool = false, valueOn anchor: CalendarDate = "2026-01-31") -> Library {
        var library = Library(accounts: [
            Account(id: "conto", name: "Conto corrente", kind: .cash, currency: .eur, opened: "2020-01-01",
                    institution: "Banca Esempio"),
            Account(id: "deposito", name: "Conto deposito", kind: .savings, currency: .eur, opened: "2020-01-01"),
            Account(id: "esempio-sim", name: "Esempio SIM", kind: .brokerage, currency: .eur, opened: "2021-01-01"),
            Account(id: "visa", name: "Visa Oro", kind: .creditCard, currency: .eur, opened: "2021-01-01"),
        ])
        library.upsert(Valuation(account: "conto", date: anchor, balance: d("5210.85")))
        if deposit {
            library.upsert(Trade(account: "esempio-sim", date: "2026-02-06", type: .deposit, amount: d("500")))
        }
        return library
    }

    static func session(_ name: String, account: AccountID) throws -> ImportSession {
        var session = try Samples.session("statements/\(name)")
        session.profile.constants.account = account
        return session
    }

    static func line(_ preview: ImportPreview, row: Int) throws -> StatementLine {
        try #require(preview.statementLines.first { $0.row == row })
    }

    // MARK: - Detecting

    @Test func statementsAreDetected() throws {
        for name in ["italian-bank.csv", "english-bank.csv"] {
            let session = try Samples.session("statements/\(name)")
            #expect(session.looksLikeStatement, "\(name)")
            #expect(session.profile.layout == .statement, "\(name)")
        }
        for name in ["italian-excel-1252.csv", "us-export.csv", "numbers-export.csv", "titles-totals-utf16.tsv",
                     "month-only.csv", "excel-serial.csv", "long-format.csv", "positions.csv",
                     "positive-debts.csv", "trades/directa.csv", "trades/fineco.csv", "trades/degiro.csv",
                     "trades/ibkr.csv"] {
            let session = try Samples.session(name)
            #expect(!session.looksLikeStatement, "\(name)")
            #expect(session.profile.layout != .statement, "\(name)")
        }
        // A long file whose debts are negative names accounts, not who was paid.
        let long = """
            Date,Account name,Amount,Currency
            2026-01-31,Conto corrente,5210.85,EUR
            2026-01-31,Mutuo casa,-120000.00,EUR
            """
        #expect(try !ImportSession(data: Data(long.utf8)).looksLikeStatement)
        let payee = """
            Date,Payee Name,Amount
            2026-02-02,Supermercato Rossi,-45.90
            2026-02-10,ACME SRL,2800.00
            """
        #expect(try ImportSession(data: Data(payee.utf8)).looksLikeStatement)
    }

    @Test func columnsAreProposedByTheirHeaders() throws {
        let italian = try Samples.session("statements/italian-bank.csv")
        let fields = Dictionary(uniqueKeysWithValues: italian.profile.columns.map { ($0.header ?? "", $0.field) })
        #expect(fields == ["Data operazione": .date, "Data valuta": .ignore, "Entrate": .credit, "Uscite": .debit,
                           "Descrizione": .description])
        let english = try Samples.session("statements/english-bank.csv")
        #expect(english.profile.columns.map(\.field) == [.date, .description, .amount, .balance])
    }

    @Test func germanHeadersAreKnown() throws {
        let csv = """
            Buchungstag;Auftraggeber / Empfänger;Verwendungszweck;Soll;Haben;Saldo
            02.03.2026;Supermarkt;Kartenzahlung;45,90;;1.200,00
            05.03.2026;ACME GmbH;Gehalt März;;3.100,00;4.300,00
            """
        let session = try ImportSession(data: Data(csv.utf8))
        #expect(session.profile.layout == .statement)
        #expect(session.profile.columns.map(\.field) == [.date, .counterparty, .description, .debit, .credit,
                                                         .balance])
    }

    // MARK: - Classifying

    @Test func linesAreClassifiedFromTheSurestSource() throws {
        let session = try Self.session("italian-bank.csv", account: "conto")
        let library = Self.library(deposit: true)
        let preview = session.preview(against: library, today: Self.today)
        #expect(preview.issues.filter { !$0.isNote }.isEmpty, "\(preview.issues)")
        #expect(preview.statementLines.count == 11)
        // The file lists the newest first; the lines are in date order.
        #expect(preview.statementLines.map(\.date) == preview.statementLines.map(\.date).sorted())
        let deposit = try Self.line(preview, row: 14)
        #expect(deposit.amount == -500)
        #expect(deposit.statementClass == .transfer)
        #expect(deposit.source == .trade(library.trades(for: "esempio-sim")[0].key))
        #expect(try Self.line(preview, row: 13).statementClass == .income)
        #expect(try Self.line(preview, row: 13).source == .words)
        #expect(try Self.line(preview, row: 10).statementClass == .transfer)
        #expect(try Self.line(preview, row: 10).source == .words)
        #expect(try Self.line(preview, row: 12).statementClass == .spending)
        #expect(try Self.line(preview, row: 12).source == .sign)
        #expect(try Self.line(preview, row: 6).statementClass == .interest)
        #expect(try Self.line(preview, row: 9).statementClass == .income)
        #expect(try Self.line(preview, row: 9).source == .sign)
    }

    @Test func anotherAccountNamedInALineIsATransferOrADebtPayment() throws {
        // Without the broker's deposit, its name says it.
        let session = try Self.session("italian-bank.csv", account: "conto")
        var library = Self.library()
        library.accounts["visa"]?.name = "Carta di credito Visa"
        let preview = session.preview(against: library, today: Self.today)
        #expect(try Self.line(preview, row: 14).source == .account("esempio-sim"))
        #expect(try Self.line(preview, row: 14).statementClass == .transfer)
        // A name made only of words any card has says nothing.
        #expect(try Self.line(preview, row: 11).source == .sign)
        library.accounts["visa"]?.institution = "Esempio Credito"
        let card = """
            Data;Entrate;Uscite;Descrizione
            20/02/2026;;320,50;Addebito Esempio Credito
            25/02/2026;40,00;;Rimborso Esempio Credito
            """
        var paid = try ImportSession(data: Data(card.utf8))
        paid.proposeMapping(layout: .statement)
        paid.profile.constants.account = "conto"
        let lines = paid.preview(against: library, today: Self.today).statementLines
        #expect(lines.map(\.source) == [.account("visa"), .account("visa")])
        // Paying the card is spending; money back from it is moved between accounts.
        #expect(lines.map(\.statementClass) == [.spending, .transfer])
    }

    @Test func eachTradeMatchesTheLineNearestIt() throws {
        let csv = """
            Data;Uscite;Descrizione
            03/02/2026;500,00;Affitto
            06/02/2026;500,00;Bonifico
            """
        var session = try ImportSession(data: Data(csv.utf8))
        session.proposeMapping(layout: .statement)
        session.profile.constants.account = "conto"
        // The deposit of 500 into the broker on 6 February is the second line, not the first.
        let lines = session.preview(against: Self.library(deposit: true), today: Self.today).statementLines
        #expect(lines.map(\.statementClass) == [.spending, .transfer])
        #expect(lines.map(\.date) == ["2026-02-03", "2026-02-06"])
    }

    @Test func rulesAndChosenClassesCorrectLines() throws {
        var session = try Self.session("italian-bank.csv", account: "conto")
        session.setStatementRule(.transfer, for: "Bonifico a favore di")
        session.setStatementRule(.ignore, for: "rimborso")
        session.setStatementRule(.spending, for: "Addebito carta di credito")
        session.setStatementClass(.ignore, forRow: 13)
        let preview = session.preview(against: Self.library(), today: Self.today)
        #expect(try Self.line(preview, row: 14).source == .rule("Bonifico a favore di"))
        #expect(try Self.line(preview, row: 9).statementClass == .ignore)
        #expect(try Self.line(preview, row: 13).source == .chosen)
        #expect(try Self.line(preview, row: 13).statementClass == .ignore)
        // The longest phrase wins, and a rule for the same words replaces the old one.
        session.setStatementRule(.income, for: "Accredito")
        session.setStatementRule(.transfer, for: "accredito  STIPENDIO")
        #expect(session.statementRule(for: "Accredito stipendio ACME")?.statementClass == .transfer)
        session.setStatementRule(.spending, for: "Accredito Stipendio")
        #expect(session.profile.rules.filter { $0.match.lowercased().hasPrefix("accredito") }.count == 2)
        session.setStatementRule(nil, for: "accredito stipendio")
        #expect(session.statementRule(for: "Accredito stipendio ACME")?.statementClass == .income)
    }

    // MARK: - Values

    @Test func monthEndsGetBalancesAndMoneyInAndOut() throws {
        let session = try Self.session("italian-bank.csv", account: "conto")
        let preview = session.preview(against: Self.library(deposit: true), today: Self.today)
        #expect(preview.records.map(\.imported.key) == [.valuation("conto", "2026-02-28"),
                                                        .valuation("conto", "2026-03-31")])
        let february = try #require(preview.record(.valuation("conto", "2026-02-28")))
        #expect(february.status == .new)
        #expect(february.imported.balance == d("6044.45"))
        #expect(february.imported.moneyIn == 2800)
        #expect(february.imported.moneyOut == d("1266.40"))
        #expect(february.imported.flow == d("833.60"))
        #expect(february.imported.interest == nil)
        let march = try #require(preview.record(.valuation("conto", "2026-03-31")))
        // A current account's interest is money in.
        #expect(march.imported.moneyIn == d("2836.20"))
        #expect(march.imported.moneyOut == 60)
        #expect(march.imported.balance == d("8820.65"))
        // April isn't over: its line waits for the next statement.
        #expect(try Self.line(preview, row: 5).period == nil)
        #expect(try Self.line(preview, row: 15).period == "2026-02-28")
        #expect(preview.issues.contains { $0.kind == .linesAfterLastValue(count: 1, after: "2026-03-31") })
        #expect(preview.firstDate == "2026-02-02")
        #expect(preview.lastDate == "2026-04-02")

        let result = preview.apply(to: Self.library(deposit: true))
        let written = try #require(result.library.valuations(for: "conto").first { $0.date == "2026-02-28" })
        #expect(written == Valuation(account: "conto", date: "2026-02-28", balance: d("6044.45"), flow: d("833.60"),
                                     moneyIn: 2800, moneyOut: d("1266.40"), source: .import))
        #expect(written.moved == -700)
        // Importing the same file again changes nothing.
        let again = try Self.session("italian-bank.csv", account: "conto")
            .preview(against: result.library, today: Self.today)
        #expect(again.records.allSatisfy { $0.status == .identical })
    }

    @Test func checkInsInTheSpanGetTheirMoneyInAndOutFilledIn() throws {
        var library = Self.library(deposit: true)
        // Money out left as the check-in suggested it, with the transfer to the broker in it.
        library.upsert(Valuation(account: "conto", date: "2026-02-20", balance: d("6244.45"), flow: d("1033.60"),
                                 moneyIn: 2800, moneyOut: d("1766.40")))
        let preview = try Self.session("italian-bank.csv", account: "conto").preview(against: library,
                                                                                     today: Self.today)
        // February has a value, so it gets no month end.
        #expect(preview.records.map(\.imported.key) == [.valuation("conto", "2026-02-20"),
                                                        .valuation("conto", "2026-03-31")])
        let checkIn = try #require(preview.record(.valuation("conto", "2026-02-20")))
        #expect(checkIn.imported.balance == d("6244.45"))
        #expect(checkIn.imported.moneyIn == 2800)
        #expect(checkIn.imported.moneyOut == d("1266.40"))
        // The check-in's money out differs: the policy decides.
        #expect(checkIn.status == .conflict)
        let march = try #require(preview.record(.valuation("conto", "2026-03-31")))
        #expect(march.imported.moneyOut == 60)
        #expect(march.imported.flow == d("2576.20"))
    }

    @Test func aSavingsAccountsInterestIsItsOwn() throws {
        var session = try Self.session("english-bank.csv", account: "deposito")
        session.setStatementRule(.transfer, for: "Transfer")
        let preview = session.preview(against: Self.library(), today: Self.today)
        #expect(preview.issues.filter { !$0.isNote }.isEmpty, "\(preview.issues)")
        // No value before the file: January is the account's first, without money in and out.
        let january = try #require(preview.record(.valuation("deposito", "2026-01-31")))
        #expect(january.imported.balance == d("11012.50"))
        #expect(january.imported.moneyIn == nil)
        #expect(preview.issues.contains { $0.kind == .moneyInOutFrom("deposito", value: "2026-01-31", previous: nil) })
        let february = try #require(preview.record(.valuation("deposito", "2026-02-28")))
        #expect(february.imported.balance == d("10524.30"))
        #expect(february.imported.moneyIn == 0)
        #expect(february.imported.moneyOut == 0)
        #expect(february.imported.interest == d("11.80"))
        #expect(february.imported.flow == -500)
    }

    @Test func aGapBeforeTheFileLeavesItsFirstMonthWithoutMoneyInAndOut() throws {
        let library = Self.library(valueOn: "2025-12-31")
        let session = try Self.session("italian-bank.csv", account: "conto")
        let preview = session.preview(against: library, today: Self.today)
        // Without a balance column the balance can't be known across the gap.
        #expect(preview.issues.contains { $0.kind == .needsOpeningBalance("conto") })
        #expect(preview.records.isEmpty)

        var opened = session
        opened.statementOpeningBalance = d("5210.85")
        let withOpening = opened.preview(against: library, today: Self.today)
        let february = try #require(withOpening.record(.valuation("conto", "2026-02-28")))
        #expect(february.imported.balance == d("6044.45"))
        #expect(february.imported.moneyIn == nil)
        #expect(withOpening.issues.contains {
            $0.kind == .moneyInOutFrom("conto", value: "2026-02-28", previous: "2025-12-31")
        })
        #expect(withOpening.record(.valuation("conto", "2026-03-31"))?.imported.moneyIn == d("2836.20"))
    }

    @Test func aRunningBalanceThatAgreesWithTheLibraryBridgesAGap() throws {
        var library = Self.library()
        library.upsert(Valuation(account: "deposito", date: "2025-11-30", balance: d("10000")))
        var session = try Self.session("english-bank.csv", account: "deposito")
        session.setStatementRule(.transfer, for: "Transfer")
        let preview = session.preview(against: library, today: Self.today)
        let january = try #require(preview.record(.valuation("deposito", "2026-01-31")))
        #expect(january.imported.moneyIn == 0)
        #expect(january.imported.interest == d("12.50"))
        #expect(january.imported.flow == 1000)
    }

    // MARK: - The days a file covers

    @Test func aFileCoversWholeMonthsUnlessItsDaysAreGiven() throws {
        var session = try Self.session("italian-bank.csv", account: "conto")
        let preview = session.preview(against: Self.library(), today: Self.today)
        #expect(preview.issues.contains { $0.kind == .statementPeriod(from: "2026-02-01", through: "2026-04-12") })

        // An export made on 5 April: its last day gets a value, which the next file follows on from.
        session.statementThrough = "2026-04-05"
        let through = session.preview(against: Self.library(), today: Self.today)
        let fifth = try #require(through.record(.valuation("conto", "2026-04-05")))
        #expect(fifth.imported.balance == d("8775.65"))
        #expect(fifth.imported.moneyOut == 45)
        #expect(!through.issues.contains { if case .linesAfterLastValue = $0.kind { true } else { false } })
    }

    @Test func aFileThatStartsMidMonthDoesntFollowOnFromTheMonthBefore() throws {
        var session = try Self.session("italian-bank.csv", account: "conto")
        // A file of the last 90 days: 31 January's value isn't the balance before its first line.
        session.statementFrom = "2026-02-02"
        let preview = session.preview(against: Self.library(), today: Self.today)
        #expect(preview.issues.contains { $0.kind == .needsOpeningBalance("conto") })
        #expect(preview.records.isEmpty)

        session.statementFrom = "2026-02-03"
        let late = session.preview(against: Self.library(), today: Self.today)
        #expect(late.issues.contains {
            $0.kind == .linesOutsidePeriod(count: 1, from: "2026-02-03", through: "2026-04-12")
        })
        #expect(late.records.isEmpty)
    }

    @Test func anOpeningBalanceThatDisagreesWithTheValueBeforeLeavesTheFirstMonthOut() throws {
        var session = try Self.session("italian-bank.csv", account: "conto")
        session.statementOpeningBalance = 5000
        let preview = session.preview(against: Self.library(), today: Self.today)
        let february = try #require(preview.record(.valuation("conto", "2026-02-28")))
        #expect(february.imported.balance == d("5833.60"))
        #expect(february.imported.moneyIn == nil)
        #expect(preview.issues.contains {
            $0.kind == .moneyInOutFrom("conto", value: "2026-02-28", previous: "2026-01-31")
        })
    }

    @Test func aLaterValuesMoneyInAndOutThatTheFileSplitsIsNoted() throws {
        var library = Self.library()
        var later = Valuation(account: "conto", date: "2026-04-30", balance: d("8775.65"))
        later.moneyIn = d("5636.20")
        library.upsert(later)
        let session = try Self.session("italian-bank.csv", account: "conto")
        let preview = session.preview(against: library, today: Self.today)
        #expect(preview.issues.contains {
            $0.kind == .laterMoneyInOut("conto", value: "2026-04-30", since: "2026-01-31")
        })
        // Without money in and out, the later value has nothing to split.
        library.upsert(Valuation(account: "conto", date: "2026-04-30", balance: d("8775.65")))
        #expect(!session.preview(against: library, today: Self.today).issues.contains {
            if case .laterMoneyInOut = $0.kind { true } else { false }
        })
    }

    // MARK: - The account's dates

    @Test func anAccountOpenedAfterTheFileStartsIsProposedToOpenEarlier() throws {
        var library = Self.library()
        library.accounts["conto"]?.opened = "2026-03-01"
        let session = try Self.session("italian-bank.csv", account: "conto")
        let preview = session.preview(against: library, today: Self.today)
        #expect(preview.accountChanges
            == [AccountChangeProposal(account: "conto", change: .openEarlier(on: "2026-02-28"))])
    }

    @Test func valuesAfterAnAccountClosedAreAnIssue() throws {
        // The month that isn't over has lines after the last month end, which don't close the account.
        let session = try Self.session("italian-bank.csv", account: "conto")
        #expect(session.preview(against: Self.library(), today: Self.today).accountChanges.isEmpty)

        var library = Self.library()
        library.accounts["conto"]?.closed = "2026-03-01"
        let preview = session.preview(against: library, today: Self.today)
        #expect(preview.issues.contains { $0.kind == .valuesAfterClosed("conto", closed: "2026-03-01") })
    }

    @Test func aBalanceThatDoesntAddUpIsNoted() throws {
        let csv = """
            Date,Description,Amount,Balance
            2026-03-02,Shop,-10.00,90.00
            2026-03-03,Shop,-10.00,75.00
            2026-03-03,Pay,100.00,175.00
            """
        var session = try ImportSession(data: Data(csv.utf8))
        session.profile.constants.account = "conto"
        let preview = session.preview(against: Self.library(), today: Self.today)
        #expect(preview.issues.contains { $0.kind == .runningBalanceBreaks(count: 1) })
    }

    @Test func onlyCashAndSavingsAccountsTakeAStatement() throws {
        let broker = try Self.session("italian-bank.csv", account: "esempio-sim")
        #expect(broker.preview(against: Self.library(), today: Self.today).issues
            .contains { $0.kind == .noMoneyInOut("esempio-sim") })
        let unknown = try Self.session("italian-bank.csv", account: "nowhere")
        #expect(unknown.preview(against: Self.library(), today: Self.today).issues
            .contains { $0.kind == .unknownAccount("nowhere") })
        let none = try Samples.session("statements/italian-bank.csv")
        #expect(none.preview(against: Self.library(), today: Self.today).issues
            .contains { $0.kind == .missingField(.account) })
    }

    @Test func theExampleLibrarysProfileReadsTheStatement() throws {
        let library = try Fixtures.exampleLibrary()
        let profile = try #require(library.importProfiles["fineco-movimenti"])
        let session = try ImportSession(data: Samples.data("statements/italian-bank.csv"), profile: profile)
        let preview = session.preview(against: library, today: Self.today)
        #expect(preview.issues.filter { !$0.isNote }.isEmpty, "\(preview.issues)")
        #expect(try Self.line(preview, row: 11).source == .rule("Addebito carta di credito"))
        #expect(preview.records.map(\.imported.key) == [.valuation("conto-fineco", "2026-02-28"),
                                                        .valuation("conto-fineco", "2026-03-31")])
    }

    @Test func theProfileKeepsTheRules() throws {
        var session = try Self.session("italian-bank.csv", account: "conto")
        session.setStatementRule(.transfer, for: "Bonifico a favore di")
        session.setStatementClass(.ignore, forRow: 13)
        let profile = session.makeProfile(id: "banca", name: "Banca", library: Self.library())
        #expect(profile.layout == .statement)
        #expect(profile.rules == [StatementRule(match: "Bonifico a favore di", statementClass: .transfer)])
        #expect(profile.constants.account == "conto")
        let encoded = try JSONEncoder().encode(profile)
        #expect(try JSONDecoder().decode(ImportProfile.self, from: encoded) == profile)
        // A line's own class belongs to the file.
        let next = try ImportSession(data: Samples.data("statements/italian-bank.csv"), profile: profile)
        #expect(next.statementLineClasses.isEmpty)
        #expect(next.preview(against: Self.library(), today: Self.today).statementLines
            .first { $0.row == 14 }?.source == .rule("Bonifico a favore di"))
    }
}
