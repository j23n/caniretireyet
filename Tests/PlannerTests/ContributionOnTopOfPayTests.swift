import Foundation
import Model
@testable import Planner
import Testing
import TestSupport

/// A contribution paid on top of take-home pay (`onTopOfPay`, PLANNER.md,
/// "Work, pensions and other income"): pay that never reaches the bank
/// account, such as what an employer pays into a pension. It's income of
/// the year, saved on top of what the pay saves; one without the mark comes
/// out of the pay. Zero volatility and equity at 5%, from a year-end.
struct ContributionOnTopOfPayTests {
    /// Born 1986-01-01, 39 on the start date: 50,000 at the broker and
    /// 10,000 in a pension fund available from 60.
    let library = Sample.library(birth: "1986-01-01", on: "2025-12-31", [
        SampleAccount(id: "broker", balance: 50_000),
        SampleAccount(id: "fund", kind: .pensionFund, mix: [.equity: 1], balance: 10_000, availableFromAge: 60),
    ])

    /// Works until 45 on `pay`, spending 40,000, with 5,000 a year into the fund.
    func plan(pay: String, onTopOfPay: Bool?) -> PlanDocument {
        Sample.plan(retire: .age(45), endAge: 50, working: "40000", retired: "30000",
                    work: [Sample.work(from: "2026-01-01", net: pay)],
                    contributions: [PlanContribution(account: "fund", perYear: 5_000, onTopOfPay: onTopOfPay)])
    }

