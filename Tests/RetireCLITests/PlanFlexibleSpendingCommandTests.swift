import Foundation
import Model
import Planner
@testable import RetireCLI
import Testing
import TestSupport

/// `retire plan show` and `retire plan` with flexible spending (PLANNER.md,
/// "Flexible spending"). Plans are edited in the app or by hand.
struct PlanFlexibleSpendingCommandTests {
    @Test func showDescribesTheRule() async throws {
        let library = try TemporaryFolder.exampleLibrary()
        var text = try library.text("plans/base.json")
        text = text.replacingOccurrences(of: #""spending": {"#, with: #""spending": { "flexible": { "enabled": true, "floor": "0.75" },"#)
        try library.write("plans/base.json", text)
        let shown = await retire(["plan", "show", "--library", library.path])
        #expect(shown.output.contains("Flexible spending: on: cuts of 10% of the plan's spending, never below 75% "
            + "(27,000 EUR a year); guardrails 20% above and 20% below the first retirement year's withdrawal rate\n"),
                "\(shown.all)")
        let json = try parseJSON(await retire(["plan", "show", "--library", library.path, "--json"]).output)
        let flexible = try #require((json["spending"] as? [String: Any])?["flexible"] as? [String: Any])
        #expect(flexible["enabled"] as? Bool == true && flexible["floor"] as? String == "0.75")
        #expect(flexible["cut"] as? String == "0.1" && flexible["upperGuardrail"] as? String == "0.2")

        let other = await retire(["plan", "show", "--library", library.path, "--plan", "part-time-from-50"])
        #expect(other.output.contains("Flexible spending: off (kept: cuts of 10% of the plan's spending, never below "
            + "85% (27,200 EUR a year); guardrails 20% above and 20% below the first retirement year's withdrawal rate)\n"))
    }

    @Test func thePlanReportsWhatFlexibleSpendingDid() async throws {
        let library = try TemporaryFolder.exampleLibrary()
        let plan = "part-time-from-50"
        // Without the rule, nothing about it.
        let fixed = try parseJSON(await retire(["plan", "--library", library.path, "--plan", plan, "--fast", "--json"])
            .output)
        #expect(fixed["flexibleSpending"] == nil)

        // The example plan keeps a rule switched off, with a floor of 85%: on, it applies.
        let file = "plans/\(plan).json"
        try library.write(file, try library.text(file).replacingOccurrences(of: #""enabled": false"#,
                                                                            with: #""enabled": true"#))
        let run = await retire(["plan", "--library", library.path, "--plan", plan, "--fast"])
        #expect(run.status == 0, "\(run.all)")
        let lines = run.output.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let title = try #require(lines.firstIndex { $0.hasPrefix("Flexible spending, retiring at ") })
        #expect(lines[title].hasSuffix("(cuts of 10% down to 85% of 32,000 EUR a year)"), "\(lines[title])")
        #expect(lines[title + 1].hasPrefix("  In a bad case (1 in 10) ") || lines[title + 1].hasPrefix("  Even in a bad case"))
        #expect(lines[title + 2].hasPrefix("  The median future spends "))
        #expect(lines.contains { $0.hasPrefix("  Spending paid (EUR, today's money; a run that has failed pays 0") })

        let json = try parseJSON(await retire(["plan", "--library", library.path, "--plan", plan, "--fast", "--json"]).output)
        let flexible = try #require(json["flexibleSpending"] as? [String: Any])
        #expect(flexible["cut"] as? Double == 0.1 && flexible["floor"] as? Double == 0.85)
        #expect(flexible["planSpending"] as? String == "32000")
        #expect((flexible["shareWithCut"] as? Double).map { (0...1).contains($0) } == true)
        let years = try #require(flexible["spending"] as? [[String: Any]])
        #expect(!years.isEmpty && years[0]["p50"] is String)
    }
}
