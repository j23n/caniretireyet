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

    /// Crypto at a 0% median and 70% volatility averages 16.6% a year,
    /// which a mix collects part of: the report says so under the returns.
    @Test func aClassWhoseAverageIsFarAboveItsTypicalYearIsExplained() async throws {
        #expect(!(try await report()).contains("far above its typical year"))
        var plan = Self.plan()
        plan.assumptions.returns[.crypto] = ReturnAssumption(medianReal: 0, volatility: d("0.7"))
        plan.portfolio.targetMix = [.equity: d("0.8"), .crypto: d("0.2")]
        let text = try await report(plan)
        #expect(text.contains("Crypto's average year (16.6%) is far above its typical year (0%), because of its "
            + "volatility."))
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

    // MARK: The rows add up

    /// A year table's rows as numbers: Year, Age, Income, Windfalls,
    /// Spending, Expenses, the three taxes, Sold, Saved, At the end.
    private func rows(_ text: String, table: String) throws -> [[Double]] {
        let lines = text.components(separatedBy: "\n")
        let start = try #require(lines.firstIndex { $0.hasPrefix("## \(table)") })
        #expect(lines[start + 2] == "| Year | Age | Income | Windfalls | Spending | Expenses | Tax on investments | "
            + "Wealth tax | Tax on withdrawals | Sold | Saved | At the end |")
        return try lines[(start + 4)...].prefix { $0.hasPrefix("| ") }.map { line in
            try line.split(separator: "|").map { cell in
                let text = cell.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: "")
                    .replacingOccurrences(of: "\u{2212}", with: "-")
                return try #require(Double(text), "\(line)")
            }
        }
    }

    /// Every year of both tables adds up as PLANNER.md's yearly step does
    /// (`YearRow`): income, windfalls and what was sold, less spending,
    /// expenses and the taxes paid from the year's money, is what was
    /// saved into accounts; the first year's tax on withdrawals holds the
    /// tax paying off debts took from pre-tax money at the start, which the
    /// year's money didn't pay. With every class at one return and no
    /// volatility, the value at the end is what was there after the year's
    /// money moved, grown by it. Amounts are rounded to whole units, so a row is checked to 6.
    @Test(arguments: [false, true])
    func everyRowAddsUp(debtFromPreTaxMoney: Bool) async throws {
        var plan = Self.plan()
        // A car while working: a year that sells and pays into the fund.
        plan.events.append(PlanEvent(name: "Car", timing: .year(2028), amount: d("-60000")))
        plan.assumptions = YearRowTests.oneReturn(plan.assumptions, "0.03")
        var library = Self.library
        if debtFromPreTaxMoney {
            library = Sample.library(birth: "1980-01-01", on: "2025-12-31", [
                SampleAccount(id: "secret-broker", kind: .cash, mix: nil, balance: 5_000),
                SampleAccount(id: "secret-ira", balance: 450_000, withdrawalTaxRate: d("0.2")),
                SampleAccount(id: "secret-fund", kind: .pensionFund, mix: [.equity: 0.6, .bonds: 0.4],
                              balance: 50_000, availableFromAge: 60),
                SampleAccount(id: "secret-loan", kind: .loan, mix: nil, balance: -25_000),
            ])
        }
        let run = try await Planner.computeRun(plan: plan, library: library,
                                               options: PlannerOptions(today: "2026-01-02"), progress: nil)
        let text = CalculationsReport(result: run.result, model: run.model, options: CalculationsOptions()).markdown
        let debtTax = run.model.portfolio.debtWithdrawalTax
        #expect((debtTax > 0) == debtFromPreTaxMoney)
        let start = run.result.start.planAssets.doubleValue
        for (table, path) in [("The deterministic run", run.result.expectedPath),
                              ("The median run", run.result.medianPath)] {
            let rows = try rows(text, table: table)
            #expect(rows.count == path.years.count)
            var before = start
            for (index, row) in rows.enumerated() where path.failure == nil || index < rows.count - 1 {
                let paid = row[4] + row[5] + row[6] + row[7] + row[8] - (index == 0 ? debtTax : 0)
                let cash = row[2] + row[3] + row[9] - paid - row[10]
                #expect(abs(cash) <= 6, "\(table), \(Int(row[0])): the money in and out is \(cash) more than saved")
                if table == "The deterministic run" {
                    let grown = (before + row[10] - row[9]) * pow(1.03, path.years[index].fraction)
                    #expect(abs(row[11] - grown) <= 6, "\(table), \(Int(row[0])): ends at \(row[11]), not \(grown)")
                }
                before = row[11]
            }
            #expect(rows.contains { $0[9] > 0 && $0[10] > 0 }, "\(table): a year that sells and saves")
        }
    }
}
