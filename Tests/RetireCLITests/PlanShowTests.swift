import Foundation
import Model
@testable import RetireCLI
import Testing
import TestSupport

/// `retire plan show`: a plan's inputs in words, or as JSON.
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
        #expect(returns["equity"]?["median"] as? String == "0.05" && returns["equity"]?["real"] as? String == "0.063334")
        #expect(returns["equity"]?["givenAs"] as? String == "median" && returns["equity"]?["isDefault"] as? Bool == true)
    }

    /// It runs, assuming no tax on investments, and says so.
    @Test func aPlanWithoutItsInvestmentRateSaysSo() async throws {
        let library = try TemporaryFolder.exampleLibrary()
        var text = try library.text("plans/base.json")
        text = text.replacingOccurrences(of: #""tax": { "investmentRate": "0.26", "wealthAllowance": "5000", "wealthRate": "0.002" },"#,
                                         with: "")
        try library.write("plans/base.json", text)
        let shown = await retire(["plan", "show", "--library", library.path])
        #expect(shown.output.contains("Taxes: none on investment income and gains (tax.investmentRate isn't set, "
            + "so the plan assumes 0%); no wealth tax\n"))
        let run = await retire(["plan", "--library", library.path, "--fast"])
        #expect(run.status == 0, "\(run.all)")
        #expect(run.output.contains("warning The tax rate on investment income and gains isn't set"))
    }
}
