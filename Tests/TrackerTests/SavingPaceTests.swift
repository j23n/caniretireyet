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

    /// A month that saves nothing isn't unusual, even with no plan assets
    /// to judge it by.
    @Test func aMonthSavingNothingIsntUnusual() {
        let pace = SavingPace.pace(of: [1_000, 0, 1_000], planAssets: 0)
        #expect(pace.unusual == [false, false, false])
        #expect(pace.perYear == 8_000)
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

    /// Saving 3,000 every third month, with a check-in every month that
    /// records nothing in between: each 3,000 is saved over the three
    /// months since the one before, so the usual month is about 1,000 and
    /// no month is unusual.
    @Test func savingEveryThirdMonth() throws {
        let flows = (0..<12).map { $0.isMultiple(of: 3) ? Decimal(3_000) : 0 }
        let pace = try #require(Valuator(library: library(flows: flows)).savingPace(asOf: "2026-09-30"))
        // From 30 Jun to 30 Sep: 31, 31 and 30 of 92 days.
        let months = pace.months.suffix(3).map { $0.newMoney.rounded(scale: 2) }
        #expect(months == [d("1010.87"), d("1010.87"), d("978.26")])
        #expect(pace.usualMonth.rounded(scale: 2) == d("1005.43"))
        #expect(pace.unusualMonths.isEmpty)
        #expect(pace.perYear.rounded(scale: 2) == 12_000)
        #expect(pace.carriedForward.isEmpty)
    }

    /// A pension fund paid 3,000 a quarter and marked unchanged in the
    /// months between, with 130,000 in it: the quarter's 3,000 isn't an
    /// unusual month, so the pace is 24,000, not 12,000.
    @Test func aQuarterlyPaymentMarkedUnchangedBetweenIsntUnusual() throws {
        var library = self.library(flows: [Decimal](repeating: 1_000, count: 12))
        library.accounts["pension"] = Account(id: "pension", name: "Pension", kind: .pensionFund, currency: .eur,
                                              opened: "2020-01-01")
        var balance: Decimal = 130_000
        library.upsert(Valuation(account: "pension", date: "2025-09-30", balance: balance, flow: 0))
        for back in (0..<12).reversed() {
            let flow: Decimal = back.isMultiple(of: 3) ? 3_000 : 0
            balance += flow
            library.upsert(Valuation(account: "pension", date: SavingPace.monthEnd(back, before: "2026-09-30"),
                                     balance: balance, flow: flow))
        }
        let pace = try #require(Valuator(library: library).savingPace(asOf: "2026-09-30"))
        #expect(pace.unusualMonths.isEmpty)
        #expect(pace.perYear.rounded(scale: 2) == 24_000)
        #expect(pace.byAccount["pension"]?.rounded(scale: 2) == 12_000)
        #expect(pace.carriedForward.isEmpty)
    }

    /// 500 into a savings account every quarter, then 30,000 in
    /// September, or 20,000 taken out: neither is like the usual 500, so
    /// it stays in September, which is unusual.
    @Test func aOneOffAmongRegularPaymentsStaysInItsMonth() throws {
        for oneOff: Decimal in [30_000, -20_000] {
            var library = self.library(flows: [Decimal](repeating: 1_000, count: 12))
            library.accounts["savings"] = Account(id: "savings", name: "Savings", kind: .savings,
                                                  currency: .eur, opened: "2020-01-01")
            var balance: Decimal = 50_000
            library.upsert(Valuation(account: "savings", date: "2025-09-30", balance: balance, flow: 0))
            for back in (0..<12).reversed() {
                let flow: Decimal = back == 0 ? oneOff : back.isMultiple(of: 3) ? 500 : 0
                balance += flow
                library.upsert(Valuation(account: "savings", date: SavingPace.monthEnd(back, before: "2026-09-30"),
                                         balance: balance, flow: flow))
            }
            let pace = try #require(Valuator(library: library).savingPace(asOf: "2026-09-30"))
            #expect(pace.months.last?.newMoney == 1_000 + oneOff)
            #expect(pace.unusualMonths.map(\.end) == ["2026-09-30"])
        }
    }

    /// A pension fund paid 3,000 a quarter a month before each quarter's
    /// end, and marked unchanged in between: it goes on saving after its
    /// latest payment, on 31 Aug, so the year comes to about 12,000.
    @Test func aQuarterlyPaymentGoesOnAfterTheLatestOne() throws {
        var library = self.library(flows: [Decimal](repeating: 1_000, count: 18))
        library.accounts["pension"] = Account(id: "pension", name: "Pension", kind: .pensionFund, currency: .eur,
                                              opened: "2020-01-01")
        var balance: Decimal = 130_000
        library.upsert(Valuation(account: "pension", date: SavingPace.monthEnd(18, before: "2026-09-30"),
                                 balance: balance, flow: 0))
        for back in (0..<18).reversed() {
            let flow: Decimal = back % 3 == 1 ? 3_000 : 0
            balance += flow
            library.upsert(Valuation(account: "pension", date: SavingPace.monthEnd(back, before: "2026-09-30"),
                                     balance: balance, flow: flow))
        }
        let pace = try #require(Valuator(library: library).savingPace(asOf: "2026-09-30"))
        #expect(pace.carriedForward == ["pension"])
        let pension = try #require(pace.byAccount["pension"])
        #expect(abs(pension - 12_000) < 50, "\(pension)")
        #expect(pace.unusualMonths.isEmpty)
    }

    /// A pension fund paid 3,000 a quarter through 30 Jun 2025 and not
    /// valued since: carried forward to 29 Sep 2025, before the months, so
    /// it isn't listed.
    @Test func aCarryEndingBeforeTheMonthsIsntListed() throws {
        var library = self.library(flows: [Decimal](repeating: 1_000, count: 24))
        library.accounts["pension"] = Account(id: "pension", name: "Pension", kind: .pensionFund, currency: .eur,
                                              opened: "2020-01-01")
        library.upsert(Valuation(account: "pension", date: "2024-09-30", balance: 10_000, flow: 0))
        library.upsert(Valuation(account: "pension", date: "2024-12-31", balance: 13_000, flow: 3_000))
        library.upsert(Valuation(account: "pension", date: "2025-03-31", balance: 16_000, flow: 3_000))
        library.upsert(Valuation(account: "pension", date: "2025-06-30", balance: 19_000, flow: 3_000))
        let pace = try #require(Valuator(library: library).savingPace(asOf: "2026-09-30"))
        #expect(pace.carriedForward.isEmpty)
        #expect(pace.perYear == 12_000)
    }

    /// A pension fund valued monthly, paid 3,000 a quarter through 31 Mar
    /// and nothing since: its next payment is overdue, so it isn't carried
    /// forward, and its year is the 6,000 paid.
    @Test func aRegularPaymentThatStoppedIsntCarriedForward() throws {
        var library = self.library(flows: [Decimal](repeating: 1_000, count: 12))
        library.accounts["pension"] = Account(id: "pension", name: "Pension", kind: .pensionFund, currency: .eur,
                                              opened: "2020-01-01")
        var balance: Decimal = 10_000
        for back in (0...21).reversed() {
            let date = SavingPace.monthEnd(back, before: "2026-09-30")
            let flow: Decimal = back >= 6 && back % 3 == 0 ? 3_000 : 0
            balance += flow
            library.upsert(Valuation(account: "pension", date: date, balance: balance, flow: flow))
        }
        let pace = try #require(Valuator(library: library).savingPace(asOf: "2026-09-30"))
        #expect(pace.carriedForward.isEmpty)
        #expect(pace.byAccount["pension"]?.rounded(scale: 2) == 6_000)
        #expect(abs(pace.perYear - 18_000) < d("0.01"), "\(pace.perYear)")
    }

    /// A pension fund valued once a year, with 6,000 paid in at its
    /// statement on 20 Sep 2025, before the months: it goes on at that rate
    /// from its statement for 335 days, 325 of them in the months.
    @Test func aStatementBeforeTheMonthsGoesOnIntoThem() throws {
        var library = self.library(flows: [Decimal](repeating: 1_000, count: 12))
        library.accounts["pension"] = Account(id: "pension", name: "Pension", kind: .pensionFund, currency: .eur,
                                              opened: "2020-01-01")
        library.upsert(Valuation(account: "pension", date: "2024-10-20", balance: 20_000, flow: 0))
        library.upsert(Valuation(account: "pension", date: "2025-09-20", balance: 26_000, flow: 6_000))
        let pace = try #require(Valuator(library: library).savingPace(asOf: "2026-09-30"))
        #expect(pace.months.count == 12)
        #expect(pace.carriedForward == ["pension"])
        let pension = try #require(pace.byAccount["pension"])
        #expect(abs(pension - 6_000 * 325 / 335) < d("0.01"), "\(pension)")
        #expect(abs(pace.perYear - 12_000 - 6_000 * 325 / 335) < d("0.01"), "\(pace.perYear)")
    }

    /// A savings account valued once, at 20,000, and closed on 15 Sep: the
    /// money taken out is in September, which is unusual, not spread over
    /// the year since its value. Closed on the day of a check-in, 30 Jun,
    /// it's open that day, so the money is taken out in July.
    @Test(arguments: [("2026-09-15", "2026-09-30"), ("2026-06-30", "2026-07-31")] as [(CalendarDate, CalendarDate)])
    func aClosingStaysAtItsCheckIn(closed: CalendarDate, month: CalendarDate) throws {
        var library = self.library(flows: [Decimal](repeating: 1_000, count: 12))
        library.accounts["savings"] = Account(id: "savings", name: "Savings", kind: .savings, currency: .eur,
                                              opened: "2020-01-01", closed: closed)
        library.upsert(Valuation(account: "savings", date: "2025-09-30", balance: 20_000, flow: 0))
        let pace = try #require(Valuator(library: library).savingPace(asOf: "2026-09-30"))
        #expect(pace.unusualMonths.map(\.end) == [month])
        #expect(pace.perYear == 12_000)
    }

    /// A pension fund valued once a year, on 31 Mar, with 6,000 paid in:
    /// it goes on saving at that rate from its statement to 30 Sep, so the
    /// year's 6,000 isn't cut to the 182 days before its statement.
    @Test func anAccountValuedOnceAYearIsCarriedForward() throws {
        var library = self.library(flows: [Decimal](repeating: 1_000, count: 12))
        library.accounts["pension"] = Account(id: "pension", name: "Pension", kind: .pensionFund, currency: .eur,
                                              opened: "2020-01-01")
        library.upsert(Valuation(account: "pension", date: "2025-03-31", balance: 20_000, flow: 0))
        library.upsert(Valuation(account: "pension", date: "2026-03-31", balance: 26_000, flow: 6_000))
        let pace = try #require(Valuator(library: library).savingPace(asOf: "2026-09-30"))
        #expect(pace.carriedForward == ["pension"])
        #expect(pace.byAccount["pension"]?.rounded(scale: 2) == 6_000)
        #expect(pace.byAccount["current"] == 12_000)
        // April to September: 6,000 × 30/365 in April.
        #expect(pace.months[6].newMoney.rounded(scale: 2) == d("1493.15"))
        #expect(pace.perYear.rounded(scale: 2) == 18_000)
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
    /// check-in it was made before, not spread back to its last trade or
    /// its deposit before.
    @Test func aTradesAccountsDepositStaysInItsMonth() throws {
        var library = self.library(flows: [Decimal](repeating: 1_000, count: 12))
        library.accounts["broker"] = Account(id: "broker", name: "Broker", kind: .brokerage, currency: .eur,
                                             opened: "2024-01-01", valuation: .trades)
        library.upsert(Trade(account: "broker", date: "2024-09-01", id: "first", type: .deposit, amount: 1_000))
        library.upsert(Trade(account: "broker", date: "2025-10-15", id: "second", type: .deposit, amount: 100))
        library.upsert(Trade(account: "broker", date: "2026-09-15", id: "third", type: .deposit, amount: 12_000))
        let pace = try #require(Valuator(library: library).savingPace(asOf: "2026-09-30"))
        #expect(pace.months.first?.newMoney == 1_100)
        #expect(pace.months.last?.newMoney == 13_000)
        #expect(pace.months.dropFirst().dropLast().allSatisfy { $0.newMoney == 1_000 })
        #expect(pace.unusualMonths.map(\.end) == ["2026-09-30"])
        #expect(pace.byAccount["broker"] == 12_100)
        #expect(pace.carriedForward.isEmpty)
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
                                             opened: "2026-08-31")
        library.upsert(Valuation(account: "broker", date: "2026-08-31", cash: 0,
                                 positions: [Position(instrument: "unpriced", quantity: 1)], flow: 0))
        library.upsert(Valuation(account: "broker", date: "2026-09-30", cash: 0,
                                 positions: [Position(instrument: "unpriced", quantity: 1)], flow: 0))
        let pace = try #require(Valuator(library: library).savingPace(asOf: "2026-09-30"))
        #expect(!pace.isComplete)
        #expect(pace.perYear == 12_000)
    }

    /// An account opened inside the months, with something in it at its
    /// first record: what it held then isn't new money, the months before
    /// it aren't missing anything, and a pension fund's first value isn't
    /// taken from the plan. Opened before its first record, with no
    /// check-in between, it isn't missing any month either.
    @Test(arguments: ["2026-03-31", "2026-03-15"] as [CalendarDate])
    func anAccountWhoseRecordsStartInsideTheMonths(opened: CalendarDate) throws {
        var library = self.library(flows: [Decimal](repeating: 1_000, count: 12))
        library.accounts["wallet"] = Account(id: "wallet", name: "Wallet", kind: .crypto, currency: .eur,
                                             opened: opened)
        library.upsert(PriceRecord(instrument: "btc", date: "2026-03-31", price: 90_000, currency: .eur))
        library.upsert(Valuation(account: "wallet", date: "2026-03-31", cash: 0,
                                 positions: [Position(instrument: "btc", quantity: d("0.4"))]))
        library.settings = LibrarySettings(person: Person(birthDate: "1988-04-12"), mainPlan: "base")
        library.plans["base"] = PlanDocument(
            id: "base", name: "Base", retirement: PlanRetirement(age: .age(55)),
            spending: PlanSpending(working: 30_000, retired: 30_000),
            contributions: [PlanContribution(account: "pension", perYear: 5_000)])
        library.accounts["pension"] = Account(id: "pension", name: "Pension", kind: .pensionFund, currency: .eur,
                                              opened: opened)
        library.upsert(Valuation(account: "pension", date: "2026-03-31", balance: 10_000))
        let pace = try #require(Valuator(library: library).savingPace(asOf: "2026-09-30"))
        #expect(pace.months.count == 12)
        #expect(pace.months.allSatisfy { $0.newMoney == 1_000 })
        #expect(pace.perYear == 12_000)
        #expect(pace.byAccount == ["current": 12_000])
        #expect(pace.leftOut.isEmpty)
        #expect(pace.isComplete)
    }

    /// A pension fund valued a year ago, and a current account only since
    /// April: the months start in April, when every plan asset is tracked,
    /// not with the pension's older record.
    @Test func theMonthsStartWhenEveryPlanAssetIsTracked() throws {
        var library = Library(accounts: [
            Account(id: "current", name: "Current", kind: .cash, currency: .eur, opened: "2020-01-01"),
            Account(id: "pension", name: "Pension", kind: .pensionFund, currency: .eur, opened: "2020-01-01"),
        ])
        library.upsert(Valuation(account: "pension", date: "2025-09-30", balance: 10_000, flow: 0))
        library.upsert(Valuation(account: "pension", date: "2026-09-30", balance: 10_000, flow: 0))
        var balance: Decimal = 10_000
        library.upsert(Valuation(account: "current", date: "2026-04-30", balance: balance, flow: 0))
        for back in (0..<5).reversed() {
            balance += 1_000
            library.upsert(Valuation(account: "current", date: SavingPace.monthEnd(back, before: "2026-09-30"),
                                     balance: balance, flow: 1_000))
        }
        let pace = try #require(Valuator(library: library).savingPace(asOf: "2026-09-30"))
        #expect(pace.months.count == 5)
        #expect(pace.months.first?.end == "2026-05-31")
        #expect(pace.isScaled)
        #expect(pace.perYear == 12_000)
    }

    /// 1,000 a month into the current account, and 20,000 into a pension
    /// fund in September, which is unusual: in the pace, September counts
    /// as the usual 1,000, split as September was, 1/21 to the current
    /// account and 20/21 to the pension fund.
    @Test func eachAccountsShareOfThePaceCountsAnUnusualMonthAsUsual() throws {
        var library = self.library(flows: [Decimal](repeating: 1_000, count: 12))
        library.accounts["pension"] = Account(id: "pension", name: "Pension", kind: .pensionFund, currency: .eur,
                                              opened: "2020-01-01")
        for back in (0...12).reversed() {
            let flow: Decimal = back == 0 ? 20_000 : 0
            library.upsert(Valuation(account: "pension", date: SavingPace.monthEnd(back, before: "2026-09-30"),
                                     balance: flow, flow: flow))
        }
        let pace = try #require(Valuator(library: library).savingPace(asOf: "2026-09-30"))
        #expect(pace.unusualMonths.map(\.end) == ["2026-09-30"])
        #expect(pace.perYear == 12_000)
        #expect(pace.byAccount["pension"] == 20_000)
        #expect(pace.byAccountInPace["pension"]?.rounded(scale: 2) == d("952.38"))
        #expect(pace.byAccountInPace["current"]?.rounded(scale: 2) == d("11047.62"))
        let shares = pace.byAccountInPace.values.reduce(Decimal(0), +)
        #expect(shares.rounded(scale: 2) == 12_000)
    }

    /// 500 a month into the current account and 1,000 into a pension fund,
    /// and in September 5,000 out of the current account, which is unusual:
    /// September counts as the usual 1,500, split as the usual months were,
    /// a third to the current account and two thirds to the pension fund.
    @Test func anUnusualMonthTakingMoneyOutIsSplitAsTheUsualMonths() throws {
        var flows = [Decimal](repeating: 500, count: 12)
        flows[0] = -5_000
        var library = self.library(flows: flows)
        library.accounts["pension"] = Account(id: "pension", name: "Pension", kind: .pensionFund, currency: .eur,
                                              opened: "2020-01-01")
        var balance: Decimal = 0
        for back in (0...12).reversed() {
            let flow: Decimal = back == 12 ? 0 : 1_000
            balance += flow
            library.upsert(Valuation(account: "pension", date: SavingPace.monthEnd(back, before: "2026-09-30"),
                                     balance: balance, flow: flow))
        }
        let pace = try #require(Valuator(library: library).savingPace(asOf: "2026-09-30"))
        #expect(pace.unusualMonths.map(\.end) == ["2026-09-30"])
        #expect(pace.perYear == 18_000)
        #expect(pace.byAccountInPace["pension"]?.rounded(scale: 2) == 12_000)
        #expect(pace.byAccountInPace["current"]?.rounded(scale: 2) == 6_000)
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

    /// The range in today's money, with an index from before the oldest of
    /// 13 months: prices rose 10% at the last check-in, so the months
    /// before it count 10% more, 13,100 to 13,750.
    @Test func theRangeInTodaysMoney() throws {
        var flows = [Decimal](repeating: 1_000, count: 13)
        flows[12] = 1_500
        let index = InflationIndex([IndexRecord(index: .hicpIT, date: "2025-08-31", value: 100),
                                    IndexRecord(index: .hicpIT, date: "2026-09-30", value: 110)],
                                   index: .hicpIT)
        let pace = try #require(Valuator(library: library(flows: flows)).savingPace(asOf: "2026-09-30",
                                                                                   inflation: index))
        #expect(pace.isInTodaysMoney)
        #expect(pace.perYear == 13_100)
        #expect(pace.range == 13_100...13_750)
    }

    /// A pension fund paid 3,000 a quarter, then 20,000 once on 30 Jun, and
    /// not valued since: the one-off isn't carried forward.
    @Test func aOneOffIsntCarriedForward() throws {
        var library = self.library(flows: [Decimal](repeating: 1_000, count: 12))
        library.accounts["pension"] = Account(id: "pension", name: "Pension", kind: .pensionFund, currency: .eur,
                                              opened: "2020-01-01")
        library.upsert(Valuation(account: "pension", date: "2025-09-30", balance: 10_000, flow: 0))
        for (date, balance, flow) in [("2025-12-31", 13_000, 3_000), ("2026-03-31", 16_000, 3_000),
                                      ("2026-06-30", 36_000, 20_000)] as [(CalendarDate, Decimal, Decimal)] {
            library.upsert(Valuation(account: "pension", date: date, balance: balance, flow: flow))
        }
        let pace = try #require(Valuator(library: library).savingPace(asOf: "2026-09-30"))
        #expect(pace.carriedForward.isEmpty)
        #expect(pace.byAccount["pension"]?.rounded(scale: 2) == 26_000)
    }

    /// A pension fund paid 1,500 on 31 Dec for the quarter, and not valued
    /// since: it's carried forward for one more quarter, to 2 Apr, not to
    /// September.
    @Test func carryingForwardStopsAfterAsLongAgain() throws {
        var library = self.library(flows: [Decimal](repeating: 1_000, count: 12))
        library.accounts["pension"] = Account(id: "pension", name: "Pension", kind: .pensionFund, currency: .eur,
                                              opened: "2020-01-01")
        library.upsert(Valuation(account: "pension", date: "2025-09-30", balance: 10_000, flow: 0))
        library.upsert(Valuation(account: "pension", date: "2025-12-31", balance: 11_500, flow: 1_500))
        let pace = try #require(Valuator(library: library).savingPace(asOf: "2026-09-30"))
        #expect(pace.carriedForward == ["pension"])
        #expect(pace.byAccount["pension"]?.rounded(scale: 2) == 3_000)
        #expect(pace.months.suffix(5).allSatisfy { $0.newMoney == 1_000 })
    }

    /// 500 into a savings account in each of October, November and December,
    /// then 500 again in September: it's spread over half as long again as
    /// the usual 31 days between payments, from 15 Aug, not back to December.
    @Test func aPaymentLongAfterTheOthersIsntSpreadBackToThem() throws {
        var library = self.library(flows: [Decimal](repeating: 1_000, count: 12))
        library.accounts["savings"] = Account(id: "savings", name: "Savings", kind: .savings, currency: .eur,
                                              opened: "2020-01-01")
        var balance: Decimal = 0
        library.upsert(Valuation(account: "savings", date: "2025-09-30", balance: balance, flow: 0))
        for back in (0..<12).reversed() {
            let flow: Decimal = back == 0 || back >= 9 ? 500 : 0
            balance += flow
            library.upsert(Valuation(account: "savings", date: SavingPace.monthEnd(back, before: "2026-09-30"),
                                     balance: balance, flow: flow))
        }
        let pace = try #require(Valuator(library: library).savingPace(asOf: "2026-09-30"))
        // 500 over the 46 days from 15 Aug: 16 in August, 30 in September.
        #expect(pace.months.suffix(2).map { $0.newMoney.rounded(scale: 2) } == [d("1173.91"), d("1326.09")])
        #expect(pace.months.dropFirst(3).dropLast(2).allSatisfy { $0.newMoney == 1_000 })
    }

    /// A pension fund valued on 20 Oct makes that the latest check-in: the
    /// current account, valued at each month end, goes on saving to it.
    @Test func aPartialLatestCheckInCarriesTheOthersForward() throws {
        var library = self.library(flows: [Decimal](repeating: 1_000, count: 13))
        library.accounts["pension"] = Account(id: "pension", name: "Pension", kind: .pensionFund, currency: .eur,
                                              opened: "2020-01-01")
        library.upsert(Valuation(account: "pension", date: "2025-10-20", balance: 10_000, flow: 0))
        library.upsert(Valuation(account: "pension", date: "2026-10-20", balance: 16_000, flow: 6_000))
        let pace = try #require(Valuator(library: library).savingPace(asOf: "2026-10-31"))
        #expect(pace.asOf == "2026-10-20")
        #expect(pace.carriedForward == ["current"])
        // 10 days of September's 1,000, 20 carried forward, and 30 of the
        // pension's 365.
        #expect(pace.months.last?.newMoney.rounded(scale: 2) == d("1493.15"))
    }

    /// A savings account emptied on 31 Mar and not valued since: taking
    /// the 5,000 out isn't carried forward.
    @Test func moneyTakenOutIsntCarriedForward() throws {
        var library = self.library(flows: [Decimal](repeating: 1_000, count: 12))
        library.accounts["savings"] = Account(id: "savings", name: "Savings", kind: .savings, currency: .eur,
                                              opened: "2020-01-01")
        library.upsert(Valuation(account: "savings", date: "2025-09-30", balance: 5_000, flow: 0))
        library.upsert(Valuation(account: "savings", date: "2026-03-31", balance: 0, flow: -5_000))
        let pace = try #require(Valuator(library: library).savingPace(asOf: "2026-09-30"))
        #expect(pace.carriedForward.isEmpty)
        #expect(pace.byAccount["savings"]?.rounded(scale: 2) == -5_000)
    }

    /// With 18 months and an index from 30 Jun 2025, the last 12 are in
    /// today's money, and there's no range, which would need the months
    /// before.
    @Test func anIndexCoveringOnlyThePaceLeavesOutTheRange() throws {
        let index = InflationIndex([IndexRecord(index: .hicpIT, date: "2025-06-30", value: 100),
                                    IndexRecord(index: .hicpIT, date: "2026-09-30", value: 100)],
                                   index: .hicpIT)
        let pace = try #require(Valuator(library: library(flows: [Decimal](repeating: 1_000, count: 18)))
            .savingPace(asOf: "2026-09-30", inflation: index))
        #expect(pace.isInTodaysMoney)
        #expect(pace.range == nil)
        #expect(pace.perYear == 12_000)
    }

    /// A savings account valued monthly, paid 200 in August and skipped
    /// in September: the 200 isn't repeated in September.
    @Test func anAccountSkippedAtTheLatestCheckInIsntCarriedForward() throws {
        var library = self.library(flows: [Decimal](repeating: 1_000, count: 12))
        library.accounts["savings"] = Account(id: "savings", name: "Savings", kind: .savings, currency: .eur,
                                              opened: "2020-01-01")
        library.upsert(Valuation(account: "savings", date: "2025-09-30", balance: 0, flow: 0))
        library.upsert(Valuation(account: "savings", date: "2026-07-31", balance: 0, flow: 0))
        library.upsert(Valuation(account: "savings", date: "2026-08-31", balance: 200, flow: 200))
        let pace = try #require(Valuator(library: library).savingPace(asOf: "2026-09-30"))
        #expect(pace.carriedForward.isEmpty)
        #expect(pace.byAccount["savings"] == 200)
        #expect(pace.perYear == 12_200)
    }

    /// A pension fund valued without new money and no main plan: its new
    /// money is missing, so it's listed as left out.
    @Test func anAccountWithoutRecordedNewMoneyOrAPlanIsLeftOut() throws {
        var library = self.library(flows: [Decimal](repeating: 1_000, count: 12))
        library.accounts["pension"] = Account(id: "pension", name: "Pension", kind: .pensionFund, currency: .eur,
                                              opened: "2020-01-01")
        library.upsert(Valuation(account: "pension", date: "2025-09-30", balance: 10_000))
        library.upsert(Valuation(account: "pension", date: "2026-09-30", balance: 16_000))
        let pace = try #require(Valuator(library: library).savingPace(asOf: "2026-09-30"))
        #expect(pace.leftOut == ["pension"])
        #expect(pace.byAccount == ["current": 12_000])
    }

    /// Accounts opened inside the months, with their first record after
    /// their opening day, are new: they don't shorten the months.
    @Test func anAccountOpenedInsideTheMonthsIsNew() throws {
        var library = self.library(flows: [Decimal](repeating: 1_000, count: 12))
        library.accounts["savings"] = Account(id: "savings", name: "Savings", kind: .savings, currency: .eur,
                                              opened: "2026-07-01")
        library.upsert(Valuation(account: "savings", date: "2026-07-31", balance: 500, flow: 500))
        library.accounts["broker"] = Account(id: "broker", name: "Broker", kind: .brokerage, currency: .eur,
                                             opened: "2026-09-01", valuation: .trades)
        library.upsert(Trade(account: "broker", date: "2026-09-10", id: "first", type: .deposit, amount: 1_000))
        let pace = try #require(Valuator(library: library).savingPace(asOf: "2026-09-30"))
        #expect(pace.months.count == 12)
        #expect(pace.byAccount["broker"] == 1_000)
    }

    /// 19,000 taken out of the current account at the check-in where the
    /// pension fund gets its quarterly 3,000: it isn't a transfer, so the
    /// 3,000 is still saved over the quarter.
    @Test func aLargeWithdrawalIsntMovedMoney() throws {
        var flows = [Decimal](repeating: 1_000, count: 12)
        flows[0] = -19_000
        var library = self.library(flows: flows)
        library.accounts["pension"] = Account(id: "pension", name: "Pension", kind: .pensionFund, currency: .eur,
                                              opened: "2020-01-01")
        var balance: Decimal = 130_000
        library.upsert(Valuation(account: "pension", date: "2025-09-30", balance: balance, flow: 0))
        for back in (0..<12).reversed() {
            let flow: Decimal = back.isMultiple(of: 3) ? 3_000 : 0
            balance += flow
            library.upsert(Valuation(account: "pension", date: SavingPace.monthEnd(back, before: "2026-09-30"),
                                     balance: balance, flow: flow))
        }
        let pace = try #require(Valuator(library: library).savingPace(asOf: "2026-09-30"))
        #expect(pace.byAccount["pension"]?.rounded(scale: 2) == 12_000)
        #expect(pace.unusualMonths.map(\.end) == ["2026-09-30"])
    }

    /// A pension fund with new money recorded at one check-in and taken
    /// from the plan at the next: the recorded 3,000 counts, the plan's
    /// doesn't, and the account is listed as left out.
    @Test func recordedNewMoneyCountsNextToTheLeftOut() throws {
        var library = self.library(flows: [Decimal](repeating: 1_000, count: 12))
        library.settings = LibrarySettings(person: Person(birthDate: "1988-04-12"), mainPlan: "base")
        library.plans["base"] = PlanDocument(
            id: "base", name: "Base", retirement: PlanRetirement(age: .age(55)),
            spending: PlanSpending(working: 30_000, retired: 30_000),
            contributions: [PlanContribution(account: "pension", perYear: 5_000)])
        library.accounts["pension"] = Account(id: "pension", name: "Pension", kind: .pensionFund, currency: .eur,
                                              opened: "2020-01-01")
        library.upsert(Valuation(account: "pension", date: "2025-09-30", balance: 10_000, flow: 0))
        library.upsert(Valuation(account: "pension", date: "2026-03-31", balance: 13_000, flow: 3_000))
        library.upsert(Valuation(account: "pension", date: "2026-09-30", balance: 16_000))
        let pace = try #require(Valuator(library: library).savingPace(asOf: "2026-09-30"))
        #expect(pace.leftOut == ["pension"])
        #expect(pace.byAccount.mapValues { $0.rounded(scale: 2) } == ["current": 12_000, "pension": 3_000])
        #expect(pace.perYear.rounded(scale: 2) == 15_000)
        #expect(pace.carriedForward.isEmpty)
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
