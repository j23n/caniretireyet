import Foundation
@testable import Importer
import Model
import Testing
import TestSupport
import Tracker

/// Money a bank statement's line moved to an account that records trades
/// (IMPORT.md, "Moved to or from an account"): the line is the account's
/// deposit, so the money counts as saved in the month it left the bank,
/// once, whichever file is imported first. A made-up January: pay of
/// 3,000, rent of 900 and 1,500 moved to a broker.
struct StatementMoveTradesTests {
    static let today: CalendarDate = "2026-02-10"

    static let statement = """
        Data;Importo;Descrizione
        05/01/2026;-900,00;Affitto gennaio
        15/01/2026;-1.500,00;Bonifico a broker
        27/01/2026;3.000,00;Bonifico SEPA da ACME GmbH rif 0126
        """

    /// The broker's own export, with the deposit a day after it left the bank.
    static let brokerFile = """
        Tipo;Data;Titolo;Quantità;Prezzo;Importo
        Versamento;16/01/2026;;;;1.500,00
        """

    /// A current account and a broker that records trades, with a deposit
    /// in June 2025 when `history` is set.
    static func library(history: Bool = true) -> Library {
        var library = Library(accounts: [
            Account(id: "conto", name: "Conto corrente", kind: .cash, currency: .eur, opened: "2020-01-01"),
            Account(id: "broker", name: "Broker", kind: .brokerage, currency: .eur, opened: "2025-01-01",
                    valuation: .trades),
        ])
        library.upsert(Valuation(account: "conto", date: "2025-12-31", balance: 10000))
        if history {
            library.upsert(Trade(account: "broker", date: "2025-06-02", id: "first", type: .deposit, amount: 1000))
        }
        return library
    }

    /// The statement with the pay answered as income and the 1,500 as moved to `account`.
    static func statementSession(against library: Library, movingTo account: AccountID = "broker") throws
        -> ImportSession {
        var session = try ImportSession(data: Data(statement.utf8))
        session.proposeMapping(layout: .statement)
        session.profile.constants.account = "conto"
        let lines = session.preview(against: library, today: today).statementLines
        let pay = try #require(lines.first { $0.text.hasPrefix("Bonifico SEPA") })
        let moved = try #require(lines.first { $0.text.hasPrefix("Bonifico a broker") })
        session.setStatementClass(.income, forRow: pay.row)
        session.setStatementAsset(.moved(account), forRow: moved.row)
        return session
    }

    static func brokerSession() throws -> ImportSession {
        var session = try ImportSession(data: Data(brokerFile.utf8))
        if session.profile.layout != .trades { session.proposeMapping(layout: .trades) }
        session.profile.constants.account = "broker"
        return session
    }

    /// The deposit the statement's line records: the ID the broker's own
    /// file gives a deposit of 1,500 on the same day.
    static let deposit: TradeKey = {
        let trade = Trade(account: "broker", date: "2026-01-15", type: .deposit, amount: 1500)
        return TradeKey(account: "broker", date: "2026-01-15", id: TradeID.stable(for: trade))
    }()

    /// January's savings rate: 3,000 came in, so 900 spent means 2,100 saved.
    static func january(_ library: Library) throws -> SavingsRate {
        try #require(Valuator(library: library).savingsRate(from: "2026-01-01", through: "2026-01-31"))
    }

    @Test func aMoveToATradesAccountIsItsDeposit() throws {
        let preview = try Self.statementSession(against: Self.library())
            .preview(against: Self.library(), today: Self.today)
        let line = try #require(preview.statementLines.first { $0.text.hasPrefix("Bonifico a broker") })
        #expect(line.statementClass == .transfer)
        #expect(line.assetAccount == "broker")
        let record = try #require(preview.record(.trade(Self.deposit)))
        #expect(record.status == .new)
        #expect(record.imported.trade?.type == .deposit)
        #expect(record.imported.trade?.amount == 1500)
        #expect(preview.record(.valuation("conto", "2026-01-31"))?.imported.moneyOut == 900)

        let library = preview.apply(to: Self.library()).library
        #expect(library.trade(Self.deposit) != nil)
        let january = try Self.january(library)
        #expect(january.income == 3000)
        #expect(january.saved == 2100)
        #expect(january.spent == 900)

        // Importing the statement again adds nothing.
        let again = try Self.statementSession(against: library).preview(against: library, today: Self.today)
        #expect(again.apply(to: library).library.trades(for: "broker") == library.trades(for: "broker"))
    }

    /// Without the answer, the 1,500 left the bank and reached no account:
    /// it's spent, as the statement can't tell.
    @Test func aBrokerWithoutTheDepositCountsItAsSpent() throws {
        var library = Self.library()
        let preview = try Self.statementSession(against: library).preview(against: library, today: Self.today)
        library = preview.apply(to: library).library
        library.months["2026-01"]?.trades.removeAll { $0.key == Self.deposit }
        #expect(try Self.january(library).spent == 2400)
    }

    @Test func theBrokersFileFindsTheDepositTheStatementRecorded() throws {
        var library = Self.library()
        library = try Self.statementSession(against: library).preview(against: library, today: Self.today)
            .apply(to: library).library
        let preview = try Self.brokerSession().preview(against: library)
        #expect(preview.records.map(\.imported.key) == [.trade(Self.deposit)])
        #expect(preview.records.allSatisfy { $0.status != .new })
        library = preview.apply(to: library).library
        #expect(library.trades(for: "broker").count == 2)
        #expect(try Self.january(library).spent == 900)
        // Importing the broker's file again finds it too.
        #expect(try Self.brokerSession().preview(against: library).records.allSatisfy { $0.status != .new })
    }

    @Test func theStatementFindsTheDepositTheBrokersFileRecorded() throws {
        var library = try Self.brokerSession().preview(against: Self.library()).apply(to: Self.library()).library
        #expect(library.trades(for: "broker").map(\.date) == ["2025-06-02", "2026-01-16"])
        let preview = try Self.statementSession(against: library).preview(against: library, today: Self.today)
        #expect(!preview.records.contains { $0.imported.key.isTrade })
        library = preview.apply(to: library).library
        #expect(library.trades(for: "broker").count == 2)
        #expect(try Self.january(library).spent == 900)
    }

    /// A broker whose records start with the deposit: what the current
    /// account moved out pays for it, so it's saved, though the current
    /// account saved 600 too.
    @Test func aNewBrokerFundedFromTheStatementIsSaved() throws {
        var library = Self.library(history: false)
        library = try Self.statementSession(against: library).preview(against: library, today: Self.today)
            .apply(to: library).library
        let january = try Self.january(library)
        #expect(january.saved == 2100)
        #expect(january.spent == 900)
    }

    /// A broker in another currency, or not yet opened, records its side itself.
    @Test func aBrokerItCantRecordADepositInIsLeftAsItIs() throws {
        var library = Self.library()
        library.accounts["broker"]?.currency = .usd
        var preview = try Self.statementSession(against: library).preview(against: library, today: Self.today)
        #expect(!preview.records.contains { $0.imported.key.isTrade })
        library = Self.library()
        library.accounts["broker"]?.opened = "2026-01-20"
        preview = try Self.statementSession(against: library).preview(against: library, today: Self.today)
        #expect(!preview.records.contains { $0.imported.key.isTrade })
    }
}
