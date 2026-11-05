import ArgumentParser
import Foundation
import Model
import Planner
import Tracker

/// `retire audit`: every number the app shows at each check-in (``Audit``),
/// the checks that they agree (Tracker's `AuditChecks`), or one check-in
/// account by account (``AuditExplainReport``), to compare with statements.
struct AuditCommand: RetireSubcommand {
    static let configuration = CommandConfiguration(
        commandName: "audit",
        abstract: "Print every number the app shows, check that they agree, or explain one check-in.",
        discussion: """
            Works out, at each check-in on or before --through, the numbers the app shows, with the \
            functions its screens use: net worth and plan assets, each account's change since the \
            check-in before, What moved it and Your pay, the check-in's bars, the savings rate over \
            the check-in's month, the 12 months to it and the year so far, This year, and the saving \
            pace; then Where your money came from by year, and Progress's years and the milestones \
            reached for --plan, or the main plan. With --plan, it also runs that plan with \
            \(Audit.planRuns) runs and its own seed, from the latest check-in as the app does, and \
            prints its answer. Without --json it prints \
            a summary; --json prints every number, amounts exactly as the library writes them and \
            the planner's to 4 significant figures, in a stable order, so two runs can be diffed.

            --check prints only where the numbers disagree: a check-in whose change has a part \
            nothing explains though every saved amount is known, bank lines that don't add up to the \
            balance, a broker statement's quantities that differ from the trades, What moved it and \
            the check-in's bars disagreeing on what was saved, a month's savings rate below -50% or \
            above 100%, and an account that started with more than the month's money in. Each line \
            has the date, the account and the rule; --amounts adds the amounts. Exits with status 1 \
            when there's one.

            --explain <date> prints one check-in account by account: each one's start, saved, \
            markets, other and end, and your pay, to compare with bank and broker statements.
            """)

    @OptionGroup var options: LibraryOptions

    @Option(help: ArgumentHelp("Progress for this plan, and its answer. Default: the main plan, without its answer.",
                               valueName: "id"))
    var plan: String?

    @Option(help: ArgumentHelp("Only the check-ins on or before this date, YYYY-MM-DD. Default: today.",
                               valueName: "date"))
    var through: String?

    @Flag(help: "Check that the numbers agree; print only where they don't.")
    var check = false

    @Flag(help: "With --check, also print the amounts.")
    var amounts = false

    @Option(help: ArgumentHelp("Explain the check-in on this date account by account.", valueName: "date"))
    var explain: String?

    @Flag(help: "Print JSON.")
    var json = false

    func validate() throws {
        _ = try parseDate(through, option: "--through")
        _ = try parseDate(explain, option: "--explain")
        if check, explain != nil { throw ValidationError("--check and --explain can't be used together.") }
        if amounts, !check { throw ValidationError("--amounts goes with --check.") }
        if through != nil, explain != nil { throw ValidationError("--through doesn't go with --explain.") }
        if plan != nil, check || explain != nil {
            throw ValidationError("--plan goes with the full audit, not with --check or --explain.")
        }
    }

    func run(in context: CLIContext) async throws {
        let library = try options.load(in: context).library
        let through = try parseDate(through, option: "--through") ?? context.today
        if let date = try parseDate(explain, option: "--explain") {
            try context.console.print(try AuditExplainReport(library: library, date: date), json: json)
            return
        }
        if check {
            let checks = AuditChecks(library: library)
            let report = AuditCheckReport(violations: checks.violations(through: through), amounts: amounts,
                                          checkIns: checks.valuator.checkInDates(through: through).count)
            try context.console.print(report, json: json)
            if !report.violations.isEmpty { throw ExitCode.failure }
            return
        }
        var run: PlanResult?
        if let id = plan.map({ PlanID($0) }) {
            let document = try PlanCommand.plan(id, in: library)
            let options = PlannerOptions(mode: .fast(runs: Audit.planRuns), ageScan: .full, solveCoastAge: true,
                                         solveWithoutWindfalls: true, solvePaceAge: true, today: through)
            do {
                run = try await Planner.run(plan: document, library: library, options: options)
            } catch let error as PlannerError {
                throw CLIError(PlanCommand.message(for: error, plan: document))
            }
        }
        let progressPlan = (plan.map { PlanID($0) } ?? library.settings.mainPlan).flatMap {
            library.plans[$0] == nil ? nil : $0
        }
        let audit = Audit(library: library, through: through, plan: progressPlan, run: run)
        try context.console.print(AuditSummary(audit: audit), json: json)
    }
}

/// What `retire audit` prints without `--check` or `--explain`: a line per
/// check-in and per year as text; every number as JSON.
struct AuditSummary: CommandReport {
    let audit: Audit

    var json: Audit { audit }

    /// A number the audit wrote exactly, as an amount: `1,234.56`.
    static func amount(_ text: String?) -> String {
        guard let text, let value = Decimal(fileString: text) else { return "" }
        return Format.amount(value)
    }

