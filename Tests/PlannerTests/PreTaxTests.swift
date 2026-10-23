import Foundation
import Model
@testable import Planner
import Testing
import TestSupport

/// Pre-tax accounts (`withdrawalTaxRate`, PLANNER.md, "The yearly step"):
/// every amount taken from one pays its rate, in place of the investment
/// rate, which taxes neither its gains nor its income yield. Worked out by
/// hand with zero volatility, from a year-end start.
struct PreTaxTests {
    @Test func aPreTaxAccountPaysItsRateOnWhatsTakenFromIt() async throws {
        let library = Sample.library(birth: "1966-01-01", on: "2025-12-31", [
            SampleAccount(id: "ira", kind: .pensionFund, balance: 100_000, withdrawalTaxRate: d("0.25")),
        ])
        let plan = Sample.plan(retire: .age(59), endAge: 64, retired: "9000", equityReturn: "0",
                               investmentRate: "0.1")
        let result = try await Sample.run(plan, library)

        // 9,000 after a quarter's tax: 12,000 sold, 3,000 of it tax.
        let first = try #require(result.expectedYear(2026))
        #expect(close(first.income.first { $0.kind == .withdrawal }?.amount, 12_000))
        #expect(close(first.withdrawalTax, 3_000))
        #expect(first.investmentTax == 0)
        #expect(close(result.expectedValue(in: 2026), 88_000))
        // The pre-tax money is a group of its own; the money you can draw holds nothing taxable.
        #expect(result.start.buckets.map(\.withdrawalTaxRate) == [nil, 0.25])
        #expect(result.start.buckets.map(\.availableFromAge) == [nil, nil])
        #expect(result.start.buckets[1].accounts == ["ira"])
        // Its gains are never taxed, so not knowing what was paid doesn't matter.
        #expect(!result.issues.contains { $0.code == "planner.unknownCostBasis" })
    }

    @Test func aRateOfZeroTaxesNeitherGainsNorIncome() async throws {
        func run(_ rate: Decimal?) async throws -> PlanResult {
            let library = Sample.library(birth: "1966-01-01", on: "2025-12-31", [
                SampleAccount(id: "roth", kind: .pensionFund, balance: 100_000, withdrawalTaxRate: rate),
            ])
            let plan = Sample.plan(retire: .age(59), endAge: 64, retired: "10000", equityReturn: "0.05",
                                   equityYield: "0.02", inflation: "0", investmentRate: "0.25",
                                   unrealizedGainShare: "0.5")
            return try await Sample.run(plan, library)
        }
        let roth = try await run(0)
        // 10,000 a year, untaxed, then 5%: V_k = (V_{k−1} − 10,000) × 1.05.
        #expect(roth.expectedPath.years.allSatisfy { $0.totalTax == 0 })
        #expect(close(roth.expectedValue(in: 2026), 94_500))
        #expect(close(roth.expectedValue(in: 2027), 88_725))
        // The same account as taxable money pays on its gains and its income yield.
        let taxable = try await run(nil)
        #expect(taxable.expectedPath.years.allSatisfy { $0.withdrawalTax == 0 })
        #expect((taxable.expectedYear(2026)?.investmentTax ?? 0) > 0)
        #expect((taxable.expectedYear(2027)?.investmentTax ?? 0) > 0)
    }

