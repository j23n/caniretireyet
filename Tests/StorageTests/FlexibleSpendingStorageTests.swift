import Foundation
import Model
@testable import Storage
import Testing
import TestSupport

/// `spending.flexible` in a plan file: it reads and writes back as written,
/// and keys a newer version adds inside it survive an edit by this one.
struct FlexibleSpendingStorageTests {
    @Test func theRuleRoundTripsAndKeepsUnknownKeys() throws {
        let folder = try TemporaryFolder.exampleLibrary()
        var text = try folder.text("plans/base.json")
        let original = "\"retired\": \"36000\","
        #expect(text.contains(original))
        text = text.replacingOccurrences(
            of: original,
            with: "\"flexible\": { \"enabled\": true, \"floor\": \"0.75\", \"rule\": \"guardrails-v2\" },\n    " + original)
        try folder.write("plans/base.json", text)

        let previous = try folder.library.load().library
        var plan = try #require(previous.plans["base"])
        let rule = try #require(plan.spending.flexibleRule)
        #expect(rule.floor == Decimal(fileString: "0.75") && rule.cut == nil)

        // Switched off with a cut of its own: the newer key stays.
        var library = previous
        plan.spending.flexible?.enabled = false
        plan.spending.flexible?.cut = Decimal(fileString: "0.15")
        library.plans["base"] = plan
        try folder.library.save(library, previous: previous)
        let json = try folder.json("plans/base.json")
        #expect(json["spending"]?["flexible"] == [
            "enabled": false, "cut": "0.15", "floor": "0.75", "rule": "guardrails-v2",
        ])
        #expect(try folder.library.load().library.plans["base"] == plan)
    }
}
