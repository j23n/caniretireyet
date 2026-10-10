import ArgumentParser
import Foundation
import Model
import Planner

/// `retire plan`: runs a plan (the default, ``PlanCommand``), shows its
/// inputs and your saving pace (``PlanPaceCommand``), and writes every
/// calculation behind its answer. Plans are edited in the app, or by hand
/// in plans/<id>.json (PLANNER.md, "Plan file").
struct PlanGroupCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "plan",
        abstract: "Run a plan, show its inputs and your saving pace, and write every calculation behind its answer.",
        discussion: """
            retire plan [run] [--fast] [--years]      run the plan, print the answer
            retire plan show                          its taxes, income, pensions, mix and returns
            retire plan debug [--anonymize] [--output file]
                                                      every calculation behind the answer
            retire plan pace [--date YYYY-MM-DD]      how much you've saved a month, the last 12 months

            Every command but pace takes --plan <id>; without it, the main plan. Plans are edited in \\
            the app, or by hand in plans/<id>.json.
            """,
        subcommands: [PlanCommand.self, PlanShowCommand.self, PlanDebugCommand.self, PlanPaceCommand.self],
        defaultSubcommand: PlanCommand.self)
}

/// `retire plan show`: the plan's inputs in words.
struct PlanShowCommand: RetireSubcommand {
    static let configuration = CommandConfiguration(
        commandName: "show",
        abstract: "Show a plan's taxes, income, pensions, contributions, target mix and returns.")

    @OptionGroup var options: LibraryOptions

    @Option(help: ArgumentHelp("The plan, plans/<id>.json. Default: the main plan.", valueName: "id"))
    var plan: String?

    @Flag(help: "Print JSON.")
    var json = false

    func run(in context: CLIContext) async throws {
        let loaded = try options.load(in: context)
        let document = try PlanCommand.plan(plan.map { PlanID($0) }, in: loaded.library)
        let report = PlanInputsReport(plan: document, library: loaded.library, today: context.today)
        try context.console.print(report, json: json)
    }
}

/// A plan's inputs in words (`retire plan show`).
struct PlanInputsReport: CommandReport {
    let plan: PlanDocument
    let library: Library
    let today: CalendarDate

    var currency: CurrencyCode { library.settings.baseCurrency }

    func lines() -> [String] {
        var lines = ["Plan \(plan.id): \(plan.name)", "Amounts in \(currency), a year, in today's money, after tax."]

        lines.append("")
        lines.append("Taxes: " + taxText())
        lines.append("Spending: " + spendingText())
        lines.append("Flexible spending: " + PlanFlexibleSpending.describe(plan.spending, currency: currency))

        lines.append("")
        lines.append("Work")
        if plan.work.isEmpty { lines.append("  None.") }
        for (index, phase) in plan.work.enumerated() {
            let amount = phase.netIncome.map { Format.amount($0, places: 0) } ?? "? (enter the income after tax)"
            let growth = phase.realGrowth.map { ", growing \(Format.percent($0)) a year" } ?? ""
            lines.append("  \(index + 1). \(plan.workName(index)) · \(amount) from \(phase.from) until "
                + "\(Self.until(phase.until))\(growth)")
        }

        lines.append("")
        lines.append("Pensions")
        if plan.pensions.isEmpty { lines.append("  None.") }
        for (index, pension) in plan.pensions.enumerated() {
            let amount = pension.perYear.map { Format.amount($0, places: 0) } ?? "?"
            lines.append("  \(index + 1). \(plan.pensionName(index)) · \(amount) from "
                + "\(pension.fromAge.map(String.init) ?? "?")")
        }

        if !plan.income.isEmpty {
            lines.append("")
            lines.append("Other income")
            for (index, income) in plan.income.enumerated() {
                let amount = income.perYear.map { Format.amount($0, places: 0) } ?? "?"
                let until = income.untilAge.map { " until \($0)" } ?? ""
                lines.append("  \(index + 1). \(plan.incomeName(index)) · \(amount) from "
                    + "\(Self.start(income.from))\(until)")
            }
        }

        lines.append("")
        lines.append("Contributions")
        if plan.contributions.isEmpty { lines.append("  None.") }
        for (index, contribution) in plan.contributions.enumerated() {
            let name = library.accounts[contribution.account]?.name ?? contribution.account.rawValue
            let timing = contribution.amount.map { "\(Format.amount($0, places: 0)) in \(contribution.year ?? 0)" }
                ?? "\(Format.amount(contribution.perYear, places: 0)) a year until \(Self.until(contribution.effectiveUntil))"
            lines.append("  \(index + 1). Into \(name) · \(timing)")
        }

        lines.append("")
        lines += mixLines()

        lines.append("")
        lines.append("Returns, real, a year")
        var table = TextTable([.left("Class"), .right("Mean"), .right("Median"), .right("Volatility"),
                               .right("Income yield"), .left("Set as")])
        for (assetClass, assumption) in returns() {
            let given = assumption.isGivenByMedian ? "median" : "mean"
            table.add([assetClass.rawValue, Format.percent(assumption.real), Format.percent(assumption.impliedMedianReal),
                       Format.percent(assumption.volatility), Format.percent(assumption.incomeYield),
                       plan.assumptions.returns[assetClass] == nil ? given + " (default)" : given])
        }
        lines += table.lines()
        lines.append("Mean: the average year. Median: the typical year, about what a portfolio rebalanced every year "
            + "grows at; the more volatile the class, the further below the mean.")
        lines.append("Income yield: the part of the return paid as income each year, taxed every year at the "
            + "investment rate.")
        return lines
    }

