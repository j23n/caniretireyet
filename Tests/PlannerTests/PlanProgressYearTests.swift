import Foundation
import Model
@testable import Planner
import Testing
import TestSupport
import Tracker

/// One calendar year of progress, as Progress and Trends' *Year by year*
/// read it (UI.md, "Year" and "Trends"; PROGRESS.md), from the example
/// library: check-ins from October 2025 to September 2026, the main plan's
/// automatic baseline for 2026 starting 31 December 2025, which planned
/// 18.000 € of saving a year and 36.000 € of spending while working.
struct PlanProgressYearTests {
    let library: Library
    let index: InflationIndex
    private let latest: CalendarDate = "2026-09-30"

    init() throws {
        library = try Fixtures.exampleLibrary()
        index = InflationIndex(library: library, index: "hicp-it")
    }

    /// The years, oldest first, through `end`.
    private func years(in library: Library? = nil, through end: CalendarDate = "2026-09-30") -> [PlanProgressYear] {
        let library = library ?? self.library
        return PlanProgress(plan: "base", document: library.plans["base"], library: library,
                            valuator: Valuator(library: library), asOf: end).years
    }

    // MARK: The years

    @Test func oneYearForEachCalendarYearWithTheLatestSoFar() throws {
        let years = self.years()
        #expect(years.map(\.year) == [2025, 2026])
        let thisYear = try #require(years.last)
        #expect(thisYear.isLatest)
        #expect(thisYear.isSoFar)
        #expect(thisYear.to == latest)
        #expect(thisYear.baseline != nil)
        // From the baseline's start, 31 December, to the latest check-in: 273 of 365 days,
        // in the year's money.
        let planned = try #require(index.convert(Decimal(18_000) * 273 / 365, from: "2025-12-31", to: latest))
        #expect(thisYear.plannedSaving == planned)
        let valuator = Valuator(library: library)
        let sources = valuator.moneySources(.months, through: latest)
        #expect(thisYear.saved == sources.years.first { $0.year == 2026 }?.saved)
        // 2025 has no automatic baseline of its own, and no past baseline before it.
        let lastYear = try #require(years.first)
        #expect(!lastYear.isLatest)
        #expect(!lastYear.isSoFar)
        #expect(lastYear.baseline == nil)
        #expect(lastYear.plannedSaving == nil)
        #expect(lastYear.plannedSpending == nil)
        #expect(lastYear.savedGrade == nil)
        #expect(lastYear.spent == nil)
    }

    @Test func eachYearStartsWhereTheOneBeforeEnds() {
        let years = self.years()
        for (before, after) in zip(years, years.dropFirst()) {
            #expect(after.from == before.to)
            #expect(after.change.start == before.change.end)
        }
    }

    @Test func aYearEndingOn31DecemberIsntSoFar() throws {
        let years = self.years(through: "2025-12-31")
        #expect(years.map(\.year) == [2025])
        let lastYear = try #require(years.first)
        #expect(lastYear.isLatest)
        #expect(!lastYear.isSoFar)
    }

    @Test func aYearOfOneCheckInSaysNothingOfMarkets() throws {
        // The first check-in is the first record: the year starts and ends there.
        let years = self.years(through: "2025-10-31")
        #expect(years.map(\.year) == [2025])
        let firstYear = try #require(years.first)
        #expect(firstYear.marketYear == nil)
    }

    // MARK: A baseline that starts in the middle of the year

    @Test func savedCountsFromABaselineThatStartsInTheYear() throws {
        var library = self.library
        library.projections["base"]?.baselines["2026-01-05"]?.start.date = "2026-03-31"
        let valuator = Valuator(library: library)
        let thisYear = try #require(years(in: library).last)
        #expect(thisYear.year == 2026)
        // From 31 March to the latest check-in: 183 of the 275 days left in the year,
        // in the year's money.
        let planned = try #require(index.convert(Decimal(18_000) * 183 / 275, from: "2026-03-31", to: latest))
        #expect(thisYear.plannedSaving == planned)
        #expect(thisYear.saved == PlanProgressYear.saved(after: "2026-03-31", through: latest, valuator: valuator))
        // Less than the whole year's: the first quarter's saving isn't counted.
        let wholeYear = try #require(valuator.moneySources(.months, through: latest).years.first { $0.year == 2026 })
        #expect(thisYear.saved < wholeYear.saved)
    }

