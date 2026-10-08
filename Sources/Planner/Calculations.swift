import Foundation
import Model

/// How ``Planner/calculations(plan:library:options:)`` writes its report.
public struct CalculationsOptions: Hashable, Sendable {
    /// Leaves out names and dates and rounds amounts, so the report can be
    /// shared: accounts, phases, pensions, other income and events get
    /// generic names, the start is only a year, and amounts are rounded to
    /// ``rounding``.
    public var anonymize: Bool
    /// What amounts are rounded to when anonymized (default 100).
    public var rounding: Double
    /// The day a plan without a check-in starts (default: today).
    public var today: CalendarDate?

    public init(anonymize: Bool = false, rounding: Double = 100, today: CalendarDate? = nil) {
        self.anonymize = anonymize
        self.rounding = rounding
        self.today = today
    }
}

extension Planner {
    /// Every input and calculation behind a plan's answer, as Markdown
    /// (PLANNER.md, "Calculations"): the plan as the planner read it, the
    /// starting portfolio, the chance of success by retirement age, the
    /// deterministic run and the median run year by year, and why runs fail.
    /// It runs the plan in full first.
    public static func calculations(plan: PlanDocument, library: Library,
                                    options: CalculationsOptions = CalculationsOptions()) async throws -> String {
        let run = try await withTaskExecutorPreference(PlannerExecutor.shared) {
            try await computeRun(plan: plan, library: library, options: PlannerOptions(today: options.today),
                                 progress: nil)
        }
        return CalculationsReport(result: run.result, model: run.model, options: options).markdown
    }
}

/// The Markdown of the calculations report.
struct CalculationsReport {
    let result: PlanResult
    /// The plan as the run read it.
    let model: PlanModel
    let options: CalculationsOptions

    var markdown: String {
        var lines: [String] = []
        let title = options.anonymize ? "Plan" : model.plan.name
        lines.append("# Calculations: \(title)")
        lines.append("")
        lines.append("Engine \(result.engine), \(model.runs) runs, seed \(model.seed), starting "
            + (options.anonymize ? "in \(model.startDate.year)" : "the day after \(model.startDate)")
            + ", in \(model.currency.rawValue), in today's money. Estimates, not financial or tax advice.")
        lines += answer() + planAsRead() + startingPortfolio() + successCurve()
        lines += yearByYear("The deterministic run (expected returns), retiring at \(result.focusAge)",
                            result.expectedPath)
        lines += yearByYear("The median run, retiring at \(result.focusAge)", result.medianPath)
        lines += flexibleSpending() + failures() + warnings()
        return lines.joined(separator: "\n") + "\n"
    }

    // MARK: Sections

    private func answer() -> [String] {
        let answer = result.answer
        var lines = ["", "## The answer", ""]
        lines.append("- Retiring today succeeds in \(percent(answer.successIfRetiringNow)) of simulated futures; "
            + "the plan asks for \(percent(answer.confidence)).")
        if let earliest = answer.earliestAge {
            lines.append("- The earliest age with \(percent(answer.confidence)) confidence is \(earliest).")
        } else {
            lines.append("- No age up to the latest simulated reaches \(percent(answer.confidence)).")
        }
        if let target = answer.targetAge, let success = answer.successAtTarget {
            lines.append("- Retiring at \(target) succeeds in \(percent(success)).")
        }
        if let needed = answer.assetsNeeded?.amount {
            lines.append("- Retiring today needs \(money(needed)) in plan assets; there are \(money(result.start.planAssets.doubleValue)).")
        }
        if let spending = answer.sustainableSpending {
            lines.append("- What you could spend from \(spending.age): \(money(spending.perYear)) a year "
                + "(\(percent(spending.success)) of futures).")
        }
        return lines
    }

