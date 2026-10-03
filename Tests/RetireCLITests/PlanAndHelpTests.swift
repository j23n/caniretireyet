import Foundation
import Model
import Planner
@testable import RetireCLI
import Testing
import TestSupport

struct PlanAndHelpTests {
    @Test func planRunsTheMainPlan() async throws {
        let library = try TemporaryFolder.exampleLibrary()
        let run = await retire(["plan", "--library", library.path, "--fast"])
        #expect(run.status == 0, "\(run.all)")
        let lines = run.output.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        #expect(lines.first == "Plan base: Base case")
        #expect(lines.dropFirst().first == "250 runs (fast) from 2026-09-30 · engine 1.0.0 · tax parameters it 2026")
        #expect(run.output.contains("Not yet: ") || run.output.contains("Yes: "))
        #expect(run.output.contains("At your target age, 55, the chance of success is "))
        // What retiring today would need replaces the old FI number, which is never printed.
        #expect(run.output.contains("Needed to retire today: "))
        #expect(!run.output.contains("FI number") && !run.output.contains("financial independence"))
        #expect(run.output.contains("What you could spend: "))
        #expect(run.output.contains("Chance of success by retirement age"))
        #expect(run.output.contains("   55  2043  "))
        // Nothing is written without --save-baseline.
        #expect(!library.exists("projections/base/baselines/2026-09-30.json"))
    }

    @Test func planPrintsJSONForAnotherPlan() async throws {
        let library = try TemporaryFolder.exampleLibrary()
        let run = await retire(["plan", "--library", library.path, "--plan", "part-time-from-50", "--fast", "--json"])
        #expect(run.status == 0, "\(run.all)")
        let json = try parseJSON(run.output)
        #expect(json["plan"] as? String == "part-time-from-50")
        #expect(json["runs"] as? Int == 250)
        #expect(json["fast"] as? Bool == true)
        #expect(json["engine"] as? String == "1.0.0")
        // `earliest`: the target age is the earliest age, if one reaches the confidence.
        let earliest = json["earliestAge"] as? Int
        #expect(json["targetAge"] as? Int == earliest)
        let ages = try #require(json["successByAge"] as? [[String: Any]])
        #expect(ages.count > 10)
        #expect(ages.allSatisfy { ($0["success"] as? Double).map { (0...1).contains($0) } == true })
        #expect((json["issues"] as? [[String: Any]])?.contains { $0["severity"] as? String == "error" } == false)
        // What retiring today would need: found, so an amount and a readiness below 1 (no age works yet).
        let outcome = try #require(json["assetsNeededOutcome"] as? String)
        #expect(["found", "atMost", "moreThanMaximum", "noPlanAssets"].contains(outcome))
        if outcome == "found" {
            let amount = try #require(json["assetsNeededToday"] as? Double)
            let readiness = try #require(json["readiness"] as? Double)
            #expect(amount > 0 && readiness > 0)
            #expect((readiness >= 1) == (json["canRetireToday"] as? Bool))
        }
        // The keys it always had are still there.
        for key in ["headline", "canRetireToday", "confidence", "successToday", "successByAge", "issues"] {
            #expect(json[key] != nil, "\(key)")
        }
    }

