import Foundation
import Model
@testable import Planner
import TaxKit
import Testing

/// How the engine uses what TaxKit tells it about wrappers and pensions:
/// cost basis and membership on payouts, revaluation set by law, severance
/// pay paid out when a job ends, the old-age pension age, the shared `fixed`
/// scheme, and year-by-year validation. Worked out by hand on the made-up
/// flat system, with zero volatility.
struct WrapperAndPensionTests {
    @Test(arguments: [true, false])
    func pensionFundPayoutsAreTaxedOnWhatWasPaidIn(exact: Bool) async throws {
        // Born 1960, retired, drawing 10,000 a year from a pension fund joined in 2006.
        let library = Sample.library(birth: "1960-01-01", on: "2025-12-31", [
            SampleAccount(id: "broker", balance: 0),
            SampleAccount(id: "fund", kind: .pensionFund, wrapper: "flat.pension", balance: 100_000,
                          joined: "2006-01-01"),
        ])
        var system = FlatTaxSystem()
        system.payoutRate = 0.15
        system.payoutOnCostBasis = true
        system.payoutDiscountPerMembershipYear = 0.003
        system.exactGrossUp = exact
        let plan = Sample.plan(retire: .age(65), endAge: 68, retired: "10000")
        let result = try await Sample.run(plan, library, system: system)

        // Each year: the rate is 15% less 0.3 points per year of membership (20
        // at the end of 2026), on the share of the payout that was paid in. The
        // fund earns 5%; what was paid in only shrinks by 2% inflation.
        var value = 100_000.0
        var paidIn = 100_000.0
        for (k, year) in (2026...2028).enumerated() {
            let rate = 0.15 - 0.003 * Double(20 + k)
            let taxedShare = paidIn / value
            let payout = 10_000 / (1 - rate * taxedShare)
            let tax = rate * payout * taxedShare
            paidIn *= (1 - payout / value) / 1.02
            value = (value - payout) * 1.05
            let tolerance = exact ? 1e-9 : 1e-6
            #expect(close(result.expectedValue(in: year), value, tolerance), "\(year)")
            let detail = try #require(result.expectedPath.years.first { $0.year == year })
            #expect(close(detail.taxes.first { $0.id == "flat.payout" }?.amount, tax, tolerance), "\(year)")
            #expect(close(detail.income.first { $0.kind == .payout }?.amount, payout, tolerance), "\(year)")
        }
    }

    @Test func severancePayIsRevaluedByLawAndPaidOutWhenTheJobEnds() async throws {
        // Born 1986: employed 2026–2028 with 10% of 60,000 credited to severance
        // pay, then self-employed until retiring at 45 (2031).
        let library = Sample.library(birth: "1986-01-01", on: "2025-12-31", [SampleAccount(id: "broker", balance: 0)])
        var system = FlatTaxSystem()
        system.tfrRate = 0.1
        system.tfrRevaluation = WrapperRevaluation(fixedRate: 0.015, inflationShare: 0.75)
        system.tfrGrowthTaxRate = 0.17
        system.payoutRate = 0.2
        system.payoutOnCostBasis = true
        system.payoutDiscountPerMembershipYear = 0.01
        let work = [Sample.employee(from: "2026-01-01", until: .date("2028-12-31"), gross: "60000"),
                    WorkPhase(kind: .selfEmployed, from: "2029-01-01", until: .retirement, revenue: d("60000"))]
        let plan = Sample.plan(retire: .age(45), endAge: 47, working: "60000", retired: "0", equityReturn: "0",
                               work: work)
        let result = try await Sample.run(plan, library, system: system)

        // It grows by 1.5% + 75% of 2% inflation, less 17% tax, in today's euros;
        // markets don't move it. The credits were paid in, deflated by inflation.
        let real = (1 + 0.03 * 0.83) / 1.02 - 1
        #expect(close(result.expectedValue(in: 2027), 6_000 * (1 + real) * (1 + real) + 6_000 * (1 + real)))
        let payout = 6_000 * ((1 + real) * (1 + real) + (1 + real) + 1)
        let paidIn = 6_000 * (1 / (1.02 * 1.02) + 1 / 1.02 + 1)
        // Paid when the job ends on 31 December 2028, after 2 years of
        // membership counted from the first credit: 20% − 2 points, withheld.
        let tax = 0.18 * paidIn
        let year2028 = try #require(result.expectedPath.years.first { $0.year == 2028 })
        #expect(close(year2028.income.first { $0.kind == .payout && $0.id == "flat.tfr" }?.amount, payout))
        #expect(close(year2028.taxes.first { $0.id == "flat.payout" }?.amount, tax))
        for year in 2028...2033 {
            #expect(close(result.expectedValue(in: year), payout - tax), "\(year)")
        }

        // Retiring at 41 ends the job at the end of 2026: the first credit is
        // paid at once, with no membership yet.
        let early = try await Sample.run(Sample.plan(retire: .age(41), endAge: 47, working: "60000", retired: "0",
                                                     equityReturn: "0", work: work),
                                         library, system: system)
        #expect(close(early.expectedValue(in: 2026), 6_000 * 0.8))
        #expect(early.expectedPath.years.first { $0.year == 2026 }?.income.contains { $0.kind == .payout } == true)
    }

