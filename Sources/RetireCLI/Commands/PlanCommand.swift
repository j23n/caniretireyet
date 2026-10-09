import ArgumentParser
import Foundation
import Model
import Planner
import Storage

/// `retire plan run`, also just `retire plan`: runs a plan and prints the answer.
///
/// Runs the main plan (`mainPlan` in library.json) or `--plan <id>` and
/// prints the Planner's `PlanResult` (``PlanReport``), as text or JSON, in
/// the library's base currency. `--fast` uses fewer runs (the app's quick
/// what-if mode); `--years` adds the median run's years; `--save-baseline`
/// writes the result as a manual baseline (PROGRESS.md, "Baselines").
///
/// While the plan runs, a one-line progress shows on standard error when
/// it's a terminal (``PlanProgressLine``), and is erased before the answer.
/// Nothing is shown when standard error is piped or captured, or with `--json`.
struct PlanCommand: RetireSubcommand {
    static let configuration = CommandConfiguration(
        commandName: "run",
        abstract: "Run a plan and print the answer (the default).",
        discussion: """
            Runs the library's main plan (mainPlan in library.json), or --plan <id>, and prints \
            the headline answer, what retiring today would need (the plan assets that make it reach \
            the plan's confidence, and your share of them), what you could spend, with flexible \
            spending what it did (how low spending goes in a bad case, how often and how long it's cut, \
            and the spending paid every five years), the chance of success by retirement age, how the \
            plan read your library (the money you can draw now, and accounts available from a later age), \
            and any issues, in the library's base currency. The plan starts from the \
            latest check-in. --fast uses \(PlannerOptions.defaultFastRuns) runs instead of the plan's \
            own number (2,000 by default), with the same random draws. --years adds the median run \
            year by year: income after tax, investments sold, taxes on investments and wealth, spending \
            and what's left. --save-baseline <label> saves the result as a \
            baseline in projections/<plan>/baselines/, to compare your actual numbers against later.
            """)

    @OptionGroup var options: LibraryOptions

    @Option(help: ArgumentHelp("The plan to run, plans/<id>.json. Default: the main plan.", valueName: "id"))
    var plan: String?

    @Flag(help: "Use fewer runs, for a quick answer.")
    var fast = false

    @Flag(help: "Also print the median run, year by year.")
    var years = false

    @Option(help: ArgumentHelp("Save the result as a baseline with this label.", valueName: "label"))
    var saveBaseline: String?

    @Flag(help: "Print JSON.")
    var json = false