    // MARK: Planned saving and spending in the year's money

    @Test func plannedSpendingIsInTheYearsMoneyWhereTheIndexAllows() throws {
        let thisYear = try #require(years().last)
        let inYearsMoney = try #require(index.convert(36_000, from: "2025-12-31", to: latest))
        #expect(inYearsMoney > 36_000)
        #expect(thisYear.plannedSpending == inYearsMoney)
    }

    @Test func plannedAmountsAreAsRecordedWithoutAnIndex() throws {
        var library = self.library
        for month in library.months.keys { library.months[month]?.indices = [] }
        let thisYear = try #require(years(in: library).last)
        #expect(thisYear.plannedSpending == 36_000)
        #expect(thisYear.plannedSaving == Decimal(18_000) * 273 / 365)
    }

    // MARK: You saved

    /// So far's *You saved* and its pay's *You saved* are one number: the
    /// year's pay's, as the savings rate counts it. The example library's
    /// money in and out start on 30 June 2026, so 2026's pay, and what it
    /// saved, count from then, against what was planned over those 92 days.
    @Test func youSavedIsWhatTheYearsPaySaved() throws {
        let valuator = Valuator(library: library)
        let thisYear = try #require(years().last)
        let pay = try #require(thisYear.pay)
        let rate = try #require(valuator.savingsRate(from: "2026-01-01", through: latest))
        #expect(pay == rate)
        #expect(thisYear.youSaved == rate.saved)
        #expect(thisYear.youSaved == rate.pay.saved)
        #expect(rate.pay.cameIn - rate.pay.tax - rate.pay.spent + rate.pay.oneOffs == thisYear.youSaved)
        #expect(thisYear.youSavedFrom == "2026-06-30")
        // The year's money in and out, as *Year by year* and *Money in and out* count them, say the same.
        let period = try #require(valuator.moneyInOutSeries(.years, through: latest).periods.last)
        #expect(period.saved == thisYear.youSaved)
        // Planned over the days the pay covers: 92 of the baseline's 365 days of 2026.
        let planned = try #require(index.convert(Decimal(18_000) * 92 / 365, from: "2025-12-31", to: latest))
        #expect(thisYear.plannedYouSaved == planned)
        #expect(thisYear.plannedPaySaving == planned)
        #expect(thisYear.savedGrade == PlanComparison(thisYear.youSaved, planned: planned))
    }

    /// An inheritance of 20.000 € into the current account in September is
    /// saved: *You saved* counts it, and so does its pay's *You saved*,
    /// after the pay's lines and the one-off. The savings rate and what was
    /// spent stay the pay's.
    @Test func youSavedCountsAOneOff() throws {
        let before = try #require(years().last)
        var library = self.library
        library.upsert(Valuation(account: "conto-fineco", date: latest, balance: d("24210.55"), moneyIn: 3400,
                                 moneyOut: d("2554.65"), oneOff: 20_000))
        let thisYear = try #require(years(in: library).last)
        let pay = try #require(thisYear.pay)
        let beforePay = try #require(before.pay)
        #expect(pay.oneOffs == 20_000)
        #expect(thisYear.youSaved == before.youSaved + 20_000)
        #expect(thisYear.youSaved == pay.pay.saved)
        #expect(pay.pay.cameIn - pay.pay.tax - pay.pay.spent + pay.pay.oneOffs == thisYear.youSaved)
        #expect(pay.savedFromPay == beforePay.saved)
        #expect(pay.rate == beforePay.rate)
        #expect(thisYear.spentPerYear == before.spentPerYear)
        // *Where your money came from* counted it already.
        #expect(thisYear.saved == before.saved + 20_000)
    }

