import ArgumentParser
import Foundation
import Model
import Planner
import Storage

/// `retire plan run`, also just `retire plan`: runs a plan and prints the answer.
///
/// Runs the main plan (`mainPlan` in library.json) or `--plan <id>`, maps the
/// Planner's `PlanResult` into a ``PlanReport`` and prints it, as text or
/// JSON, in the library's base currency. `--fast` uses fewer runs (the app's quick
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

    mutating func run() async throws {
        try await run(in: .live())
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

        var report = PlanReport(result: result, currency: result.currency ?? loaded.library.settings.baseCurrency,
                                fast: fast)
        report.reading = PlanReport.Reading(result.start)
        if years { report.years = PlanReport.YearRow.rows(result.medianPath.years) }
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

    /// A problem with the plan.
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
    /// What retiring today would need, from the simulation. `nil` for a
    /// report made by hand.
    var needed: Needed?
    var issues: [Issue]

    /// What retiring today would need (PLANNER.md, "Assets needed to retire
    /// today"): the plan assets that make retiring at today's age reach the
    /// confidence level, and today's as a share of them. It replaces the
    /// old FI number, which the report never shows.
    struct Needed {
        /// How the search ended, as in `AssetsNeeded.Outcome`.
        enum Outcome: String {
            case found, atMost, moreThanMaximum, noPlanAssets
        }

        var outcome: Outcome
        /// Today's plan assets.
        var planAssets: Double
        /// The plan assets needed: within 1% when found, the bound for `atMost`.
        var amount: Double?
        /// `planAssets / amount`: 1 or more exactly when retiring today works.
        var readiness: Double?
        /// The most times today's plan assets the search tries.
        var maximumScale: Double = AssetsNeeded.maximumScale
        /// The money added to the accounts that can be drawn now (`amount −
        /// planAssets`; negative when it could be taken out). `nil` for a
        /// report made by hand.
        var extra: Double?
        /// For `atMost`: whether the bound is what's locked away, with
        /// nothing left in the accounts that can be drawn now.
        var onlyLockedMoney = false

        init(outcome: Outcome, planAssets: Double, amount: Double? = nil, readiness: Double? = nil,
             extra: Double? = nil, onlyLockedMoney: Bool = false) {
            self.outcome = outcome
            self.planAssets = planAssets
            self.amount = amount
            self.readiness = readiness
            self.extra = extra
            self.onlyLockedMoney = onlyLockedMoney
        }

        init(_ needed: AssetsNeeded, planAssets: Double) {
            let outcome: Outcome = switch needed.outcome {
            case .found: .found
            case .atMost: .atMost
            case .moreThanMaximum: .moreThanMaximum
            case .noPlanAssets: .noPlanAssets
            }
            self.init(outcome: outcome, planAssets: planAssets, amount: needed.amount, readiness: needed.readiness,
                      extra: needed.outcome == .found ? needed.extra : nil,
                      onlyLockedMoney: needed.leavesOnlyLockedMoney)
        }

        /// A readiness as a percentage, rounded down below 100% so it never
        /// reads 100% while retiring today falls short: "7%".
        static func percent(_ readiness: Double) -> String {
            guard readiness < 1 else { return PlanReport.percent(readiness) }
            return "\(min(99, Int((readiness * 100 + 1e-9).rounded(.down))))%"
        }

        /// "Needed to retire today: 2,002,118 EUR in plan assets, at 90%
        /// confidence, with the extra 1,853,310 EUR in accounts you can draw
        /// now. You have 148,808 EUR (7%)."
        func text(currency: CurrencyCode, confidence: Double) -> String {
            let at = "at \(PlanReport.percent(confidence)) confidence"
            let have = "\(PlanReport.whole(planAssets)) \(currency)"
            let times = String(Int(maximumScale))
            switch outcome {
            case .found:
                let share = readiness.map(Self.percent).map { " (\($0))" } ?? ""
                var how = ""
                if let extra, PlanReport.whole(extra) != "0" {
                    how = extra > 0
                        ? ", with the extra \(PlanReport.whole(extra)) \(currency) in accounts you can draw now"
                        : ": \(PlanReport.whole(-extra)) \(currency) less in accounts you can draw now"
                }
                return "Needed to retire today: \(PlanReport.whole(amount ?? 0)) \(currency) in plan assets, \(at)"
                    + "\(how). You have \(have)\(share)."
            case .atMost:
                if onlyLockedMoney {
                    return "Needed to retire today: at most the \(PlanReport.whole(amount ?? 0)) \(currency) locked "
                        + "away, \(at): it works with nothing in accounts you can draw now. You have \(have)."
                }
                return "Needed to retire today: at most \(PlanReport.whole(amount ?? 0)) \(currency) in plan assets, "
                    + "\(at). You have \(have), \(times) times that or more."
            case .moreThanMaximum:
                return "Needed to retire today: more than \(times) times your plan assets (\(have)), \(at)."
            case .noPlanAssets:
                return amount == 0 ? "Retiring today needs no plan assets, \(at)."
                    : "The plan counts no assets, and retiring today needs some, \(at)."
            }
        }
    }
    /// How the plan ran: the number of runs, fast or full, and the engine.
    /// `nil` for a report made by hand.
    var run: Run?
    /// The path of the baseline saved with `--save-baseline`.
    var savedBaseline: String?
    /// How the plan read the library: the money you can draw now and the
    /// accounts available from a later age. `nil` for a report made by hand.
    var reading: Reading?
    /// The median run's years, with `--years`.
    var years: [YearRow]?
    /// What flexible spending did at the focus age; `nil` without it.
    var flexible: PlanFlexibleSpending.Report?

    /// How a plan read the library (PLANNER.md, "The portfolio"): the money you
    /// can draw now, and the accounts available from a later age.
    struct Reading {
        struct Bucket {
            var name: String
            var availableFromAge: Int?
            var value: Double
            var accounts: [AccountID]
        }

        var date: CalendarDate
        var buckets: [Bucket]

        init(date: CalendarDate, buckets: [Bucket]) {
            self.date = date
            self.buckets = buckets
        }

        init(_ start: PlanStart) {
            self.init(date: start.date, buckets: start.buckets.map {
                Bucket(name: $0.name, availableFromAge: $0.availableFromAge, value: $0.value, accounts: $0.accounts)
            })
        }

        func lines(currency: CurrencyCode) -> [String] {
            var lines = ["How the plan reads your library, on \(date) (\(currency))"]
            var table = TextTable([.left("Money"), .right("Value"), .left("Drawn"), .left("Accounts")])
            for bucket in buckets {
                table.add([bucket.name, PlanReport.whole(bucket.value),
                           bucket.availableFromAge.map { "from \($0)" } ?? "now",
                           bucket.accounts.map(\.rawValue).joined(separator: ", ")])
            }
            lines += table.lines()
            return lines
        }

        var json: JSON.Start {
            JSON.Start(date: date.description, buckets: buckets.map {
                JSON.Bucket(name: $0.name, availableFromAge: $0.availableFromAge, value: PlanReport.rounded($0.value),
                            accounts: $0.accounts.map(\.rawValue))
            })
        }
    }

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

    /// How a plan ran.
    struct Run {
        var runs: Int
        var fast: Bool
        var engine: String
        var startDate: CalendarDate
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
        needed = answer.assetsNeeded.map { Needed($0, planAssets: result.start.planAssets.doubleValue) }
        run = Run(runs: result.settings.runs, fast: fast, engine: result.engine, startDate: result.start.date)
        flexible = result.flexibleSpending.map { PlanFlexibleSpending.Report($0, fan: result.fan) }
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

    /// "2,000 runs from 2026-09-30 · engine 2.0.0".
    var runText: String? {
        guard let run else { return nil }
        var parts = ["\(Format.amount(Decimal(run.runs), places: 0)) \(run.runs == 1 ? "run" : "runs")"
            + (run.fast ? " (fast)" : "") + " from \(run.startDate)"]
        parts.append("engine \(run.engine)")
        return parts.joined(separator: " · ")
    }

    func lines() -> [String] {
        var lines = ["Plan \(planID): \(planName)"]
        if let runText { lines.append(runText) }
        lines += ["", headlineText]
        if let target = headline.targetAge, let success = headline.successAtTarget {
            lines.append("At your target age, \(target), the chance of success is \(Self.percent(success)).")
        }
        if let needed {
            lines.append(needed.text(currency: currency, confidence: headline.confidence))
        }
        if let spending = sustainableSpending, spending.isFinite {
            let amount = Format.amount(Decimal(Int(spending.rounded())), places: 0)
            lines.append("What you could spend: \(amount) \(currency) a year in today's "
                + "money\(headline.targetAge.map { " from age \($0)" } ?? ""), "
                + "at \(Self.percent(headline.confidence)) confidence.")
        }
        if let flexible {
            lines.append("")
            lines += flexible.lines(currency: currency, startYear: run?.startDate.year ?? 0)
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
        if let reading {
            lines.append("")
            lines += reading.lines(currency: currency)
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
             assetsNeededToday: needed?.amount.flatMap { $0.isFinite ? $0.rounded() : nil },
             assetsNeededOutcome: needed?.outcome.rawValue,
             assetsNeededExtra: needed?.extra.flatMap { $0.isFinite ? $0.rounded() : nil },
             readiness: needed?.readiness.flatMap { $0.isFinite ? ($0 * 10_000 + 1e-9).rounded(.down) / 10_000 : nil },
             issues: issues.map { JSON.Issue(severity: $0.isError ? "error" : "warning", message: $0.message) },
             runs: run?.runs, fast: run?.fast, engine: run?.engine, startDate: run?.startDate.description,
             savedBaseline: savedBaseline, start: reading?.json,
             flexibleSpending: flexible?.json,
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
            var year: Int?
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
        var runs: Int?
        var fast: Bool?
        var engine: String?
        var startDate: String?
        var savedBaseline: String?
        var start: Start?
        /// What flexible spending did at the focus age; absent without it.
        var flexibleSpending: PlanFlexibleSpending.JSONReport?
        var years: [Year]?
    }
}
