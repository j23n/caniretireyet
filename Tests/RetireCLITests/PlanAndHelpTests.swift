import Foundation
import Model
@testable import Planner
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
        #expect(lines.dropFirst().first == "250 runs (fast) from 2026-09-30 · engine \(Planner.engineVersion)")
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
        #expect(json["engine"] as? String == Planner.engineVersion)
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

        let run = await retire(["plan", "--library", library.path, "--save-baseline", "Before going freelance"])
        #expect(run.status == 0, "\(run.all)")
        #expect(run.output.contains("40 runs from 2026-09-30"))
        #expect(run.output.hasSuffix("Saved the baseline projections/base/baselines/2026-09-30.json.\n"))
        let saved = try library.load()
        let baseline = try #require(saved.projections["base"]?.baselines["2026-09-30"])
        #expect(baseline.kind == .manual)
        #expect(baseline.label == "Before going freelance")
        #expect(baseline.created == "2026-09-30")
        #expect(baseline.start.date == "2026-09-30")
        #expect(baseline.engine == Planner.engineVersion)
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
            "plans/base.json (Base case) can't run: Add your birth date (Settings): the plan needs your age."))
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

    /// A made-up result of the example's base plan: 2,000 runs from the
    /// September check-in, with all the money in one account you can draw now.
    private static func sampleResult(of plan: PlanDocument) -> PlanResult {
        let answer = PlanAnswer(
            confidence: 0.9, currentAge: 38, successIfRetiringNow: 0.41, earliestAge: 54, earliestDate: "2042-04-12",
            targetAge: 55, successAtTarget: 0.93,
            sustainableSpending: SustainableSpending(age: 55, perYear: 38_412.4, success: 0.9), agesWithout: [])
        let start = PlanStart(
            date: "2026-09-30", planAssets: d("148808.36"), accounts: ["conto-fineco"],
            buckets: [BucketSummary(name: "Money you can draw", availableFromAge: nil, value: 148_808.36,
                                    costBasis: 148_808.36, mix: [:], accounts: ["conto-fineco"])])
        return PlanResult(
            plan: plan, engine: "1.0.0", planHash: "", start: start, settings: SimulationSettings(runs: 2000, endAge: 95),
            answer: answer,
            successCurve: [AgeSuccess(age: 53, retirementDate: "2041-04-12", success: 0.85),
                           AgeSuccess(age: 54, retirementDate: "2042-04-12", success: 0.9)],
            focusAge: 55, fan: [], expectedPath: PathDetail(years: []), medianPath: PathDetail(years: []),
            failures: FailureSummary(runs: 2000, failed: 0, failureRate: 0, byAge: [], bridges: []), markers: [],
            issues: [PlanIssue(.warning, code: "test", message: "No birth date.", section: .person)], currency: .eur)
    }

    @Test func planReportPrintsTheAnswer() throws {
        let library = try Fixtures.exampleLibrary()
        let result = Self.sampleResult(of: try #require(library.plans["base"]))
        let report = PlanReport(result: result, fast: false)
        #expect(report.lines() == [
            "Plan base: Base case",
            "2,000 runs from 2026-09-30 · engine 1.0.0",
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
            "How the plan reads your library, on 2026-09-30 (EUR)",
            "  Money                 Value  Drawn  Accounts",
            "  Money you can draw  148,808  now    conto-fineco",
            "",
            "Issues",
            "  warning No birth date.",
        ])

        var yes = result
        yes.answer.successIfRetiringNow = 0.95
        #expect(PlanReport(result: yes, fast: false).headlineText
            == "Yes: retiring today succeeds in 95% of simulated futures (you asked for 90%).")
        let json = try parseJSON(try JSONOutput.string(PlanReport(result: yes, fast: false).json))
        #expect(json["canRetireToday"] as? Bool == true)
        #expect(json["earliestAge"] as? Int == 54)
        #expect(json["runs"] as? Int == 2000)

        // What retiring today would need, after the target age.
        var needing = result
        needing.answer.assetsNeeded = AssetsNeeded(age: 38, outcome: .found, amount: 545_212.4, readiness: 0.27294)
        #expect(Array(PlanReport(result: needing, fast: false).lines()[4...6]) == [
            "At your target age, 55, the chance of success is 93%.",
            "Needed to retire today: 545,212 EUR in plan assets, at 90% confidence. You have 148,808 EUR (27%).",
            "What you could spend: 38,412 EUR a year in today's money from age 55, at 90% confidence.",
        ])
        let neededJSON = try parseJSON(try JSONOutput.string(PlanReport(result: needing, fast: false).json))
        #expect(neededJSON["assetsNeededToday"] as? Double == 545_212)
        #expect(neededJSON["readiness"] as? Double == 0.2729)
        #expect(neededJSON["assetsNeededOutcome"] as? String == "found")
        #expect(json["assetsNeededToday"] == nil && json["readiness"] == nil)

        // Just below 100% never reads 100%; the limits in words.
        #expect(PlanReport.readinessPercent(0.996) == "99%")
        #expect(PlanReport.readinessPercent(1.3) == "130%")
        func text(_ needed: AssetsNeeded, planAssets: Double) -> String {
            PlanReport.neededText(needed, planAssets: planAssets, currency: .eur, confidence: 0.9)
        }
        #expect(text(AssetsNeeded(age: 38, outcome: .moreThanMaximum), planAssets: 1_000)
            == "Needed to retire today: more than 20 times your plan assets (1,000 EUR), at 90% confidence.")
        #expect(text(AssetsNeeded(age: 38, outcome: .atMost, amount: 5_000, readiness: 20), planAssets: 100_000)
            == "Needed to retire today: at most 5,000 EUR in plan assets, at 90% confidence. "
            + "You have 100,000 EUR, 20 times that or more.")
        // The extra money goes into the accounts that can be drawn now.
        let extra = AssetsNeeded(age: 38, outcome: .found, amount: 545_212, readiness: 0.2729, extra: 396_404)
        #expect(text(extra, planAssets: 148_808)
            == "Needed to retire today: 545,212 EUR in plan assets, at 90% confidence, with the extra 396,404 EUR in "
            + "accounts you can draw now. You have 148,808 EUR (27%).")
        let less = AssetsNeeded(age: 38, outcome: .found, amount: 600_000, readiness: 1.5, extra: -300_000)
        #expect(text(less, planAssets: 900_000)
            == "Needed to retire today: 600,000 EUR in plan assets, at 90% confidence: 300,000 EUR less in accounts "
            + "you can draw now. You have 900,000 EUR (150%).")
        // Emptying the 100,000 EUR you can draw now still works: only what's locked away is needed.
        let locked = AssetsNeeded(age: 38, outcome: .atMost, amount: 60_000, readiness: 2.67, extra: -100_000,
                                  accessible: 100_000)
        #expect(text(locked, planAssets: 160_000)
            == "Needed to retire today: at most the 60,000 EUR locked away, at 90% confidence: it works with nothing "
            + "in accounts you can draw now. You have 160,000 EUR.")
        var extraResult = result
        extraResult.answer.assetsNeeded = extra
        let extraJSON = try parseJSON(try JSONOutput.string(PlanReport(result: extraResult, fast: false).json))
        #expect(extraJSON["assetsNeededExtra"] as? Double == 396_404)

        var saved = report
        saved.savedBaseline = "projections/base/baselines/2026-09-30.json"
        #expect(saved.lines().last == "Saved the baseline projections/base/baselines/2026-09-30.json.")
    }

    @Test func helpListsTheCommands() async throws {
        let run = await retire(["--help"])
        #expect(run.status == 0)
        for command in ["init", "validate", "networth", "import", "prices", "plan", "export"] {
            #expect(run.output.contains("  \(command) "), "\(command)")
        }
        let version = await retire(["--version"])
        #expect(version.output == "0.2.0\n")
        let importHelp = await retire(["help", "import"])
        #expect(importHelp.output.contains("--accept-new-accounts"))
        #expect(importHelp.output.contains("--library <path>"))
        let planHelp = await retire(["help", "plan"])
        #expect(planHelp.output.contains("run (default)"))
        for subcommand in ["show", "debug"] {
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
