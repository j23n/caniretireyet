import Foundation
import Model
import Testing
import TestSupport
import Tracker

/// C1, five accounts and one month (Resources/ReferenceLedgers/c1-five-accounts,
/// expected.md): every number its expected.md works out by hand.
@Suite struct C1FiveAccountsTests {
    let valuator: Valuator
    let january: ChangeReport

    init() throws {
        valuator = Valuator(library: try ReferenceLedger.fiveAccounts.library())
        january = valuator.change(from: "2024-12-31", to: "2025-01-31")
    }

    @Test func netWorth() {
        #expect(valuator.netWorth(on: "2024-12-31").total == -66100)
        #expect(valuator.netWorth(on: "2025-01-31").total == -64400)
        #expect(valuator.netWorth(on: "2025-01-31").isComplete)
        #expect(valuator.total(on: "2025-01-31", in: .planAssets).total == 35100)
    }

    @Test func eachAccountsChange() {
        let byAccount = Dictionary(uniqueKeysWithValues: january.accounts.map { ($0.account, $0.change) })
        #expect(byAccount["current"]?.saved == -550)
        #expect(byAccount["card"]?.saved == 200)
        #expect(byAccount["broker"]?.saved == 1000)
        #expect(byAccount["broker"]?.market == 200)
        #expect(byAccount["mortgage"]?.saved == 500)
        #expect(byAccount["pension"]?.saved == 300)
        #expect(byAccount["pension"]?.market == 50)
        for change in byAccount.values {
            #expect(change.other == 0)
            #expect(change.lost == 0)
        }
    }

    @Test func whatMoved() throws {
        let moved = valuator.whatMoved(january)
        #expect(moved.start == -66100)
        #expect(moved.change == 1700)
        #expect(moved.saved == 1450)
        #expect(moved.markets == 250)
        #expect(moved.oneOffs == 0)
        #expect(moved.startedWith == 0)
        #expect(moved.lost == 0)
        #expect(moved.unexplained == 0)
        #expect(moved.isPriced)
        let pay = try #require(moved.pay)
        #expect(pay.moneyIn == 4000)
        #expect(pay.pension == 300)
        #expect(pay.cameIn == 4300)
        #expect(pay.tax == 0)
        #expect(pay.afterTax == 4300)
        #expect(pay.spent == 2850)
        #expect(pay.saved == 1450)
        #expect(pay.savedShare == Decimal(1450) / 4300)
    }

    @Test func savedSplit() {
        let split = valuator.savedSplit(of: january)
        #expect(split.saved == 1450)
        #expect(split.market == 250)
        #expect(split.other == 0)
        #expect(split.lost == 0)
    }

    @Test func savingsRate() throws {
        let rate = try #require(valuator.savingsRate(from: "2025-01-01", through: "2025-01-31"))
        #expect(rate.from == "2024-12-31")
        #expect(rate.through == "2025-01-31")
        #expect(rate.moneyInOut.moneyIn == 4000)
        #expect(rate.moneyInOut.moneyOut == 3550)
        #expect(rate.moneyInOut.moneyOutPerYear == d("41798.39"))
        #expect(rate.pensionContributions == 300)
        #expect(rate.tax == 0)
        #expect(rate.income == 4300)
        #expect(rate.savedByAccount == ["current": -550, "card": 200, "broker": 1000, "mortgage": 500,
                                        "pension": 300])
        #expect(rate.saved == 1450)
        #expect(rate.spent == 2850)
        #expect(rate.spentPerYear == d("33556.45"))
        #expect(rate.rate == Decimal(1450) / 4300)
        #expect(rate.rate?.rounded(2) == d("0.34"))
        #expect(rate.noRate == nil)
        #expect(rate.isPriced)
    }

    /// Over the whole year, as `retire spending --year 2025` asks for it:
    /// the values still cover January only, so a year's spending is
    /// January's scaled by its 31 days, as money out a year is.
    @Test func savingsRateOverTheYear() throws {
        let rate = try #require(valuator.savingsRate(from: "2025-01-01", through: "2025-12-31"))
        #expect(rate.spent == 2850)
        #expect(rate.moneyInOut.moneyOutPerYear == d("41798.39"))
        #expect(rate.spentPerYear == d("33556.45"))
    }

    /// A deposit of 1,000 to the broker on 15 February, after the current
    /// account's last value: what the current account paid for it isn't
    /// recorded yet, so the year's pay, which ends on 31 January, leaves it
    /// out. Counted through 31 December, it would be saved and the year's
    /// spent 1,850 (21,782.26 a year).
    @Test func aDepositAfterThePaysLastValue() throws {
        var library = try ReferenceLedger.fiveAccounts.library()
        library.upsert(Trade(account: "broker", date: "2025-02-15", id: "dep-feb", type: .deposit, amount: 1000))
        let valuator = Valuator(library: library)
        let rate = try #require(valuator.savingsRate(from: "2025-01-01", through: "2025-12-31"))
        #expect(rate.from == "2024-12-31")
        #expect(rate.payThrough == "2025-01-31")
        #expect(rate.savedByAccount["broker"] == 1000)
        #expect(rate.saved == 1450)
        #expect(rate.spent == 2850)
        #expect(rate.spentPerYear == d("33556.45"))
    }

    @Test func moneyInOutSeries() throws {
        let series = valuator.moneyInOutSeries(.months, through: "2025-01-31")
        #expect(series.periods.count == 1)
        let january = try #require(series.periods.first)
        #expect(january.from == "2025-01-01")
        #expect(january.cameIn == 4300)
        #expect(january.saved == 1450)
        #expect(january.spent == 2850)
        #expect(!january.coversMore(.months))
        let bars = try #require(january.bars)
        #expect(bars.cameIn == [.init(part: .moneyIn, from: 0, to: 4000), .init(part: .pension, from: 4000, to: 4300)])
        #expect(bars.wentOut == [.init(part: .spent, from: 0, to: 2850)])
        #expect(bars.top == 4300)
        #expect(bars.bottom == 0)
    }

    @Test func moneySources() {
        let sources = valuator.moneySources(.months, through: "2025-01-31")
        #expect(sources.points == [
            MoneySourcesPoint(date: "2024-12-31", total: 33900, startedWith: 33900, saved: 0),
            MoneySourcesPoint(date: "2025-01-31", total: 35100, startedWith: 33900, saved: 950),
        ])
        #expect(sources.points.last?.markets == 250)
    }

    @Test func changeThisYear() throws {
        let year = try #require(valuator.changeThisYear(asOf: "2025-01-31"))
        #expect(year.from == "2024-12-31")
        #expect(year.total.change == 1700)
        #expect(year.total.saved == 1450)
        #expect(year.total.market == 250)
        #expect(year.total.other == 0)
    }

    @Test func theBrokersTrades() throws {
        let ledger = try #require(valuator.ledger(for: "broker"))
        #expect(ledger.positions(on: "2025-01-31") == [Position(instrument: "world-fund", quantity: 100,
                                                                  costBasis: 8000)])
        #expect(valuator.tradeCash(of: "broker", on: "2025-01-31") == 1000)
    }
}
