import Foundation
import Model
import Planner
@testable import RetireCLI
import Testing
import TestSupport

/// `retire plan show` and `retire plan` with flexible spending (PLANNER.md,
/// "Flexible spending"). Plans are edited in the app or by hand.
struct PlanFlexibleSpendingCommandTests {
    @Test func showHasTheRule() async throws {
        let library = try TemporaryFolder.exampleLibrary()
        var text = try library.text("plans/base.json")
        text = text.replacingOccurrences(of: #""spending": {"#, with: #""spending": { "flexible": { "enabled": true, "floor": "0.75" },"#)
        try library.write("plans/base.json", text)
        let json = try parseJSON(await retire(["plan", "show", "--library", library.path, "--json"]).output)
        let flexible = try #require((json["spending"] as? [String: Any])?["flexible"] as? [String: Any])
        #expect(flexible["enabled"] as? Bool == true && flexible["floor"] as? String == "0.75")
        // The settings left out are shown with their defaults.
        #expect(flexible["cut"] is String && flexible["upperGuardrail"] is String)
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
        let json = try parseJSON(await retire(["plan", "--library", library.path, "--plan", plan, "--fast", "--json"]).output)
        let flexible = try #require(json["flexibleSpending"] as? [String: Any])
        #expect(flexible["floor"] as? Double == 0.85)
        #expect(flexible["planSpending"] as? String == "32000")
        #expect((flexible["shareWithCut"] as? Double).map { (0...1).contains($0) } == true)
        let years = try #require(flexible["spending"] as? [[String: Any]])
        #expect(!years.isEmpty && years[0]["p50"] is String)
    }
}
