import Foundation
import Model
import Testing
import TestSupport
import Tracker

/// How much you've been saving (PLANNER.md, "Continue as you have"),
/// worked out by hand.
struct SavingPaceTests {
    /// A current account valued at each month end through 30 Sep 2026,
    /// from 10,000 a month before the oldest, with `flows[k]` added in the
    /// month `k` months before September (the oldest last).
    private func library(flows: [Decimal]) -> Library {
        var library = Library(accounts: [
            Account(id: "current", name: "Current", kind: .cash, currency: .eur, opened: "2020-01-01"),
        ])
        let months = flows.count
        var balance: Decimal = 10_000
        library.upsert(Valuation(account: "current", date: SavingPace.monthEnd(months, before: "2026-09-30"),
                                 balance: balance, flow: 0))
        for back in (0..<months).reversed() {
            let flow = flows[back]
            balance += flow
            library.upsert(Valuation(account: "current", date: SavingPace.monthEnd(back, before: "2026-09-30"),
                                     balance: balance, flow: flow))
        }
        return library
    }

    @Test func monthEnds() {
        #expect(SavingPace.monthEnd(0, before: "2026-09-30") == "2026-09-30")
        #expect(SavingPace.monthEnd(1, before: "2026-09-30") == "2026-08-31")
        #expect(SavingPace.monthEnd(7, before: "2026-09-30") == "2026-02-28")
        #expect(SavingPace.monthEnd(1, before: "2026-10-15") == "2026-09-15")
        #expect(SavingPace.monthEnd(1, before: "2026-03-30") == "2026-02-28")
        #expect(SavingPace.monthEnd(2, before: "2026-03-30") == "2026-01-30")
    }

    /// 1,000 a month, and 20,000 once in March: the usual month is 1,000,
    /// and March is counted as one.
    @Test func anUnusualMonthCountsAsAUsualOne() throws {
        var flows = [Decimal](repeating: 1_000, count: 12)
        flows[6] = 20_000
        let pace = try #require(Valuator(library: library(flows: flows)).savingPace(asOf: "2026-10-10"))
        #expect(pace.asOf == "2026-09-30")
        #expect(pace.months.count == 12)
        #expect(pace.months.first?.end == "2025-10-31")
        #expect(pace.months.last?.end == "2026-09-30")
        #expect(pace.months.map(\.newMoney) == Array(flows.reversed()))
        #expect(pace.unusualMonths.map(\.end) == ["2026-03-31"])
        #expect(pace.usualMonth == 1_000)
        #expect(pace.perYear == 12_000)
        #expect(pace.byAccount == ["current": 31_000])
        #expect(pace.range == nil)
        #expect(!pace.isScaled)
        #expect(!pace.isInTodaysMoney)
        #expect(pace.isComplete)
        #expect(pace.leftOut.isEmpty)
    }

    /// Taking out 20,000 is as unusual as putting it in.
    @Test func aMonthFarBelowIsUnusualToo() throws {
        var flows = [Decimal](repeating: 1_000, count: 12)
        flows[2] = -20_000
        let pace = try #require(Valuator(library: library(flows: flows)).savingPace(asOf: "2026-09-30"))
        #expect(pace.unusualMonths.map(\.end) == ["2026-07-31"])
        #expect(pace.perYear == 12_000)
    }