    @Test func planSavesABaseline() async throws {
        let library = try TemporaryFolder.exampleLibrary()
        // Few runs, so the full run is quick in a debug build.
        var plan = try library.text("plans/base.json")
        plan = plan.replacingOccurrences(of: #""runs": 2000"#, with: #""runs": 40"#)
        try library.write("plans/base.json", plan)

        let run = await retire(["plan", "--library", library.path, "--save-baseline", "Before forfettario"])
        #expect(run.status == 0, "\(run.all)")
        #expect(run.output.contains("40 runs from 2026-09-30"))
        #expect(run.output.hasSuffix("Saved the baseline projections/base/baselines/2026-09-30.json.\n"))
        let saved = try library.load()
        let baseline = try #require(saved.projections["base"]?.baselines["2026-09-30"])
        #expect(baseline.kind == .manual)
        #expect(baseline.label == "Before forfettario")
        #expect(baseline.created == "2026-09-30")
        #expect(baseline.start.date == "2026-09-30")
        #expect(baseline.engine == "1.0.0")
        #expect(baseline.taxParameters == ["it": 2026])
        #expect(baseline.years.first?.year == 2026)
        #expect(baseline.years.last?.year == 1988 + 95)
        #expect(try baseline.planDocument().id == "base")
        // The example's baseline from January is still there.
        #expect(saved.projections["base"]?.baselines["2026-01-05"] != nil)

        // A second one on the same day gets its own file.
        let again = await retire(["plan", "--library", library.path, "--save-baseline", "Again", "--json"])
        #expect(again.status == 0, "\(again.all)")
        let json = try parseJSON(again.output)
        #expect(json["savedBaseline"] as? String == "projections/base/baselines/2026-09-30-2.json")
    }

    @Test func planRefusesWhatItCantDo() async throws {
        let library = try TemporaryFolder.exampleLibrary()
        let missing = await retire(["plan", "--library", library.path, "--plan", "nope"])
        #expect(missing.status == 1)
        #expect(missing.errors.contains("There's no plan \"nope\" in plans/. Plans: base, part-time-from-50."))

        let fastBaseline = await retire(["plan", "--library", library.path, "--fast", "--save-baseline", "x"])
        #expect(fastBaseline.status == 64)
        #expect(fastBaseline.errors.contains("A baseline needs every run: leave out --fast to save one."))
        let emptyLabel = await retire(["plan", "--library", library.path, "--save-baseline", " "])
        #expect(emptyLabel.status == 64)

        // Without a birth date the plan can't run.
        var settings = try library.text("library.json")
        settings = settings.replacingOccurrences(of: #""birthDate": "1988-04-12", "#, with: "")
        try library.write("library.json", settings)
        let noBirthDate = await retire(["plan", "--library", library.path, "--fast"])
        #expect(noBirthDate.status == 1)
        #expect(noBirthDate.errors.contains(
            "plans/base.json (Base case) can't run: The plan needs your birth date (library settings)."))
    }

    @Test func planShowsItsProgressOnATerminalOnly() async throws {
        let library = try TemporaryFolder.exampleLibrary()
        let quiet = await retire(["plan", "--library", library.path, "--fast"])
        #expect(quiet.status == 0, "\(quiet.all)")
        #expect(quiet.errors.isEmpty)

        let shown = await retire(["plan", "--library", library.path, "--fast"], terminal: true)
        #expect(shown.status == 0, "\(shown.all)")
        #expect(shown.output == quiet.output)
        // One line, rewritten in place, then erased before the answer.
        #expect(!shown.errors.contains("\n"))
        #expect(shown.errors.hasPrefix("\r["))
        #expect(shown.errors.contains("Earliest age · ages "))
        #expect(shown.errors.hasSuffix("100% Summarising\u{1B}[K\r\u{1B}[K"))

        let json = await retire(["plan", "--library", library.path, "--fast", "--json"], terminal: true)
        #expect(json.status == 0, "\(json.all)")
        #expect(json.errors.isEmpty)
    }

