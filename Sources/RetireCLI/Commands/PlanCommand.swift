import ArgumentParser
import Foundation
import Model
import Planner
import Storage

/// `retire plan`: runs a plan and prints the answer.
///
/// Runs the main plan (`mainPlan` in library.json) or `--plan <id>` with the
/// tax systems the app registers (``TaxSystems/registry()``), maps the
/// Planner's `PlanResult` into a ``PlanReport`` and prints it, as text or
/// JSON. `--fast` uses fewer runs (the app's slider mode); `--save-baseline`
/// writes the result as a manual baseline (PROGRESS.md, "Baselines").
struct PlanCommand: RetireSubcommand {
    static let configuration = CommandConfiguration(
        commandName: "plan",
        abstract: "Run a plan and print the answer.",
        discussion: """
            Runs the library's main plan (mainPlan in library.json), or --plan <id>, and prints \
            the headline answer, the chance of success by retirement age, what you could spend, \
            and any issues. The plan starts from the latest check-in. --fast uses \
            \(PlannerOptions.defaultFastRuns) runs instead of the plan's own number (2,000 by default), \
            with the same random draws. --save-baseline <label> saves the result as a baseline in \
            projections/<plan>/baselines/, to compare your actual numbers against later.
            """)

    @OptionGroup var options: LibraryOptions

    @Option(help: ArgumentHelp("The plan to run, plans/<id>.json. Default: the main plan.", valueName: "id"))
    var plan: String?

    @Flag(help: "Use fewer runs, for a quick answer.")
    var fast = false

    @Option(help: ArgumentHelp("Save the result as a baseline with this label.", valueName: "label"))
    var saveBaseline: String?

    @Flag(help: "Print JSON.")
    var json = false

    mutating func validate() throws {
        if fast, saveBaseline != nil {
            throw ValidationError("A baseline needs every run: leave out --fast to save one.")
        }
        if let saveBaseline, saveBaseline.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw ValidationError("--save-baseline needs a label, e.g. \"Before forfettario\".")
        }
    }

    mutating func run() async throws {
        try await run(in: .live())
    }

    func run(in context: CLIContext) async throws {
        let loaded = try options.load(in: context)
        if saveBaseline != nil { try loaded.checkWritable() }
        let document = try Self.plan(plan.map { PlanID($0) }, in: loaded.library)
        let plannerOptions = fast ? PlannerOptions.fast() : PlannerOptions()
        let result: PlanResult
        do {
            result = try await Planner.run(
                plan: document, library: loaded.library, registry: TaxSystems.registry(),
                options: Self.options(plannerOptions, today: context.today))
        } catch let error as PlannerError {
            throw CLIError(Self.message(for: error, plan: document))
        }

        var report = PlanReport(result: result, currency: loaded.library.settings.baseCurrency, fast: fast)
        if let label = saveBaseline?.trimmingCharacters(in: .whitespacesAndNewlines) {
            report.savedBaseline = try Self.save(result, label: label, loaded: loaded, on: context.today)
        }
        if json {
            context.console.print(try JSONOutput.string(report.json))
        } else {
            context.console.print(lines: report.lines())
        }
    }

    /// The options for a run started on `today` (used when the library has no check-in yet).
    static func options(_ options: PlannerOptions, today: CalendarDate) -> PlannerOptions {
        var options = options
        options.today = today
        return options
    }

    /// Why the plan can't run: its errors, one per line after the first.
    static func message(for error: PlannerError, plan: PlanDocument) -> String {
        let errors = error.issues.filter(\.isError).map(\.message)
        let path = LibraryFile.planPath(plan.id)
        guard !errors.isEmpty else { return "\(path) (\(plan.name)) can't run." }
        if errors.count == 1 { return "\(path) (\(plan.name)) can't run: \(errors[0])" }
        return "\(path) (\(plan.name)) can't run:\n" + errors.map { "  \($0)" }.joined(separator: "\n")
    }

    /// Saves `result` as a manual baseline created on `date` and returns its path.
    static func save(_ result: PlanResult, label: String, loaded: LoadedLibrary, on date: CalendarDate) throws
        -> String {
        let baseline = result.baseline(created: date, kind: .manual, label: label)
        let plan = result.plan.id
        let existing = loaded.library.projections[plan]?.baselines.keys.map { $0 } ?? []
        let id = BaselineID.make(from: date.description, existing: existing)
        try loaded.folder.save(baseline, id: id, plan: plan)
        return LibraryFile.baseline(plan: plan, id: id).path
    }

    /// The plan to run: the one asked for, or the main plan.
    static func plan(_ id: PlanID?, in library: Library) throws -> PlanDocument {
        let known = library.plans.keys.sorted().map(\.rawValue)
        let list = known.isEmpty ? "The library has no plans yet." : "Plans: \(known.joined(separator: ", "))."
        guard let id = id ?? library.settings.mainPlan else {
            throw CLIError("Which plan? Pass --plan <id>, or set mainPlan in library.json. \(list)")
        }
        guard let plan = library.plans[id] else { throw CLIError("There's no plan \"\(id)\" in plans/. \(list)") }
        return plan
    }
}

