import ArgumentParser
import Foundation
import Model
import Storage
import Tracker

/// `retire trades summary <account> | --all`: a year of trades (Tracker's
/// `TradeLedger.summary(for:)` for one account, in its currency, or
/// `Valuator.tradeSummary(for:)` for every trades account, in the base
/// currency).
struct TradesSummaryCommand: RetireSubcommand {
    static let configuration = CommandConfiguration(
        commandName: "summary",
        abstract: "Sum up a year of trades: realised gains, dividends, interest, fees, taxes, money in and out.",
        discussion: """
            One account's figures are in its currency; with --all, every account that records trades \
            is summed in the library's base currency, each amount converted at its trade date. \
            Realised gains are on the average cost (costo medio ponderato); dividends and interest \
            are before tax withheld. The tax due isn't worked out here.
            """)

    @Argument(help: ArgumentHelp("The account's ID.", valueName: "account"))
    var account: String?

    @OptionGroup var options: LibraryOptions

    @Flag(help: "Every account that records trades, in the base currency.")
    var all = false

    @Option(help: "The year. Default: this year.")
    var year: Int?

    @Flag(help: "Print JSON.")
    var json = false

    func validate() throws {
        if all, account != nil { throw ValidationError("Give an account or --all, not both.") }
        if !all, account == nil { throw ValidationError("Give the account to sum up, or --all.") }
    }

    func run(in context: CLIContext) async throws {
        let loaded = try options.load(in: context)
        let year = year ?? context.today.year
        let valuator = Valuator(library: loaded.library)
        let summary: TradeYearSummary
        let title: String
        if let id = account {
            let account = try loaded.account(id)
            guard let ledger = valuator.ledger(for: account.id) else {
                throw CLIError("\(account.id) doesn't record trades, so there's nothing to sum up. Switch it to "
                    + "recording trades in the app (Switch to Trade History on the account).")
            }
            summary = ledger.summary(for: year)
            title = "\(account.name) (\(account.id))"
        } else {
            summary = valuator.tradeSummary(for: year)
            let accounts = loaded.library.sortedAccounts.filter(\.recordsTrades).map(\.id.rawValue)
            title = accounts.isEmpty ? "no account records trades" : accounts.joined(separator: ", ")
        }
        let report = Report(title: title, summary: summary, library: loaded.library, account: account)
        try context.console.print(report, json: json)
    }

    struct Report: CommandReport {
        let title: String
        let summary: TradeYearSummary
        let library: Library
        let account: String?

        func lines() -> [String] {
            var lines = ["Trades in \(summary.year): \(title), in \(summary.currency.rawValue)"]
            var table = TextTable([.left(""), .right("")], showsHeader: false)
            table.add(["Realised gains", Format.signed(summary.realizedGain)])
            for (instrument, gain) in summary.realizedGainByInstrument.sorted(by: { $0.key < $1.key }) {
                table.add(["  \(instrument)", Format.signed(gain)])
            }
            table.add(["Dividends", Format.amount(summary.dividends)])
            for (instrument, amount) in summary.dividendsByInstrument.sorted(by: { $0.key < $1.key }) {
                table.add(["  \(instrument)", Format.amount(amount)])
            }
            table.add(["Interest", Format.amount(summary.interest)])
            table.add(["Fees", Format.amount(summary.fees)])
            table.add(["Taxes", Format.amount(summary.taxes)])
            table.add(["  withheld on income", Format.amount(summary.incomeTax)])
            table.add(["Income after tax", Format.amount(summary.netIncome)])
            table.add(["Deposits", Format.amount(summary.deposits)])
            table.add(["Withdrawals", Format.amount(summary.withdrawals)])
            lines += table.lines()
            if !summary.salesWithUnknownGain.isEmpty {
                lines.append("Sales whose gain isn't known (a cost is unknown, or more was sold than held), left out: "
                    + summary.salesWithUnknownGain.map(\.description).joined(separator: ", ") + ".")
            }
            if !summary.unconverted.isEmpty {
                lines.append("Trades without an exchange rate into \(summary.currency.rawValue), left out: "
                    + summary.unconverted.map(\.description).joined(separator: ", ") + ".")
            }
            return lines
        }

        var json: JSON {
            JSON(year: summary.year, currency: summary.currency.rawValue, account: account,
                 realizedGain: Format.json(summary.realizedGain),
                 realizedGainByInstrument: summary.realizedGainByInstrument.reduce(into: [:]) {
                     $0[$1.key.rawValue] = Format.json($1.value)
                 },
                 salesWithUnknownGain: summary.salesWithUnknownGain.map(\.description),
                 dividends: Format.json(summary.dividends),
                 dividendsByInstrument: summary.dividendsByInstrument.reduce(into: [:]) {
                     $0[$1.key.rawValue] = Format.json($1.value)
                 },
                 interest: Format.json(summary.interest), fees: Format.json(summary.fees),
                 taxes: Format.json(summary.taxes), incomeTax: Format.json(summary.incomeTax),
                 netIncome: Format.json(summary.netIncome), deposits: Format.json(summary.deposits),
                 withdrawals: Format.json(summary.withdrawals), unconverted: summary.unconverted.map(\.description))
        }

        struct JSON: Encodable {
            var year: Int
            var currency: String
            /// The account summed up; absent with --all.
            var account: String?
            var realizedGain: String
            var realizedGainByInstrument: [String: String]
            var salesWithUnknownGain: [String]
            var dividends: String
            var dividendsByInstrument: [String: String]
            var interest: String
            var fees: String
            var taxes: String
            /// The part of `taxes` withheld on dividends and interest.
            var incomeTax: String
            var netIncome: String
            var deposits: String
            var withdrawals: String
            var unconverted: [String]
        }
    }
}