    /// A check-in after the pay account's latest value, such as the
    /// wallet's on 10 October: the saving planned against the pay's saved
    /// ends with the pay's days on 30 September, while the year and its
    /// planned saving run to 10 October.
    @Test func thePaysPlannedSavingEndsWithTheDaysItCovers() throws {
        var library = self.library
        var wallet = try #require(library.valuations(for: "ledger-wallet").last)
        wallet.date = "2026-10-10"
        library.upsert(wallet)
        let thisYear = try #require(years(in: library, through: "2026-10-10").last)
        #expect(thisYear.to == "2026-10-10")
        let pay = try #require(thisYear.pay)
        #expect(pay.from == "2026-06-30")
        #expect(pay.payThrough == latest)
        // 92 days of the baseline's 2026 against the 283 through 10 October, both in the year's money.
        let planned = try #require(thisYear.plannedSaving)
        let paySaving = try #require(thisYear.plannedPaySaving)
        #expect(abs(paySaving - planned * 92 / 283) < d("0.000001"))
        #expect(thisYear.savedGrade == PlanComparison(thisYear.youSaved, planned: paySaving))
    }

    /// A baseline that starts after the pay does: *You saved*, its pay and
    /// the planned saving all count from the baseline's start.
    @Test func youSavedCountsFromABaselineThatStartsAfterThePay() throws {
        var library = self.library
        library.projections["base"]?.baselines["2026-01-05"]?.start.date = "2026-08-31"
        let valuator = Valuator(library: library)
        let thisYear = try #require(years(in: library).last)
        let rate = try #require(valuator.savingsRate(from: "2026-09-01", through: latest))
        #expect(thisYear.pay == rate)
        #expect(thisYear.youSaved == rate.saved)
        #expect(thisYear.youSavedFrom == "2026-08-31")
        #expect(thisYear.spentPerYear == rate.spentPerYear)
        // From 31 August to the latest check-in: 30 of the 122 days left in the year, in the year's money.
        let planned = try #require(index.convert(Decimal(18_000) * 30 / 122, from: "2026-08-31", to: latest))
        #expect(thisYear.plannedSaving == planned)
        #expect(thisYear.plannedYouSaved == planned)
        #expect(thisYear.savedGrade == PlanComparison(rate.saved, planned: planned))
    }

    /// A baseline saved on the latest check-in, such as the first check-in
    /// after months of imported statements, leaves no days after its start:
    /// the year's pay still counts from the year's first day, and nothing is
    /// graded.
    @Test func aBaselineStartingOnTheLatestCheckInKeepsTheYearsPay() throws {
        var library = self.library
        library.projections["base"]?.baselines["2026-01-05"]?.start.date = latest
        let valuator = Valuator(library: library)
        let thisYear = try #require(years(in: library).last)
        let rate = try #require(valuator.savingsRate(from: "2026-01-01", through: latest))
        #expect(thisYear.pay == rate)
        #expect(thisYear.youSaved == rate.saved)
        #expect(thisYear.spentPerYear == rate.spentPerYear)
        #expect(thisYear.savedGrade == nil)
        #expect(thisYear.nothingPlannedYet)
        #expect(try #require(years().last).nothingPlannedYet == false)
    }

    /// Without money in and out, *You saved* is what the plan assets saved
    /// in the year, against what was planned for the whole year.
    @Test func youSavedWithoutMoneyInAndOutIsWhatPlanAssetsSaved() throws {
        let lastYear = try #require(years().first)
        #expect(lastYear.pay == nil)
        #expect(lastYear.youSaved == lastYear.saved)
        #expect(lastYear.youSavedFrom == lastYear.from)
        #expect(lastYear.plannedYouSaved == lastYear.plannedSaving)
    }

