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

    mutating func run() async throws {
        try await run(in: .live())
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
                throw CLIError("\(account.id) doesn't record trades, so there's nothing to sum up. Record them with "
                    + "`retire trades convert \(account.id) --to trades`.")
            }
            summary = ledger.summary(for: year)
            title = "\(account.name) (\(account.id))"
        } else {
            summary = valuator.tradeSummary(for: year)
            let accounts = loaded.library.sortedAccounts.filter(\.recordsTrades).map(\.id.rawValue)
            title = accounts.isEmpty ? "no account records trades" : accounts.joined(separator: ", ")
        }
        let report = Report(title: title, summary: summary, library: loaded.library, account: account)
        if json {
            context.console.print(try JSONOutput.string(report.json))
        } else {
            context.console.print(lines: report.lines())
        }
    }

    struct Report {
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

/// `retire trades convert <account> --to trades|snapshots [--apply]`:
/// switches how an account is recorded (Tracker's `conversionToTrades` and
/// `conversionToSnapshots`), previewing by default.
struct TradesConvertCommand: RetireSubcommand {
    static let configuration = CommandConfiguration(
        commandName: "convert",
        abstract: "Convert an account between snapshots (balances or holdings) and trades.",
        discussion: """
            To trades: an opening per position at the account's first valuation (at its cost, or its \
            value then), then a buy or sell per change in quantity at each later valuation, at that \
            day's price; the valuations keep their cash and flows and lose their positions. To \
            snapshots: each valuation gets the positions, average cost and cash the trades give, and \
            the trades are removed (their income and realised gains aren't recorded any more). Values \
            and flows stay the same (docs/TRADES.md, "Converting an account").

            Nothing is written unless you pass --apply; then the files that change are backed up to \
            backups/ first.
            """)

    enum Target: String, ExpressibleByArgument, CaseIterable {
        case trades, snapshots
    }

    @Argument(help: ArgumentHelp("The account's ID.", valueName: "account"))
    var account: String

    @OptionGroup var options: LibraryOptions

    @Option(help: "What the account records from now on: trades or snapshots.")
    var to: Target

    @Flag(help: "Convert: back up the files that change, then write them.")
    var apply = false

    @Option(help: ArgumentHelp("How many trades the preview lists.", valueName: "count"))
    var rows = 20

    @Flag(help: "Print JSON.")
    var json = false

    /// The backup labels of conversions, as the app writes them
    /// (`LibraryStore.convertToTradesBackupLabel`, `convertToSnapshotsBackupLabel`).
    static let toTradesBackupLabel = "convert-to-trades"
    static let toSnapshotsBackupLabel = "convert-to-snapshots"

    mutating func run() async throws {
        try await run(in: .live())
    }

    func run(in context: CLIContext) async throws {
        let loaded = try options.load(in: context)
        let account = try loaded.account(self.account)
        let conversion: AccountConversion?
        switch to {
        case .trades:
            guard !account.recordsTrades else { throw CLIError("\(account.id) already records trades.") }
            conversion = loaded.library.conversionToTrades(of: account.id)
        case .snapshots:
            guard account.recordsTrades else {
                throw CLIError("\(account.id) doesn't record trades: it already records "
                    + "\(account.valuationMode.rawValue == "balance" ? "balances" : "holdings").")
            }
            conversion = loaded.library.conversionToSnapshots(of: account.id)
        }
        guard let conversion else { throw CLIError("\(account.id) can't be converted.") }
        var library = loaded.library
        conversion.apply(to: &library)
        let changedValuations = conversion.valuations.filter { valuation in
            loaded.library.valuations(for: account.id).first { $0.key == valuation.key } != valuation
        }
        var report = Report(account: account, conversion: conversion, changedValuations: changedValuations.count,
                            apply: apply, rows: rows)
        if apply {
            var lines: [String] = []
            let label = to == .trades ? Self.toTradesBackupLabel : Self.toSnapshotsBackupLabel
            try TradeText.write(library, over: loaded, label: label, dryRun: false, context: context,
                                lines: &lines)
            report.written = lines
        }
        if json {
            context.console.print(try JSONOutput.string(report.json))
        } else {
            context.console.print(lines: report.lines())
        }
    }

    struct Report {
        let account: Account
        let conversion: AccountConversion
        let changedValuations: Int
        let apply: Bool
        let rows: Int
        /// What --apply wrote.
        var written: [String] = []

        var to: String { conversion.account.recordsTrades ? "trades" : "snapshots" }

        func lines() -> [String] {
            var lines = ["\(apply ? "Converted" : "Converting") \(account.name) (\(account.id)) to \(to)"]
            var table = TextTable([.left(""), .left("")], showsHeader: false)
            table.add(["Records", "\(account.valuationMode.rawValue) → \(conversion.account.valuationMode.rawValue)"])
            table.add(["Trades", "\(conversion.trades.count) added, \(conversion.removedTrades.count) removed"])
            table.add(["Valuations", "\(changedValuations) changed of \(conversion.valuations.count)"])
            if let first = conversion.months.first, let last = conversion.months.last {
                table.add(["Months", first == last ? first.description : "\(first) to \(last)"])
            }
            lines += table.lines()
            let trades = conversion.trades
            if !trades.isEmpty, rows > 0 {
                lines.append("")
                lines.append("Trades to add")
                var list = TextTable([.left("Date"), .left("Type"), .left("Instrument"), .right("Quantity"),
                                      .right("Price"), .right("Amount"), .right("Cost"), .left("ID")])
                for trade in trades.prefix(rows) {
                    list.add([trade.date.description, trade.type.rawValue, trade.instrument?.rawValue ?? "",
                              trade.quantity.map(Format.exact) ?? "", trade.price.map(Format.exact) ?? "",
                              trade.amount.map { Format.signed($0) } ?? "", trade.cost.map { Format.amount($0) } ?? "",
                              trade.id.rawValue])
                }
                lines += list.lines()
                if trades.count > rows {
                    lines.append("  … and \(Format.count(trades.count - rows, "more trade")) (--rows to list more).")
                }
            }
            if !conversion.notes.isEmpty {
                lines.append("")
                lines.append("Notes")
                lines += conversion.notes.map { "  \($0)" }
            }
            lines.append("")
            if apply {
                lines += written.isEmpty ? ["Nothing to write."] : written
            } else {
                lines.append("Dry run: nothing was written. To convert, run again with --apply.")
            }
            return lines
        }

        var json: JSON {
            JSON(account: account.id.rawValue, from: account.valuationMode.rawValue,
                 to: conversion.account.valuationMode.rawValue, mode: apply ? "apply" : "dry-run",
                 addedTrades: conversion.trades.map { trade in
                     JSON.TradeRow(id: trade.id.rawValue, date: trade.date.description, type: trade.type.rawValue,
                                   instrument: trade.instrument?.rawValue, quantity: trade.quantity?.fileString,
                                   price: trade.price?.fileString, amount: trade.amount?.fileString,
                                   cost: trade.cost?.fileString)
                 },
                 removedTrades: conversion.removedTrades.map(\.key.description),
                 valuations: conversion.valuations.count, changedValuations: changedValuations,
                 months: conversion.months.map(\.description), notes: conversion.notes.map(\.description),
                 written: written)
        }

        struct JSON: Encodable {
            struct TradeRow: Encodable {
                var id: String
                var date: String
                var type: String
                var instrument: String?
                var quantity: String?
                var price: String?
                var amount: String?
                var cost: String?
            }

            var account: String
            var from: String
            var to: String
            var mode: String
            var addedTrades: [TradeRow]
            var removedTrades: [String]
            var valuations: Int
            var changedValuations: Int
            var months: [String]
            var notes: [String]
            /// What --apply wrote and where the backup is.
            var written: [String]
        }
    }
}