extension LibraryFile {
    /// `plans/<id>.json`.
    static func planPath(_ id: PlanID) -> String { LibraryFile.plan(id).path }
}

/// What `retire plan` prints, in the CLI's own terms: the Planner's result
/// is mapped into it by ``init(result:currency:fast:)``.
struct PlanReport {
    /// The answer to "can I retire yet?".
    struct Headline {
        /// The share of simulated futures that must succeed, e.g. 0.9.
        var confidence: Double
        /// The chance of success if you retired today.
        var successToday: Double
        /// The earliest age reaching the confidence, and its year; `nil` if none does before the plan ends.
        var earliestAge: Int?
        var earliestYear: Int?
        /// The plan's target retirement age and its chance of success.
        var targetAge: Int?
        var successAtTarget: Double?

        var canRetireToday: Bool { successToday >= confidence }
    }

    /// The chance of success when retiring at one age.
    struct AgeSuccess {
        var age: Int
        var year: Int?
        var success: Double
    }

    /// A problem with the plan, e.g. from the tax system's validation.
    struct Issue {
        var isError: Bool
        var message: String
    }

    var planID: PlanID
    var planName: String
    var currency: CurrencyCode
    var headline: Headline
    var successByAge: [AgeSuccess]
    /// The highest yearly spending in retirement, in today's money, that
    /// reaches the confidence at the target age.
    var sustainableSpending: Double?
    var issues: [Issue]
    /// How the plan ran: the number of runs, fast or full, the engine and
    /// the tax parameters. `nil` for a report made by hand.
    var run: Run?
    /// The path of the baseline saved with `--save-baseline`.
    var savedBaseline: String?

    /// How a plan ran.
    struct Run {
        var runs: Int
        var fast: Bool
        var engine: String
        var startDate: CalendarDate
        /// The newest tax-parameter year per tax system.
        var taxParameters: [String: Int]
    }

    init(plan: PlanDocument, currency: CurrencyCode, headline: Headline, successByAge: [AgeSuccess],
         sustainableSpending: Double?, issues: [Issue]) {
        planID = plan.id
        planName = plan.name
        self.currency = currency
        self.headline = headline
        self.successByAge = successByAge
        self.sustainableSpending = sustainableSpending
        self.issues = issues
    }

    /// The report for a Planner result.
    init(result: PlanResult, currency: CurrencyCode, fast: Bool) {
        let answer = result.answer
        self.init(
            plan: result.plan, currency: currency,
            headline: Headline(
                confidence: answer.confidence, successToday: answer.successIfRetiringNow,
                earliestAge: answer.earliestAge, earliestYear: answer.earliestDate?.year,
                targetAge: answer.targetAge, successAtTarget: answer.successAtTarget),
            successByAge: result.successCurve.map {
                AgeSuccess(age: $0.age, year: $0.retirementDate.year, success: $0.success)
            },
            sustainableSpending: answer.sustainableSpending?.perYear,
            issues: result.issues.map { Issue(isError: $0.isError, message: $0.message) })
        run = Run(runs: result.settings.runs, fast: fast, engine: result.engine, startDate: result.start.date,
                  taxParameters: result.taxParameters)
    }

    static func percent(_ share: Double) -> String {
        "\(Int((share * 100).rounded()))%"
    }

