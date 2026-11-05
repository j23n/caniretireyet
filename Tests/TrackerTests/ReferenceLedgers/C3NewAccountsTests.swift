import Foundation
import Model
import Testing
import TestSupport
import Tracker

/// C3, two accounts first recorded in the same month
/// (Resources/ReferenceLedgers/c3-new-accounts, expected.md): every number
/// its expected.md works out by hand.
@Suite struct C3NewAccountsTests {
    let library: Library
    let valuator: Valuator
    let februarysChange: ChangeReport

    init() throws {
        library = try ReferenceLedger.newAccounts.library()
        valuator = Valuator(library: library)
        februarysChange = valuator.change(from: "2025-01-31", to: "2025-02-28")
    }

    @Test func netWorth() {
        #expect(valuator.netWorth(on: "2024-12-31").total == 8000)
        #expect(valuator.netWorth(on: "2025-01-31").total == 10000)
        #expect(valuator.netWorth(on: "2025-02-28").total == 23274)
    }

    @Test func january() throws {
        let moved = valuator.whatMoved(valuator.change(from: "2024-12-31", to: "2025-01-31"))
        #expect(moved.change == 2000)
        #expect(moved.saved == 2000)
        #expect(moved.pay?.spent == 2000)
        #expect(moved.unexplained == 0)
    }

    /// The 5,000 moved from the current account pays for that much of the
    /// two first amounts, shared in proportion to them; the rest is what
    /// they started with.
    @Test func february() throws {
        let moved = valuator.whatMoved(februarysChange)
        #expect(moved.start == 10000)
        #expect(moved.change == 13274)
        #expect(moved.saved == 2000)
        #expect(moved.markets == 274)
        #expect(moved.startedWith == 11000)
        #expect(moved.oneOffs == 0)
        #expect(moved.lost == 0)
        #expect(moved.unexplained == 0)
        let pay = try #require(moved.pay)
        #expect(pay.moneyIn == 4000)
        #expect(pay.spent == 2000)
        #expect(pay.savedShare == d("0.5"))

        let stretch = try #require(valuator.savedStretches(between: ["2025-01-31", "2025-02-28"], in: .netWorth)
            .first)
        #expect(stretch.saved == ["current": -3000, "broker": 3125, "savings": 1875])
        #expect(stretch.startedWith == ["broker": 6875, "savings": 4125])
    }

    @Test func februarysSavedSplit() {
        let byAccount = Dictionary(uniqueKeysWithValues: februarysChange.accounts.map { ($0.account, $0.change) })
        #expect(byAccount["current"]?.saved == -3000)
        #expect(byAccount["broker"]?.saved == 10000)
        #expect(byAccount["broker"]?.market == 274)
        #expect(byAccount["savings"]?.other == 6000)

        let split = valuator.savedSplit(of: februarysChange)
        #expect(split.saved == 2000)
        #expect(split.market == 274)
        #expect(split.other == 11000)
    }

    @Test func theYearSoFar() throws {
        let year = try #require(valuator.changeThisYear(asOf: "2025-02-28"))
        #expect(year.total.change == 15274)
        #expect(year.total.saved == 9000)
        #expect(year.total.market == 274)
        #expect(year.total.other == 6000)
        let split = valuator.savedSplit(of: year)
        #expect(split.saved == 4000)
        #expect(split.other == 11000)

        let rate = try #require(valuator.savingsRate(from: "2025-01-01", through: "2025-02-28"))
        #expect(rate.from == "2024-12-31")
        #expect(rate.income == 8000)
        #expect(rate.saved == 4000)
        #expect(rate.spent == 4000)
        #expect(rate.spentPerYear == d("24745.76"))
        #expect(rate.rate == d("0.5"))
    }

    @Test func moneySources() {
        let sources = valuator.moneySources(.months, through: "2025-02-28")
        #expect(sources.points == [
            MoneySourcesPoint(date: "2024-12-31", total: 8000, startedWith: 8000, saved: 0),
            MoneySourcesPoint(date: "2025-01-31", total: 10000, startedWith: 8000, saved: 2000),
            MoneySourcesPoint(date: "2025-02-28", total: 23274, startedWith: 19000, saved: 4000),
        ])
        #expect(sources.points.last?.markets == 274)
    }

    @Test func theBrokersTrades() throws {
        let ledger = try #require(valuator.ledger(for: "broker"))
        #expect(ledger.positions(on: "2025-02-28") == [Position(instrument: "world-fund", quantity: 78,
                                                                  costBasis: 8544)])
        #expect(valuator.tradeCash(of: "broker", on: "2025-02-28") == 56)
        let flows = valuator.tradeFlows(of: "broker", after: nil, through: "2025-02-28")
        #expect(flows.compactMap(\.amount).reduce(0, +) == 10000)
    }

    /// The savings account first valued on 15 February, the day it was
    /// added, instead of with its statement on the 28th: a check-in between
    /// the broker's first trades and the current account's value that
    /// records the money moved to it. Nothing that happened changes, so
    /// February's numbers are the same. Through the 15th both accounts
    /// started with their first amounts; the current account's value on
    /// the 28th, which covers the days since 31 January, pays for 5,000 of
    /// them, which then counts as saved.
    @Test func aCheckInInTheMiddleOfTheMonth() throws {
        var library = library
        library.upsert(Valuation(account: "savings", date: "2025-02-15", balance: 6000))
        library.upsert(Valuation(account: "savings", date: "2025-02-28", balance: 6000, moneyIn: 0, moneyOut: 0))
        let valuator = Valuator(library: library)
        let moved = valuator.whatMoved(valuator.change(from: "2025-01-31", to: "2025-02-28"))
        #expect(moved.change == 13274)
        #expect(moved.markets == 274)
        #expect(moved.saved == 2000)
        #expect(moved.startedWith == 11000)
        #expect(moved.pay?.spent == 2000)

        let stretches = valuator.savedStretches(between: ["2025-01-31", "2025-02-15", "2025-02-28"], in: .netWorth)
        #expect(stretches.map(\.saved) == [["current": 0, "broker": 0, "savings": 0],
                                            ["current": -3000, "broker": 3125, "savings": 1875]])
        #expect(stretches.map(\.startedWith) == [["broker": 10000, "savings": 6000],
                                                  ["broker": -3125, "savings": -1875]])
        let second = valuator.whatMoved(valuator.change(from: "2025-02-15", to: "2025-02-28"))
        #expect(second.saved == 2000)
        #expect(second.startedWith == -5000)
        #expect(second.pay?.spent == 2000)
    }
}
