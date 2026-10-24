import Foundation
import Model
@testable import Planner
import Testing
import TestSupport

/// The calculations report (PLANNER.md, "Calculations"): every input and
/// result behind the answer, as Markdown, and its anonymized form.
struct CalculationsTests {
    /// Born 1980-01-01, 45 on the start date: an equity brokerage account and
    /// a pension fund available from 60.
    static let library = Sample.library(birth: "1980-01-01", on: "2025-12-31", [
        SampleAccount(id: "secret-broker", balance: 400_123),
        SampleAccount(id: "secret-fund", kind: .pensionFund, mix: [.equity: 0.6, .bonds: 0.4], balance: 50_000,
                      availableFromAge: 60),
    ])

    /// Work to 50, then 30,000 a year to 85, a pension from 67, a windfall, an
    /// expense and a contribution into the fund.
    static func plan() -> PlanDocument {
        var plan = Sample.plan(
            retire: .age(50), endAge: 85, working: "35000", retired: "30000", volatility: "0.17",
            work: [WorkPhase(name: "Secret employer", from: "2026-01-01", until: .retirement, netIncome: d("52345"))],
            pensions: [PlanPension(name: "Statement pension", fromAge: 67, perYear: d("9000"))],
            contributions: [PlanContribution(account: "secret-fund", perYear: d("3000"))],
            events: [PlanEvent(name: "Gift from aunt", timing: .year(2040), amount: d("40000")),
                     PlanEvent(name: "Roof", timing: .age(58), amount: d("-15000"))],
            investmentRate: "0.26", wealthRate: "0.002", wealthAllowance: "50000", unrealizedGainShare: "0.3",
            runs: 100)
        plan.name = "Secret plan"
        return plan
    }

    func report(_ plan: PlanDocument = plan(), anonymize: Bool = false) async throws -> String {
        try await Planner.calculations(plan: plan, library: Self.library,
                                       options: CalculationsOptions(anonymize: anonymize, today: "2026-01-02"))
    }

    @Test func theYearTablesHaveARowPerYear() async throws {
        let text = try await report()
        let lines = text.components(separatedBy: "\n")
        let start = try #require(lines.firstIndex { $0.hasPrefix("## The deterministic run") })
        let rows = lines[(start + 4)...].prefix { $0.hasPrefix("| ") }
        let result = try await Planner.run(plan: Self.plan(), library: Self.library,
                                           options: PlannerOptions(today: "2026-01-02"))
        #expect(rows.count == result.expectedPath.years.count)
        #expect(rows.first?.hasPrefix("| 2026 | 46 | 52,345 |") == true)
        if let failure = result.expectedPath.failure {
            #expect(text.contains("The money runs out in \(failure.year), at \(failure.age)."))
        }
    }

    @Test func anonymizingRemovesNamesAndDatesAndRoundsAmounts() async throws {
        let text = try await report(anonymize: true)
        for secret in ["Secret", "secret-", "Gift from aunt", "Statement pension", "Roof", "2025-12-31", "2026-01-01",
                       "52,345", "400,123"] {
            #expect(!text.contains(secret), "\(secret)")
        }
        #expect(text.contains("# Calculations: Plan\n"))
        #expect(text.contains("| Work 1 | 2026 | retirement | 52,300 | 0% |"))
        #expect(text.contains("| Accounts available later 1 | 60 | 50,000 | 50,000 |"))
        #expect(text.contains("starting in 2025,"))
    }

    /// A pre-tax account shows its rate in the starting portfolio, and the
    /// years their tax on withdrawals next to the other two taxes.
    @Test func preTaxAccountsShowTheirTaxOnWithdrawals() async throws {
        let library = Sample.library(birth: "1966-01-01", on: "2025-12-31", [
            SampleAccount(id: "secret-broker", balance: 100_000),
            SampleAccount(id: "secret-ira", kind: .pensionFund, balance: 50_000, withdrawalTaxRate: d("0.2")),
        ])
        let plan = Sample.plan(retire: .age(59), endAge: 64, retired: "10000", equityReturn: "0",
                               investmentRate: "0.25", unrealizedGainShare: "0.5")
        let text = try await Planner.calculations(plan: plan, library: library,
                                                  options: CalculationsOptions(anonymize: true, today: "2026-01-02"))
        #expect(text.contains("| Accounts | Available from | Value | Purchase cost | Mix | Tax on withdrawals |"))
        #expect(text.contains("| Money you can draw | now | 100,000 | 50,000 | equity 100% | – |"))
        #expect(text.contains("| Pre-tax accounts 1 | now | 50,000 | 50,000 | equity 100% | 20% |"))
        #expect(text.contains("| Tax on investments | Wealth tax | Tax on withdrawals | Sold |"))
        #expect(text.contains("pre-tax accounts pay their own rate"))

        // 2026: s × (100,000 × 0.875 + 50,000 × 0.8) = 10,000, so s = 10,000 / 127,500:
        // the IRA's 3,922 sold pays 784 (rounded to 800).
        let lines = text.components(separatedBy: "\n")
        let start = try #require(lines.firstIndex { $0.hasPrefix("## The deterministic run") })
        let first = try #require(lines[(start + 4)...].first)
        #expect(first.hasPrefix("| 2026 | 60 | 0 | 0 | 10,000 | 0 | 1,000 | 0 | 800 |"), "\(first)")
    }
}
