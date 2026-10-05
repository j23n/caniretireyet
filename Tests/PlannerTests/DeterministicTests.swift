import Foundation
import Model
@testable import Planner
import Testing

/// Cases worked out by hand: zero volatility and known returns. The start
/// date is a year-end unless a test says otherwise, so every simulated
/// year is whole.
struct DeterministicTests {
    /// Born 1966-01-01, 59 on the start date, retiring now, funding ages 60–64.
    let retiree = Sample.library(birth: "1966-01-01", on: "2025-12-31",
                                 [SampleAccount(id: "broker", balance: 100_000)])

    @Test func drawdownMatchesTheClosedForm() async throws {
        let plan = Sample.plan(retire: .age(59), endAge: 64, retired: "10000")
        let result = try await Sample.run(plan, retiree)

        // Spending is withdrawn at the start of each year, then the rest earns 5%:
        // V_k = (V_{k-1} − S) × 1.05, so V_n = 1.05^n V_0 − S × 1.05 × (1.05^n − 1) / 0.05.
        #expect(result.expectedPath.years.map(\.year) == Array(2026...2030))
        #expect(close(result.expectedValue(in: 2026), 94_500))
        #expect(close(result.expectedValue(in: 2027), 88_725))
        #expect(close(result.expectedValue(in: 2028), 82_661.25))
        let growth: Double = pow(1.05, 5)
        let closedForm: Double = growth * 100_000 - 10_000 * 1.05 * (growth - 1) / 0.05
        #expect(close(result.expectedValue(in: 2030), closedForm))
        #expect(close(result.expectedValue(in: 2030), 69_609.028125))

        #expect(result.answer.currentAge == 59)
        #expect(result.answer.canRetireNow)
        #expect(result.answer.successIfRetiringNow == 1)
        #expect(result.answer.earliestAge == 59)
        #expect(result.expectedPath.failure == nil)
        let firstYear = try #require(result.expectedPath.years.first)
        #expect(firstYear.fraction == 1 && firstYear.workingShare == 0)
        #expect(close(firstYear.spending, 10_000))
        #expect(firstYear.income.map(\.kind) == [.withdrawal])
        #expect(firstYear.taxes.isEmpty)
        #expect(close(firstYear.savings, -10_000))
    }

    @Test func runningOutIsAFailure() async throws {
        let library = Sample.library(birth: "1966-01-01", on: "2025-12-31",
                                     [SampleAccount(id: "broker", balance: 30_000)])
        let plan = Sample.plan(retire: .age(59), endAge: 64, retired: "10000", equityReturn: "0")
        let result = try await Sample.run(plan, library)

        // 30,000 covers 2026–2028; 2029 (age 63) has nothing left.
        #expect(result.expectedPath.failure == RunFailure(year: 2029, age: 63, reason: .depleted))
        #expect(result.answer.successIfRetiringNow == 0)
        #expect(!result.answer.canRetireNow)
        #expect(zip(result.fan.map(\.p50), [20_000.0, 10_000, 0, 0, 0]).allSatisfy { close($0, $1, 1e-9) })
        #expect(result.failures.failed == result.failures.runs)
        #expect(result.failures.medianFailureAge == 63)
        #expect(result.failures.bridgeFailures == 0)
    }

    @Test func savingThenDrawingDown() async throws {
        // Born 1986-01-01: works 2026–2030, retires on 1 January 2031 at 45.
        let library = Sample.library(birth: "1986-01-01", on: "2025-12-31",
                                     [SampleAccount(id: "broker", balance: 50_000)])
        let plan = Sample.plan(retire: .age(45), endAge: 50, working: "40000", retired: "30000",
                               work: [Sample.work(from: "2026-01-01", net: "60000")])
        let result = try await Sample.run(plan, library)

        // Savings of 20,000 go in at the start of each working year.
        let growth: Double = pow(1.05, 5)
        let saved: Double = growth * 50_000 + 20_000 * 1.05 * (growth - 1) / 0.05
        #expect(close(result.expectedValue(in: 2030), saved))
        #expect(close(result.expectedValue(in: 2031), (saved - 30_000) * 1.05))
        let first = try #require(result.expectedPath.years.first)
        #expect(first.workingShare == 1)
        #expect(close(first.savings, 20_000))
        #expect(first.income == [IncomeItem(kind: .work, id: "work-0", label: "Work", amount: 60_000)])
        #expect(first.taxes.isEmpty)
        #expect(result.expectedPath.years.first { $0.year == 2031 }?.workingShare == 0)
        #expect(result.markers.contains(TimelineMarker(kind: .retirement, year: 2031, age: 45, label: "Retirement")))
    }

