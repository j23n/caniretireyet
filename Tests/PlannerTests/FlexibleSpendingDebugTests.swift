import Foundation
import Model
@testable import Planner
import TaxKit
import Testing

/// The plan debugger with flexible spending (PLANNER.md, "Flexible
/// spending"): the rule in the plan as read, each traced year's withdrawal
/// rate against the guardrails and what the rule did, the summary over every
/// run, retiring today without the rule, and the diagnosis.
struct FlexibleSpendingDebugTests {
    static func plan(flexible: FlexibleSpending? = FlexibleSpending()) -> PlanDocument {
        var plan = PlanDebugTests.plan()
        plan.spending.flexible = flexible
        return plan
    }

    func report(_ options: PlanDebugOptions, plan: PlanDocument = plan()) async throws -> PlanDebugReport {
        try await Planner.debugReport(for: plan, library: PlanDebugTests.library,
                                      registry: Sample.registry(PlanDebugTests.system), options: options)
    }

    @Test func tracedYearsShowTheRuleAndReproduceTheMainRun() async throws {
        let report = try await report(PlanDebugOptions(planner: PlanDebugTests.planner, retirementAge: .target,
                                                       paths: .automatic(count: 3), runDate: "2026-01-02"))
        let rule = try #require(report.plan.flexibleSpending)
        #expect(rule.cut == 0.1 && rule.floor == 0.8 && rule.upperGuardrail == 0.2 && rule.lowerGuardrail == 0.2)
        #expect(report.plan.withdrawals.strategy == "fixed-real, with flexible spending")
        #expect(report.simulation.allRunsReproduced == true)
        for path in report.paths {
            #expect(path.matchesMainRun, "\(path.label)")
            for year in path.years {
                let retired = report.schedule.years.first { $0.year == year.year }.map { $0.workingShare < 1 } ?? false
                #expect((year.flexible != nil) == retired, "\(path.label) \(year.year)")
                guard let flexible = year.flexible, !year.failed else { continue }
                // The guardrails are the first year's rate ± 20%, and the level stays between the floor and 100%.
                if let initial = flexible.initialRate {
                    #expect(abs((flexible.upperRate ?? 0) - initial * 1.2) < 1e-6)
                    #expect(abs((flexible.lowerRate ?? 0) - initial * 0.8) < 1e-6)
                }
                #expect(flexible.level >= 0.8 - 1e-9 && flexible.level <= 1 + 1e-9)
                // Retired all year: what was met is the plan's spending at the level paid.
                #expect(abs(year.spendingMet - year.expenses - flexible.plannedSpending * flexible.paidLevel) < 0.02,
                        "\(path.label) \(year.year)")
            }
            // Each retirement year starts with the rule waiting or starting.
            let actions = path.years.compactMap { $0.flexible?.action }
            #expect(actions.first.map { ["waiting", "start"].contains($0) } == true, "\(actions)")
            #expect(actions.filter { $0 == "start" }.count <= 1)
        }
        // The rule's decisions show in the Markdown, and the summary over every run.
        let outcome = try #require(report.simulation.flexibleSpending)
        #expect(outcome.planSpending == 30_000 && outcome.retirementYears == 36)
        #expect((0...1).contains(outcome.shareWithCut) && outcome.assetsNeededWithoutRule != nil)
        let markdown = report.markdown()
        #expect(markdown.contains("- Flexible spending: cuts of 10% of the plan's spending, never below 80%"))
        #expect(markdown.contains("### Flexible spending (retiring at 50)"))
        #expect(markdown.contains("| Year | Age | Withdrawal rate | First year's | Guardrails | Action | Level | Paid | "
            + "Spending |"))
        #expect(markdown.contains("Spending p10"))
        #expect(report.percentiles.allSatisfy { $0.spending != nil })
        #expect(report.diagnosis.contains { $0.code == "flexible" })
    }

    @Test func retiringTodayIsComparedWithoutTheRule() async throws {
        let report = try await report(PlanDebugOptions(planner: PlanDebugTests.planner, retirementAge: .today,
                                                       paths: .automatic(count: 1), runDate: "2026-01-02"))
        let outcome = try #require(report.simulation.flexibleSpending)
        let needed = try #require(report.simulation.assetsNeeded)
        #expect(needed.outcome == "found")
        let amount = try #require(needed.amount)
        let without = try #require(outcome.assetsNeededWithoutRule)
        #expect(outcome.assetsNeededWithoutRuleOutcome == "found" && amount < without)
        #expect((outcome.successTodayWithoutRule ?? 1) <= report.simulation.successToday + 1e-9)
        let finding = try #require(report.diagnosis.first { $0.code == "flexible" })
        #expect(finding.text.hasPrefix("With flexible spending (cuts of 10% down to 80% of the plan's 30,000 a year), "
            + "retiring today needs \(PlanDebugFormat.money(amount)) EUR in plan assets instead of "
            + "\(PlanDebugFormat.money(without)). Retiring at 45 with "), "\(finding.text)")
        #expect(finding.text.contains("of futures never cut"))
    }

    @Test func theJSONRoundTripsAndAnonymizingKeepsTheRule() async throws {
        let report = try await report(PlanDebugOptions(planner: PlanDebugTests.planner, retirementAge: .target,
                                                       paths: .automatic(count: 2), runDate: "2026-01-02"))
        #expect(try PlanDebugReport.decode(json: report.json()) == report)
        let anonymized = report.anonymized()
        #expect(anonymized.plan.flexibleSpending?.floor == 0.8)
        #expect(anonymized.paths.flatMap(\.years).contains { $0.flexible != nil })
        #expect(anonymized.diagnosis.contains { $0.code == "flexible" })
        // A report without the rule has none of it.
        let fixed = try await self.report(PlanDebugOptions(planner: PlanDebugTests.planner, retirementAge: .target,
                                                           paths: .automatic(count: 1), runDate: "2026-01-02"),
                                          plan: Self.plan(flexible: nil))
        #expect(fixed.plan.flexibleSpending == nil && fixed.simulation.flexibleSpending == nil)
        #expect(fixed.paths.flatMap(\.years).allSatisfy { $0.flexible == nil })
        #expect(fixed.percentiles.allSatisfy { $0.spending == nil })
        #expect(!fixed.diagnosis.contains { $0.code == "flexible" })
    }
}
