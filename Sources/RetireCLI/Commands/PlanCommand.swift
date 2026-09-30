import ArgumentParser
import Foundation
import Model
import Storage

/// `retire plan`: runs a plan and prints the answer.
///
/// Not available yet: the `Planner` module is still being written. The
/// command already finds the plan (`--plan <id>`, or `mainPlan` in
/// library.json) and ``PlanReport`` already prints a result, so wiring it is
/// one step:
///
/// TODO(planner): once `Planner` is merged, replace the `CLIError` in
/// `run(in:)` with a run of the plan, and map its result into a `PlanReport`.
/// The API this expects (see docs/PLANNER.md), named as the Planner names it:
///
///     let registry = TaxSystems.registry()            // Italy and generic, registered once
///     let planner = Planner(library: loaded.library, taxes: registry)
///     let result = try planner.run(plan)              // deterministic + Monte Carlo (plan.simulation)
///
///     result.headline             // can retire today?, confidence required, chance of success today,
///                                 // earliest age and year reaching the confidence, target age's chance
///     result.successByAge         // [(age, year, successRate)] from the same random draws
///     result.sustainableSpending  // highest yearly retirement spending (today's euros) reaching the
///                                 // confidence at the target retirement age
///     result.issues               // tax validation (`TaxIssue`) and planner warnings, e.g. a missing
///                                 // birth date or an account the plan names that doesn't exist
///
/// Then `PlanReport(plan:currency:headline:successByAge:sustainableSpending:issues:)`, and
/// `console.print(lines: report.lines())` or `JSONOutput.string(report.json)` for `--json`.
/// Add `--runs <n>` and `--seed <n>` options if the Planner takes overrides.
struct PlanCommand: RetireSubcommand {
    static let configuration = CommandConfiguration(
        commandName: "plan",
        abstract: "Run a plan and print the answer (not available yet).",
        discussion: """
            Runs the library's main plan (mainPlan in library.json), or --plan <id>, and prints \
            the headline answer, the chance of success by retirement age, what you could spend, \
            and any issues. Not available yet: the planner is being integrated.
            """)

    @OptionGroup var options: LibraryOptions

    @Option(help: ArgumentHelp("The plan to run, plans/<id>.json. Default: the main plan.", valueName: "id"))
    var plan: String?

    @Flag(help: "Print JSON.")
    var json = false

    mutating func run() async throws {
        try await run(in: .live())
    }

    func run(in context: CLIContext) async throws {
        let loaded = try options.load(in: context)
        let document = try Self.plan(plan.map { PlanID($0) }, in: loaded.library)
        throw CLIError("Not available yet: the planner is being integrated. "
            + "\(LibraryFile.planPath(document.id)) (\(document.name)) will run here once it is.")
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

/// What `retire plan` prints, in the CLI's own terms, so the Planner's
/// result only has to be mapped into it (see ``PlanCommand``).
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

    func lines() -> [String] {
        var lines = ["Plan \(planID): \(planName)", "", headlineText]
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
             issues: issues.map { JSON.Issue(severity: $0.isError ? "error" : "warning", message: $0.message) })
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
    }
}