    @Test func incomeFromWorkGrowsInRealTerms() async throws {
        let library = Sample.library(birth: "1986-01-01", on: "2025-12-31",
                                     [SampleAccount(id: "broker", balance: 0)])
        let plan = Sample.plan(retire: .age(45), endAge: 50, retired: "0", equityReturn: "0",
                               work: [Sample.work(from: "2026-01-01", net: "40000", growth: "0.1")])
        let result = try await Sample.run(plan, library)

        // 40,000, then 44,000, then 48,400, all saved.
        #expect(close(result.expectedValue(in: 2026), 40_000))
        #expect(close(result.expectedValue(in: 2027), 84_000))
        #expect(close(result.expectedValue(in: 2028), 132_400))
    }

    @Test func salesPayTaxOnTheirGainShare() async throws {
        let plan = Sample.plan(retire: .age(59), endAge: 64, retired: "10000", investmentRate: "0.25",
                               unrealizedGainShare: "0.5")
        let result = try await Sample.run(plan, retiree)

        // Half of each sale is gain: sell 10,000 / (1 − 0.25 × 0.5) = 11,428.57,
        // leaving 88,571.43, which grows to 93,000. The tax is paid out of the sale.
        #expect(close(result.expectedValue(in: 2026), 93_000))
        let first = try #require(result.expectedPath.years.first)
        #expect(first.taxes.map(\.id) == [TaxLine.investment])
        #expect(first.taxes.first?.label == "Tax on investments")
        #expect(close(first.totalTax, 10_000 / 0.875 * 0.5 * 0.25))
        #expect(close(first.income.first { $0.kind == .withdrawal }?.amount, 10_000 / 0.875))
        #expect(close(first.savings, -10_000 / 0.875))
    }

    /// Purchase costs stay in the money of the day they were paid, so the
    /// part of a value that's only inflation counts as gain.
    @Test func inflationCountsAsGain() async throws {
        let plan = Sample.plan(retire: .age(59), endAge: 64, retired: "10000", equityReturn: "0",
                               investmentRate: "0.5", unrealizedGainShare: "0")
        let result = try await Sample.run(plan, retiree)

        // 2026 sells at cost: no tax, 90,000 left, its cost now 90,000 / 1.02 in
        // today's money. 2027's sale is 1/51 gain: 10,000 / (1 − 0.5 / 51).
        #expect(close(result.expectedValue(in: 2026), 90_000))
        #expect(result.expectedYear(2026)?.taxes.isEmpty == true)
        let sold = 10_000 / (1 - 0.5 / 51)
        #expect(close(result.expectedYear(2027)?.income.first { $0.kind == .withdrawal }?.amount, sold))
        #expect(close(result.expectedValue(in: 2027), 90_000 - sold))
        #expect(close(result.expectedYear(2027)?.totalTax, sold - 10_000))
    }

    @Test func noCostRecordedMeansEverySaleIsGain() async throws {
        let plan = Sample.plan(retire: .age(59), endAge: 64, retired: "10000", equityReturn: "0",
                               investmentRate: "0.2")
        let result = try await Sample.run(plan, retiree)

        // A balance with no purchase cost and no estimate: 10,000 / 0.8 sold.
        #expect(close(result.expectedValue(in: 2026), 87_500))
        #expect(result.issues.contains { $0.code == "planner.unknownCostBasis" && !$0.isError })
    }

    @Test func investmentIncomeIsTaxedTheFollowingYear() async throws {
        let plan = Sample.plan(retire: .age(59), endAge: 64, retired: "0", equityReturn: "0", equityYield: "0.02",
                               inflation: "0", investmentRate: "0.25", unrealizedGainShare: "0")
        let result = try await Sample.run(plan, retiree)

        // 2026 pays out 2,000 of income, reinvested; its 500 of tax is paid in
        // 2027 by selling at cost (the reinvested income raised the cost).
        #expect(close(result.expectedValue(in: 2026), 100_000))
        #expect(result.expectedYear(2026)?.taxes.isEmpty == true)
        #expect(close(result.expectedValue(in: 2027), 99_500))
        #expect(result.expectedYear(2027)?.taxes.map(\.id) == [TaxLine.investment])
        #expect(close(result.expectedYear(2027)?.totalTax, 500))
        #expect(close(result.expectedValue(in: 2028), 99_500 - 0.25 * 0.02 * 99_500))
    }