    @Test func itIsSavedOnTopOfWhatThePaySaves() async throws {
        let result = try await Sample.run(plan(pay: "60000", onTopOfPay: true), library)
        let first = try #require(result.expectedPath.years.first)
        // The pay saves 20,000, and the fund gets its 5,000 on top, in the
        // middle of the year: they earn half its 5%.
        #expect(close(first.savings, 25_000))
        #expect(close(result.expectedValue(in: 2026), 60_000 * 1.05 + 25_000 * 1.05.squareRoot()))
        // It's income from work, under its own name.
        #expect(first.income == [
            IncomeItem(kind: .work, id: "work-0", label: "Work", amount: 60_000),
            IncomeItem(kind: .work, id: "contribution-0", label: "Into fund, on top of pay", amount: 5_000),
        ])
        #expect(YearRow(detail: first).sold == 0)
    }

    @Test func withoutTheMarkItComesOutOfThePay() async throws {
        for onTopOfPay in [nil, false] as [Bool?] {
            let result = try await Sample.run(plan(pay: "60000", onTopOfPay: onTopOfPay), library)
            let first = try #require(result.expectedPath.years.first)
            // 5,000 of the 20,000 the pay saves goes into the fund.
            #expect(close(first.savings, 20_000))
            #expect(close(result.expectedValue(in: 2026), 60_000 * 1.05 + 20_000 * 1.05.squareRoot()))
            #expect(first.income.map(\.id) == ["work-0"])
        }
    }

    /// Pay that all goes on spending: a contribution out of it sells
    /// investments to pay the fund; one on top of it sells nothing.
    @Test func itSellsNothingWhenThePayIsSpent() async throws {
        let onTop = try await Sample.run(plan(pay: "40000", onTopOfPay: true), library)
        let fromPay = try await Sample.run(plan(pay: "40000", onTopOfPay: nil), library)
        let working = { (result: PlanResult) in result.expectedPath.years.filter { $0.workingShare == 1 } }
        #expect(working(onTop).count == 5)
        #expect(working(onTop).allSatisfy { YearRow(detail: $0).sold == 0 && close($0.savings, 5_000) })
        #expect(working(fromPay).allSatisfy { close(YearRow(detail: $0).sold, 5_000) && close($0.savings, 0) })
    }

    /// It stops when work stops, and the years still add up.
    @Test func itStopsWithWorkAndTheYearsAddUp() async throws {
        let result = try await Sample.run(plan(pay: "60000", onTopOfPay: true), library)
        let retired = try #require(result.expectedPath.years.first { $0.workingShare == 0 })
        #expect(!retired.income.contains { $0.id == "contribution-0" })
        expectYearsAddUp(result.expectedPath, start: 60_000, growth: .exactly { _ in 1.05 }, "on top of pay")
    }

    /// A one-off amount on top of the pay, such as an employer's bonus
    /// into the fund, is income of its year.
    @Test func aOneOffOnTopOfThePay() async throws {
        var plan = plan(pay: "60000", onTopOfPay: nil)
        plan.contributions = [PlanContribution(account: "fund", amount: 8_000, year: 2027, onTopOfPay: true)]
        let result = try await Sample.run(plan, library)
        let year = try #require(result.expectedPath.years.first { $0.year == 2027 })
        #expect(close(year.savings, 28_000))
        #expect(year.income.last == IncomeItem(kind: .work, id: "contribution-0", label: "Into fund, on top of pay",
                                               amount: 8_000))
        #expect(result.expectedPath.years.filter { $0.income.contains { $0.id == "contribution-0" } }.count == 1)
    }

    /// It's paid with the pay: over the days a work phase is in force, so
    /// not in the years between the last work phase and retirement. One
    /// out of the pay is paid in those years too, from the money you can draw.
    @Test func itIsPaidOnlyWhileAWorkPhaseIsInForce() async throws {
        var plan = plan(pay: "60000", onTopOfPay: true)
        plan.work = [Sample.work(from: "2026-01-01", until: .date("2027-06-30"), net: "60000")]
        let result = try await Sample.run(plan, library)
        func onTop(_ year: Int) -> Double? {
            result.expectedPath.years.first { $0.year == year }?.income.first { $0.id == "contribution-0" }?.amount
        }
        #expect(close(onTop(2026), 5_000))
        // Half of 2027: 181 of its 365 days.
        #expect(close(onTop(2027), 5_000 * 181 / 365))
        #expect(onTop(2028) == nil && onTop(2030) == nil)
        #expect(!result.issues.contains { $0.code == "planner.contributionWithoutWork" })

        plan.contributions = [PlanContribution(account: "fund", perYear: 5_000)]
        let fromPay = try await Sample.run(plan, library)
        let gap = try #require(fromPay.expectedPath.years.first { $0.year == 2029 })
        #expect(YearRow(detail: gap).sold > 5_000)
    }

    /// Without a work phase in its years it's never paid, and the plan says so.
    @Test func withoutWorkInItsYearsItIsLeftOutWithAWarning() async throws {
        var plan = plan(pay: "60000", onTopOfPay: true)
        plan.work = [Sample.work(from: "2026-01-01", until: .date("2027-06-30"), net: "60000")]
        plan.contributions = [PlanContribution(account: "fund", amount: 8_000, year: 2029, onTopOfPay: true)]
        let oneOff = try await Sample.run(plan, library)
        #expect(!oneOff.expectedPath.years.contains { $0.income.contains { $0.id == "contribution-0" } })
        let warning = try #require(oneOff.issues.first { $0.code == "planner.contributionWithoutWork" })
        #expect(warning.severity == .warning && warning.index == 0)
        #expect(warning.message == "A contribution into fund is paid on top of your pay, but the plan has no work "
            + "in 2029, so it's left out.")

        // Work that ended before the plan starts isn't work in its first year.
        plan.work = [Sample.work(from: "2020-01-01", until: .date("2025-11-30"), net: "60000")]
        plan.contributions = [PlanContribution(account: "fund", amount: 8_000, year: 2025, onTopOfPay: true)]
        let before = try await Sample.run(plan, library)
        #expect(!before.expectedPath.years.contains { $0.income.contains { $0.id == "contribution-0" } })
        #expect(before.issues.contains { $0.code == "planner.contributionWithoutWork" })

        plan.work = []
        plan.contributions = [PlanContribution(account: "fund", perYear: 5_000, onTopOfPay: true)]
        let yearly = try await Sample.run(plan, library)
        #expect(!yearly.expectedPath.years.contains { $0.income.contains { $0.id == "contribution-0" } })
        #expect(yearly.issues.first { $0.code == "planner.contributionWithoutWork" }?.message
            == "A contribution into fund is paid on top of your pay, but the plan has no work while it's paid, so "
            + "it's left out.")
    }

    /// The plan's own saving while working leaves out one into an account
    /// the plan excludes, as a run does.
    @Test func thePlansSavingLeavesOutOneIntoAnExcludedAccount() {
        var plan = plan(pay: "60000", onTopOfPay: true)
        #expect(plan.contributionsOnTopOfPay(on: "2026-06-30") == 5_000)
        #expect(plan.workingSaving(on: "2026-06-30")?.saving == 25_000)
        plan.portfolio.exclude = ["fund"]
        #expect(plan.contributionsOnTopOfPay(on: "2026-06-30") == 0)
        #expect(plan.workingSaving(on: "2026-06-30")?.saving == 20_000)
    }
}
