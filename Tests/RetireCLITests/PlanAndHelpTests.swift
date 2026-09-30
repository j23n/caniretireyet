import Foundation
import Model
@testable import RetireCLI
import Testing
import TestSupport

struct PlanAndHelpTests {
    @Test func planIsNotAvailableYet() async throws {
        let library = try TemporaryFolder.exampleLibrary()
        let main = await retire(["plan", "--library", library.path])
        #expect(main.status == 1)
        #expect(main.errors.contains("Not available yet: the planner is being integrated. "
            + "plans/base.json (Base case) will run here once it is."))
        let other = await retire(["plan", "--library", library.path, "--plan", "part-time-from-50"])
        #expect(other.errors.contains("plans/part-time-from-50.json"))
        let missing = await retire(["plan", "--library", library.path, "--plan", "nope"])
        #expect(missing.status == 1)
        #expect(missing.errors.contains("There's no plan \"nope\" in plans/. Plans: base, part-time-from-50."))
    }

    @Test func planReportPrintsTheAnswer() throws {
        let library = try Fixtures.exampleLibrary()
        let plan = try #require(library.plans["base"])
        let headline = PlanReport.Headline(confidence: 0.9, successToday: 0.41, earliestAge: 54, earliestYear: 2042,
                                           targetAge: 55, successAtTarget: 0.93)
        let report = PlanReport(
            plan: plan, currency: .eur, headline: headline,
            successByAge: [.init(age: 53, year: 2041, success: 0.85), .init(age: 54, year: 2042, success: 0.9)],
            sustainableSpending: 38_412.4, issues: [.init(isError: false, message: "No birth date.")])
        #expect(report.lines() == [
            "Plan base: Base case",
            "",
            "Not yet: the earliest age with 90% confidence is 54 (2042). "
                + "Retiring today succeeds in 41% of simulated futures.",
            "At your target age, 55, the chance of success is 93%.",
            "What you could spend: 38,412 EUR a year in today's money from age 55, at 90% confidence.",
            "",
            "Chance of success by retirement age",
            "  Age  Year  Success",
            "   53  2041      85%  #################",
            "   54  2042      90%  ##################",
            "",
            "Issues",
            "  warning No birth date.",
        ])

        var yes = report
        yes.headline.successToday = 0.95
        #expect(yes.headlineText == "Yes: retiring today succeeds in 95% of simulated futures (you asked for 90%).")
        let json = try parseJSON(try JSONOutput.string(yes.json))
        #expect(json["canRetireToday"] as? Bool == true)
        #expect(json["earliestAge"] as? Int == 54)
    }

    @Test func helpListsTheCommands() async throws {
        let run = await retire(["--help"])
        #expect(run.status == 0)
        for command in ["init", "validate", "networth", "import", "prices", "plan"] {
            #expect(run.output.contains("  \(command) "), "\(command)")
        }
        let version = await retire(["--version"])
        #expect(version.output == "0.2.0\n")
        let importHelp = await retire(["help", "import"])
        #expect(importHelp.output.contains("--accept-new-accounts"))
        #expect(importHelp.output.contains("--library <path>"))
    }
}
