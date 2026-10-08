import Foundation
import Model
import Testing
import TestSupport

/// `spending.flexible` (PLANNER.md, "Flexible spending"): optional, off when
/// absent, on when present unless `enabled` is false, with each setting
/// defaulting when left out. Made-up amounts.
struct FlexibleSpendingModelTests {
    @Test func absentMeansFixedSpending() throws {
        let spending = try decode(PlanSpending.self, #"{ "working": "30000", "retired": "28000" }"#)
        #expect(spending.flexible == nil && spending.flexibleRule == nil)
        #expect(try json(spending) == #"{"retired":"28000","working":"30000"}"#)
    }

    @Test func presentMeansOnWithTheDefaults() throws {
        let spending = try decode(PlanSpending.self, #"{ "working": "1", "retired": "28000", "flexible": { "enabled": true } }"#)
        let rule = try #require(spending.flexibleRule)
        #expect(rule.isEnabled && rule.usesDefaults)
        #expect(rule.effectiveCut == d("0.1") && rule.effectiveFloor == d("0.8"))
        #expect(rule.effectiveUpperGuardrail == d("0.2") && rule.effectiveLowerGuardrail == d("0.2"))
        // Without `enabled`, written by hand, it's on too.
        #expect(try decode(PlanSpending.self, #"{ "working": "1", "retired": "1", "flexible": {} }"#).flexibleRule != nil)
        // The rule the app writes when it's switched on.
        #expect(try json(FlexibleSpending()) == #"{"enabled":true}"#)
    }

    @Test func offKeepsTheSettings() throws {
        let text = #"""
        { "working": "1", "retired": "28000",
          "flexible": { "enabled": false, "cut": "0.15", "floor": "0.75", "upperGuardrail": "0.25", "lowerGuardrail": "0.15" } }
        """#
        let spending = try decode(PlanSpending.self, text)
        #expect(spending.flexibleRule == nil)
        let rule = try #require(spending.flexible)
        #expect(!rule.isEnabled && !rule.usesDefaults)
        #expect(rule.effectiveCut == d("0.15") && rule.effectiveFloor == d("0.75"))
        #expect(rule.effectiveUpperGuardrail == d("0.25") && rule.effectiveLowerGuardrail == d("0.15"))
        // It reads back as written, decimals as strings.
        #expect(try decode(PlanSpending.self, try json(spending)) == spending)
        #expect(try json(rule) == #"{"cut":"0.15","enabled":false,"floor":"0.75","lowerGuardrail":"0.15","upperGuardrail":"0.25"}"#)
        // Numbers are read too, never through Double.
        let numbers = try decode(FlexibleSpending.self, #"{ "cut": 0.1, "floor": 0.8 }"#)
        #expect(numbers.cut == d("0.1") && numbers.floor == d("0.8"))
    }

    @Test func aPlanRoundTripsWithTheRule() throws {
        var plan = PlanDocument(id: "p", name: "P", retirement: PlanRetirement(age: .age(60)),
                                spending: PlanSpending(working: 30000, retired: 28000,
                                                       phases: [SpendingPhase(fromAge: 75, factor: d("0.9"))]))
        plan.spending.flexible = FlexibleSpending(floor: d("0.7"))
        let text = try json(plan)
        #expect(text.contains(#""flexible":{"enabled":true,"floor":"0.7"}"#), "\(text)")
        #expect(try decode(PlanDocument.self, text) == plan)
        #expect(FlexibleSpending.knownKeys == ["enabled", "cut", "floor", "upperGuardrail", "lowerGuardrail"])
        #expect(PlanSpending.knownKeys.contains("flexible"))
    }
}
