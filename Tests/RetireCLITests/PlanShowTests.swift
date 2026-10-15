import Foundation
import Model
@testable import RetireCLI
import Testing
import TestSupport

/// `retire plan show --json`: a plan's inputs.
struct PlanShowTests {
    @Test func theJSONHasEveryInput() async throws {
        let library = try TemporaryFolder.exampleLibrary()
        let json = try parseJSON(await retire(["plan", "show", "--library", library.path, "--plan",
                                               "part-time-from-50", "--json"]).output)
        #expect(json["plan"] as? String == "part-time-from-50" && json["currency"] as? String == "EUR")
        let tax = try #require(json["tax"] as? [String: Any])
        #expect(tax["investmentRate"] as? String == "0.26" && tax["wealthRate"] as? String == "0")
        let work = try #require(json["work"] as? [[String: Any]])
        #expect(work.map { $0["netIncome"] as? String } == ["40000", "18000"])
        #expect(work[1]["name"] as? String == "Part-time" && work[1]["until"] as? String == "retirement")
        let steps = try #require(json["targetMixByAge"] as? [[String: Any]])
        #expect(steps.map { $0["fromAge"] as? String } == ["retirement", "75"])
        let returns = try #require(json["returns"] as? [String: [String: Any]])
        // The defaults, given by their median.
        #expect(returns["equity"]?["givenAs"] as? String == "median" && returns["equity"]?["isDefault"] as? Bool == true)
    }
}