    /// A savings account's typed value that records what moved keeps the
    /// year's pay. One that lacks it turns money in and out off, and with it
    /// the year's pay: *You saved* falls back to what plan assets saved.
    @Test func aTypedSavingsValueWithoutWhatMovedTurnsThePayOff() throws {
        var library = self.library
        let savings = try #require(library.accounts.values.first { $0.kind == .savings })
        library.accounts[savings.id]?.values = .typed
        var typed = try #require(library.valuations(for: savings.id).last)
        #expect(typed.date == latest)
        typed.source = .manual
        library.upsert(typed)
        #expect(!library.typedValuesTurnOffTrends(try #require(library.accounts[savings.id])))
        #expect(try #require(years(in: library).last).pay != nil)

        typed.moneyIn = nil
        typed.moneyOut = nil
        library.upsert(typed)
        #expect(library.accountsTurningOffTrends.map(\.id) == [savings.id])
        let thisYear = try #require(years(in: library).last)
        #expect(thisYear.pay == nil)
        #expect(thisYear.youSaved == thisYear.saved)
        #expect(thisYear.plannedYouSaved == thisYear.plannedSaving)
    }

    // MARK: Graded within 5%

    /// The latest year with `saved`, `plannedSaving`, `spent` and `plannedSpending` in place of its own,
    /// and no pay, so `saved` is what it saved.
    private func graded(saved: Decimal = 0, plannedSaving: Decimal? = nil, spent: Decimal? = nil,
                        plannedSpending: Decimal? = nil) throws -> PlanProgressYear {
        var year = try #require(years().last)
        year.pay = nil
        year.saved = saved
        year.plannedSaving = plannedSaving
        year.spentPerYear = spent
        year.plannedSpending = plannedSpending
        return year
    }

    @Test func withinFivePercentEitherWayIsAsPlanned() {
        #expect(PlanComparison(10_000, planned: 10_000) == .asPlanned)
        #expect(PlanComparison(10_500, planned: 10_000) == .asPlanned)
        #expect(PlanComparison(9_500, planned: 10_000) == .asPlanned)
        #expect(PlanComparison(10_501, planned: 10_000) == .more)
        #expect(PlanComparison(9_499, planned: 10_000) == .less)
        #expect(PlanComparison(5_000, planned: 0) == nil)
    }

    @Test func savedIsGradedAgainstPlannedSaving() throws {
        #expect(try graded(saved: 20_486, plannedSaving: 13_463).savedGrade == .more)
        #expect(try graded(saved: 13_000, plannedSaving: 13_463).savedGrade == .asPlanned)
        #expect(try graded(saved: 4_000, plannedSaving: 13_463).savedGrade == .less)
        // No saving planned: not graded.
        #expect(try graded(saved: 5_000, plannedSaving: -2_000).savedGrade == nil)
        #expect(try graded(saved: 5_000).savedGrade == nil)
    }

    @Test func spentIsWhatWasSpentAgainstSpendingWhileWorking() throws {
        #expect(try graded(spent: 30_000, plannedSpending: 36_000).spent == .less)
        #expect(try graded(spent: 37_000, plannedSpending: 36_000).spent == .asPlanned)
        #expect(try graded(spent: 40_000, plannedSpending: 36_000).spent == .more)
        // No money in and out recorded in the year, or the baseline's plan past working.
        #expect(try graded(plannedSpending: 36_000).spent == nil)
        #expect(try graded(spent: 30_000).spent == nil)
    }

    // MARK: Past working

    private let birthDate: CalendarDate = "1988-04-12"

