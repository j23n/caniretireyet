import Foundation
import Model
@testable import Planner
import Testing
import TestSupport

/// PLANNER.md, "Safe withdrawal rates implied by the defaults": the share
/// of the starting money that can be spent every year, fixed in real terms,
/// in 90% of futures, with no tax, no pensions and nothing else, from a
/// script that isn't the engine (200,000 runs, spending at the start of each
/// year, then the year's return, mixes rebalanced every year). The engine's
/// sustainable spending over its starting assets should land on that table.
///
/// The plans match the script's setup: one account at the mix, rebalanced
/// to it every year, the current default returns and correlations, no tax,
/// retiring today, and a check-in on 31 December, so every simulated year is
/// whole and spending comes out on 1 January before the year's return. The
/// horizon is set by the birth year: 30, 40 or 57 years to 95.
///
/// The table is rounded to 0.1 percentage points, so a cell is up to 0.05
/// from the script's own value. 2,000 runs are a sample: in 100 blocks of
/// 2,000 of the script's runs, a cell's 90% rate has a standard deviation of
/// 0.04 to 0.06 points, and up to 0.071 with flexible spending. ±0.1 points
/// would leave the sample about one of them, so at the plans' 2,000 runs
/// a cell is checked to ±0.25: 0.05 for the rounding and 0.2, about 3
/// standard deviations, for the sample. With three seeds of 10,000 runs,
/// 30,000 in all, the standard deviation is at most 0.071 / √15 ≈ 0.018,
/// and the whole table is checked to ±0.1: 0.05 and 2.7 of them.
///
/// The whole table takes about ten minutes in a debug build, so it runs
/// only in release builds, or when `PLANNER_REFERENCE_TESTS=1` is set:
///
///     PLANNER_REFERENCE_TESTS=1 swift test --filter PlannerTests.WithdrawalRateTests
///
/// The 30-year column at 2,000 runs, and the closed form without
/// volatility, always run.
struct WithdrawalRateTests {
    /// Whether the whole table runs: in release builds, or with `PLANNER_REFERENCE_TESTS=1`.
    static var fullTableEnabled: Bool {
        #if DEBUG
        ProcessInfo.processInfo.environment["PLANNER_REFERENCE_TESTS"] == "1"
        #else
        true
        #endif
    }

    /// One cell of the table.
    struct Cell: CustomTestStringConvertible, Sendable {
        /// The equity share; the rest is bonds.
        var equity: Decimal
        var years: Int
        var flexible: Bool
        /// The table's rate, in percent.
        var percent: Double

        var testDescription: String {
            "\(equity == 1 ? "100% equity" : "70/30"), \(years) years\(flexible ? ", flexible" : ""): \(percent)%"
        }
    }

    /// PLANNER.md's table for the current defaults, then the rates with
    /// flexible spending from the paragraph under it.
    static let table: [Cell] = [
        Cell(equity: 1, years: 30, flexible: false, percent: 3.4),
        Cell(equity: 1, years: 40, flexible: false, percent: 2.9),
        Cell(equity: 1, years: 57, flexible: false, percent: 2.4),
        Cell(equity: d("0.7"), years: 30, flexible: false, percent: 3.7),
        Cell(equity: d("0.7"), years: 40, flexible: false, percent: 3.1),
        Cell(equity: d("0.7"), years: 57, flexible: false, percent: 2.6),
        Cell(equity: 1, years: 30, flexible: true, percent: 4.1),
        Cell(equity: 1, years: 40, flexible: true, percent: 3.5),
        Cell(equity: 1, years: 57, flexible: true, percent: 2.9),
        Cell(equity: d("0.7"), years: 30, flexible: true, percent: 4.5),
        Cell(equity: d("0.7"), years: 40, flexible: true, percent: 3.7),
        Cell(equity: d("0.7"), years: 57, flexible: true, percent: 3.1),
    ]

    /// The starting money: large, so the engine's tolerance of 1 unit and
    /// the solver's rounding down to 10 are far below 0.01 points.
    static let start: Decimal = 1_000_000

    /// Valued on 31 December 2026, born on 30 June of the year that makes
    /// the plan `years` long to 95: the first simulated year is 2027, whole.
    static func library(equity: Decimal, years: Int) -> Library {
        let birth = CalendarDate(year: 2026 + years - 95, month: 6, day: 30)!
        let mix: AssetMix = equity == 1 ? [.equity: 1] : [.equity: equity, .bonds: 1 - equity]
        return Sample.library(birth: birth, on: "2026-12-31",
                              [SampleAccount(id: "portfolio", mix: mix, balance: start)])
    }

    /// Retiring today on `retired` a year, with the default returns and
    /// correlations, no tax and nothing else.
    static func plan(age: Int, retired: Decimal = 30_000, flexible: Bool, runs: Int, seed: UInt64,
                     assumptions: PlanAssumptions = PlanAssumptions()) -> PlanDocument {
        PlanDocument(
            id: "swr", name: "Withdrawal rate", retirement: PlanRetirement(age: .age(age)),
            tax: PlanTax(investmentRate: 0),
            spending: PlanSpending(working: 0, retired: retired,
                                   flexible: flexible ? FlexibleSpending(enabled: true) : nil),
            assumptions: assumptions,
            simulation: PlanSimulation(runs: runs, seed: seed, confidence: d("0.9")))
    }

