import ArgumentParser
import Foundation
import Model
import Planner

/// `retire plan debug`: every calculation behind a plan's answer, as a
/// Markdown or JSON report (`Planner.debugReport`, PLANNER.md, "Plan
/// debugger"), optionally anonymized to give to someone else.
struct PlanDebugCommand: RetireSubcommand {
    static let configuration = CommandConfiguration(
        commandName: "debug",
        abstract: "Show every calculation behind a plan's answer, to check it or share it.",
        discussion: """
            Runs the plan as `retire plan` does and writes a report of how it got its answer: a short \
            diagnosis of what weighs most on the result, the plan and the library as read, the \
            assumptions (with each class's median return), the starting portfolio by account and \
            bucket, the year-by-year schedule, the success by retirement age and both searches step \
            by step, percentiles by year, a few runs traced year by year (returns drawn, money in and \
            out, every tax line, rebalancing, each bucket's balance), and the issues.

            The details are for retiring today (--age today, the scenario behind "needed to retire \
            today"), at the plan's target age (--age target), or at an age (--age 60). When the details \
            are for retiring today and today's plan assets fall short, the percentiles and traced runs \
            start from what retiring today needs, today's with extra money in the accounts that can be \
            drawn now, to show why it's that much (--scale actual for today's assets, needed, or a \
            multiple of today's, every holding alike, e.g. --scale 5). It traces the \
            deterministic run and, by default, 3 runs chosen by outcome: the median, a 10th-percentile \
            one and the first that fails (--paths N for more or fewer, --path-index to pick runs by \
            number). --anonymize replaces names and IDs with neutral labels, removes the birth date \
            and rounds money (--round none, 100 or 3sig; 3sig by default), so the report can be \
            given to someone else. --format json writes every detail; Markdown (the default) skips \
            some years of long tables. --output writes to a file instead of the terminal.
            """)

    @OptionGroup var options: LibraryOptions

    @Option(help: ArgumentHelp("The plan, plans/<id>.json. Default: the main plan.", valueName: "id"))
    var plan: String?

    @Option(help: ArgumentHelp("The retirement age the details are for: today, target or an age.",
                               valueName: "today|target|N"))
    var age = "today"

    @Option(help: ArgumentHelp("What the percentiles and traced runs start from: auto, actual (today's plan assets), "
                               + "needed (what retiring today needs) or a multiple of today's (every holding alike).",
                               valueName: "auto|actual|needed|x"))
    var scale = "auto"

    @Option(help: ArgumentHelp("How many runs to trace, chosen by outcome.", valueName: "N"))
    var paths = PlanDebugOptions.defaultPathCount

    @Option(name: .customLong("path-index"), parsing: .upToNextOption,
            help: ArgumentHelp("Trace these runs, by number from 0, instead.", valueName: "i"))
    var pathIndex: [Int] = []

    @Flag(help: "Replace names and IDs with neutral labels, remove the birth date and round money.")
    var anonymize = false

    @Option(help: ArgumentHelp("How --anonymize rounds money: none, 100 or 3sig.", valueName: "none|100|3sig"))
    var round: String?

    @Option(help: ArgumentHelp("md (Markdown) or json.", valueName: "md|json"))
    var format = "md"

    @Option(help: ArgumentHelp("Write the report to this file.", valueName: "file"))
    var output: String?

    @Flag(help: "Use fewer runs, for a quick report.")
    var fast = false

    mutating func validate() throws {
        _ = try retirementAge()
        _ = try startScale()
        if paths < 0 { throw ValidationError("--paths can't be negative.") }
        if pathIndex.contains(where: { $0 < 0 }) { throw ValidationError("--path-index counts runs from 0.") }
        if let round {
            guard PlanDebugAnonymization.Rounding(rawValue: round) != nil else {
                throw ValidationError("--round takes none, 100 or 3sig, not \"\(round)\".")
            }
            guard anonymize else { throw ValidationError("--round goes with --anonymize.") }
        }
        guard ["md", "markdown", "json"].contains(format) else {
            throw ValidationError("--format takes md or json, not \"\(format)\".")
        }
    }

    /// `--age` as the planner's choice.
    func retirementAge() throws -> PlanDebugOptions.RetirementAge {
        switch age.lowercased() {
        case "today": return .today
        case "target": return .target
        default:
            guard let value = Int(age), value > 0 else {
                throw ValidationError("--age takes today, target or an age, not \"\(age)\".")
            }
            return .age(value)
        }
    }

    /// `--scale` as the planner's choice.
    func startScale() throws -> PlanDebugOptions.StartScale {
        switch scale.lowercased() {
        case "auto": return .automatic
        case "actual": return .actual
        case "needed": return .assetsNeeded
        default:
            guard let factor = Double(scale), factor.isFinite, factor > 0 else {
                throw ValidationError("--scale takes auto, actual, needed or a positive number, not \"\(scale)\".")
            }
            return .factor(factor)
        }
    }

    mutating func run() async throws {
        try await run(in: .live())
    }

    func run(in context: CLIContext) async throws {
        let loaded = try options.load(in: context)
        let document = try PlanCommand.plan(plan.map { PlanID($0) }, in: loaded.library)
        let planner = PlanCommand.options(fast ? PlannerOptions.fast() : PlannerOptions(), today: context.today)
        let rounding = round.flatMap(PlanDebugAnonymization.Rounding.init(rawValue:)) ?? .significantFigures
        let debugOptions = PlanDebugOptions(
            planner: planner, retirementAge: try retirementAge(), startScale: try startScale(),
            paths: pathIndex.isEmpty ? .automatic(count: paths) : .runs(pathIndex),
            anonymization: anonymize ? PlanDebugAnonymization(rounding: rounding) : nil, runDate: context.today)

        let console = context.console
        console.status("Running \(document.id) and tracing its paths…")
        let report: PlanDebugReport
        do {
            defer { console.clearStatus() }
            report = try await Planner.debugReport(for: document, library: loaded.library,
                                                   registry: TaxSystems.registry(), options: debugOptions)
        } catch let error as PlannerError {
            throw CLIError(PlanCommand.message(for: error, plan: document))
        }
        let text = format == "json" ? try report.json() + "\n" : report.markdown()

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