    private func planAsRead() -> [String] {
        let plan = model.plan
        var lines = ["", "## The plan as read", ""]
        lines.append("- Age at the start \(model.currentAge); the plan runs to \(model.endAge). Retirement: "
            + (model.planAge.map { "at \($0)" } ?? "the earliest age that reaches the confidence level") + ".")
        lines.append("- Inflation \(percent(model.inflation)) a year.")
        lines.append("- Taxes: \(percent(model.taxes.investmentRate)) on investment income and gains; wealth tax "
            + "\(percent(model.taxes.wealthRate))" + (model.taxes.wealthAllowance > 0
                ? " above \(money(model.taxes.wealthAllowance))" : "") + ".")
        var spending = "- Spending: \(money(model.spending.working)) a year while working, "
            + "\(money(model.spending.retired)) in retirement"
        if !model.spending.phases.isEmpty {
            spending += " (" + model.spending.phases.map { "× \(number($0.factor)) from \($0.fromAge)" }
                .joined(separator: ", ") + ")"
        }
        lines.append(spending + ".")
        if let rule = model.spending.flexible {
            lines.append("- Flexible spending: cuts of \(percent(rule.cut)) down to \(percent(rule.floor)), when the "
                + "withdrawal rate is \(percent(rule.upper)) above the first year's; raised back when it's "
                + "\(percent(rule.lower)) below.")
        }
        if !model.work.isEmpty {
            lines += ["", "| Work | From | Until | After tax a year | Real growth |", "|---|---|---|---:|---:|"]
            for (n, phase) in model.work.enumerated() {
                lines.append("| \(name(phase.label, generic: "Work \(n + 1)")) | \(date(phase.from)) | "
                    + "\(phase.until.map(date) ?? "retirement") | \(money(phase.net)) | \(percent(phase.realGrowth)) |")
            }
        }
        if !model.pensions.isEmpty {
            lines += ["", "| Pension | From age | After tax a year |", "|---|---:|---:|"]
            for (n, pension) in model.pensions.enumerated() {
                lines.append("| \(name(pension.name, generic: "Pension \(n + 1)")) | \(pension.fromAge) | "
                    + "\(money(pension.perYear)) |")
            }
        }
        if !model.income.isEmpty {
            lines += ["", "| Other income | From | Until age | After tax a year |", "|---|---|---:|---:|"]
            for (n, other) in model.income.enumerated() {
                let from = other.fromAge.map(String.init) ?? "retirement"
                let until = other.untilAge.map(String.init) ?? "end"
                lines.append("| \(name(other.name, generic: "Other income \(n + 1)")) | \(from) | \(until) | "
                    + "\(money(other.perYear)) |")
            }
        }
        if !model.contributions.isEmpty {
            lines += ["", "| Contribution into | Amount | When |", "|---|---:|---|"]
            for contribution in model.contributions {
                let into = name(model.portfolio.buckets[contribution.bucket].name,
                                generic: "Account group \(contribution.bucket + 1)")
                if let oneOff = contribution.oneOff {
                    lines.append("| \(into) | \(money(oneOff.amount)) | in \(oneOff.year) |")
                } else {
                    lines.append("| \(into) | \(money(contribution.perYear)) a year | until "
                        + "\(contribution.until.map(date) ?? "retirement") |")
                }
            }
        }
        if !model.events.isEmpty {
            lines += ["", "| Event | Year | Amount | Chance |", "|---|---:|---:|---:|"]
            for (n, event) in model.events.enumerated() {
                lines.append("| \(name(event.name, generic: "Event \(n + 1)")) | \(event.year) | "
                    + "\(money(event.amount)) | \(percent(event.probability)) |")
            }
        }
        if let mix = plan.portfolio.targetMix.flatMap(Portfolio.shares) {
            lines.append("")
            lines.append("- Target mix of the money you can draw: \(describe(mix)).")
        }
        for step in plan.portfolio.targetMixByAge {
            guard let mix = Portfolio.shares(step.mix) else { continue }
            let from = step.fromAge.age.map { "from \($0)" } ?? "from retirement"
            lines.append("- \(from.prefix(1).uppercased() + from.dropFirst()): \(describe(mix)).")
        }
        let returns = model.returns
        lines += ["", "| Class | Mean | Median | Volatility | Income yield |", "|---|---:|---:|---:|---:|"]
        for (c, assetClass) in model.portfolio.classes.enumerated() {
            let median = exp(returns.logMean[c]) - 1
            lines.append("| \(assetClass.rawValue) | \(percent(returns.expected[c])) | \(percent(median)) | "
                + "\(percent(returns.volatility[c])) | \(percent(model.incomeYields[c])) |")
        }
        return lines
    }

    private func startingPortfolio() -> [String] {
        var lines = ["", "## The starting portfolio", "",
                     "| Accounts | Available from | Value | Purchase cost | Mix |", "|---|---:|---:|---:|---|"]
        for (n, bucket) in result.start.buckets.enumerated() {
            let label = n == 0 ? "Money you can draw" : name(bucket.name, generic: "Accounts available later \(n)")
            lines.append("| \(label) | \(bucket.availableFromAge.map(String.init) ?? "now") | \(money(bucket.value)) | "
                + "\(money(bucket.costBasis)) | \(describe(bucket.mix)) |")
        }
        if model.portfolio.debtPaidOff > 0 {
            lines.append("")
            lines.append("Debts the plan counts, \(money(model.portfolio.debtPaidOff)), are paid off from the money "
                + "you can draw at the start.")
        }
        return lines
    }

