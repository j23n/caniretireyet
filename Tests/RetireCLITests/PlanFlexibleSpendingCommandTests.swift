import Foundation
import Model
import Planner
@testable import RetireCLI
import Testing
import TestSupport

/// `retire plan set --flexible …`, `retire plan show` and `retire plan` with
/// flexible spending (PLANNER.md, "Flexible spending").
struct PlanFlexibleSpendingCommandTests {
    @Test func setTurnsTheRuleOnChangesItAndTurnsItOff() async throws {
        let library = try TemporaryFolder.exampleLibrary()
        let on = await retire(["plan", "set", "--library", library.path, "--flexible", "on"])
        #expect(on.status == 0, "\(on.all)")
        #expect(on.output.hasPrefix("Flexible spending: on: cuts of 10% of the plan's spending, never below 80% "
            + "(28,800 EUR a year); guardrails 20% above and 20% below the first retirement year's withdrawal rate.\n"))
        #expect(try library.text("plans/base.json").contains(#""flexible": { "enabled": true }"#))

        let changed = await retire(["plan", "set", "--library", library.path, "--flexible-cut", "15%",
                                    "--flexible-floor", "0.75", "--flexible-guardrails", "25%,15%"])
        #expect(changed.status == 0, "\(changed.all)")
        var rule = try #require(try library.load().plans["base"]?.spending.flexible)
        #expect(rule == FlexibleSpending(enabled: true, cut: dec("0.15"), floor: dec("0.75"),
                                         upperGuardrail: dec("0.25"), lowerGuardrail: dec("0.15")))

        // Off keeps the settings; the default cut isn't written.
        let off = await retire(["plan", "set", "--library", library.path, "--flexible", "off", "--flexible-cut", "10%"])
        #expect(off.status == 0, "\(off.all)")
        rule = try #require(try library.load().plans["base"]?.spending.flexible)
        #expect(!rule.isEnabled && rule.cut == nil && rule.floor == dec("0.75"))
        let shown = await retire(["plan", "show", "--library", library.path])
        #expect(shown.output.contains("Flexible spending: off (kept: cuts of 10% of the plan's spending, never below 75% "
            + "(27,000 EUR a year); guardrails 25% above and 15% below the first retirement year's withdrawal rate)\n"))
        #expect(shown.output.contains("Spending: 36,000 EUR a year while working, 36,000 in retirement, 90% of it "
            + "from 75 and 80% from 85\n"))
        let json = try parseJSON(await retire(["plan", "show", "--library", library.path, "--json"]).output)
        let flexible = try #require((json["spending"] as? [String: Any])?["flexible"] as? [String: Any])
        #expect(flexible["enabled"] as? Bool == false && flexible["floor"] as? String == "0.75")
        #expect(flexible["cut"] as? String == "0.1" && flexible["upperGuardrail"] as? String == "0.25")

        // A rule with only the defaults, switched off, leaves nothing in the file.
        _ = await retire(["plan", "set", "--library", library.path, "--flexible-floor", "80%",
                          "--flexible-guardrails", "20%"])
        let removed = await retire(["plan", "set", "--library", library.path, "--flexible", "off"])
        #expect(removed.output.hasPrefix("Flexible spending: off (spending is fixed in real terms).\n"), "\(removed.all)")
        #expect(try library.load().plans["base"]?.spending.flexible == nil)
        #expect(!(try library.text("plans/base.json")).contains("flexible"))
    }

    @Test func badValuesAreRefused() async throws {
        let library = try TemporaryFolder.exampleLibrary()
        for (arguments, message) in [
            (["--flexible", "maybe"], "--flexible takes on or off, not “maybe”."),
            (["--flexible-cut", "0"], "--flexible-cut must be more than 0% and at most 100% of the plan's spending."),
            (["--flexible-floor", "120%"], "--flexible-floor must be between 0% and 100% of the plan's spending."),
            (["--flexible-guardrails", "20%,150%"], "--flexible-guardrails must be at least 0%, and the lower one at most 100%."),
            (["--flexible-cut", "a lot"], "--flexible-cut: “a lot” isn't a share written like 10% or 0.1."),
        ] {
            let run = await retire(["plan", "set", "--library", library.path] + arguments)
            #expect(run.status != 0)
            #expect(run.all.contains(message), "\(run.all)")
        }
    }

    @Test func thePlanReportsWhatFlexibleSpendingDid() async throws {
        let library = try TemporaryFolder.exampleLibrary()
        let plan = "part-time-from-50"
        // Without the rule, nothing about it.
        let fixed = try parseJSON(await retire(["plan", "--library", library.path, "--plan", plan, "--fast", "--json"])
            .output)
        #expect(fixed["flexibleSpending"] == nil)

        // The example plan keeps a rule switched off, with a floor of 85%: on, it applies.
        let on = await retire(["plan", "set", "--library", library.path, "--plan", plan, "--flexible", "on"])
        #expect(on.output.hasPrefix("Flexible spending: on: cuts of 10% of the plan's spending, never below 85% "
            + "(27,200 EUR a year);"), "\(on.all)")
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
