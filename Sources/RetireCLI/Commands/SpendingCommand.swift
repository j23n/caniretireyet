import ArgumentParser
import Foundation
import Model
import Storage
import Tracker

/// `retire spending`: the money in and out recorded at check-ins on cash and
/// savings accounts, summed over a year (Tracker's
/// `Valuator.moneyInOut(from:through:accounts:)`), and the savings rate
/// (`Valuator.savingsRate(from:through:)`).
struct SpendingCommand: RetireSubcommand {
    static let configuration = CommandConfiguration(
        commandName: "spending",
        abstract: "Sum up the money that came in and went out of cash and savings accounts.",
        discussion: """
            Adds up moneyIn and moneyOut, recorded at check-ins on cash and savings accounts, over \
            the twelve months to today, or a calendar year with --year, in the library's base \
            currency. Money moved between your own accounts isn't in either, so money out is \
            roughly what you spent. Values without both amounts, and an account's first value, aren't counted. \
            Without --account, also the savings rate: what you kept of what came in, with what was paid into \
            pension funds and TFR over the same days counted on both sides.
            """)

    @OptionGroup var options: LibraryOptions

    @Option(help: "A calendar year. Default: the twelve months to today.")
    var year: Int?

    @Option(help: ArgumentHelp("Only this account.", valueName: "account"))
    var account: String?

    @Flag(help: "Print JSON.")
    var json = false

    func validate() throws {
        if let year, !(1...9999).contains(year) { throw ValidationError("--year must be between 1 and 9999.") }
    }

    func run(in context: CLIContext) async throws {
        let loaded = try options.load(in: context)
        var only: Set<AccountID>?
        if let id = account {
            let account = try loaded.account(id)
            guard account.kind.recordsMoneyInOut else {
                throw CLIError("\(account.id) is a \(account.kind.rawValue) account; only cash and savings accounts "
                    + "record money in and out.")
            }
            only = [account.id]
        }
        let valuator = Valuator(library: loaded.library)
        let from = year.map { CalendarDate.firstDay(ofYear: $0) } ?? context.today.adding(years: -1).adding(days: 1)
        let through = year.map { CalendarDate.lastDay(ofYear: $0) } ?? context.today
        let summary = valuator.moneyInOut(from: from, through: through, accounts: only)
        let savings = only == nil ? valuator.savingsRate(from: from, through: through) : nil
        try context.console.print(Report(summary: summary, account: only?.first, savings: savings), json: json)
    }

    struct Report: CommandReport {
        let summary: MoneyInOutSummary
        let account: AccountID?
        /// The savings rate over the same values; `nil` for one account.
        var savings: SavingsRate? = nil

        func lines() -> [String] {
            let whose = account.map { " of \($0)" } ?? ""
            var lines = ["Money in and out\(whose), \(Format.range(summary.from, summary.through)), "
                + "in \(summary.currency.rawValue)"]
            let unconverted = "Values without an exchange rate into \(summary.currency.rawValue), left out: "
                + summary.unconverted.map(\.rawValue).joined(separator: ", ") + "."
            guard let perYear = summary.moneyOutPerYear else {
                lines.append(summary.isComplete
                    ? "Nothing recorded. Set \"moneyInOut\": true on a cash or savings account, and record "
                        + "moneyIn and moneyOut at its check-ins."
                    : unconverted)
                return lines
            }
            var table = TextTable([.left(""), .right("")], showsHeader: false)
            table.add(["In", Format.amount(summary.moneyIn)])
            table.add(["Out", Format.amount(summary.moneyOut)])
            table.add(["Net", Format.signed(summary.net)])
            table.add(["Out a year", Format.amount(perYear)])
            lines += table.lines()
            let months = summary.months.count
            lines.append("\(Wording.count(months, "month")) recorded "
                + "(\(Format.range(summary.months[0], summary.months[months - 1]))); out a year scales each account's "
                + "money out to 365 days by the days its values cover.")
            if let savings, let rate = savings.rate {
                let pensions = savings.pensionContributions > 0
                    ? ", with the \(Format.amount(savings.pensionContributions)) paid into pension funds and TFR "
                        + "counted as both"
                    : ""
                lines.append("Savings rate \(Format.percent(rate)): you kept \(Format.amount(savings.saved)) of the "
                    + "\(Format.amount(savings.income)) that came in from \(savings.from.adding(days: 1)) to "
                    + "\(savings.through)\(pensions).")
                if !savings.plannedContributionAccounts.isEmpty {
                    lines.append("Paid into pensions as the main plan pays, since check-ins didn't record it: "
                        + savings.plannedContributionAccounts.map(\.rawValue).joined(separator: ", ") + ".")
                }
            }
            if !summary.isComplete { lines.append(unconverted) }
            return lines
        }

        var json: JSON {
            JSON(from: summary.from.description, through: summary.through.description,
                 currency: summary.currency.rawValue, account: account?.rawValue,
                 moneyIn: Format.json(summary.moneyIn), moneyOut: Format.json(summary.moneyOut),
                 net: Format.json(summary.net), moneyOutPerYear: summary.moneyOutPerYear.map { Format.json($0) },
                 months: summary.months.map(\.description), unconverted: summary.unconverted.map(\.rawValue),
                 savingsRate: savings?.rate.map { Format.json($0, places: 4) },
                 pensionContributions: savings.map { Format.json($0.pensionContributions) })
        }

        struct JSON: Encodable {
            var from: String
            var through: String
            var currency: String
            /// The account summed up; absent for every account.
            var account: String?
            var moneyIn: String
            var moneyOut: String
            var net: String
            /// Each account's money out × 365 / the days its values cover, added
            /// up; absent when nothing was recorded.
            var moneyOutPerYear: String?
            /// The months with a value counted.
            var months: [String]
            var unconverted: [String]
            /// What was kept of what came in, as a fraction; absent for one
            /// account, when no money in and out was counted, or when nothing
            /// came in.
            var savingsRate: String?
            /// What was paid into pension funds and TFR over the days the pay
            /// covers, counted as both kept and come in; absent for one account
            /// or when no money in and out was counted.
            var pensionContributions: String?
        }
    }
}