    /// Five months of history give a pace scaled to a year; two don't.
    /// 1,500 is less than twice the usual 1,000: it counts as it is.
    @Test func fewerMonthsAreScaledToAYear() throws {
        let pace = try #require(Valuator(library: library(flows: [1_000, 1_000, 1_500, 1_000, 1_000]))
            .savingPace(asOf: "2026-09-30"))
        #expect(pace.months.count == 5)
        #expect(pace.isScaled)
        #expect(pace.unusualMonths.isEmpty)
        #expect(pace.perYear == 13_200)
        #expect(pace.byAccount == ["current": 13_200])
        #expect(Valuator(library: library(flows: [1_000, 1_000])).savingPace(asOf: "2026-09-30") == nil)
    }

    /// A quarterly check-in's new money is spread over its days: 3,000
    /// from 30 Jun to 30 Sep is 31, 31 and 30 of 92 days.
    @Test func anIntervalIsSpreadOverItsDays() throws {
        var library = Library(accounts: [
            Account(id: "current", name: "Current", kind: .cash, currency: .eur, opened: "2020-01-01"),
        ])
        library.upsert(Valuation(account: "current", date: "2025-09-30", balance: 10_000, flow: 0))
        library.upsert(Valuation(account: "current", date: "2025-12-31", balance: 10_000, flow: 0))
        library.upsert(Valuation(account: "current", date: "2026-06-30", balance: 10_000, flow: 0))
        library.upsert(Valuation(account: "current", date: "2026-09-30", balance: 13_000, flow: 3_000))
        let pace = try #require(Valuator(library: library).savingPace(asOf: "2026-09-30"))
        let months = pace.months.suffix(3).map { $0.newMoney.rounded(scale: 2) }
        #expect(months == [d("1010.87"), d("1010.87"), d("978.26")])
        #expect(pace.months.prefix(9).allSatisfy { $0.newMoney == 0 })
        // The usual month is 0: saving once a quarter is how you save.
        #expect(pace.usualMonth == 0)
        #expect(pace.unusualMonths.isEmpty)
        #expect(pace.perYear.rounded(scale: 2) == 3_000)
    }

    /// Saving 3,000 every third month, with a check-in every month: the
    /// usual month is 0, and no month is unusual.
    @Test func savingEveryThirdMonth() throws {
        let flows = (0..<12).map { $0.isMultiple(of: 3) ? Decimal(3_000) : 0 }
        let pace = try #require(Valuator(library: library(flows: flows)).savingPace(asOf: "2026-09-30"))
        #expect(pace.usualMonth == 0)
        #expect(pace.unusualMonths.isEmpty)
        #expect(pace.perYear == 12_000)
    }

    /// A month that saves more than twice the usual one is unusual only
    /// when it's at least 1% of plan assets too.
    @Test func unusualOnlyFromOnePercentOfPlanAssets() throws {
        var flows = [Decimal](repeating: 10, count: 12)
        flows[4] = 50
        // Plan assets: 10,000 + 11 × 10 + 50 = 10,160; 1% is 101.60.
        let small = try #require(Valuator(library: library(flows: flows)).savingPace(asOf: "2026-09-30"))
        #expect(small.unusualMonths.isEmpty)
        #expect(small.perYear == 160)
        flows[4] = 500
        let large = try #require(Valuator(library: library(flows: flows)).savingPace(asOf: "2026-09-30"))
        #expect(large.unusualMonths.map(\.end) == ["2026-05-31"])
        #expect(large.perYear == 120)
    }

    /// Money moved from the current account to a broker cancels out.
    @Test func moneyMovedBetweenPlanAssetsCancelsOut() throws {
        var library = self.library(flows: [Decimal](repeating: 1_000, count: 12))
        library.accounts["savings"] = Account(id: "savings", name: "Savings", kind: .savings, currency: .eur,
                                              opened: "2020-01-01")
        library.upsert(Valuation(account: "savings", date: "2025-09-30", balance: 0, flow: 0))
        library.upsert(Valuation(account: "savings", date: "2026-08-31", balance: 0, flow: 0))
        library.upsert(Valuation(account: "savings", date: "2026-09-30", balance: 5_000, flow: 5_000))
        library.upsert(Valuation(account: "current", date: "2026-09-30", balance: 17_000, flow: -4_000))
        let pace = try #require(Valuator(library: library).savingPace(asOf: "2026-09-30"))
        #expect(pace.months.last?.newMoney == 1_000)
        // September's 4,000 moved comes off both: the current account's
        // −4,000 entirely, and 4,000 of the savings account's 5,000.
        #expect(pace.byAccount == ["current": 11_000, "savings": 1_000])
    }

    /// Money moved into an account valued once a year cancels out too: the
    /// current account's −3,000 in September isn't left against 4,000
    /// spread over the year.
    @Test func moneyMovedIntoAnAccountValuedLessOftenCancelsOut() throws {
        var flows = [Decimal](repeating: 1_000, count: 12)
        flows[0] = -3_000
        var library = self.library(flows: flows)
        library.accounts["savings"] = Account(id: "savings", name: "Savings", kind: .savings, currency: .eur,
                                              opened: "2020-01-01")
        library.upsert(Valuation(account: "savings", date: "2025-09-30", balance: 0, flow: 0))
        library.upsert(Valuation(account: "savings", date: "2026-09-30", balance: 4_000, flow: 4_000))
        let pace = try #require(Valuator(library: library).savingPace(asOf: "2026-09-30"))
        // The 1,000 left of the savings account's 4,000, by days of the year.
        #expect(pace.months.last?.newMoney.rounded(scale: 2) == d("82.19"))
        #expect(pace.unusualMonths.isEmpty)
        #expect(pace.perYear.rounded(scale: 2) == 12_000)
        #expect(pace.byAccount.mapValues { $0.rounded(scale: 2) } == ["current": 11_000, "savings": 1_000])
    }

    /// A pension fund valued each quarter, with 3,000 recorded each time,
    /// saved over the quarter, not all in its last month, while the
    /// current account is valued every month.
    @Test func anAccountValuedLessOftenIsSpreadOverItsOwnInterval() throws {
        var library = self.library(flows: [Decimal](repeating: 1_000, count: 12))
        library.accounts["pension"] = Account(id: "pension", name: "Pension", kind: .pensionFund, currency: .eur,
                                              opened: "2020-01-01")
        library.upsert(Valuation(account: "pension", date: "2025-09-30", balance: 10_000, flow: 0))
        for (date, balance) in [("2025-12-31", 13_000), ("2026-03-31", 16_000), ("2026-06-30", 19_000),
                                ("2026-09-30", 22_000)] as [(CalendarDate, Decimal)] {
            library.upsert(Valuation(account: "pension", date: date, balance: balance, flow: 3_000))
        }
        let pace = try #require(Valuator(library: library).savingPace(asOf: "2026-09-30"))
        // Each quarter's 3,000 by its months' days: 31, 30 and 31 of 92 from October.
        let pension = ["1010.87", "978.26", "1010.87", "1033.33", "933.33", "1033.33",
                       "989.01", "1021.98", "989.01", "1010.87", "1010.87", "978.26"].map { 1_000 + d($0) }
        #expect(pace.months.map { $0.newMoney.rounded(scale: 2) } == pension)
        #expect(pace.unusualMonths.isEmpty)
        #expect(pace.byAccount["pension"]?.rounded(scale: 2) == 12_000)
        #expect(pace.leftOut.isEmpty)
    }

    /// A trades account's deposit after a long quiet stretch counts at the
    /// check-in it was made before, not spread back to its last trade.
    @Test func aTradesAccountsDepositStaysInItsMonth() throws {
        var library = self.library(flows: [Decimal](repeating: 1_000, count: 12))
        library.accounts["broker"] = Account(id: "broker", name: "Broker", kind: .brokerage, currency: .eur,
                                             opened: "2024-01-01", valuation: .trades)
        library.upsert(Trade(account: "broker", date: "2024-09-01", id: "first", type: .deposit, amount: 1_000))
        library.upsert(Trade(account: "broker", date: "2026-09-15", id: "second", type: .deposit, amount: 12_000))
        let pace = try #require(Valuator(library: library).savingPace(asOf: "2026-09-30"))
        #expect(pace.months.last?.newMoney == 13_000)
        #expect(pace.months.dropLast().allSatisfy { $0.newMoney == 1_000 })
        #expect(pace.byAccount["broker"] == 12_000)
    }

    /// In today's money: prices rose 10% by the last check-in.
    @Test func inTodaysMoney() throws {
        let index = InflationIndex([IndexRecord(index: .hicpIT, date: "2025-09-30", value: 100),
                                    IndexRecord(index: .hicpIT, date: "2026-09-30", value: 110)],
                                   index: .hicpIT)
        let pace = try #require(Valuator(library: library(flows: [Decimal](repeating: 1_000, count: 12)))
            .savingPace(asOf: "2026-09-30", inflation: index))
        #expect(pace.isInTodaysMoney)
        #expect(pace.months.first?.newMoney == 1_100)
        #expect(pace.months.last?.newMoney == 1_000)
        #expect(pace.perYear == 13_100)
    }

    /// An index whose first value falls inside the months can't put them
    /// all in today's money: none is converted.
    @Test func anIndexStartingLateLeavesEveryMonthAsItWas() throws {
        let index = InflationIndex([IndexRecord(index: .hicpIT, date: "2026-03-31", value: 100),
                                    IndexRecord(index: .hicpIT, date: "2026-09-30", value: 110)],
                                   index: .hicpIT)
        let pace = try #require(Valuator(library: library(flows: [Decimal](repeating: 1_000, count: 12)))
            .savingPace(asOf: "2026-09-30", inflation: index))
        #expect(!pace.isInTodaysMoney)
        #expect(pace.months.allSatisfy { $0.newMoney == 1_000 })
        #expect(pace.perYear == 12_000)
    }

    /// A holding without a price in the months makes the pace incomplete.
    @Test func aMissingPriceMakesItIncomplete() throws {
        var library = self.library(flows: [Decimal](repeating: 1_000, count: 12))
        library.accounts["broker"] = Account(id: "broker", name: "Broker", kind: .brokerage, currency: .eur,
                                             opened: "2020-01-01")
        library.upsert(Valuation(account: "broker", date: "2026-08-31", cash: 0,
                                 positions: [Position(instrument: "unpriced", quantity: 1)], flow: 0))
        library.upsert(Valuation(account: "broker", date: "2026-09-30", cash: 0,
                                 positions: [Position(instrument: "unpriced", quantity: 1)], flow: 0))
        let pace = try #require(Valuator(library: library).savingPace(asOf: "2026-09-30"))
        #expect(!pace.isComplete)
        #expect(pace.perYear == 12_000)
    }

    /// The range of the 12 months ending at each of the last month ends:
    /// with 1,500 in the oldest of 13 months, 12,000 to 12,500.
    @Test func theRangeOverThePastYear() throws {
        var flows = [Decimal](repeating: 1_000, count: 13)
        flows[12] = 1_500
        let pace = try #require(Valuator(library: library(flows: flows)).savingPace(asOf: "2026-09-30"))
        #expect(pace.perYear == 12_000)
        #expect(pace.range == 12_000...12_500)
    }

    /// A pension fund without recorded new money counts what the main plan
    /// pays in: it's left out of the pace.
    @Test func newMoneyFromThePlanIsLeftOut() throws {
        var library = self.library(flows: [Decimal](repeating: 1_000, count: 12))
        library.settings = LibrarySettings(person: Person(birthDate: "1988-04-12"), mainPlan: "base")
        library.plans["base"] = PlanDocument(
            id: "base", name: "Base", retirement: PlanRetirement(age: .age(55)),
            spending: PlanSpending(working: 30_000, retired: 30_000),
            contributions: [PlanContribution(account: "pension", perYear: 5_000)])
        library.accounts["pension"] = Account(id: "pension", name: "Pension", kind: .pensionFund, currency: .eur,
                                              opened: "2020-01-01")
        library.upsert(Valuation(account: "pension", date: "2025-09-30", balance: 10_000))
        library.upsert(Valuation(account: "pension", date: "2026-09-30", balance: 16_000))
        let pace = try #require(Valuator(library: library).savingPace(asOf: "2026-09-30"))
        #expect(pace.leftOut == ["pension"])
        #expect(pace.perYear == 12_000)
        #expect(pace.byAccount == ["current": 12_000])
    }
}