    /// "26% on investment income and gains; wealth tax 0.2% above 50,000", or what's missing.
    private func taxText() -> String {
        guard let rate = plan.tax.investmentRate else {
            return "the investment rate isn't set (tax.investmentRate): the plan can't run until it is"
        }
        var text = "\(Format.percent(rate)) on investment income and gains"
        let wealth = plan.tax.effectiveWealthRate
        if wealth > 0 {
            text += "; wealth tax \(Format.percent(wealth))"
            if plan.tax.effectiveWealthAllowance > 0 {
                text += " above \(Format.amount(plan.tax.effectiveWealthAllowance, places: 0))"
            }
        } else {
            text += "; no wealth tax"
        }
        return text
    }

    /// "36,000 a year while working, 36,000 in retirement, 90% of it from 75 and 80% from 85".
    private func spendingText() -> String {
        let spending = plan.spending
        let phases = spending.phases.sorted { $0.fromAge < $1.fromAge }.enumerated().map { index, phase in
            "\(Format.percent(phase.factor, places: 0))\(index == 0 ? " of it" : "") from \(phase.fromAge)"
        }
        return "\(Format.amount(spending.working, places: 0)) a year while working, "
            + "\(Format.amount(spending.retired, places: 0)) in retirement"
            + (phases.isEmpty ? "" : ", " + Wording.list(phases))
    }

    /// The target mix, its changes with age, and what the money you can draw holds today.
    private func mixLines() -> [String] {
        var lines = ["Target mix of the money you can draw"]
        if let mix = plan.portfolio.targetMix {
            lines.append("  From today: " + Self.describe(mix.shares.mapValues { $0 }))
        } else {
            lines.append("  Not set: it keeps today's mix.")
        }
        for step in plan.portfolio.targetMixByAge {
            let from = step.fromAge.age.map { "From \($0)" } ?? "From retirement"
            lines.append("  \(from): " + Self.describe(step.mix.shares.mapValues { $0 }))
        }
        let today = Planner.startingMix(plan: plan, library: library, today: self.today)
        if !today.accessibleShares.isEmpty {
            lines.append("  Today (\(today.date)): " + Self.describe(today.accessibleShares.mapValues {
                Decimal(string: String(format: "%.4f", $0)) ?? 0
            }))
        }
        return lines
    }

    /// "equity 80%, bonds 20%".
    static func describe(_ shares: [AssetClass: Decimal]) -> String {
        shares.filter { $0.value > 0 }.sorted { $0.key < $1.key }
            .map { "\($0.key.rawValue) \(Format.percent($0.value, places: 0))" }.joined(separator: ", ")
    }

    /// Each asset class's assumption, the plan's or the default, in the
    /// usual order, then any other the plan names.
    private func returns() -> [(AssetClass, ReturnAssumption)] {
        let classes = AssetClass.knownValues.filter { $0 != .other }
            + plan.assumptions.returns.keys.filter { !AssetClass.knownValues.contains($0) }.sorted()
        return classes.compactMap { assetClass in
            plan.assumptions.returnAssumption(for: assetClass).map { (assetClass, $0) }
        }
    }

    static func until(_ end: PhaseEnd) -> String {
        switch end {
        case .retirement: "retirement"
        case .date(let date): date.description
        }
    }

    /// When other income starts: an age, or "retirement"; "?" when not given.
    static func start(_ from: AgeOrRetirement?) -> String {
        switch from {
        case .age(let age): "\(age)"
        case .retirement: "retirement"
        case nil: "?"
        }
    }

