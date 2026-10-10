import ArgumentParser
import Foundation
import Model
import Tracker

/// `retire plan pace`: how much you've been saving into plan assets
/// (``SavingPace``), month by month, for checking by hand.
struct PlanPaceCommand: RetireSubcommand {
    static let configuration = CommandConfiguration(
        commandName: "pace",
        abstract: "Show how much you've been saving into plan assets over the last 12 months.",
        discussion: """
            Prints the new money into plan assets in each of the last 12 months through the latest \
            check-in on or before --date: each account's new money spread evenly over the days since \
            its record before, in today's money with the library's inflation index. Money moved between \
            plan assets cancels out. When the usual month (the median) saves something, a month that \
            saves at least twice as much and at least 1% of plan assets, or takes out at least 1% of \
            plan assets, is unusual and counts as the usual month: the pace is the year's total with \
            those. With fewer than 12 months it's scaled to a year; with fewer than 3 there's none. \
            Accounts whose new money wasn't recorded, so that it's taken from the main plan's \
            contributions, are left out.
            """)

    @OptionGroup var options: LibraryOptions

    @Option(help: ArgumentHelp("The date, YYYY-MM-DD. Default: today.", valueName: "date"))
    var date: String?

    @Flag(help: "Print JSON.")
    var json = false

    func validate() throws {
        _ = try parseDate(date, option: "--date")
    }

    func run(in context: CLIContext) async throws {
        let loaded = try options.load(in: context)
        let date = try parseDate(date, option: "--date") ?? context.today
        let library = loaded.library
        let pace = Valuator(library: library).savingPace(asOf: date, inflation: InflationIndex(library: library))
        try context.console.print(Report(library: library, pace: pace), json: json)
    }

    /// The pace in words, or `nil` without enough history.
    struct Report: CommandReport {
        let library: Library
        let pace: SavingPace?

        func name(_ id: AccountID) -> String { library.accounts[id]?.name ?? id.rawValue }

        func lines() -> [String] {
            guard let pace else {
                return ["Not enough history for a saving pace: it needs check-ins of plan assets at least "
                    + "\(SavingPace.minimumMonths) months apart."]
            }
            let money = pace.isInTodaysMoney ? "in money of \(pace.asOf)"
                : "in money of each check-in (the inflation index doesn't cover these months)"
            var lines = ["Saving pace through \(pace.asOf), \(money), \(pace.currency)"
                + (pace.isComplete ? "" : " (incomplete: a value or its new money is missing)")]

            lines.append("")
            var table = TextTable([.left("Month to"), .right("New money"), .left("")])
            for month in pace.months {
                table.add([month.end.description, Format.amount(month.newMoney),
                           month.isUnusual ? "unusual: counts as \(Format.amount(pace.usualMonth))" : ""])
            }
            lines += table.lines()

            lines.append("")
            lines.append("Usual month: \(Format.amount(pace.usualMonth))")
            let months = pace.isScaled ? " (from \(pace.months.count) months, scaled to a year)" : ""
            lines.append("Pace: \(Format.amount(pace.perYear)) a year\(months)")
            if let range = pace.range {
                lines.append("Over the past year: \(Format.amount(range.lowerBound)) to "
                    + "\(Format.amount(range.upperBound)) a year")
            }

            if !pace.byAccount.isEmpty {
                lines.append("")
                lines.append("By account, a year (unusual months included)")
                var accounts = TextTable([.left("Account"), .right("New money")])
                let sorted = pace.byAccount.sorted { (name($0.key), $0.key) < (name($1.key), $1.key) }
                for (account, amount) in sorted {
                    accounts.add([name(account), Format.amount(amount)])
                }
                lines += accounts.lines()
            }
            if !pace.leftOut.isEmpty {
                lines.append("")
                lines.append("Left out, without recorded new money: " + pace.leftOut.map(name).joined(separator: ", "))
            }
            return lines
        }

        var json: JSON {
            JSON(pace: pace.map { pace in
                JSON.Pace(
                    asOf: pace.asOf.description, currency: pace.currency.rawValue,
                    inTodaysMoney: pace.isInTodaysMoney, complete: pace.isComplete,
                    months: pace.months.map {
                        JSON.Month(end: $0.end.description, newMoney: Format.json($0.newMoney), unusual: $0.isUnusual)
                    },
                    usualMonth: Format.json(pace.usualMonth), perYear: Format.json(pace.perYear),
                    range: pace.range.map { [Format.json($0.lowerBound), Format.json($0.upperBound)] },
                    byAccount: Dictionary(uniqueKeysWithValues: pace.byAccount.map {
                        ($0.key.rawValue, Format.json($0.value))
                    }),
                    leftOut: pace.leftOut.map(\.rawValue))
            })
        }

        struct JSON: Encodable {
            struct Month: Encodable {
                var end: String
                var newMoney: String
                var unusual: Bool
            }

            struct Pace: Encodable {
                var asOf: String
                var currency: String
                var inTodaysMoney: Bool
                var complete: Bool
                var months: [Month]
                var usualMonth: String
                var perYear: String
                var range: [String]?
                var byAccount: [String: String]
                var leftOut: [String]
            }

            var pace: Pace?
        }
    }
}
