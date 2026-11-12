import ArgumentParser
import Foundation
import Model
import Planner

/// `retire plan debug`: every calculation behind a plan's answer, as a
/// Markdown report (`Planner.calculations`, PLANNER.md, "Calculations"),
/// optionally anonymized to give to someone else. With `--json`, the
/// deterministic run alone, unrounded (`Planner.deterministicRun`), for a
/// second implementation to check (`tools/oracle`).
struct PlanDebugCommand: RetireSubcommand {
    static let configuration = CommandConfiguration(
        commandName: "debug",
        abstract: "Write every calculation behind a plan's answer, to check it or share it.",
        discussion: """
            Runs the plan as `retire plan` does and writes, as Markdown, how it got its answer: the \
            plan as read (taxes, spending, income, pensions, contributions, events, target mix and \
            returns), the starting portfolio, the chance of success by retirement age, the \
            deterministic run and the median run year by year, and why runs fail. --anonymize leaves \
            out names and dates and rounds amounts (to 100, or --round), so the report can be given \
            to someone else. --output writes to a file instead of the terminal. --json prints the \
            deterministic run alone instead, unrounded, with the groups of accounts it starts from: \
            what tools/oracle works out again. It retires at the plan's age, at today's when the plan \
            asks for the earliest, or at --age.
            """)

    @OptionGroup var options: LibraryOptions

    @Option(help: ArgumentHelp("The plan, plans/<id>.json. Default: the main plan.", valueName: "id"))
    var plan: String?

    @Flag(help: "Leave out names and dates and round amounts.")
    var anonymize = false

    @Option(help: ArgumentHelp("What --anonymize rounds amounts to (default 100).", valueName: "amount"))
    var round: Double?

    @Option(help: ArgumentHelp("Write the report to this file.", valueName: "file"))
    var output: String?

    @Flag(help: "Print the deterministic run as JSON, unrounded.")
    var json = false

    @Option(help: ArgumentHelp("The retirement age of the run --json prints.", valueName: "age"))
    var age: Int?

    mutating func validate() throws {
        if let round {
            guard round > 0 else { throw ValidationError("--round takes an amount above 0, e.g. 1000.") }
            guard anonymize else { throw ValidationError("--round goes with --anonymize.") }
        }
        if json, anonymize || output != nil {
            throw ValidationError("--json prints the run as it is: leave out --anonymize and --output.")
        }
        if age != nil, !json { throw ValidationError("--age goes with --json.") }
    }

    func run(in context: CLIContext) async throws {
        let loaded = try options.load(in: context)
        let document = try PlanCommand.plan(plan.map { PlanID($0) }, in: loaded.library)
        if json {
            do {
                let run = try Planner.deterministicRun(plan: document, library: loaded.library, retirementAge: age,
                                                       today: context.today)
                context.console.print(try JSONOutput.string(DeterministicRunJSON(run)))
            } catch let error as PlannerError {
                throw CLIError(PlanCommand.message(for: error, plan: document))
            }
            return
        }
        let reportOptions = CalculationsOptions(anonymize: anonymize, rounding: round ?? 100, today: context.today)

        let console = context.console
        console.status("Running \(document.id)…")
        let text: String
        do {
            defer { console.clearStatus() }
            text = try await Planner.calculations(plan: document, library: loaded.library, options: reportOptions)
        } catch let error as PlannerError {
            throw CLIError(PlanCommand.message(for: error, plan: document))
        }

        guard let output else {
            console.print(String(text.dropLast()))
            return
        }
        let url = context.url(forPath: output)
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try Data(text.utf8).write(to: url, options: .atomic)
        } catch {
            throw CLIError("Couldn't write \(output): \(error.localizedDescription)")
        }
        console.print("Wrote the report on \(document.id)\(anonymize ? ", anonymized," : "") to \(output).")
    }
}

/// What `retire plan debug --json` prints: the deterministic run with what
/// it starts from, every amount unrounded.
struct DeterministicRunJSON: Encodable {
    struct Group: Encodable {
        var name: String
        var accounts: [String]
        var availableFromAge: Int?
        var withdrawalTaxRate: Double?
        var value: Double
        /// What was paid for what it holds.
        var paid: Double
        /// Shares by asset class.
        var mix: [String: Double]
    }

    struct Failure: Encodable {
        var year: Int
        var age: Int
        /// "depleted", or "locked" with the accounts still locked.
        var reason: String
        var locked: String?
    }

    struct Year: Encodable {
        var year: Int
        var age: Int
        var fraction: Double
        var work = 0.0
        var pensions = 0.0
        var other = 0.0
        var windfalls = 0.0
        var sold = 0.0
        var spending: Double
        var expenses: Double
        var investmentTax: Double
        var wealthTax: Double
        var withdrawalTax: Double
        var debtWithdrawalTax: Double
        var savings: Double
        var endAssets: Double
        var spendingLevel: Double?
    }

    var plan: String
    var engine: String
    var currency: String
    var birthDate: String
    var startDate: String
    var retirementAge: Int
    var groups: [Group]
    var debtGainsTax: Double
    var debtWithdrawalTax: Double
    var failure: Failure?
    var years: [Year]

    init(_ run: DeterministicRun) {
        plan = run.plan.rawValue
        engine = run.engine
        currency = run.currency.rawValue
        birthDate = run.birthDate.description
        startDate = run.startDate.description
        retirementAge = run.retirementAge
        groups = run.groups.map { group in
            Group(name: group.name, accounts: group.accounts.map(\.rawValue), availableFromAge: group.availableFromAge,
                  withdrawalTaxRate: group.withdrawalTaxRate, value: group.value, paid: group.costBasis,
                  mix: Dictionary(uniqueKeysWithValues: group.mix.map { ($0.key.rawValue, $0.value) }))
        }
        debtGainsTax = run.debtGainsTax
        debtWithdrawalTax = run.debtWithdrawalTax
        failure = run.path.failure.map { failure in
            switch failure.reason {
            case .depleted: Failure(year: failure.year, age: failure.age, reason: "depleted")
            case .locked(let money): Failure(year: failure.year, age: failure.age, reason: "locked", locked: money.name)
            }
        }
        years = run.path.years.map { detail in
            var year = Year(year: detail.year, age: detail.age, fraction: detail.fraction, spending: detail.spending,
                            expenses: detail.expenses, investmentTax: detail.investmentTax,
                            wealthTax: detail.wealthTax, withdrawalTax: detail.withdrawalTax,
                            debtWithdrawalTax: detail.debtWithdrawalTax, savings: detail.savings,
                            endAssets: detail.endAssets, spendingLevel: detail.spendingLevel)
            for item in detail.income {
                switch item.kind {
                case .work: year.work += item.amount
                case .pension: year.pensions += item.amount
                case .other: year.other += item.amount
                case .windfall: year.windfalls += item.amount
                default: year.sold += item.amount
                }
            }
            return year
        }
    }
}