    var json: JSON {
        JSON(plan: plan.id.rawValue, name: plan.name, currency: currency.rawValue,
             tax: JSON.Tax(investmentRate: plan.tax.investmentRate?.fileString,
                           wealthRate: plan.tax.effectiveWealthRate.fileString,
                           wealthAllowance: plan.tax.effectiveWealthAllowance.fileString),
             spending: JSON.Spending(working: plan.spending.working.fileString,
                                     retired: plan.spending.retired.fileString,
                                     flexible: PlanFlexibleSpending.JSON(plan.spending)),
             work: plan.work.enumerated().map { index, phase in
                 JSON.Work(number: index + 1, name: phase.name, from: phase.from.description,
                           until: Self.until(phase.until), netIncome: phase.netIncome?.fileString,
                           realGrowth: phase.realGrowth?.fileString)
             },
             pensions: plan.pensions.enumerated().map { index, pension in
                 JSON.Pension(number: index + 1, name: pension.name, fromAge: pension.fromAge,
                              perYear: pension.perYear?.fileString)
             },
             income: plan.income.isEmpty ? nil : plan.income.enumerated().map { index, income in
                 JSON.Income(number: index + 1, name: income.name, from: income.from.map { Self.start($0) },
                             untilAge: income.untilAge, perYear: income.perYear?.fileString)
             },
             contributions: plan.contributions.enumerated().map { index, contribution in
                 JSON.Contribution(number: index + 1, account: contribution.account.rawValue,
                                   perYear: contribution.isOneOff ? nil : contribution.perYear.fileString,
                                   until: contribution.isOneOff ? nil : contribution.until.map(Self.until),
                                   amount: contribution.amount?.fileString, year: contribution.year)
             },
             targetMix: plan.portfolio.targetMix.map { Self.shares($0) },
             targetMixByAge: plan.portfolio.targetMixByAge.map { step in
                 JSON.Step(fromAge: step.fromAge.age.map(String.init) ?? "retirement", mix: Self.shares(step.mix))
             },
             returns: Dictionary(uniqueKeysWithValues: returns().map { assetClass, assumption in
                 (assetClass.rawValue, JSON.Return(
                     real: (assumption.realAsWritten ?? assumption.real.rounded(scale: 6)).fileString,
                     volatility: assumption.volatility.fileString,
                     incomeYield: assumption.incomeYield?.fileString,
                     median: (assumption.isGivenByMedian ? assumption.impliedMedianReal
                         : assumption.impliedMedianReal.rounded(scale: 6)).fileString,
                     givenAs: assumption.isGivenByMedian ? "median" : "mean",
                     isDefault: plan.assumptions.returns[assetClass] == nil))
             }))
    }

    private static func shares(_ mix: AssetMix) -> [String: String] {
        Dictionary(uniqueKeysWithValues: mix.shares.filter { $0.value > 0 }.map { ($0.key.rawValue, $0.value.fileString) })
    }

    struct JSON: Encodable {
        struct Tax: Encodable {
            var investmentRate: String?
            var wealthRate: String
            var wealthAllowance: String
        }

        struct Spending: Encodable {
            var working: String
            var retired: String
            /// The flexible-spending rule with its defaults filled in; absent without one.
            var flexible: PlanFlexibleSpending.JSON?
        }

        struct Work: Encodable {
            var number: Int
            var name: String?
            var from: String
            var until: String
            var netIncome: String?
            var realGrowth: String?
        }

        struct Pension: Encodable {
            var number: Int
            var name: String?
            var fromAge: Int?
            var perYear: String?
        }

        /// Other income: `from` is an age or "retirement".
        struct Income: Encodable {
            var number: Int
            var name: String?
            var from: String?
            var untilAge: Int?
            var perYear: String?
        }

        struct Contribution: Encodable {
            var number: Int
            var account: String
            var perYear: String?
            var until: String?
            var amount: String?
            var year: Int?
        }

        struct Step: Encodable {
            var fromAge: String
            var mix: [String: String]
        }

        struct Return: Encodable {
            /// The mean (arithmetic) real return: as written, or derived from
            /// the median, to 6 decimals.
            var real: String
            var volatility: String
            var incomeYield: String?
            /// The median real return: as written, or derived from the mean.
            var median: String
            /// `mean` or `median`: what the plan, or the default, gives.
            var givenAs: String
            /// Whether it's the default (the plan sets nothing for the class).
            var isDefault: Bool
        }

        var plan: String
        var name: String
        var currency: String
        var tax: Tax
        var spending: Spending
        var work: [Work]
        var pensions: [Pension]
        /// Absent without other income.
        var income: [Income]?
        var contributions: [Contribution]
        var targetMix: [String: String]?
        var targetMixByAge: [Step]
        var returns: [String: Return]
    }
}
