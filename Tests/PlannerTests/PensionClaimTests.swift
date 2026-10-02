import Foundation
import Model
@testable import Planner
import TaxKit
import Testing

/// Claim options with lump sums, claim routes, annuities that change in real
/// terms, contributions into a scheme (buy-ins) and one-off ones, and
/// schemes started from accounts. Worked out by hand on the made-up flat
/// system's `flat.fund` scheme, with zero volatility and returns.
struct PensionClaimTests {
    /// Born 1966: 60 in 2026, retiring then, with nothing in the bank.
    let retiree = Sample.library(birth: "1966-01-01", on: "2025-12-31", [SampleAccount(id: "broker", balance: 0)])

    func plan(route: String? = nil, balance: String = "200000") -> PlanDocument {
        var plan = Sample.plan(retire: .age(60), endAge: 63, retired: "0", equityReturn: "0", runs: 10)
        plan.pensions = [PlanPension(scheme: "flat.fund", claim: .age(60), options: ["startingBalance": .string(balance)],
                                     claimRoute: route)]
        return plan
    }

    var system: FlatTaxSystem {
        var system = FlatTaxSystem()
        system.incomeRate = 0.2
        system.lumpSumRate = 0.1
        return system
    }

    func year(_ result: PlanResult, _ year: Int) throws -> YearDetail {
        try #require(result.expectedPath.years.first { $0.year == year })
    }