    /// A baseline of the example's main plan with `work`, retiring at `age`,
    /// that answered `earliestAge`.
    private func baseline(work: [WorkPhase], retiringAt age: AgeChoice = .age(55),
                          earliestAge: Int? = nil) throws -> Baseline {
        var plan = try #require(library.plans["base"])
        plan.work = work
        plan.retirement.age = age
        let copy = try JSONValue(encoding: plan)
        return Baseline(created: "2026-01-05", kind: .yearly, engine: "test", accounts: [],
                        headline: HeadlineSummary(earliestAge: earliestAge), plan: copy,
                        start: BaselineStart(date: "2025-12-31", value: 100_000), years: [])
    }

    private func untilRetirement() -> [WorkPhase] {
        [WorkPhase(from: "2026-01-01", until: .retirement, netIncome: 40_000)]
    }

    /// Spending while working is planned through the year the last phase
    /// ends: its date, or the birthday of the retirement age, which the
    /// earliest answer gives when the plan asks for the earliest age.
    @Test func workingEndsInTheYearTheLastPhaseEnds() throws {
        let dated = [WorkPhase(from: "2026-01-01", until: .date("2028-12-31"), netIncome: 40_000)]
        // 55 on 12 April 2043; 50 on 12 April 2038.
        let cases: [(work: [WorkPhase], age: AgeChoice, earliestAge: Int?, lastYear: Int)] = [
            (dated, .age(55), nil, 2028),
            (untilRetirement(), .age(55), 50, 2043),
            (untilRetirement(), .earliest, 50, 2038),
        ]
        for item in cases {
            let planned = try baseline(work: item.work, retiringAt: item.age, earliestAge: item.earliestAge)
            #expect(PlanProgressYear.plannedSpending(of: planned, in: item.lastYear, birthDate: birthDate) == 36_000)
            #expect(PlanProgressYear.plannedSpending(of: planned, in: item.lastYear + 1, birthDate: birthDate) == nil)
        }
        // Without either, or without a birth date, it never ends.
        let unknown = try baseline(work: untilRetirement(), retiringAt: .earliest)
        #expect(PlanProgressYear.plannedSpending(of: unknown, in: 2090, birthDate: birthDate) == 36_000)
        let retiring = try baseline(work: untilRetirement(), retiringAt: .age(55))
        #expect(PlanProgressYear.plannedSpending(of: retiring, in: 2090, birthDate: nil) == 36_000)
        // A plan without work is past working.
        let retired = try baseline(work: [])
        #expect(PlanProgressYear.plannedSpending(of: retired, in: 2026, birthDate: birthDate) == nil)
    }

    // MARK: The plan's references for money in and out

    @Test func thePlansSpendingAndSavingsRateWhileWorking() throws {
        let plan = try #require(library.plans["base"])
        let birth = library.settings.person?.birthDate
        let reference = PlanMoneyReference(plan: plan, on: latest, earliestAge: nil, birthDate: birth)
        #expect(reference.spendingWhileWorking == 36_000)
        #expect(reference.spending(per: .months) == 3_000)
        #expect(reference.spending(per: .years) == 36_000)
        // 40.000 € of pay, 36.000 € spent: 10%.
        #expect(reference.savingsRate == Decimal(string: "0.1"))

        // Before any work phase: no rate, though it still works later.
        let before = PlanMoneyReference(plan: plan, on: "2025-12-31", earliestAge: nil, birthDate: birth)
        #expect(before.savingsRate == nil)
        #expect(before.spendingWhileWorking == 36_000)

        // Every work phase over: past working.
        var retired = plan
        retired.work = [WorkPhase(from: "2020-01-01", until: .date("2025-12-31"), netIncome: 40_000)]
        let past = PlanMoneyReference(plan: retired, on: latest, earliestAge: nil, birthDate: birth)
        #expect(past.spendingWhileWorking == nil)
        #expect(past.spending(per: .months) == nil)
        #expect(past.savingsRate == nil)

        #expect(PlanMoneyReference(plan: nil, on: latest, earliestAge: nil, birthDate: birth)
            == PlanMoneyReference(spendingWhileWorking: nil, savingsRate: nil))
    }
}
