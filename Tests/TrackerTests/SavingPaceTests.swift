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
        // The usual month is 0, so the three are unusual against 1% of
        // 13,000 (130), and the pace is nothing.
        #expect(pace.unusualMonths.count == 3)
        #expect(pace.perYear == 0)
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
        #expect(pace.byAccount == ["current": 7_000, "savings": 5_000])
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
