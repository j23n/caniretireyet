import ArgumentParser
import Foundation
import Model
import Planner

/// `retire plan debug`: every calculation behind a plan's answer, as a
/// Markdown report (`Planner.calculations`, PLANNER.md, "Calculations"),
/// optionally anonymized to give to someone else.
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
            to someone else. --output writes to a file instead of the terminal.
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

    mutating func validate() throws {
        if let round {
            guard round > 0 else { throw ValidationError("--round takes an amount above 0, e.g. 1000.") }
            guard anonymize else { throw ValidationError("--round goes with --anonymize.") }
        }
    }

    func run(in context: CLIContext) async throws {
        let loaded = try options.load(in: context)
        let document = try PlanCommand.plan(plan.map { PlanID($0) }, in: loaded.library)
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