    @Test func wealthTaxOnWhatIsAboveTheAllowance() async throws {
        let plan = Sample.plan(retire: .age(59), endAge: 64, retired: "0", equityReturn: "0", wealthRate: "0.01")
        let result = try await Sample.run(plan, retiree)

        // 1% of the value at the start of each year: V_k = 100,000 × 0.99^k.
        for (k, year) in (2026...2030).enumerated() {
            #expect(close(result.expectedValue(in: year), 100_000 * pow(0.99, Double(k + 1))))
        }
        #expect(result.expectedYear(2027)?.taxes.map(\.id) == [TaxLine.wealth])
        #expect(result.expectedYear(2027)?.taxes.first?.label == "Wealth tax")
        #expect(close(result.expectedYear(2027)?.totalTax, 990))

        // With 50,000 untaxed: 500, then 1% of 49,500.
        let allowance = try await Sample.run(
            Sample.plan(retire: .age(59), endAge: 64, retired: "0", equityReturn: "0", wealthRate: "0.01",
                        wealthAllowance: "50000"), retiree)
        #expect(close(allowance.expectedValue(in: 2026), 99_500))
        #expect(close(allowance.expectedValue(in: 2027), 99_005))
    }

    @Test func lockedMoneyIsNotWealthTaxed() async throws {
        let library = Sample.library(birth: "1966-01-01", on: "2025-12-31", [
            SampleAccount(id: "broker", balance: 100_000),
            SampleAccount(id: "fund", kind: .pensionFund, balance: 100_000, availableFromAge: 63),
        ])
        let plan = Sample.plan(retire: .age(59), endAge: 64, retired: "0", equityReturn: "0", wealthRate: "0.01")
        let result = try await Sample.run(plan, library)

        // 2026–2028 tax only the broker; from 2029 (63 on 1 January) the fund too.
        #expect(close(result.expectedYear(2026)?.totalTax, 1_000))
        #expect(close(result.expectedYear(2029)?.totalTax, 0.01 * (100_000 * pow(0.99, 3) + 100_000)))
    }

    @Test func aPartYearPaysPartOfTheWealthTax() async throws {
        let library = Sample.library(birth: "1966-01-01", on: "2026-09-30",
                                     [SampleAccount(id: "broker", balance: 100_000)])
        let plan = Sample.plan(retire: .age(60), endAge: 64, retired: "0", equityReturn: "0", wealthRate: "0.01")
        let result = try await Sample.run(plan, library)
        #expect(close(result.expectedYear(2026)?.totalTax, 1_000 * 92 / 365))
    }

    @Test func theFirstYearStartsAfterTheCheckIn() async throws {
        let library = Sample.library(birth: "1966-01-01", on: "2026-09-30",
                                     [SampleAccount(id: "broker", balance: 100_000)])
        let plan = Sample.plan(retire: .age(60), endAge: 64, retired: "36500", equityReturn: "0")
        let result = try await Sample.run(plan, library)

        // October to December is 92 days of spending.
        let first = try #require(result.expectedPath.years.first)
        #expect(first.year == 2026 && close(first.fraction, 92.0 / 365))
        #expect(close(first.spending, 9_200))
        #expect(close(result.expectedValue(in: 2026), 90_800))
        #expect(close(result.expectedValue(in: 2027), 54_300))
        #expect(result.start.date == "2026-09-30" && result.start.age == 60)
    }

    /// Prices move by the time simulated: a first year of 92 days has 92/365
    /// of a year's inflation.
    @Test func inflationCoversTheSimulatedPart() throws {
        let library = Sample.library(birth: "1966-01-01", on: "2026-09-30",
                                     [SampleAccount(id: "broker", balance: 100_000)])
        let plan = Sample.plan(retire: .age(60), endAge: 64, retired: "10000")
        let model = try #require(PlanInterpreter.interpret(plan: plan, library: library, options: PlannerOptions()).0)
        #expect(close(model.frames[0].inflationStep, pow(1.02, 92.0 / 365), 1e-12))
        #expect(close(model.frames[1].inflationStep, 1.02, 1e-12))
    }

    @Test func aCheckInOnTheLastDayOfTheYearStartsNextYear() async throws {
        let plan = Sample.plan(retire: .age(59), endAge: 64, retired: "10000")
        let result = try await Sample.run(plan, retiree)
        #expect(result.fan.first?.year == 2026)
        #expect(result.expectedPath.years.first?.fraction == 1)
    }