    private func successCurve() -> [String] {
        var lines = ["", "## Chance of success by retirement age", "", "| Age | Year | Success |", "|---:|---:|---:|"]
        for point in result.successCurve {
            lines.append("| \(point.age) | \(point.retirementDate.year) | \(percent(point.success)) |")
        }
        return lines
    }

    private func yearByYear(_ title: String, _ path: PathDetail) -> [String] {
        var lines = ["", "## \(title)", "",
                     "| Year | Age | Income | Windfalls | Spending | Expenses | Tax on investments | Wealth tax | "
                         + "Sold | Saved | At the end |",
                     "|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|"]
        for year in path.years {
            func sum(_ kinds: Set<IncomeKind>) -> Double {
                year.income.filter { kinds.contains($0.kind) }.reduce(0) { $0 + $1.amount }
            }
            lines.append("| \(year.year) | \(year.age) | \(money(sum([.work, .pension, .other]))) | "
                + "\(money(sum([.windfall]))) | "
                + "\(money(year.spending)) | \(money(year.expenses)) | \(money(year.investmentTax)) | "
                + "\(money(year.wealthTax)) | \(money(sum([.withdrawal]))) | \(money(max(0, year.savings))) | "
                + "\(money(year.endAssets)) |")
        }
        if let failure = path.failure {
            lines.append("")
            lines.append("The money runs out in \(failure.year), at \(failure.age).")
        }
        return lines
    }

    private func flexibleSpending() -> [String] {
        guard let summary = result.flexibleSpending else { return [] }
        var lines = ["", "## Flexible spending, retiring at \(summary.age)", ""]
        lines.append("- \(percent(summary.shareWithCut)) of futures cut spending at least once; "
            + "\(percent(summary.failureRate)) can't pay even the floor of \(money(summary.floorSpending)) a year.")
        if let median = summary.medianLowestSpending {
            lines.append("- The lowest spending in a typical future: \(money(median)) a year"
                + (summary.p10LowestSpending.map { ", in a bad one (10th percentile) \(money($0))" } ?? "") + ".")
        }
        lines.append("- A typical future spends less than planned in \(summary.medianYearsBelow) of "
            + "\(summary.retirementYears) retirement years.")
        return lines
    }

    private func failures() -> [String] {
        let summary = result.failures
        var lines = ["", "## When runs fail", ""]
        guard summary.failed > 0 else {
            lines.append("No run fails retiring at \(result.focusAge).")
            return lines
        }
        lines.append("\(summary.failed) of \(summary.runs) runs (\(percent(summary.failureRate))) fail retiring at "
            + "\(result.focusAge)" + (summary.medianFailureAge.map { ", half of them by \($0)" } ?? "") + ".")
        for (n, bridge) in summary.bridges.enumerated() {
            lines.append("- \(bridge.count) run out while \(name(bridge.name, generic: "accounts available later \(n + 1)")) "
                + (bridge.accessibleFromAge.map { "can't be drawn until \($0)." } ?? "can't be drawn."))
        }
        return lines
    }

    private func warnings() -> [String] {
        guard !result.issues.isEmpty else { return [] }
        return ["", "## Warnings", ""] + result.issues.map { "- \(options.anonymize ? $0.code : $0.message)" }
    }

    // MARK: Formatting

    private func name(_ name: String, generic: String) -> String {
        options.anonymize ? generic : name
    }

    private func date(_ date: CalendarDate) -> String {
        options.anonymize ? String(date.year) : date.description
    }

    private func money(_ value: Double) -> String {
        guard value.isFinite else { return "–" }
        let rounded = options.anonymize && options.rounding > 0
            ? (value / options.rounding).rounded() * options.rounding : value.rounded()
        let digits = String(Int64(abs(rounded)))
        var grouped = ""
        for (offset, digit) in digits.enumerated() {
            if offset > 0, (digits.count - offset) % 3 == 0 { grouped.append(",") }
            grouped.append(digit)
        }
        return (rounded < 0 ? "−" : "") + grouped
    }

    private func percent(_ value: Double) -> String {
        guard value.isFinite else { return "–" }
        let text = String(format: "%.1f", value * 100)
        return (text.hasSuffix(".0") ? String(text.dropLast(2)) : text) + "%"
    }

    private func number(_ value: Double) -> String {
        String(format: "%.2f", value)
    }

    private func describe(_ mix: [AssetClass: Double]) -> String {
        mix.isEmpty ? "–" : mix.sorted { $0.key < $1.key }.map { "\($0.key.rawValue) \(percent($0.value))" }
            .joined(separator: ", ")
    }
}