    @Test func severancePayAlreadyThereIsPaidWhenTheJobHeldAtTheStartEnds() async throws {
        let library = Sample.library(birth: "1986-01-01", on: "2025-12-31", [
            SampleAccount(id: "broker", balance: 0),
            SampleAccount(id: "tfr", kind: .tfr, wrapper: "flat.tfr", mix: nil, balance: 20_000),
        ])
        var system = FlatTaxSystem()
        system.payoutRate = 0.1
        let job = Sample.employee(from: "2024-01-01", until: .date("2027-06-30"), gross: "50000")
        let plan = Sample.plan(retire: .age(50), endAge: 52, working: "0", retired: "0", equityReturn: "0",
                               work: [job])
        let result = try await Sample.run(plan, library, system: system)

        // The job ends on 30 June 2027: the 20,000 is paid then, less 10% tax.
        let firstHalf = 50_000 * 181.0 / 365
        #expect(close(result.expectedValue(in: 2026), 20_000 + 50_000))
        #expect(close(result.expectedValue(in: 2027), 50_000 + firstHalf + 18_000))
        let year2027 = try #require(result.expectedPath.years.first { $0.year == 2027 })
        #expect(year2027.income.contains(IncomeItem(kind: .payout, id: "flat.tfr", label: "Severance", amount: 20_000)))

        // Without a job at the start, it's paid at once.
        var noJob = plan
        noJob.work = []
        let paidAtOnce = try await Sample.run(noJob, library, system: system)
        #expect(close(paidAtOnce.expectedValue(in: 2026), 18_000))
    }

    @Test func theOldAgePensionAgeComesFromThePlansSchemesThenTheResidenceSystems() async throws {
        // Born 1976, retiring at 55 with a pension fund whose rule opens it at
        // the old-age pension age (60 when the planner doesn't know one).
        let library = Sample.library(birth: "1976-01-01", on: "2025-12-31", [
            SampleAccount(id: "broker", balance: 400_000),
            SampleAccount(id: "fund", kind: .pensionFund, wrapper: "flat.pension", balance: 100_000),
        ])
        func opens(_ result: PlanResult) -> Int? {
            result.markers.first { $0.kind == .accessible && $0.label == "Pension fund" }?.age
        }
        var system = FlatTaxSystem()
        system.oldAgePensionAge = 63
        let plan = Sample.plan(retire: .age(55), endAge: 70, retired: "20000", equityReturn: "0")

        #expect(opens(try await Sample.run(plan, library)) == 60)
        // The plan has no pensions: the residence system's scheme says 63.
        #expect(opens(try await Sample.run(plan, library, system: system)) == 63)
        // The plan's own scheme, with its options, comes first.
        var withPension = plan
        withPension.pensions = [PlanPension(scheme: "flat.state", options: ["oldAgePensionAge": "62"])]
        #expect(opens(try await Sample.run(withPension, library, system: system)) == 62)
    }

    @Test func aFixedPensionIsClaimedThroughTheSharedScheme() async throws {
        let library = Sample.library(birth: "1966-01-01", on: "2025-12-31",
                                     [SampleAccount(id: "broker", balance: 1_000_000)])
        let plan = Sample.plan(
            retire: .age(59), endAge: 70, retired: "20000", equityReturn: "0",
            pensions: [PlanPension(scheme: .fixed, name: "Old job", claim: .age(60), fromAge: 67, perYear: d("12000"))])
        let result = try await Sample.run(plan, library)

        // The statement pays from 67: asking for 60 claims it at 67, with a warning.
        let start = try #require(result.markers.first { $0.kind == .pensionStart })
        #expect(start.label == "Old job" && start.age == 67 && start.amount == 12_000)
        #expect(result.successCurve.first?.pensionStartAges == ["pension-0": 67])
        #expect(result.issues.contains { $0.code == "planner.claimLater" && $0.index == 0 })
        #expect(close(result.expectedValue(in: 2033), 1_000_000 - 7 * 20_000 - 8_000))
    }

    @Test func checksThatNeedEachYearsAmountsComeFromTheSystemsYearByYearValidation() async throws {
        var system = FlatTaxSystem()
        system.revenueLimit = 65_000
        let library = Sample.library(birth: "1976-01-01", on: "2025-12-31", [SampleAccount(id: "broker", balance: 100_000)])
        // The salary grows 5% a year: above 65,000 from 2028 until retiring at 56 (2032).
        let plan = Sample.plan(retire: .age(56), endAge: 80, working: "30000", retired: "30000",
                               work: [Sample.employee(from: "2026-01-01", gross: "60000", growth: "0.05")], runs: 20)
        let registry = Sample.registry(system)
        func limitYears(_ issues: [PlanIssue]) -> [Int?] {
            issues.filter { $0.code == "flat.revenueLimit" }.map(\.year)
        }

        let validated = Planner.validate(plan: plan, library: library, registry: registry)
        #expect(limitYears(validated) == [2028, 2029, 2030, 2031])
        #expect(validated.first { $0.code == "flat.revenueLimit" }?.section == .work)
        let result = try await Sample.run(plan, library, system: system)
        #expect(limitYears(result.issues) == [2028, 2029, 2030, 2031])
        #expect(Set(result.issues).count == result.issues.count)

        // With "earliest" the years aren't known until a run, which reports
        // them for the age its details are for.
        var earliest = plan
        earliest.retirement.age = .earliest
        #expect(limitYears(Planner.validate(plan: earliest, library: library, registry: registry)).isEmpty)
        let run = try await Sample.run(earliest, library, system: system,
                                       options: PlannerOptions(focusAge: 55, maxRetirementAge: 70,
                                                               solveSustainableSpending: false))
        #expect(limitYears(run.issues) == [2028, 2029, 2030])
    }
}
