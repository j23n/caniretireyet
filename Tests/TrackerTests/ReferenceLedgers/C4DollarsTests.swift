import Foundation
import Model
import Testing
import TestSupport
import Tracker

/// C4, dollar accounts in a euro library (Resources/ReferenceLedgers/c4-dollars,
/// expected.md): every number its expected.md works out by hand. 1 EUR is
/// 1.25 USD on 31 December and 28 February, and 1.28 USD on 31 January.
@Suite struct C4DollarsTests {
    let valuator: Valuator

    init() throws {
        valuator = Valuator(library: try ReferenceLedger.dollars.library())
    }

    private func changes(from: CalendarDate, to: CalendarDate) -> [AccountID: ValueChange] {
        Dictionary(uniqueKeysWithValues: valuator.change(from: from, to: to).accounts.map { ($0.account, $0.change) })
    }

    @Test func netWorth() {
        #expect(valuator.netWorth(on: "2024-12-31").total == 23600)
        #expect(valuator.netWorth(on: "2025-01-31").total == d("26712.5"))
        #expect(valuator.netWorth(on: "2025-02-28").total == d("28885.6"))
    }

    /// January: what each dollar account saved is converted at its date,
    /// and markets are the rest, the dollar's fall on the balance before.
    @Test func january() throws {
        let byAccount = changes(from: "2024-12-31", to: "2025-01-31")
        #expect(byAccount["current"]?.saved == 1000)
        #expect(byAccount["us-broker"]?.saved == 1000)
        #expect(byAccount["us-broker"]?.market == 250)
        #expect(byAccount["us-401k"]?.saved == 400)
        #expect(byAccount["us-401k"]?.market == 100)
        #expect(byAccount["us-checking"]?.saved == 400)
        #expect(byAccount["us-checking"]?.market == d("-37.5"))

        let moved = valuator.whatMoved(valuator.change(from: "2024-12-31", to: "2025-01-31"))
        #expect(moved.change == d("3112.5"))
        #expect(moved.saved == 2800)
        #expect(moved.markets == d("312.5"))
        #expect(moved.unexplained == 0)
        let pay = try #require(moved.pay)
        #expect(pay.moneyIn == 4500)
        #expect(pay.pension == 400)
        #expect(pay.cameIn == 4900)
        #expect(pay.spent == 2100)
        #expect(pay.savedShare == Decimal(2800) / 4900)

        let rate = try #require(valuator.savingsRate(from: "2025-01-01", through: "2025-01-31"))
        #expect(rate.moneyInOut.moneyOut == 2100)
        #expect(rate.spentPerYear == d("24725.81"))
    }

    /// February: the 401(k)'s value has no saved amount, so its change
    /// apart from the dollar's rise on the balance before is unexplained.
    @Test func february() throws {
        let byAccount = changes(from: "2025-01-31", to: "2025-02-28")
        #expect(byAccount["current"]?.saved == 1500)
        #expect(byAccount["us-broker"]?.saved == 0)
        #expect(byAccount["us-broker"]?.market == 126)
        #expect(byAccount["us-401k"]?.saved == 0)
        #expect(byAccount["us-401k"]?.market == 204)
        #expect(byAccount["us-401k"]?.other == 296)
        #expect(byAccount["us-checking"]?.saved == 0)
        #expect(byAccount["us-checking"]?.market == d("47.1"))

        let moved = valuator.whatMoved(valuator.change(from: "2025-01-31", to: "2025-02-28"))
        #expect(moved.change == d("2173.1"))
        #expect(moved.saved == 1500)
        #expect(moved.markets == d("377.1"))
        #expect(moved.unexplained == 296)
        let pay = try #require(moved.pay)
        #expect(pay.moneyIn == 4000)
        #expect(pay.pension == 0)
        #expect(pay.spent == 2500)
        #expect(pay.savedShare == d("0.375"))
    }

    /// Both months at once. Saved adds up the two check-ins; markets come
    /// from one change over both, where the 401(k), with a value without a
    /// saved amount, counts only the dollar's move on its 31 December
    /// balance, which is none (PROGRESS.md, "What moved it", and
    /// schema/README.md, "How values are computed"). So 304 of the months'
    /// markets are unexplained here.
    @Test func bothMonths() throws {
        let byAccount = changes(from: "2024-12-31", to: "2025-02-28")
        #expect(byAccount["us-401k"]?.saved == 0)
        #expect(byAccount["us-401k"]?.market == 0)
        #expect(byAccount["us-401k"]?.other == 1000)
        #expect(byAccount["us-checking"]?.saved == 400)
        #expect(byAccount["us-checking"]?.market == d("9.6"))
        #expect(byAccount["us-broker"]?.market == 376)

        let year = try #require(valuator.changeThisYear(asOf: "2025-02-28"))
        #expect(year.total.change == d("5285.6"))
        #expect(year.total.saved == 3900)
        #expect(year.total.market == d("385.6"))
        #expect(year.total.other == 1000)

        let moved = valuator.whatMoved(year)
        #expect(moved.saved == 4300)
        #expect(moved.markets == d("385.6"))
        #expect(moved.unexplained == 600)

        let split = valuator.savedSplit(of: year)
        #expect(split.saved == 4300)
        #expect(split.market == d("385.6"))
        #expect(split.other == 600)

        let months = valuator.monthlyChanges(from: YearMonth(year: 2025, month: 1)!,
                                             through: YearMonth(year: 2025, month: 2)!, asOf: "2025-02-28")
        #expect(months.map(\.saved) == [2800, 1500])
        #expect(months.map(\.markets) == [d("312.5"), d("377.1")])

        let rate = try #require(valuator.savingsRate(from: "2025-01-01", through: "2025-02-28"))
        #expect(rate.moneyInOut.moneyIn == 8500)
        #expect(rate.pensionContributions == 400)
        #expect(rate.income == 8900)
        #expect(rate.saved == 4300)
        #expect(rate.spent == 4600)
        #expect(rate.spentPerYear == d("28457.63"))
        #expect(rate.rate == Decimal(4300) / 8900)
    }

    @Test func theDollarBrokersTrades() throws {
        let ledger = try #require(valuator.ledger(for: "us-broker"))
        #expect(ledger.currency == .usd)
        #expect(ledger.positions(on: "2025-02-28") == [Position(instrument: "us-total-market", quantity: 25,
                                                                  costBasis: 5250)])
        #expect(valuator.tradeCash(of: "us-broker", on: "2025-02-28") == 0)
        let summary = valuator.tradeSummary(for: 2025)
        #expect(summary.deposits == 1000)
    }
}