    static func percent(_ text: String?) -> String {
        guard let text, let value = Decimal(fileString: text) else { return "–" }
        return Format.percent(value)
    }

    func lines() -> [String] {
        var lines = ["Audit through \(audit.through), in \(audit.currency): "
            + Wording.count(audit.checkIns.count, "check-in")]
        guard !audit.checkIns.isEmpty else { return lines }
        lines.append("")
        var table = TextTable([.left("Check-in"), .right("Net worth"), .right("Change"), .right("Saved"),
                               .right("Markets"), .right("Other"), .right("Unexplained"), .right("Month's rate")])
        for checkIn in audit.checkIns {
            let moved = checkIn.whatMoved
            table.add([checkIn.date, Self.amount(checkIn.netWorth.total), Self.amount(moved?.change),
                       Self.amount(moved?.saved), Self.amount(moved?.markets), Self.amount(moved?.other),
                       Self.amount(moved?.unexplained),
                       checkIn.savingsRate.month == nil ? "" : Self.percent(checkIn.savingsRate.month?.rate)])
        }
        lines += table.lines()
        if let progress = audit.progress, !progress.years.isEmpty {
            lines.append("")
            lines.append("Year by year, plan \(audit.plan ?? "")")
            var years = TextTable([.left("Year"), .right("You saved"), .right("Planned"), .right("Markets"),
                                   .right("Spent a year")])
            for year in progress.years {
                years.add([year.soFar ? "\(year.year) so far" : "\(year.year)", Self.amount(year.youSaved),
                           Self.amount(year.plannedYouSaved), Self.amount(year.change.market),
                           Self.amount(year.spentPerYear)])
            }
            lines += years.lines()
            lines.append(Wording.count(progress.milestones.count, "milestone") + " reached.")
        }
        if let run = audit.planRun {
            lines.append("")
            let age = run.earliestAge.map { "earliest age \($0)" } ?? "no age reaches the confidence level"
            let readiness = run.readiness.map { ", readiness \(Self.percent($0))" } ?? ""
            lines.append("Plan \(run.plan), \(run.runs) runs: \(age)\(readiness).")
        }
        lines.append("")
        lines.append("Every number: --json. Where they disagree: --check.")
        return lines
    }
}

/// What `retire audit --check` prints: only the violations, each with its
/// date, account and rule; amounts with `--amounts`.
struct AuditCheckReport: CommandReport {
    let violations: [AuditViolation]
    /// Whether to print the amounts behind each violation.
    let amounts: Bool
    /// The check-ins checked.
    let checkIns: Int

    /// The account a violation is about, as a cell: `directa (vwce)`, or
    /// `net worth`.
    static func subject(_ violation: AuditViolation) -> String {
        let account = violation.account?.rawValue ?? "net worth"
        return violation.instrument.map { "\(account) (\($0))" } ?? account
    }

    /// The amounts behind a violation: `difference 12.5, opening 1,000`; a
    /// rate as a percentage.
    static func amounts(_ violation: AuditViolation) -> String {
        violation.amounts.map { amount in
            let value = amount.name == "rate" ? Format.percent(amount.value) : Format.exact(amount.value)
            return "\(amount.name) \(value)"
        }.joined(separator: ", ")
    }

    func lines() -> [String] {
        guard !violations.isEmpty else {
            return ["No violations in \(Wording.count(checkIns, "check-in"))."]
        }
        var columns: [TextTable.Column] = [.left("Date"), .left("Account"), .left("Rule")]
        if amounts { columns.append(.left("Amounts")) }
        var table = TextTable(columns)
        for violation in violations {
            var row = [violation.date.description, Self.subject(violation),
                       "\(violation.rule.rawValue): \(violation.rule.summary)"]
            if amounts { row.append(Self.amounts(violation)) }
            table.add(row)
        }
        return table.lines(indent: 0)
            + ["", "\(Wording.count(violations.count, "violation")) in \(Wording.count(checkIns, "check-in"))."]
    }

    var json: JSON {
        JSON(checkIns: checkIns, violations: violations.map { violation in
            JSON.Violation(date: violation.date.description, account: violation.account?.rawValue,
                           instrument: violation.instrument?.rawValue, rule: violation.rule.rawValue,
                           summary: violation.rule.summary,
                           amounts: amounts ? Dictionary(violation.amounts.map { ($0.name, $0.value.fileString) },
                                                         uniquingKeysWith: { first, _ in first }) : nil)
        })
    }

    struct JSON: Encodable {
        struct Violation: Encodable {
            var date: String
            var account: String?
            var instrument: String?
            var rule: String
            var summary: String
            /// Only with `--amounts`.
            var amounts: [String: String]?
        }

        var checkIns: Int
        var violations: [Violation]
    }
}