    @Test func aLumpSumIsTaxedAndPaidIntoTheLiquidBucket() async throws {
        // Half of 200,000 as a lump sum (taxed 10%), and 2.5% a year (taxed 20%).
        let result = try await Sample.run(plan(route: "flat.fund.half"), retiree, system: system)
        let first = try year(result, 2026)
        #expect(first.income.contains(IncomeItem(kind: .pension, id: "pension-0.lumpSum", label: "Fund (lump sum)",
                                                 amount: 100_000)))
        #expect(first.income.contains(IncomeItem(kind: .pension, id: "pension-0", label: "Fund", amount: 5_000)))
        #expect(close(first.taxes.first { $0.id == "flat.lumpSum" }?.amount, 10_000))
        #expect(close(first.taxes.first { $0.id == "flat.income" }?.amount, 1_000))
        #expect(close(result.expectedValue(in: 2026), 94_000))
        // Only once: the next year pays the annuity alone.
        let second = try year(result, 2027)
        #expect(!second.income.contains { $0.id == "pension-0.lumpSum" })
        #expect(close(result.expectedValue(in: 2027), 98_000))

        let fixed = try Sample.fixedYears(plan(route: "flat.fund.half"), retiree, system: system, age: 60)
        let lumpSum = try #require(fixed.first?.pensions.first { $0.form == .lumpSum })
        #expect(lumpSum.id == "pension-0.lumpSum" && lumpSum.amount == 100_000 && lumpSum.kind == .occupational)
        #expect(lumpSum.mandatoryShare == 0.5 && lumpSum.startYear == 2026)
        #expect(fixed[1].pensions.map(\.form) == [.annuity])
    }

    @Test func theRouteChoosesAmongOptionsAtTheSameAge() async throws {
        // Without a route, the scheme's first option: the annuity, 5% a year.
        let annuity = try await Sample.run(plan(), retiree, system: system)
        #expect(try year(annuity, 2026).income.map(\.id) == ["pension-0"])
        #expect(close(annuity.expectedValue(in: 2026), 8_000))
        // All as capital: no annuity at all.
        let capital = try await Sample.run(plan(route: "flat.fund.capital"), retiree, system: system)
        #expect(try year(capital, 2026).income.map(\.id) == ["pension-0.lumpSum"])
        #expect(close(capital.expectedValue(in: 2027), 180_000))
        #expect(capital.markers.contains { $0.kind == .pensionStart && $0.year == 2026 })

        // A route the scheme never offers: never paid, with a warning.
        let unknown = try await Sample.run(plan(route: "flat.fund.nothing"), retiree, system: system)
        #expect(unknown.issues.contains { $0.code == "planner.claimRoute" && $0.option == "claimRoute" })
        #expect(try year(unknown, 2026).income.isEmpty)
    }

    @Test func anAnnuityChangesInRealTermsAfterTheClaim() async throws {
        var shrinking = system
        shrinking.fundAnnuityGrowth = -0.01
        let result = try await Sample.run(plan(route: "flat.fund.annuity"), retiree, system: shrinking)
        for (k, year) in (2026...2029).enumerated() {
            let paid = try self.year(result, year).income.first { $0.id == "pension-0" }?.amount
            #expect(close(paid, 10_000 * pow(0.99, Double(k))), "\(year)")
        }
        #expect(result.markers.first { $0.kind == .pensionStart }?.amount == 10_000)
    }

    @Test func aLumpSumCanMoveIntoAWrapperUntaxed() async throws {
        // Born 1976, working in 2026–2027 and spending all of it; stopping at 52
        // (2028), before the fund pays at 60: its 100,000 move to `flat.vested`.
        let library = Sample.library(birth: "1976-01-01", on: "2025-12-31", [SampleAccount(id: "broker", balance: 0)])
        var plan = Sample.plan(retire: .age(52), endAge: 54, working: "50000", retired: "0", equityReturn: "0",
                               work: [Sample.employee(from: "2026-01-01", gross: "50000")], runs: 10)
        plan.pensions = [PlanPension(scheme: "flat.fund", claim: .earliest, options: ["startingBalance": "100000"])]
        let result = try await Sample.run(plan, library)

        #expect(close(result.expectedValue(in: 2027), 0))
        #expect(close(result.expectedValue(in: 2028), 100_000))
        let transfer = try year(result, 2028)
        #expect(!transfer.taxes.contains { $0.id == "flat.lumpSum" } && !transfer.income.contains { $0.kind == .pension })
        #expect(close(transfer.savings, 100_000))
        #expect(result.start.buckets.contains { $0.wrapper == "flat.vested" && $0.value == 0 })
        #expect(result.issues.contains { $0.code == "planner.newWrapper" })
    }

    @Test func aBuyInIsPaidFromSavingsAndCreditedToTheScheme() async throws {
        // Born 1976, saving 40,000 a year; 20,000 bought into the fund in 2027 is
        // all it holds when it pays out as capital at 60 (2036).
        let library = Sample.library(birth: "1976-01-01", on: "2025-12-31", [SampleAccount(id: "broker", balance: 0)])
        var plan = Sample.plan(retire: .age(55), endAge: 61, working: "60000", retired: "0", equityReturn: "0",
                               work: [Sample.employee(from: "2026-01-01", gross: "100000")],
                               contributions: [PlanContribution(pension: "flat.fund", amount: 20_000, year: 2027)],
                               runs: 10)
        plan.pensions = [PlanPension(scheme: "flat.fund", claim: .age(60), claimRoute: "flat.fund.capital")]
        let result = try await Sample.run(plan, library)

        #expect(close(result.expectedValue(in: 2026), 40_000))
        #expect(close(result.expectedValue(in: 2027), 60_000))
        #expect(close(result.expectedValue(in: 2028), 100_000))
        #expect(try year(result, 2036).income.contains(IncomeItem(kind: .pension, id: "pension-0.lumpSum",
                                                                  label: "Fund (lump sum)", amount: 20_000)))
        let fixed = try Sample.fixedYears(plan, library, age: 55)
        #expect(fixed[1].wrapperContributions == [FixedYear.WrapperContribution(wrapper: "flat.fund", amount: 20_000,
                                                                                source: "contribution-0")])
        #expect(fixed[0].wrapperContributions.isEmpty && fixed[2].wrapperContributions.isEmpty)
        #expect(!result.issues.contains { $0.code.hasPrefix("planner.contribution") })
    }

    @Test func contributionsIntoSchemesAreChecked() async throws {
        let library = Sample.library(birth: "1976-01-01", on: "2025-12-31", [SampleAccount(id: "broker", balance: 0)])
        var plan = Sample.plan(retire: .age(55), endAge: 57, working: "60000", retired: "0",
                               work: [Sample.employee(from: "2026-01-01", gross: "100000")],
                               contributions: [PlanContribution(pension: "flat.state", perYear: 1_000),
                                               PlanContribution(pension: "nowhere.scheme", amount: 1, year: 2027),
                                               PlanContribution(pension: "flat.fund", amount: 1, year: 2027)],
                               runs: 10)
        plan.pensions = [PlanPension(scheme: "flat.state", claim: .age(65))]
        let result = try await Sample.run(plan, library)
        // The flat system doesn't credit payments into its state scheme.
        #expect(result.issues.contains { $0.code == "planner.contributionNotCredited" })
        #expect(result.issues.contains { $0.code == "planner.contributionScheme" && $0.index == 1 })
        #expect(result.issues.contains { $0.code == "planner.contributionWithoutPension" && $0.index == 2 })

        var both = PlanContribution(account: "broker", perYear: 1)
        both.pension = "flat.fund"
        var twice = PlanContribution(account: "broker", amount: 1, year: 2027)
        twice.perYear = 5
        var noYear = PlanContribution(account: "broker", perYear: 0)
        noYear.amount = 5
        plan.contributions = [both, twice, noYear]
        let issues = Planner.validate(plan: plan, library: library, registry: Sample.registry())
        #expect(issues.contains { $0.code == "planner.contributionTarget" && $0.isError && $0.index == 0 })
        #expect(issues.contains { $0.code == "planner.contributionAmount" && $0.isError && $0.index == 1 })
        #expect(issues.contains { $0.code == "planner.contributionYear" && $0.isError && $0.index == 2 })
    }

    @Test func aOneOffContributionIsPaidInItsYearOnly() async throws {
        let library = Sample.library(birth: "1966-01-01", on: "2025-12-31", [
            SampleAccount(id: "broker", mix: [.cash: 1], balance: 10_000),
            SampleAccount(id: "fund", kind: .pensionFund, wrapper: "flat.pension", mix: [.cash: 1], balance: 0),
        ])
        let plan = Sample.plan(retire: .age(59), endAge: 63, retired: "0", equityReturn: "0",
                               contributions: [PlanContribution(account: "fund", amount: 5_000, year: 2027)], runs: 10)
        let fixed = try Sample.fixedYears(plan, library, age: 59)
        #expect(fixed.map(\.wrapperContributions) == [
            [], [FixedYear.WrapperContribution(wrapper: "flat.pension", amount: 5_000, source: "contribution-0")], [], [],
        ])
        let result = try await Sample.run(plan, library)
        #expect(close(result.expectedValue(in: 2027), 10_000))
        #expect(close(try year(result, 2027).income.first { $0.kind == .withdrawal }?.amount, 5_000))
        #expect(try year(result, 2028).income.isEmpty)
    }

    @Test func anAccountCanStartAScheme() async throws {
        // A fund balance tracked as an account (wrapper `flat.fundAccount`, the
        // scheme's seed wrapper) is the scheme's starting balance, not a bucket.
        let library = Sample.library(birth: "1966-01-01", on: "2025-12-31", [
            SampleAccount(id: "broker", mix: [.cash: 1], balance: 50_000),
            SampleAccount(id: "fund-account", kind: .pensionFund, wrapper: "flat.fundAccount", balance: 120_000),
        ])
        var plan = Sample.plan(retire: .age(60), endAge: 62, retired: "0", equityReturn: "0", runs: 10)
        plan.pensions = [PlanPension(scheme: "flat.fund", claim: .age(60), claimRoute: "flat.fund.capital")]
        let result = try await Sample.run(plan, library)

        #expect(result.start.planAssets == 50_000 && result.start.accounts == ["broker"])
        #expect(!result.start.buckets.contains { $0.wrapper == "flat.fundAccount" })
        #expect(result.start.schemeSeeds == [SchemeSeed(scheme: "flat.fund", name: "Fund", wrapper: "flat.fundAccount",
                                                        accounts: ["fund-account"], value: 120_000, used: true)])
        #expect(try year(result, 2026).income.first { $0.id == "pension-0.lumpSum" }?.amount == 120_000)
        #expect(close(result.expectedValue(in: 2026), 170_000))
        #expect(!result.issues.contains { $0.code == "planner.unknownWrapper" })

        // The plan's own starting balance wins, with a warning.
        plan.pensions[0].options = ["startingBalance": "80000"]
        let replaced = try await Sample.run(plan, library)
        #expect(replaced.issues.contains { $0.code == "planner.seedReplaced" })
        #expect(replaced.start.schemeSeeds.first?.used == false)
        #expect(close(replaced.expectedValue(in: 2026), 130_000))

        // Without a pension with the scheme, the account is an account.
        plan.pensions = []
        let alone = try await Sample.run(plan, library)
        #expect(alone.issues.contains { $0.code == "planner.seedWithoutPension" && $0.account == "fund-account" })
        #expect(alone.start.planAssets == 170_000 && alone.start.schemeSeeds.isEmpty)
    }
}
