import Foundation
import Model
@testable import Planner
import TaxKit
import Testing

/// Cases worked out by hand: zero volatility, known returns, flat or no
/// taxes. The start date is a year-end unless a test says otherwise, so
/// every simulated year is whole.
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
                               work: [Sample.employee(from: "2026-01-01", gross: "60000")])
        let result = try await Sample.run(plan, library)

        // Savings of 20,000 go in at the start of each working year.
        let growth: Double = pow(1.05, 5)
        let saved: Double = growth * 50_000 + 20_000 * 1.05 * (growth - 1) / 0.05
        #expect(close(result.expectedValue(in: 2030), saved))
        #expect(close(result.expectedValue(in: 2031), (saved - 30_000) * 1.05))
        let first = try #require(result.expectedPath.years.first)
        #expect(first.workingShare == 1)
        #expect(close(first.savings, 20_000))
        #expect(first.income.map(\.kind) == [.work])
        #expect(result.expectedPath.years.first { $0.year == 2031 }?.workingShare == 0)
        #expect(result.markers.contains(TimelineMarker(kind: .retirement, year: 2031, age: 45, label: "Retirement")))
    }

    @Test func workIsTaxedByTheSystem() async throws {
        let library = Sample.library(birth: "1986-01-01", on: "2025-12-31",
                                     [SampleAccount(id: "broker", balance: 50_000)])
        let plan = Sample.plan(retire: .age(45), endAge: 50, working: "30000", retired: "30000",
                               work: [Sample.employee(from: "2026-01-01", gross: "60000")])
        var system = FlatTaxSystem()
        system.incomeRate = 0.2
        system.contributionRate = 0.1
        let result = try await Sample.run(plan, library, system: system)

        // Net 60,000 − 12,000 − 6,000 = 42,000; saving 12,000.
        #expect(close(result.expectedValue(in: 2026), (50_000 + 12_000) * 1.05))
        let first = try #require(result.expectedPath.years.first)
        #expect(first.taxes == [AmountItem(id: "flat.income", label: "Income tax", amount: 12_000)])
        #expect(first.contributions == [AmountItem(id: "flat.social", label: "Social contributions", amount: 6_000)])
        #expect(first.income == [IncomeItem(kind: .work, id: "work-0", label: "Employee", amount: 60_000)])
    }

    @Test(arguments: [true, false])
    func withdrawalsAreGrossedUpForGainsTax(exact: Bool) async throws {
        var system = FlatTaxSystem()
        system.gainsRate = 0.25
        system.exactGrossUp = exact
        let plan = Sample.plan(retire: .age(59), endAge: 64, retired: "10000", unrealizedGainShare: "0.5")
        let result = try await Sample.run(plan, retiree, system: system)

        // Half of each sale is gain: sell 10,000 / (1 − 0.25 × 0.5) = 11,428.57,
        // leaving 88,571.43, which grows to 93,000. The tax was withheld on the sale.
        let tolerance = exact ? 1e-9 : 1e-6
        #expect(close(result.expectedValue(in: 2026), 93_000, tolerance))
        let first = try #require(result.expectedPath.years.first)
        let gains = try #require(first.taxes.first { $0.id == "flat.gains" })
        #expect(close(gains.amount, 10_000 / 0.875 * 0.5 * 0.25, tolerance))
        #expect(close(first.income.first { $0.kind == .withdrawal }?.amount, 10_000 / 0.875, tolerance))
    }

    @Test func wealthTaxIsPaidTheFollowingYear() async throws {
        var system = FlatTaxSystem()
        system.wealthRate = 0.01
        let plan = Sample.plan(retire: .age(59), endAge: 64, retired: "0", equityReturn: "0")
        let result = try await Sample.run(plan, retiree, system: system)

        // 1% of year-end value each year: V_k = 100,000 × 0.99^k (net of the tax due).
        for (k, year) in (2026...2030).enumerated() {
            #expect(close(result.expectedValue(in: year), 100_000 * pow(0.99, Double(k + 1))))
        }
        #expect(close(result.expectedPath.years[1].taxes.first { $0.id == "flat.wealth" }?.amount, 990))
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

    @Test func aCheckInOnTheLastDayOfTheYearStartsNextYear() async throws {
        let plan = Sample.plan(retire: .age(59), endAge: 64, retired: "10000")
        let result = try await Sample.run(plan, retiree)
        #expect(result.fan.first?.year == 2026)
        #expect(result.expectedPath.years.first?.fraction == 1)
    }

    @Test func lockedMoneyMakesABridgeFailure() async throws {
        // Born 1976, retiring at 49 with 50,000 liquid and 500,000 locked until 60.
        let library = Sample.library(birth: "1976-01-01", on: "2025-12-31", [
            SampleAccount(id: "broker", balance: 50_000),
            SampleAccount(id: "fund", kind: .pensionFund, wrapper: "flat.pension", balance: 500_000),
        ])
        let plan = Sample.plan(retire: .age(49), endAge: 70, retired: "30000", equityReturn: "0")
        let result = try await Sample.run(plan, library)

        let failure = try #require(result.expectedPath.failure)
        #expect(failure.year == 2027 && failure.age == 51)
        guard case .locked(let money) = failure.reason else {
            Issue.record("Expected a bridge failure, got \(failure.reason)")
            return
        }
        #expect(money.wrapper == "flat.pension" && money.name == "Pension fund")
        #expect(money.accessibleFromAge == 60 && money.value == 500_000)
        #expect(money.reason == "Locked until 60")
        #expect(result.failures.bridgeFailures == result.failures.runs)
        #expect(result.failures.bridges.first?.accessibleFromAge == 60)
        #expect(result.markers.contains { $0.kind == .accessible && $0.age == 60 && $0.label == "Pension fund" })

        // Retiring at 59, the fund opens in the second retirement year and carries the rest.
        let later = try await Sample.run(
            Sample.plan(retire: .age(59), endAge: 70, retired: "30000", equityReturn: "0"), library)
        #expect(later.expectedPath.failure == nil)
        let payout = later.expectedPath.years.first { $0.year == 2036 }?.income.first { $0.kind == .payout }
        #expect(payout?.id == "flat.pension")
    }

    @Test func pensionsReplaceWithdrawals() async throws {
        let plan = Sample.plan(
            retire: .age(59), endAge: 70, retired: "20000", equityReturn: "0",
            pensions: [
                PlanPension(scheme: .fixed, name: "Old job", fromAge: 62, perYear: d("12000")),
                PlanPension(scheme: "flat.state", options: ["montante": "200000", "contributionYears": "10"]),
                PlanPension(scheme: "flat.state", name: "Deferred", claim: .age(67),
                            options: ["montante": "100000", "contributionYears": "10"]),
            ])
        let library = Sample.library(birth: "1966-01-01", on: "2025-12-31",
                                     [SampleAccount(id: "broker", balance: 1_000_000)])
        let result = try await Sample.run(plan, library)

        // 2026–2027: 20,000 a year; from 2028 (62) the fixed pension pays 12,000.
        #expect(close(result.expectedValue(in: 2027), 960_000))
        #expect(close(result.expectedValue(in: 2028), 952_000))
        let year2028 = try #require(result.expectedPath.years.first { $0.year == 2028 })
        #expect(year2028.income.contains(IncomeItem(kind: .pension, id: "pension-0", label: "Old job", amount: 12_000)))

        // The scheme's earliest claim is 65 (2031): 5% of 200,000. The deferred one at 67: 5.4% of 100,000.
        let starts = Dictionary(uniqueKeysWithValues: result.markers.filter { $0.kind == .pensionStart }
            .map { ($0.label, ($0.age, $0.amount ?? 0)) })
        #expect(starts["Old job"]?.0 == 62)
        #expect(starts["State pension"]?.0 == 65 && close(starts["State pension"]?.1, 10_000))
        #expect(starts["Deferred"]?.0 == 67 && close(starts["Deferred"]?.1, 5_400))
        #expect(result.successCurve.first?.pensionStartAges == ["pension-0": 62, "pension-1": 65, "pension-2": 67])
        #expect(result.issues.contains { $0.code == "planner.duplicateScheme" })
        // From 67 the pensions (27,400) exceed spending, and the surplus is invested.
        #expect(close(result.expectedPath.years.first { $0.year == 2033 }?.savings, 7_400))
    }

    @Test func workBuildsASchemePension() async throws {
        // Born 1976: works 2026–2035 with 10% of 50,000 credited, retires at 60.
        var system = FlatTaxSystem()
        system.pensionCreditRate = 0.1
        let library = Sample.library(birth: "1976-01-01", on: "2025-12-31",
                                     [SampleAccount(id: "broker", balance: 100_000)])
        let plan = Sample.plan(retire: .age(60), endAge: 70, working: "50000", retired: "20000", equityReturn: "0",
                               work: [Sample.employee(from: "2026-01-01", gross: "50000")],
                               pensions: [PlanPension(scheme: "flat.state")])
        let result = try await Sample.run(plan, library, system: system)

        // Ten years of 5,000 credits: 50,000, paid at 5% from 65.
        let start = try #require(result.markers.first { $0.kind == .pensionStart })
        #expect(start.age == 65 && close(start.amount, 2_500))
        // Retiring now (49), there are no credits and no pension.
        #expect(result.successCurve.first { $0.age == 49 }?.pensionStartAges == [:])
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
        var system = FlatTaxSystem()
        system.windfallRate = 0.1
        let result = try await Sample.run(plan, retiree, system: system)

        // 2027: +45,000 after tax. 2029: −20,000. 2030: +900 (the 20% event is left out).
        #expect(close(result.expectedValue(in: 2026), 90_000))
        #expect(close(result.expectedValue(in: 2027), 125_000))
        #expect(close(result.expectedValue(in: 2028), 115_000))
        #expect(close(result.expectedValue(in: 2029), 85_000))
        #expect(close(result.expectedValue(in: 2030), 75_900))
        let year2027 = try #require(result.expectedPath.years.first { $0.year == 2027 })
        #expect(year2027.taxes.contains(AmountItem(id: "flat.windfall", label: "Windfall tax", amount: 5_000)))
        #expect(year2027.income.contains { $0.kind == .windfall && $0.label == "Gift" })
        #expect(result.markers.filter { $0.kind == .windfall }.map(\.label) == ["Gift", "Maybe", "Unlikely"])
        #expect(result.markers.first { $0.label == "Maybe" }?.probability == 0.8)

        // Each run draws the uncertain events: about 80% and 20% of runs get them.
        let ends = result.fan.last!
        #expect(ends.p10 < ends.p90)
    }

    @Test func contributionsGoIntoTheirAccount() async throws {
        let library = Sample.library(birth: "1986-01-01", on: "2025-12-31", [
            SampleAccount(id: "broker", balance: 0),
            SampleAccount(id: "fund", kind: .pensionFund, wrapper: "flat.pension", balance: 10_000),
        ])
        let plan = Sample.plan(retire: .age(45), endAge: 55, working: "40000", retired: "10000", equityReturn: "0",
                               work: [Sample.employee(from: "2026-01-01", gross: "60000")],
                               contributions: [PlanContribution(account: "fund", perYear: d("5000"))])
        let result = try await Sample.run(plan, library)

        // Five years of 5,000 into the fund, 15,000 a year into the liquid bucket.
        #expect(close(result.expectedValue(in: 2030), 10_000 + 5 * 20_000))
        let fund = try #require(result.start.buckets.first { $0.wrapper == "flat.pension" })
        #expect(fund.category == .taxDeferred && fund.accounts == ["fund"])
        #expect(close(result.expectedPath.years[0].savings, 20_000))
        // Retired at 45 with the fund locked until 60, the liquid 75,000 runs out at 52.
        #expect(result.expectedPath.failure?.age == 52)
    }

    @Test func creditsToAWrapperNoAccountUsesOpenABucket() async throws {
        var system = FlatTaxSystem()
        system.tfrRate = 0.1
        let library = Sample.library(birth: "1986-01-01", on: "2025-12-31",
                                     [SampleAccount(id: "broker", balance: 0)])
        let plan = Sample.plan(retire: .age(45), endAge: 50, working: "60000", retired: "10000", equityReturn: "0",
                               work: [Sample.employee(from: "2026-01-01", gross: "60000")])
        let result = try await Sample.run(plan, library, system: system)

        // 6,000 a year for five years, paid out when the job ends on 31 December
        // 2030 and invested in the liquid bucket; retirement draws on that.
        #expect(result.start.buckets.contains { $0.wrapper == "flat.tfr" })
        #expect(result.issues.contains { $0.code == "planner.newWrapper" })
        #expect(close(result.expectedValue(in: 2030), 30_000))
        #expect(close(result.expectedValue(in: 2031), 20_000))
        let lastWorkingYear = try #require(result.expectedPath.years.first { $0.year == 2030 })
        #expect(lastWorkingYear.income.contains(IncomeItem(kind: .payout, id: "flat.tfr", label: "Severance",
                                                           amount: 30_000)))
        #expect(close(lastWorkingYear.savings, 6_000))
        #expect(result.expectedPath.years.first { $0.year == 2031 }?.income.map(\.kind) == [.withdrawal])
    }

    @Test func theCashBufferIsDrawnLast() async throws {
        let library = Sample.library(birth: "1966-01-01", on: "2025-12-31", [
            SampleAccount(id: "cash", kind: .cash, mix: nil, balance: 20_000),
            SampleAccount(id: "broker", balance: 20_000),
        ])
        let plan = Sample.plan(retire: .age(59), endAge: 64, retired: "15000", equityReturn: "0", cashBuffer: "10000")
        let result = try await Sample.run(plan, library)

        // 2026 sells both halves alike, keeping the mix at 50/50; in 2027 half
        // the rest would be less than the buffer, so the buffer stays in cash
        // and everything else is sold; in 2028 only the buffer is left.
        #expect(close(result.expectedValue(in: 2026), 25_000))
        #expect(close(result.expectedValue(in: 2027), 10_000))
        #expect(result.expectedPath.failure?.age == 62)
    }
}