    /// The headline sentence, as on the app's Plan screen.
    var headlineText: String {
        let confidence = Self.percent(headline.confidence)
        if headline.canRetireToday {
            return "Yes: retiring today succeeds in \(Self.percent(headline.successToday)) of simulated futures "
                + "(you asked for \(confidence))."
        }
        let today = "Retiring today succeeds in \(Self.percent(headline.successToday)) of simulated futures."
        guard let age = headline.earliestAge else {
            return "Not yet: no retirement age reaches \(confidence) before the plan ends. \(today)"
        }
        return "Not yet: the earliest age with \(confidence) confidence is \(age)"
            + (headline.earliestYear.map { " (\($0))" } ?? "") + ". \(today)"
    }

    /// "2,000 runs from the check-in on 2026-09-30 · engine 1.0.0 · tax parameters it 2026".
    var runText: String? {
        guard let run else { return nil }
        var parts = ["\(Format.amount(Decimal(run.runs), places: 0)) \(run.runs == 1 ? "run" : "runs")"
            + (run.fast ? " (fast)" : "") + " from \(run.startDate)"]
        parts.append("engine \(run.engine)")
        if !run.taxParameters.isEmpty {
            parts.append("tax parameters " + run.taxParameters.keys.sorted()
                .map { "\($0) \(run.taxParameters[$0]!)" }.joined(separator: ", "))
        }
        return parts.joined(separator: " · ")
    }

    func lines() -> [String] {
        var lines = ["Plan \(planID): \(planName)"]
        if let runText { lines.append(runText) }
        lines += ["", headlineText]
        if let target = headline.targetAge, let success = headline.successAtTarget {
            lines.append("At your target age, \(target), the chance of success is \(Self.percent(success)).")
        }
        if let spending = sustainableSpending, spending.isFinite {
            let amount = Format.amount(Decimal(Int(spending.rounded())), places: 0)
            lines.append("What you could spend: \(amount) \(currency) a year in today's "
                + "money\(headline.targetAge.map { " from age \($0)" } ?? ""), "
                + "at \(Self.percent(headline.confidence)) confidence.")
        }
        if !successByAge.isEmpty {
            lines.append("")
            lines.append("Chance of success by retirement age")
            var table = TextTable([.right("Age"), .right("Year"), .right("Success"), .left("")])
            for row in successByAge {
                let bar = String(repeating: "#", count: Int((max(0, min(1, row.success)) * 20).rounded()))
                table.add(["\(row.age)", row.year.map(String.init) ?? "", Self.percent(row.success), bar])
            }
            lines += table.lines()
        }
        if !issues.isEmpty {
            lines.append("")
            lines.append("Issues")
            lines += issues.map { "  \($0.isError ? "error  " : "warning") \($0.message)" }
        }
        if let savedBaseline {
            lines.append("")
            lines.append("Saved the baseline \(savedBaseline).")
        }
        return lines
    }

    var json: JSON {
        JSON(plan: planID.rawValue, name: planName, currency: currency.rawValue, headline: headlineText,
             canRetireToday: headline.canRetireToday, confidence: headline.confidence,
             successToday: headline.successToday, earliestAge: headline.earliestAge,
             earliestYear: headline.earliestYear, targetAge: headline.targetAge,
             successAtTarget: headline.successAtTarget,
             successByAge: successByAge.map { JSON.Age(age: $0.age, year: $0.year, success: $0.success) },
             sustainableSpending: sustainableSpending,
             issues: issues.map { JSON.Issue(severity: $0.isError ? "error" : "warning", message: $0.message) },
             runs: run?.runs, fast: run?.fast, engine: run?.engine, startDate: run?.startDate.description,
             taxParameters: run?.taxParameters, savedBaseline: savedBaseline)
    }

    struct JSON: Encodable {
        struct Age: Encodable {
            var age: Int
            var year: Int?
            var success: Double
        }

        struct Issue: Encodable {
            var severity: String
            var message: String
        }

        var plan: String
        var name: String
        var currency: String
        var headline: String
        var canRetireToday: Bool
        var confidence: Double
        var successToday: Double
        var earliestAge: Int?
        var earliestYear: Int?
        var targetAge: Int?
        var successAtTarget: Double?
        var successByAge: [Age]
        var sustainableSpending: Double?
        var issues: [Issue]
        var runs: Int?
        var fast: Bool?
        var engine: String?
        var startDate: String?
        var taxParameters: [String: Int]?
        var savedBaseline: String?
    }
}