    @Test func aLockedPreTaxAccountKeepsItsRateOnceOpen() async throws {
        // 62 on 1 January 2028: the broker pays for 2026 and 2027, the fund from 2028.
        let library = Sample.library(birth: "1966-01-01", on: "2025-12-31", [
            SampleAccount(id: "broker", balance: 20_000),
            SampleAccount(id: "fund", kind: .pensionFund, balance: 100_000, availableFromAge: 62,
                          withdrawalTaxRate: d("0.2")),
        ])
        let plan = Sample.plan(retire: .age(59), endAge: 64, retired: "10000", equityReturn: "0", inflation: "0",
                               investmentRate: "0.25", unrealizedGainShare: "0")
        let result = try await Sample.run(plan, library)

        let fund = try #require(result.start.buckets.first { $0.accounts == ["fund"] })
        #expect(fund.availableFromAge == 62 && fund.withdrawalTaxRate == 0.2)
        #expect(result.expectedYear(2026)?.totalTax == 0)
        #expect(close(result.expectedValue(in: 2027), 100_000))
        // 10,000 after a fifth's tax: 12,500 sold, 2,500 of it tax; no tax on gains.
        let opened = try #require(result.expectedYear(2028))
        #expect(close(opened.withdrawalTax, 2_500))
        #expect(opened.investmentTax == 0)
        #expect(close(opened.endAssets, 87_500))
        #expect(result.markers.contains { $0.kind == .accessible && $0.age == 62 && $0.label == "fund" })
    }

    @Test func groupsWithDifferentRatesAreKeptApart() async throws {
        let library = Sample.library(birth: "1966-01-01", on: "2025-12-31", [
            SampleAccount(id: "high", kind: .pensionFund, balance: 50_000, withdrawalTaxRate: d("0.4")),
            SampleAccount(id: "low", kind: .pensionFund, balance: 50_000, withdrawalTaxRate: d("0.2")),
            SampleAccount(id: "low-too", kind: .pensionFund, balance: 10_000, withdrawalTaxRate: d("0.2")),
        ])
        let plan = Sample.plan(retire: .age(59), endAge: 64, retired: "9000", equityReturn: "0")
        let result = try await Sample.run(plan, library)

        // Accounts with the same rate share a group, ordered by rate.
        #expect(result.start.buckets.map(\.withdrawalTaxRate) == [nil, 0.2, 0.4])
        #expect(result.start.buckets[1].accounts == ["low", "low-too"])
        // s × (60,000 × 0.8 + 50,000 × 0.6) = 9,000: s = 9,000 / 78,000.
        let share = 9_000 / 78_000.0
        let first = try #require(result.expectedYear(2026))
        #expect(close(first.income.first { $0.kind == .withdrawal }?.amount, share * 110_000))
        #expect(close(first.withdrawalTax, share * (60_000 * 0.2 + 50_000 * 0.4)))
        #expect(close(first.endAssets, (1 - share) * 110_000))
    }

    /// Locked pre-tax money bridges a gap only with what it brings in after
    /// its rate: here 10,000 in 2027 and 30,000 a year from 52 to 59,
    /// 250,000 in all (`DeterministicTests`).
    @Test func lockedPreTaxMoneyBridgesAfterItsRate() async throws {
        func failure(fund: Decimal) async throws -> RunFailure? {
            let library = Sample.library(birth: "1976-01-01", on: "2025-12-31", [
                SampleAccount(id: "broker", balance: 50_000),
                SampleAccount(id: "fund", kind: .pensionFund, balance: fund, availableFromAge: 60,
                              withdrawalTaxRate: d("0.5")),
            ])
            let plan = Sample.plan(retire: .age(49), endAge: 70, retired: "30000", equityReturn: "0")
            return try await Sample.run(plan, library).expectedPath.failure
        }
        // 480,000 brings in 240,000; 520,000 brings in 260,000.
        #expect(try await failure(fund: 480_000) == RunFailure(year: 2027, age: 51, reason: .depleted))
        let bridged = try #require(try await failure(fund: 520_000))
        #expect(bridged.reason == .locked(LockedMoney(name: "fund", accessibleFromAge: 60)))
    }