    /// The engine's sustainable spending retiring today, over the starting money, in percent.
    static func rate(_ cell: Cell, runs: Int, seed: UInt64) async throws -> Double {
        let age = 95 - cell.years
        let library = library(equity: cell.equity, years: cell.years)
        let options = PlannerOptions(maxRetirementAge: age, solveSustainableSpending: true, solveAssetsNeeded: false)
        let result = try await Planner.run(plan: plan(age: age, flexible: cell.flexible, runs: runs, seed: seed),
                                           library: library, options: options)
        #expect(result.answer.currentAge == age)
        #expect(result.fan.count == cell.years)
        #expect(result.expectedPath.years.allSatisfy { $0.fraction == 1 })
        let spending = try #require(result.answer.sustainableSpending)
        #expect(spending.age == age)
        #expect(spending.success >= 0.9)
        return spending.perYear / start.doubleValue * 100
    }

    // MARK: The setup

    /// Without volatility every run is the median year after year, so the
    /// sustainable spending has a closed form for spending taken at the
    /// start of each year: W = P / Σ g⁻ʲ over j = 0 … N − 1, with P the
    /// starting money and g the gross median return of the mix. It's what
    /// the script's timing gives, so it shows the engine's year is the
    /// script's year.
    @Test(arguments: [30, 57])
    func withoutVolatilityTheRateIsTheClosedForm(years: Int) async throws {
        var assumptions = PlanAssumptions()
        assumptions.returns[.equity] = ReturnAssumption(medianReal: d("0.05"), volatility: 0)
        let age = 95 - years
        let result = try await Planner.run(
            plan: Self.plan(age: age, flexible: false, runs: 20, seed: 1, assumptions: assumptions),
            library: Self.library(equity: 1, years: years),
            options: PlannerOptions(maxRetirementAge: age, solveAssetsNeeded: false))
        let annuity = (0..<years).reduce(0.0) { $0 + pow(1.05, -Double($1)) }
        let closedForm = Self.start.doubleValue / annuity
        let spending = try #require(result.answer.sustainableSpending)
        // The solver brackets to 0.05% and rounds down to 10.
        #expect(spending.perYear <= closedForm)
        #expect(spending.perYear >= closedForm * (1 - 0.0005) - 10)
        #expect(spending.success == 1)
    }

    /// A check-in during the year makes the first year a part year: its
    /// spending and its return are scaled to the days left. The script has
    /// no part year, so the table is for a check-in on 31 December; on
    /// 30 June the plan is half a year shorter and spends half as much in
    /// its first half year, which the closed form with a first year of
    /// spending W/2 and growth √g gives.
    @Test func aPartFirstYearIsShorter() async throws {
        var assumptions = PlanAssumptions()
        assumptions.returns[.equity] = ReturnAssumption(medianReal: d("0.05"), volatility: 0)
        let library = Sample.library(birth: "1961-06-30", on: "2026-06-30",
                                     [SampleAccount(id: "portfolio", mix: [.equity: 1], balance: Self.start)])
        let result = try await Planner.run(
            plan: Self.plan(age: 65, flexible: false, runs: 20, seed: 1, assumptions: assumptions),
            library: library, options: PlannerOptions(maxRetirementAge: 65, solveAssetsNeeded: false))
        let first = try #require(result.expectedPath.years.first)
        #expect(first.year == 2026 && abs(first.fraction - 184.0 / 365.0) < 1e-12)
        // P = W f + W Σ g^(−f − j) over j = 0 … 29, with f the first year's share.
        let f = first.fraction
        let later = (0..<30).reduce(0.0) { $0 + pow(1.05, -f - Double($1)) }
        let closedForm = Self.start.doubleValue / (f + later)
        let spending = try #require(result.answer.sustainableSpending)
        #expect(spending.perYear <= closedForm)
        #expect(spending.perYear >= closedForm * (1 - 0.0005) - 10)
    }

    // MARK: The table

    /// The 30-year column at the plans' 2,000 runs and seed 1, to ±0.25
    /// points (the type's comment has the arithmetic).
    @Test(arguments: table.filter { $0.years == 30 })
    func theThirtyYearColumnAtTwoThousandRuns(_ cell: Cell) async throws {
        let rate = try await Self.rate(cell, runs: 2000, seed: 1)
        #expect(abs(rate - cell.percent) <= 0.25, "the engine gives \(rate)%")
    }

    /// Every cell with 30,000 runs (three seeds of 10,000), to ±0.1 points.
    @Test(.enabled(if: fullTableEnabled, "The whole table runs in release builds, or with PLANNER_REFERENCE_TESTS=1."),
          arguments: table)
    func theWholeTable(_ cell: Cell) async throws {
        var rates: [Double] = []
        for seed: UInt64 in [1, 2, 3] {
            rates.append(try await Self.rate(cell, runs: 10_000, seed: seed))
        }
        let rate = rates.reduce(0, +) / Double(rates.count)
        print("Withdrawal rate, \(cell.testDescription): the engine gives \(String(format: "%.3f", rate))% "
            + "(seeds \(rates.map { String(format: "%.3f", $0) }.joined(separator: ", ")))")
        #expect(abs(rate - cell.percent) <= 0.1, "the engine gives \(rate)%")
    }
}
