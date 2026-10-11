import Foundation
import Model
import Testing
import Tracker
@testable import CanIRetireYet

/// What an account's details list (UI.md, "Account detail"; docs/ACCOUNTS.md,
/// "The account detail"), from the example library (``PreviewLibrary``):
/// Directa records trades, with typed cash at its check-ins; the gold coins
/// record trades paid from the bank; the current and savings accounts record
/// money in and out from July 2026, and the savings account its interest.
struct AccountDetailDataTests {
    private func detail(_ account: AccountID, in library: Library = PreviewLibrary.library) throws
        -> AccountDetailData {
        let details = try #require(library.accounts[account])
        return AccountDetailData(account: details, library: library, valuator: Valuator(library: library),
                                 today: PreviewLibrary.latestCheckIn, stalenessThreshold: 45)
    }

    private func d(_ text: String) -> Decimal { PreviewLibrary.d(text) }

    // MARK: A trades account

    @Test func aTradesAccountListsItsTradesInPlaceOfItsValues() throws {
        let library = PreviewLibrary.library
        let data = try detail("directa")
        #expect(data.recordsTrades)
        #expect(data.valuations.isEmpty)
        #expect(!library.valuations(for: "directa").isEmpty)
        let trades = TradeList(account: "directa", library: library, valuator: Valuator(library: library))
        #expect(trades.totalCount == library.trades(for: "directa").count)
        #expect(trades.totalCount > 0)
        #expect(data.tradeHoldings?.rows.map(\.instrument) == ["vwce"])
    }

    @Test func itsStatementsAreTheValuesWhoseCashDiffersFromTheTrades() throws {
        let data = try detail("directa")
        // The first value's cash came before any deposit; two check-ins typed a cash the trades don't give.
        #expect(data.statements.map(\.id.date) == ["2026-09-30", "2026-07-31", "2025-10-31"])
        let september = try #require(data.statements.first)
        #expect(september.cash == d("312.1"))
        #expect(september.cashDifference == d("11.3"))
        #expect(september.positionsText == nil)
        #expect(data.statements.map(\.cashDifference) == [d("11.3"), d("-0.45"), d("215.4")])
        // Its values are still there for *Add Past Value…*.
        #expect(data.firstValueDate == "2025-10-31")
        #expect(data.pastValueDate == "2025-09-30")
    }

    @Test func aValueThatFollowsTheTradesIsntAStatement() throws {
        var library = PreviewLibrary.library
        let cash = try #require(Valuator(library: library).tradeCash(of: "directa", on: "2026-10-05"))
        library.upsert(Valuation(account: "directa", date: "2026-10-05", cash: cash, flow: 0))
        #expect(try detail("directa", in: library).statements.first?.id.date == "2026-09-30")

        library.upsert(Valuation(account: "directa", date: "2026-10-05", cash: cash + 100, flow: 100))
        let statement = try #require(try detail("directa", in: library).statements.first)
        #expect(statement.id.date == "2026-10-05")
        #expect(statement.cashDifference == 100)
        #expect(statement.cash == cash + 100)
    }

    @Test func aStatementsPositionsSayWhetherTheyMatchTheTrades() throws {
        // Lists 424,5 VWCE where the trades give 414,5.
        let mismatch = try #require(try detail("directa", in: PreviewLibrary.withStatementMismatch).statements.first)
        #expect(mismatch.id.date == "2026-09-30")
        #expect(mismatch.mismatchCount == 1)
        #expect(mismatch.positionsText == "1 position listed, 1 differs from the trades")

        var library = PreviewLibrary.library
        let held = try #require(Valuator(library: library).holdings(of: "directa", on: "2026-09-30").first)
        library.upsert(Valuation(account: "directa", date: "2026-09-30", cash: d("312.1"),
                                 positions: [Position(instrument: "vwce", quantity: held.quantity)], flow: d("11.3")))
        let matching = try #require(try detail("directa", in: library).statements.first)
        #expect(matching.mismatchCount == 0)
        #expect(matching.positionsText == "1 position listed, as the trades give")
    }

    @Test func aTradesAccountWithoutCashOfItsOwnHasNoStatements() throws {
        let data = try detail("gold-coins")
        #expect(data.valuations.isEmpty)
        #expect(data.statements.isEmpty)
    }

    // MARK: Cash and savings

    @Test func aCashAccountsValueShowsMoneyInOutAndMoved() throws {
        let data = try detail("conto-fineco")
        #expect(data.valuationsShowMoneyInOut)
        #expect(!data.valuationsShowInterest)
        let september = try #require(data.valuations.first)
        #expect(september.id.date == "2026-09-30")
        #expect(september.recordsMoneyInOut)
        #expect(september.valuation.moneyIn == 3400)
        #expect(september.valuation.moneyOut == d("2554.65"))
        // New money −304,65 = 3.400 in − 2.554,65 out − 1.150 moved to your other accounts.
        #expect(september.moved == -1150)
        #expect(data.valuations.prefix(3).map(\.moved) == [-1150, d("-850.6"), -650])
        #expect(data.movedNote == "Moved is the part of the change that money in and out don't explain: money "
            + "moved between your own accounts.")
    }

    @Test func aValueWithoutMoneyInAndOutHasNothingMoved() throws {
        let data = try detail("conto-fineco")
        let first = try #require(data.valuations.last)
        #expect(first.id.date == "2025-10-31")
        #expect(!first.recordsMoneyInOut)
        #expect(first.moved == nil)
        // Recorded before money in and out were: new money alone.
        let november = try #require(data.valuations.first { $0.id.date == "2025-11-30" })
        #expect(november.valuation.flow == d("1285.45"))
        #expect(november.moved == nil)
    }

    @Test func aSavingsAccountsValueShowsItsInterestToo() throws {
        let data = try detail("conto-deposito")
        #expect(data.valuationsShowMoneyInOut)
        #expect(data.valuationsShowInterest)
        let september = try #require(data.valuations.first)
        #expect(september.valuation.interest == d("35.05"))
        // The change less the interest is new money, 500, with nothing in or out: all of it moved.
        #expect(september.valuation.flow == 500)
        #expect(september.moved == 500)
        #expect(data.movedNote?.contains("money in and out and interest don't explain") == true)
    }

    // MARK: Other accounts

    @Test func aBalanceAccountListsItsValuesNewestFirst() throws {
        let library = PreviewLibrary.library
        let data = try detail("fondo-pensione")
        #expect(!data.recordsTrades)
        #expect(data.statements.isEmpty)
        #expect(data.tradeHoldings == nil)
        #expect(data.holdings.isEmpty)
        #expect(data.valuations.map(\.id) == library.valuations(for: "fondo-pensione").reversed().map(\.key))
        #expect(!data.valuationsShowMoneyInOut)
        #expect(data.movedNote == nil)
        #expect(data.valuations.allSatisfy { $0.moved == nil })
    }
}