    @Test func lockedMoneyMakesABridgeFailure() async throws {
        // Born 1976, retiring at 49 with 50,000 to draw and 500,000 available from 60.
        let library = Sample.library(birth: "1976-01-01", on: "2025-12-31", [
            SampleAccount(id: "broker", balance: 50_000),
            SampleAccount(id: "fund", kind: .pensionFund, balance: 500_000, availableFromAge: 60),
        ])
        let plan = Sample.plan(retire: .age(49), endAge: 70, retired: "30000", equityReturn: "0")
        let result = try await Sample.run(plan, library)

        let failure = try #require(result.expectedPath.failure)
        #expect(failure.year == 2027 && failure.age == 51)
        #expect(failure.reason == .locked(LockedMoney(name: "fund", value: 500_000, accessibleFromAge: 60,
                                                      accounts: ["fund"])))
        #expect(result.failures.bridgeFailures == result.failures.runs)
        #expect(result.failures.bridges.first?.accessibleFromAge == 60)
        #expect(result.markers.contains { $0.kind == .accessible && $0.age == 60 && $0.label == "fund" })
        let bucket = try #require(result.start.buckets.first { $0.availableFromAge == 60 })
        #expect(bucket.accounts == ["fund"] && bucket.value == 500_000)

        // Retiring at 59, the fund opens in the second retirement year and carries the rest.
        let later = try await Sample.run(
            Sample.plan(retire: .age(59), endAge: 70, retired: "30000", equityReturn: "0"), library)
        #expect(later.expectedPath.failure == nil)
        #expect(close(later.expectedValue(in: 2036), 20_000 + 500_000 - 30_000))
    }

    /// Locked money is a bridge failure only if it could have covered what's
    /// missing until it opens: here 10,000 in 2027 and 30,000 a year from 52
    /// to 59, 250,000 in all.
    @Test func lockedMoneyTooSmallToBridgeIsNotABridgeFailure() async throws {
        func failure(fund: Decimal) async throws -> RunFailure? {
            let library = Sample.library(birth: "1976-01-01", on: "2025-12-31", [
                SampleAccount(id: "broker", balance: 50_000),
                SampleAccount(id: "fund", kind: .pensionFund, balance: fund, availableFromAge: 60),
            ])
            let plan = Sample.plan(retire: .age(49), endAge: 70, retired: "30000", equityReturn: "0")
            return try await Sample.run(plan, library).expectedPath.failure
        }
        #expect(try await failure(fund: 240_000) == RunFailure(year: 2027, age: 51, reason: .depleted))
        let bridged = try #require(try await failure(fund: 250_000))
        #expect(bridged.reason == .locked(LockedMoney(name: "fund", value: 250_000, accessibleFromAge: 60,
                                                      accounts: ["fund"])))
    }

    @Test func lockedMoneyOpensInTheFirstYearAtThatAge() async throws {
        // Born mid-June 1976: 60 on 1 January 2037.
        let library = Sample.library(birth: "1976-06-15", on: "2025-12-31", [
            SampleAccount(id: "broker", balance: 100_000),
            SampleAccount(id: "fund", kind: .pensionFund, balance: 50_000, availableFromAge: 60),
        ])
        let plan = Sample.plan(retire: .age(49), endAge: 70, retired: "1000", equityReturn: "0")
        let result = try await Sample.run(plan, library)
        #expect(result.markers.first { $0.kind == .accessible }?.year == 2037)
    }

    @Test func pensionsReplaceWithdrawals() async throws {
        let plan = Sample.plan(
            retire: .age(59), endAge: 70, retired: "20000", equityReturn: "0",
            pensions: [PlanPension(name: "Old job", fromAge: 62, perYear: d("12000")),
                       PlanPension(name: "State pension", fromAge: 67, perYear: d("15400"))])
        let library = Sample.library(birth: "1966-01-01", on: "2025-12-31",
                                     [SampleAccount(id: "broker", balance: 1_000_000)])
        let result = try await Sample.run(plan, library)

        // 2026–2027: 20,000 a year; from 2028 (62) the first pension pays 12,000.
        #expect(close(result.expectedValue(in: 2027), 960_000))
        #expect(close(result.expectedValue(in: 2028), 952_000))
        let year2028 = try #require(result.expectedYear(2028))
        #expect(year2028.income.contains(IncomeItem(kind: .pension, id: "pension-0", label: "Old job", amount: 12_000)))
        let starts = result.markers.filter { $0.kind == .pensionStart }
        #expect(starts.map(\.label) == ["Old job", "State pension"])
        #expect(starts.map(\.age) == [62, 67] && starts.map(\.amount) == [12_000, 15_400])
        // From 67 the pensions (27,400) exceed spending, and the surplus is invested.
        #expect(close(result.expectedYear(2033)?.savings, 7_400))
    }

    @Test func aPensionPaysFromTheBirthday() async throws {
        let library = Sample.library(birth: "1966-07-01", on: "2025-12-31",
                                     [SampleAccount(id: "broker", balance: 1_000_000)])
        let plan = Sample.plan(retire: .age(59), endAge: 70, retired: "20000", equityReturn: "0",
                               pensions: [PlanPension(fromAge: 62, perYear: d("12000"))])
        let result = try await Sample.run(plan, library)

        // 62 on 1 July 2028: 184 of 366 days.
        let paid = try #require(result.expectedYear(2028)?.income.first { $0.kind == .pension })
        #expect(close(paid.amount, 12_000 * 184 / 366))
        #expect(paid.label == "Pension")
    }

    @Test func eventsHappenInTheirYear() async throws {
        let plan = Sample.plan(
            retire: .age(59), endAge: 64, retired: "10000", equityReturn: "0",
            events: [
                PlanEvent(name: "Gift", timing: .age(61), amount: d("50000")),
                PlanEvent(name: "Roof", timing: .year(2029), amount: d("-20000")),
                PlanEvent(name: "Maybe", timing: .year(2030), amount: d("1000"), probability: d("0.8")),
                PlanEvent(name: "Unlikely", timing: .year(2030), amount: d("5000"), probability: d("0.2")),
            ])
        let result = try await Sample.run(plan, retiree)

        // 2027: +50,000. 2029: −20,000. 2030: +1,000 (the 20% event is left out of the deterministic run).
        #expect(close(result.expectedValue(in: 2026), 90_000))
        #expect(close(result.expectedValue(in: 2027), 130_000))
        #expect(close(result.expectedValue(in: 2028), 120_000))
        #expect(close(result.expectedValue(in: 2029), 90_000))
        #expect(close(result.expectedValue(in: 2030), 81_000))
        let year2027 = try #require(result.expectedYear(2027))
        #expect(year2027.income.contains { $0.kind == .windfall && $0.label == "Gift" && $0.amount == 50_000 })
        #expect(year2027.taxes.isEmpty)
        #expect(close(result.expectedYear(2029)?.expenses, 20_000))
        #expect(result.markers.filter { $0.kind == .windfall }.map(\.label) == ["Gift", "Maybe", "Unlikely"])
        #expect(result.markers.filter { $0.kind == .expense }.map(\.label) == ["Roof"])
        #expect(result.markers.first { $0.label == "Maybe" }?.probability == 0.8)

        // Each run draws the uncertain events: about 80% and 20% of runs get them.
        let ends = try #require(result.fan.last)
        #expect(ends.p10 < ends.p90)
    }

    @Test func contributionsGoIntoTheirAccount() async throws {
        let library = Sample.library(birth: "1986-01-01", on: "2025-12-31", [
            SampleAccount(id: "broker", balance: 0),
            SampleAccount(id: "fund", kind: .pensionFund, balance: 10_000, availableFromAge: 60),
        ])
        let plan = Sample.plan(retire: .age(45), endAge: 55, working: "40000", retired: "10000", equityReturn: "0",
                               work: [Sample.work(from: "2026-01-01", net: "60000")],
                               contributions: [PlanContribution(account: "fund", perYear: d("5000"))])
        let result = try await Sample.run(plan, library)

        // Five years of 5,000 into the fund, 15,000 a year into the money you can draw.
        #expect(close(result.expectedValue(in: 2030), 10_000 + 5 * 20_000))
        #expect(close(result.expectedPath.years[0].savings, 20_000))
        // Retired at 45 with the fund locked past the plan's end, the 75,000 runs out at 52.
        #expect(result.expectedPath.failure == RunFailure(year: 2038, age: 52, reason: .depleted))
    }

    @Test func aOneOffContributionIsPaidInItsYear() async throws {
        let library = Sample.library(birth: "1986-01-01", on: "2025-12-31", [
            SampleAccount(id: "broker", balance: 100_000),
            SampleAccount(id: "fund", kind: .pensionFund, balance: 0, availableFromAge: 60),
        ])
        let plan = Sample.plan(retire: .age(45), endAge: 55, retired: "0", equityReturn: "0",
                               contributions: [PlanContribution(account: "fund", amount: d("20000"), year: 2027)])
        let result = try await Sample.run(plan, library)

        // The total doesn't change: 20,000 moves from the broker into the fund in 2027.
        #expect(close(result.expectedValue(in: 2027), 100_000))
        #expect(close(result.expectedYear(2027)?.savings, 0))
    }
}