    @Test func theProgressLineSaysWhereTheRunIs() {
        let scan = PlannerProgress(phase: .earliestAge, completed: 12, total: 35, fraction: 0.3456, ages: 41...75,
                                   runs: 2_000)
        #expect(PlanProgressLine.text(scan) == "[######--------------]  34% Earliest age · ages 41–75: 12 / 35")
        let runs = PlannerProgress(phase: .simulating, completed: 1_234, total: 2_000, fraction: 0.88, runs: 2_000)
        #expect(PlanProgressLine.text(runs) == "[#################---]  88% Simulating 1,234 / 2,000 runs")
        let steps = PlannerProgress(phase: .sustainableSpending, completed: 4, total: 12, fraction: 0.931, runs: 250)
        #expect(PlanProgressLine.text(steps) == "[##################--]  93% Sustainable spending: step 4 / 12")
        let needed = PlannerProgress(phase: .assetsNeeded, completed: 3, total: 9, fraction: 0.97, runs: 250)
        #expect(PlanProgressLine.text(needed) == "[###################-]  97% Needed to retire today: step 3 / 9")
        let done = PlannerProgress(phase: .summarising, completed: 1, total: 1, fraction: 1, runs: 250)
        #expect(PlanProgressLine.text(done) == "[####################] 100% Summarising")
        let start = PlannerProgress(phase: .earliestAge, completed: 0, total: 38, fraction: 0, runs: 250)
        #expect(PlanProgressLine.text(start) == "[--------------------]   0% Earliest age: 0 / 38")
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
        #expect(json["runs"] == nil)

        // What retiring today would need, after the target age.
        var needing = report
        needing.needed = .init(outcome: .found, planAssets: 148_808.36, amount: 545_212.4, readiness: 0.27294)
        #expect(Array(needing.lines()[3...5]) == [
            "At your target age, 55, the chance of success is 93%.",
            "Needed to retire today: 545,212 EUR in plan assets, at 90% confidence. You have 148,808 EUR (27%).",
            "What you could spend: 38,412 EUR a year in today's money from age 55, at 90% confidence.",
        ])
        let neededJSON = try parseJSON(try JSONOutput.string(needing.json))
        #expect(neededJSON["assetsNeededToday"] as? Double == 545_212)
        #expect(neededJSON["readiness"] as? Double == 0.2729)
        #expect(neededJSON["assetsNeededOutcome"] as? String == "found")
        #expect(json["assetsNeededToday"] == nil && json["readiness"] == nil)

        // Just below 100% never reads 100%; the limits in words.
        #expect(PlanReport.Needed.percent(0.996) == "99%")
        #expect(PlanReport.Needed.percent(1.3) == "130%")
        let far = PlanReport.Needed(outcome: .moreThanMaximum, planAssets: 1_000)
        #expect(far.text(currency: .eur, confidence: 0.9)
            == "Needed to retire today: more than 20 times your plan assets (1,000 EUR), at 90% confidence.")
        let little = PlanReport.Needed(outcome: .atMost, planAssets: 100_000, amount: 5_000, readiness: 20)
        #expect(little.text(currency: .eur, confidence: 0.9)
            == "Needed to retire today: at most 5,000 EUR in plan assets, at 90% confidence. "
            + "You have 100,000 EUR, 20 times that or more.")

        var ran = report
        ran.run = .init(runs: 2000, fast: false, engine: "1.0.0", startDate: "2026-09-30",
                        taxParameters: ["it": 2026, "generic": 2026])
        ran.savedBaseline = "projections/base/baselines/2026-09-30.json"
        #expect(ran.lines()[1] == "2,000 runs from 2026-09-30 · engine 1.0.0 · tax parameters generic 2026, it 2026")
        #expect(ran.lines().last == "Saved the baseline projections/base/baselines/2026-09-30.json.")
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
        let planHelp = await retire(["help", "plan"])
        #expect(planHelp.output.contains("run (default)"))
        for subcommand in ["show", "set", "contribution", "pension"] {
            #expect(planHelp.output.contains("  \(subcommand) "), "\(subcommand)")
        }
        let runHelp = await retire(["help", "plan", "run"])
        #expect(runHelp.output.contains("--save-baseline <label>"))
        #expect(runHelp.output.contains("--fast"))
        #expect(runHelp.output.contains("--years"))
        for command in ["settings", "instruments"] {
            #expect(run.output.contains("  \(command) "), "\(command)")
        }
    }
}
