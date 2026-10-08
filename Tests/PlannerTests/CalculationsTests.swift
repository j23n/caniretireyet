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
    static func plan(flexible: FlexibleSpending? = nil) -> PlanDocument {
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
        plan.spending.flexible = flexible
        return plan
    }

    func report(_ plan: PlanDocument = plan(), anonymize: Bool = false) async throws -> String {
        try await Planner.calculations(plan: plan, library: Self.library,
                                       options: CalculationsOptions(anonymize: anonymize, today: "2026-01-02"))
    }

    @Test func everySectionIsThere() async throws {
        let text = try await report()
        for heading in ["# Calculations: Secret plan", "## The answer", "## The plan as read", "## The starting portfolio",
                        "## Chance of success by retirement age", "## The deterministic run (expected returns), retiring at 50",
                        "## The median run, retiring at 50", "## When runs fail"] {
            #expect(text.contains(heading + "\n"), "\(heading)")
        }
        #expect(text.contains("- Taxes: 26% on investment income and gains; wealth tax 0.2% above 50,000."))
        #expect(text.contains("| Secret employer | 2026-01-01 | retirement | 52,345 | 0% |"))
        #expect(text.contains("| Statement pension | 67 | 9,000 |"))
        #expect(text.contains("| secret-fund | 3,000 a year | until retirement |"))
        #expect(text.contains("| Gift from aunt | 2040 | 40,000 | 100% |"))
        #expect(text.contains("| secret-fund | 60 | 50,000 | 50,000 | bonds 40%, equity 60% |"))
        #expect(!text.contains("## Flexible spending"))
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

    @Test func flexibleSpendingHasItsOwnSection() async throws {
        let text = try await report(Self.plan(flexible: FlexibleSpending()))
        #expect(text.contains("- Flexible spending: cuts of 10% down to 80%"))
        #expect(text.contains("## Flexible spending, retiring at 50\n"))
        #expect(text.contains("can't pay even the floor of 24,000 a year."))
    }
}