    /// The wealth tax counts open pre-tax money as part of the money you can
    /// draw, and locked pre-tax money not until it opens.
    @Test func openPreTaxMoneyIsWealthTaxed() async throws {
        let library = Sample.library(birth: "1966-01-01", on: "2025-12-31", [
            SampleAccount(id: "broker", balance: 100_000),
            SampleAccount(id: "ira", kind: .pensionFund, balance: 100_000, withdrawalTaxRate: d("0.2")),
            SampleAccount(id: "fund", kind: .pensionFund, balance: 100_000, availableFromAge: 63,
                          withdrawalTaxRate: d("0.2")),
        ])
        let plan = Sample.plan(retire: .age(59), endAge: 64, retired: "0", equityReturn: "0", wealthRate: "0.01")
        let result = try await Sample.run(plan, library)
        // 2026: 1% of the broker and the IRA. The tax is paid by a sale, taxed on
        // the IRA's part: 2,000 = s × (100,000 + 100,000 × 0.8).
        let first = try #require(result.expectedYear(2026))
        #expect(close(first.wealthTax, 2_000))
        #expect(close(first.withdrawalTax, 2_000 / 180_000.0 * 100_000 * 0.2))
    }

    /// Without investment tax or an income yield, a pre-tax account at 0%
    /// draws, rebalances and is wealth-taxed exactly as the same account
    /// without a rate: grouping money apart changes nothing on its own.
    @Test func aRateOfZeroWithoutInvestmentTaxPlansLikeNoRate() async throws {
        func run(_ rate: Decimal?) async throws -> PlanResult {
            let library = Sample.library(birth: "1970-01-01", on: "2025-12-31", [
                SampleAccount(id: "broker", balance: 300_000),
                SampleAccount(id: "ira", kind: .pensionFund, mix: [.bonds: 1], balance: 200_000,
                              withdrawalTaxRate: rate),
            ])
            let plan = Sample.plan(retire: .age(60), endAge: 90, working: "20000", retired: "25000",
                                   volatility: "0.17",
                                   work: [Sample.work(from: "2026-01-01", net: "30000")],
                                   wealthRate: "0.002", wealthAllowance: "50000", unrealizedGainShare: "0.3",
                                   runs: 200)
            return try await Sample.run(plan, library, options: PlannerOptions(maxRetirementAge: 62,
                                                                              solveSustainableSpending: false))
        }
        let preTax = try await run(0)
        let plain = try await run(nil)
        #expect(preTax.start.buckets.count == 2 && plain.start.buckets.count == 1)
        #expect(preTax.expectedPath.years.count == plain.expectedPath.years.count)
        for (a, b) in zip(preTax.expectedPath.years, plain.expectedPath.years) {
            #expect(close(a.endAssets, b.endAssets, 1e-9))
            #expect(close(a.wealthTax, b.wealthTax, 1e-9))
            #expect(a.withdrawalTax == 0)
        }
        for (a, b) in zip(preTax.successCurve, plain.successCurve) {
            #expect(a.age == b.age && abs(a.success - b.success) <= 0.01)
        }
    }

    @Test func aRateOutsideZeroToOneIsAnError() throws {
        let library = Sample.library(birth: "1966-01-01", on: "2025-12-31", [
            SampleAccount(id: "ira", kind: .pensionFund, balance: 100_000, withdrawalTaxRate: d("1.5")),
        ])
        let plan = Sample.plan(retire: .age(59), endAge: 64, retired: "10000")
        let (model, issues) = PlanInterpreter.interpret(plan: plan, library: library, options: PlannerOptions())
        #expect(model == nil)
        #expect(issues.contains { $0.code == "planner.withdrawalTaxRate" && $0.isError && $0.account == "ira" })
    }

    /// The year's withdrawal tax is one of the chart's taxes, and the chapter
    /// card's average counts it (`totalTax`).
    @Test func theWithdrawalTaxIsOneOfTheTaxes() {
        let year = YearDetail(year: 2040, age: 60, endAssets: 100_000, spending: 30_000, investmentTax: 500,
                              wealthTax: 200, withdrawalTax: 4_000)
        #expect(year.totalTax == 4_700)
        let taxes = PlanResultsMapping.taxes([year])
        #expect(taxes.map(\.source) == ["Tax on withdrawals", "Tax on investments", "Wealth tax"])
        #expect(taxes.first?.amount == 4_000)
    }
}
