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
        #expect(run.output.contains("250 runs (fast) from 2026-09-30"))
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

        let fastBaseline = await retire(["plan", "--library", library.path, "--fast", "--save-baseline", "x"])
        #expect(fastBaseline.status == 64)
        let emptyLabel = await retire(["plan", "--library", library.path, "--save-baseline", " "])
        #expect(emptyLabel.status == 64)

        // Without a birth date the plan can't run.
        var settings = try library.text("library.json")
        settings = settings.replacingOccurrences(of: #""birthDate": "1988-04-12", "#, with: "")
        try library.write("library.json", settings)
        let noBirthDate = await retire(["plan", "--library", library.path, "--fast"])
        #expect(noBirthDate.status == 1)
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
        #expect(shown.errors.hasSuffix("\u{1B}[K\r\u{1B}[K"))

        let json = await retire(["plan", "--library", library.path, "--fast", "--json"], terminal: true)
        #expect(json.status == 0, "\(json.all)")
        #expect(json.errors.isEmpty)
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

    @Test func planReportsTheAnswerAsJSON() throws {
        let library = try Fixtures.exampleLibrary()
        let result = Self.sampleResult(of: try #require(library.plans["base"]))
        var yes = result
        yes.answer.successIfRetiringNow = 0.95
        let json = try parseJSON(try JSONOutput.string(PlanReport(result: yes, fast: false).json))
        #expect(json["canRetireToday"] as? Bool == true)
        #expect(json["earliestAge"] as? Int == 54)
        #expect(json["runs"] as? Int == 2000)

        // What retiring today would need, after the target age.
        var needing = result
        needing.answer.assetsNeeded = AssetsNeeded(age: 38, outcome: .found, amount: 545_212.4, readiness: 0.27294)
        let neededJSON = try parseJSON(try JSONOutput.string(PlanReport(result: needing, fast: false).json))
        #expect(neededJSON["assetsNeededToday"] as? Double == 545_212)
        #expect(neededJSON["readiness"] as? Double == 0.27)
        #expect(neededJSON["assetsNeededOutcome"] as? String == "found")
        #expect(json["assetsNeededToday"] == nil && json["readiness"] == nil)

        // Just below 100% never reads 100%.
        #expect(PlanReport.readinessPercent(0.996) == "99%")
        #expect(PlanReport.readinessPercent(1.3) == "130%")
        let extra = AssetsNeeded(age: 38, outcome: .found, amount: 545_212, readiness: 0.2729, extra: 396_404)
        var extraResult = result
        extraResult.answer.assetsNeeded = extra
        let extraJSON = try parseJSON(try JSONOutput.string(PlanReport(result: extraResult, fast: false).json))
        #expect(extraJSON["assetsNeededExtra"] as? Double == 396_404)
    }
}
