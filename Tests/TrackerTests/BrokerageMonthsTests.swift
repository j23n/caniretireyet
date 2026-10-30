import Foundation
import Model
import Testing
import TestSupport
import Tracker

/// A trades account's month (docs/TRADES.md, "A brokerage month"): its
/// trades, the cash they lead to against the broker's, and money moved to
/// it from a current account's statement that it has no deposit for. A
/// made-up October: the broker opened it with 1,203.10 in cash after
/// September's check-in; the current account moved 1,500 to it on 3
/// October, and 12 VWCE were bought on 6 October for 1,433.35.
struct BrokerageMonthsTests {
    private static func library() -> Library {
        var library = Library(
            settings: LibrarySettings(baseCurrency: .eur),
            accounts: [
                Account(id: "conto", name: "Conto", kind: .cash, currency: .eur, opened: "2020-01-01"),
                Account(id: "broker", name: "Broker", kind: .brokerage, currency: .eur, opened: "2020-01-01",
                        valuation: .trades),
            ],
            instruments: [
                Instrument(id: "vwce", name: "VWCE", kind: .etf, currency: .eur, unit: .share,
                           assetClasses: .single(.equity)),
            ])
        library.upsert(Valuation(account: "conto", date: "2026-09-30", balance: 5000))
        library.upsert(Valuation(account: "broker", date: "2026-09-30", cash: d("1203.10")))
        library.upsert(BankLine(account: "conto", date: "2026-10-03", id: "move", amount: -1500,
                                text: "Bonifico a Broker", statementClass: .transfer, otherAccount: "broker",
                                confirmed: true))
        library.upsert(Trade(account: "broker", date: "2026-10-06", id: "buy", type: .buy, instrument: "vwce",
                             quantity: 12, price: d("119.20"), fees: d("2.95")))
        return library
    }

    private static func october(_ library: Library) throws -> BrokerageMonth {
        try #require(Valuator(library: library).brokerageMonth(of: "broker", after: "2026-09-30",
                                                               through: "2026-10-31", in: library))
    }

    @Test func aMoveWithoutADepositIsOneToAdd() throws {
        let month = try Self.october(Self.library())
        #expect(month.openingCash == d("1203.10"))
        #expect(month.trades.map(\.trade.id) == ["buy"])
        #expect(month.tradesCash == d("-1433.35"))
        #expect(month.depositsToAdd.map(\.id) == ["move"])
        #expect(month.status == .depositsToAdd(1))
    }

    @Test func theDepositAddedMatchesTheMove() throws {
        var library = Self.library()
        let line = try #require(library.lines(for: "conto").first)
        library.addDeposit(for: line)
        let deposit = try #require(library.trades(for: "broker").first { $0.type == .deposit })
        #expect(deposit.date == "2026-10-03")
        #expect(deposit.amount == 1500)
        #expect(deposit.source == .manual)

        let month = try Self.october(library)
        #expect(month.depositsToAdd.isEmpty)
        #expect(month.cashFromTrades == d("1269.75"))
        // Without the broker's cash, the month waits for it.
        #expect(month.status == .needsCash)
    }

    /// A deposit the broker's file dates a few days later is the same move.
    @Test func aDepositDaysLaterMatches() throws {
        var library = Self.library()
        library.upsert(Trade(account: "broker", date: "2026-10-06", id: "dep", type: .deposit, amount: 1500))
        #expect(try Self.october(library).depositsToAdd.isEmpty)

        library.upsert(Trade(account: "broker", date: "2026-10-06", id: "dep", type: .deposit, amount: 1400))
        #expect(try Self.october(library).depositsToAdd.count == 1)
    }

    /// Money moved from a euro account to a dollar account isn't a deposit
    /// to add: the two amounts are in different currencies.
    @Test func aMoveInAnotherCurrencyIsLeftAlone() throws {
        var library = Self.library()
        library.accounts["broker"]?.currency = .usd
        #expect(try Self.october(library).depositsToAdd.isEmpty)
        let line = try #require(library.lines(for: "conto").first)
        library.addDeposit(for: line)
        #expect(library.trades(for: "broker").allSatisfy { $0.type != .deposit })
    }

    /// One deposit near a check-in answers one move, not one in each month.
    @Test func aDepositMatchesOneMoveAcrossMonths() throws {
        var library = Self.library()
        library.upsert(BankLine(account: "conto", date: "2026-09-28", id: "early", amount: -500,
                                statementClass: .transfer, otherAccount: "broker", confirmed: true))
        library.upsert(BankLine(account: "conto", date: "2026-10-02", id: "late", amount: -500,
                                statementClass: .transfer, otherAccount: "broker", confirmed: true))
        library.upsert(Trade(account: "broker", date: "2026-10-01", id: "dep", type: .deposit, amount: 500))
        let ids = try Self.october(library).depositsToAdd.map(\.id)
        #expect(ids == ["late", "move"])
    }

    @Test func theBrokersCashChecksTheTrades() throws {
        var library = Self.library()
        let line = try #require(library.lines(for: "conto").first)
        library.addDeposit(for: line)
        library.setBrokerCash(d("1269.75"), of: "broker", on: "2026-10-31")
        #expect(try Self.october(library).status == .checked)

        library.setBrokerCash(d("1250"), of: "broker", on: "2026-10-31")
        let month = try Self.october(library)
        #expect(month.difference == d("-19.75"))
        #expect(month.status == .off(d("-19.75")))
        #expect(library.valuations(for: "broker").last?.source == .manual)
    }

    @Test func aMonthWithNothingIsNotDone() throws {
        var library = Self.library()
        library.months["2026-10"]?.trades.removeAll()
        library.months["2026-10"]?.lines.removeAll()
        let month = try Self.october(library)
        #expect(month.status == .notDone)
        #expect(!month.status.isDone)
    }

    @Test func monthsListTheTradesAccounts() {
        let library = Self.library()
        let months = Valuator(library: library).brokerageMonths(after: "2026-09-30", through: "2026-10-31",
                                                                in: library)
        #expect(months.map(\.account) == ["broker"])
    }
}