    mutating func validate() throws {
        if fast, saveBaseline != nil {
            throw ValidationError("A baseline needs every run: leave out --fast to save one.")
        }
        if let saveBaseline, saveBaseline.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw ValidationError("--save-baseline needs a label, e.g. \"Before the move\".")
        }
    }

    func run(in context: CLIContext) async throws {
        let loaded = try options.load(in: context)
        if saveBaseline != nil { try loaded.checkWritable() }
        let document = try Self.plan(plan.map { PlanID($0) }, in: loaded.library)
        let plannerOptions = fast ? PlannerOptions.fast() : PlannerOptions()
        let console = context.console
        var progress: (@Sendable (PlannerProgress) -> Void)?
        if console.showsStatus, !json {
            progress = { console.status(PlanProgressLine.text($0)) }
        }
        let result: PlanResult
        do {
            defer { if progress != nil { console.clearStatus() } }
            result = try await Planner.run(
                plan: document, library: loaded.library,
                options: Self.options(plannerOptions, today: context.today), progress: progress)
        } catch let error as PlannerError {
            throw CLIError(Self.message(for: error, plan: document))
        }

        var report = PlanReport(result: result, fast: fast)
        if years { report.years = PlanReport.YearRow.rows(result.medianPath.years) }
        if let label = saveBaseline?.trimmingCharacters(in: .whitespacesAndNewlines) {
            report.savedBaseline = try Self.save(result, label: label, loaded: loaded, on: context.today)
        }
        try context.console.print(report, json: json)
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
        var library = loaded.library
        library.projections[plan, default: PlanProjections()].baselines[id] = baseline
        try loaded.folder.save(library, previous: loaded.library)
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

/// The progress line `retire plan` shows on a terminal while it runs:
///
///     [#######-------------]  34% Earliest age · ages 39–75: 12 / 37
///     [#################---]  88% Simulating 1,234 / 2,000 runs
///     [##################--]  93% Sustainable spending: step 4 / 16
///     [###################-]  97% Needed to retire today: step 3 / 9
enum PlanProgressLine {
    static func text(_ progress: PlannerProgress) -> String {
        let fraction = min(1, max(0, progress.fraction))
        let filled = Int((fraction * 20).rounded(.down))
        let bar = "[" + String(repeating: "#", count: filled) + String(repeating: "-", count: 20 - filled) + "]"
        let percent = String(Int((fraction * 100).rounded(.down)))
        return bar + " " + String(repeating: " ", count: max(0, 3 - percent.count)) + percent + "% " + phase(progress)
    }

    /// "Simulating 1,234 / 2,000 runs".
    static func phase(_ progress: PlannerProgress) -> String {
        let done = Format.amount(Decimal(progress.completed), places: 0)
        let total = Format.amount(Decimal(progress.total), places: 0)
        switch progress.phase {
        case .earliestAge:
            let ages = progress.ages.map { " · ages \($0.lowerBound)–\($0.upperBound)" } ?? ""
            return "Earliest age\(ages): \(done) / \(total)"
        case .simulating:
            return "Simulating \(done) / \(total) runs"
        case .sustainableSpending:
            return "Sustainable spending: step \(done) / \(total)"
        case .assetsNeeded:
            return "Needed to retire today: step \(done) / \(total)"
        case .agesWithout:
            return "Coast age and windfalls: step \(done) / \(total)"
        case .summarising:
            return "Summarising"
        }
    }
}

extension LibraryFile {
    /// `plans/<id>.json`.
    static func planPath(_ id: PlanID) -> String { LibraryFile.plan(id).path }
}

/// What `retire plan` prints: the Planner's result, as text or JSON, in the
/// library's base currency.
struct PlanReport: CommandReport {
    let result: PlanResult
    /// Whether the plan ran with `--fast`.
    let fast: Bool
    /// The median run's years, with `--years`.
    var years: [YearRow]?
    /// The path of the baseline saved with `--save-baseline`.
    var savedBaseline: String?

    var currency: CurrencyCode { result.currency }

    /// One year of the median run: income after tax, investments sold,
    /// taxes on investments and wealth, spending and what's left.
    struct YearRow: Equatable {
        var year: Int
        var age: Int
        var work: Double = 0
        var pensions: Double = 0
        /// Other income: rent, part-time work once retired.
        var other: Double = 0
        var windfalls: Double = 0
        var sold: Double = 0
        var taxes: Double = 0
        /// Spending and one-off expenses.
        var spending: Double = 0
        var endAssets: Double = 0

        static func rows(_ years: [YearDetail]) -> [YearRow] {
            years.map { detail in
                var row = YearRow(year: detail.year, age: detail.age)
                for item in detail.income {
                    switch item.kind {
                    case .work: row.work += item.amount
                    case .pension: row.pensions += item.amount
                    case .other: row.other += item.amount
                    case .windfall: row.windfalls += item.amount
                    default: row.sold += item.amount
                    }
                }
                row.taxes = detail.totalTax
                row.spending = detail.spending + detail.expenses
                row.endAssets = detail.endAssets
                return row
            }
        }
    }

    /// A `Double` as a whole amount: `12,345`.
    static func whole(_ value: Double) -> String {
        guard value.isFinite else { return "?" }
        return Format.amount(Decimal(Int(value.rounded())), places: 0)
    }

    /// A `Double` rounded to a whole amount, for JSON: `"12345"`.
    static func rounded(_ value: Double) -> String {
        guard value.isFinite else { return "0" }
        return Decimal(Int(value.rounded())).fileString
    }

    static func percent(_ share: Double) -> String {
        "\(Int((share * 100).rounded()))%"
    }

    /// A readiness as a percentage, rounded down below 100% so it never
    /// reads 100% while retiring today falls short: "7%".
    static func readinessPercent(_ readiness: Double) -> String {
        guard readiness < 1 else { return percent(readiness) }
        return "\(min(99, Int((readiness * 100 + 1e-9).rounded(.down))))%"
    }

    /// What retiring today would need (PLANNER.md, "Assets needed to retire
    /// today"), with today's `planAssets`: "Needed to retire today:
    /// 2,002,118 EUR in plan assets, at 90% confidence, with the extra
    /// 1,853,310 EUR in accounts you can draw now. You have 148,808 EUR (7%)."
    static func neededText(_ needed: AssetsNeeded, planAssets: Double, currency: CurrencyCode,
                           confidence: Double) -> String {
        let at = "at \(percent(confidence)) confidence"
        let have = "\(whole(planAssets)) \(currency)"
        let times = String(Int(AssetsNeeded.maximumScale))
        switch needed.outcome {
        case .found:
            let share = needed.readiness.map(readinessPercent).map { " (\($0))" } ?? ""
            var how = ""
            if let extra = needed.extra, whole(extra) != "0" {
                how = extra > 0
                    ? ", with the extra \(whole(extra)) \(currency) in accounts you can draw now"
                    : ": \(whole(-extra)) \(currency) less in accounts you can draw now"
            }
            return "Needed to retire today: \(whole(needed.amount ?? 0)) \(currency) in plan assets, \(at)"
                + "\(how). You have \(have)\(share)."
        case .atMost:
            if needed.leavesOnlyLockedMoney {
                return "Needed to retire today: at most the \(whole(needed.amount ?? 0)) \(currency) locked "
                    + "away, \(at): it works with nothing in accounts you can draw now. You have \(have)."
            }
            return "Needed to retire today: at most \(whole(needed.amount ?? 0)) \(currency) in plan assets, "
                + "\(at). You have \(have), \(times) times that or more."
        case .moreThanMaximum:
            return "Needed to retire today: more than \(times) times your plan assets (\(have)), \(at)."
        case .noPlanAssets:
            return needed.amount == 0 ? "Retiring today needs no plan assets, \(at)."
                : "The plan counts no assets, and retiring today needs some, \(at)."
        }
    }

    /// How the search for what retiring today needs ended, for JSON.
    static func outcomeName(_ outcome: AssetsNeeded.Outcome) -> String {
        switch outcome {
        case .found: "found"
        case .atMost: "atMost"
        case .moreThanMaximum: "moreThanMaximum"
        case .noPlanAssets: "noPlanAssets"
        }
    }

    /// The headline sentence, as on the app's Plan screen.
    var headlineText: String {
        let answer = result.answer
        let confidence = Self.percent(answer.confidence)
        if answer.canRetireNow {
            return "Yes: retiring today succeeds in \(Self.percent(answer.successIfRetiringNow)) of simulated futures "
                + "(you asked for \(confidence))."
        }
        let today = "Retiring today succeeds in \(Self.percent(answer.successIfRetiringNow)) of simulated futures."
        guard let age = answer.earliestAge else {
            return "Not yet: no retirement age reaches \(confidence) before the plan ends. \(today)"
        }
        return "Not yet: the earliest age with \(confidence) confidence is \(age)"
            + (answer.earliestDate.map { " (\($0.year))" } ?? "") + ". \(today)"
    }

    /// "2,000 runs from 2026-09-30 · engine 2.0.0".
    var runText: String {
        let runs = result.settings.runs
        return "\(Format.amount(Decimal(runs), places: 0)) \(runs == 1 ? "run" : "runs")" + (fast ? " (fast)" : "")
            + " from \(result.start.date) · engine \(result.engine)"
    }

    func lines() -> [String] {
        let answer = result.answer
        var lines = ["Plan \(result.plan.id): \(result.plan.name)", runText, "", headlineText]
        if let target = answer.targetAge, let success = answer.successAtTarget {
            lines.append("At your target age, \(target), the chance of success is \(Self.percent(success)).")
        }
        if let needed = answer.assetsNeeded {
            lines.append(Self.neededText(needed, planAssets: result.start.planAssets.doubleValue, currency: currency,
                                         confidence: answer.confidence))
        }
        if let spending = answer.sustainableSpending?.perYear, spending.isFinite {
            let amount = Format.amount(Decimal(Int(spending.rounded())), places: 0)
            lines.append("What you could spend: \(amount) \(currency) a year in today's "
                + "money\(answer.targetAge.map { " from age \($0)" } ?? ""), "
                + "at \(Self.percent(answer.confidence)) confidence.")
        }
        if let flexible = result.flexibleSpending {
            lines.append("")
            lines += PlanFlexibleSpending.Report(flexible, fan: result.fan)
                .lines(currency: currency, startYear: result.start.date.year)
        }
        if !result.successCurve.isEmpty {
            lines.append("")
            lines.append("Chance of success by retirement age")
            var table = TextTable([.right("Age"), .right("Year"), .right("Success"), .left("")])
            for row in result.successCurve {
                let bar = String(repeating: "#", count: Int((max(0, min(1, row.success)) * 20).rounded()))
                table.add(["\(row.age)", "\(row.retirementDate.year)", Self.percent(row.success), bar])
            }
            lines += table.lines()
        }
        if let years, !years.isEmpty {
            lines.append("")
            lines.append("The median run, year by year (\(currency), today's money)")
            // Other income only has a column when the plan has some.
            let hasOther = years.contains { $0.other != 0 }
            var columns: [TextTable.Column] = [.right("Year"), .right("Age"), .right("Work"), .right("Pensions")]
            if hasOther { columns.append(.right("Other")) }
            columns += [.right("Windfalls"), .right("Sold"), .right("Taxes"), .right("Spending"), .right("At the end")]
            var table = TextTable(columns)
            for row in years {
                var amounts: [Double] = [row.work, row.pensions]
                if hasOther { amounts.append(row.other) }
                amounts += [row.windfalls, row.sold, row.taxes, row.spending, row.endAssets]
                table.add(["\(row.year)", "\(row.age)"] + amounts.map(Self.whole))
            }
            lines += table.lines()
            lines.append((hasOther ? "Work, pensions and other income after tax." : "Work and pensions after tax.")
                + " Sold: investments sold to cover the year. Taxes: on investments and on wealth. The first year "
                + "is the part after the check-in.")
        }
        lines.append("")
        lines += readingLines()
        if !result.issues.isEmpty {
            lines.append("")
            lines.append("Issues")
            lines += result.issues.map { "  \($0.isError ? "error  " : "warning") \($0.message)" }
        }
        if let savedBaseline {
            lines.append("")
            lines.append("Saved the baseline \(savedBaseline).")
        }
        return lines
    }

    /// How the plan read the library (PLANNER.md, "The portfolio"): the
    /// money you can draw now, and the accounts available from a later age.
    func readingLines() -> [String] {
        var table = TextTable([.left("Money"), .right("Value"), .left("Drawn"), .left("Accounts")])
        for bucket in result.start.buckets {
            table.add([bucket.name, Self.whole(bucket.value), bucket.availableFromAge.map { "from \($0)" } ?? "now",
                       bucket.accounts.map(\.rawValue).joined(separator: ", ")])
        }
        return ["How the plan reads your library, on \(result.start.date) (\(currency))"] + table.lines()
    }

    var json: JSON {
        let answer = result.answer
        let needed = answer.assetsNeeded
        // For an amount found: the money added to the accounts that can be drawn now.
        let extra = needed?.outcome == .found ? needed?.extra : nil
        let start = JSON.Start(date: result.start.date.description, buckets: result.start.buckets.map {
            JSON.Bucket(name: $0.name, availableFromAge: $0.availableFromAge, value: Self.rounded($0.value),
                        accounts: $0.accounts.map(\.rawValue))
        })
        return JSON(
            plan: result.plan.id.rawValue, name: result.plan.name, currency: currency.rawValue, headline: headlineText,
            canRetireToday: answer.canRetireNow, confidence: answer.confidence,
            successToday: answer.successIfRetiringNow, earliestAge: answer.earliestAge,
            earliestYear: answer.earliestDate?.year, targetAge: answer.targetAge,
            successAtTarget: answer.successAtTarget,
            successByAge: result.successCurve.map {
                JSON.Age(age: $0.age, year: $0.retirementDate.year, success: $0.success)
            },
            sustainableSpending: answer.sustainableSpending?.perYear,
            assetsNeededToday: needed?.amount.flatMap { $0.isFinite ? $0.rounded() : nil },
            assetsNeededOutcome: needed.map { Self.outcomeName($0.outcome) },
            assetsNeededExtra: extra.flatMap { $0.isFinite ? $0.rounded() : nil },
            readiness: needed?.readiness.flatMap { $0.isFinite ? ($0 * 10_000 + 1e-9).rounded(.down) / 10_000 : nil },
            issues: result.issues.map { JSON.Issue(severity: $0.severity.rawValue, message: $0.message) },
            runs: result.settings.runs, fast: fast, engine: result.engine, startDate: result.start.date.description,
            savedBaseline: savedBaseline, start: start,
            flexibleSpending: result.flexibleSpending.map { PlanFlexibleSpending.Report($0, fan: result.fan).json },
            years: years?.map { row in
                JSON.Year(year: row.year, age: row.age, work: Self.rounded(row.work),
                          pensions: Self.rounded(row.pensions), other: row.other != 0 ? Self.rounded(row.other) : nil,
                          windfalls: Self.rounded(row.windfalls),
                          sold: Self.rounded(row.sold), taxes: Self.rounded(row.taxes),
                          spending: Self.rounded(row.spending), endAssets: Self.rounded(row.endAssets))
            })
    }

    struct JSON: Encodable {
        struct Age: Encodable {
            var age: Int
            var year: Int
            var success: Double
        }

        struct Issue: Encodable {
            var severity: String
            var message: String
        }

        /// How the plan read the library.
        struct Start: Encodable {
            var date: String
            var buckets: [Bucket]
        }

        struct Bucket: Encodable {
            var name: String
            /// The age from which it can be drawn; absent for the money you can draw now.
            var availableFromAge: Int?
            var value: String
            var accounts: [String]
        }

        /// A year of the median run (`--years`), whole amounts as strings.
        struct Year: Encodable {
            var year: Int
            var age: Int
            var work: String
            var pensions: String
            /// Other income; absent without any.
            var other: String?
            var windfalls: String
            var sold: String
            var taxes: String
            var spending: String
            var endAssets: String
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
        /// The plan assets retiring today would need, whole; `nil` when more
        /// than 20 times today's would be needed.
        var assetsNeededToday: Double?
        /// How the search ended: found, atMost, moreThanMaximum or noPlanAssets.
        var assetsNeededOutcome: String?
        /// When found: the money added to the accounts that can be drawn now
        /// (negative when it could be taken out), whole.
        var assetsNeededExtra: Double?
        /// Today's plan assets over what retiring today needs, rounded down
        /// to 4 decimals: 1 or more exactly when retiring today works.
        var readiness: Double?
        var issues: [Issue]
        var runs: Int
        var fast: Bool
        var engine: String
        var startDate: String
        var savedBaseline: String?
        var start: Start
        /// What flexible spending did at the focus age; absent without it.
        var flexibleSpending: PlanFlexibleSpending.JSONReport?
        var years: [Year]?
    }
}
