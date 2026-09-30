import ArgumentParser
import Foundation
import Model
import Storage
import Tracker

/// `retire trades`: the trades of accounts that record them (docs/TRADES.md).
struct TradesGroupCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "trades",
        abstract: "List, add and remove an account's trades, sum up a year, and convert accounts.",
        discussion: """
            retire trades list <account>                   the trades, with their cash and realised gains
            retire trades add <account> --type buy …       add a trade
            retire trades remove <account> <id>            remove one
            retire trades summary <account> | --all        a year's gains, dividends, interest, fees, taxes
            retire trades convert <account> --to trades    record an account's trades (or --to snapshots)

            Adding and removing write right away, after a backup (--dry-run shows what they would \
            do); convert previews unless you pass --apply. Broker exports and ledger journals are \
            imported with `retire import`.
            """,
        subcommands: [TradesListCommand.self, TradesAddCommand.self, TradesRemoveCommand.self,
                      TradesSummaryCommand.self, TradesConvertCommand.self])
}

// MARK: - list

/// `retire trades list <account>`: the account's trades in the order they
/// apply, with what each did to the cash, and the realised gain of sales.
struct TradesListCommand: RetireSubcommand {
    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "List an account's trades.",
        discussion: """
            Trades are listed in the order they apply: by date, and within a day splits first, then \
            buys before sells. Cash is what each trade changed the account's cash by, in its currency \
            (its amount, or quantity × price with fees and tax); Gain is a sale's realised gain on \
            the average cost.
            """)

    @Argument(help: ArgumentHelp("The account's ID.", valueName: "account"))
    var account: String

    @OptionGroup var options: LibraryOptions

    @Option(help: "Only the trades of this year.")
    var year: Int?

    @Option(help: ArgumentHelp("Only the trades of this instrument.", valueName: "id"))
    var instrument: String?

    @Flag(help: "Print JSON.")
    var json = false

    mutating func run() async throws {
        try await run(in: .live())
    }

    func run(in context: CLIContext) async throws {
        let loaded = try options.load(in: context)
        let account = try loaded.account(self.account)
        let valuator = Valuator(library: loaded.library)
        let ledger = valuator.ledger(for: account.id)
        let entries = ledger?.entries.map { Row(trade: $0.trade, entry: $0) }
            ?? loaded.library.trades(for: account.id).inProcessingOrder().map { Row(trade: $0, entry: nil) }
        if let instrument, loaded.library.instruments[InstrumentID(instrument)] == nil,
           !entries.contains(where: { $0.trade.instrument?.rawValue == instrument }) {
            throw CLIError("There's no instrument \"\(instrument)\".")
        }
        let rows = entries.filter { row in
            (year.map { row.trade.date.year == $0 } ?? true)
                && (instrument.map { row.trade.instrument?.rawValue == $0 } ?? true)
        }
        let report = ListReport(account: account, rows: rows, ledger: ledger, valuator: valuator,
                                today: context.today, filtered: year != nil || instrument != nil)
        if json {
            context.console.print(try JSONOutput.string(report.json))
        } else {
            context.console.print(lines: report.lines())
        }
    }

    /// A trade, with what the ledger made of it (for a trades account).
    struct Row {
        var trade: Trade
        var entry: TradeEntry?
    }

    struct ListReport {
        let account: Account
        let rows: [Row]
        let ledger: TradeLedger?
        let valuator: Valuator
        let today: CalendarDate
        let filtered: Bool

        func lines() -> [String] {
            let currency = account.currency.rawValue
            var lines = ["Trades of \(account.name) (\(account.id), \(currency))"]
            if !account.recordsTrades {
                lines.append("  \(account.id) doesn't record trades, so its trades don't count. Record them with "
                    + "`retire trades convert \(account.id) --to trades`.")
            }
            guard !rows.isEmpty else {
                lines.append(filtered ? "  No trades match." : "  No trades yet: add one with `retire trades add`, or "
                    + "import a broker's export with `retire import`.")
                return lines
            }
            var table = TextTable([.left("Date"), .left("Type"), .left("Instrument"), .right("Quantity"),
                                   .right("Price"), .right("Cash"), .right("Fees"), .right("Tax"), .right("Gain"),
                                   .left("ID")])
            for row in rows {
                let trade = row.trade
                let priceCurrency = trade.currency.map { $0 == account.currency ? "" : " \($0.rawValue)" } ?? ""
                table.add([
                    trade.date.description, trade.type.rawValue, trade.instrument?.rawValue ?? "",
                    trade.quantity.map(Format.exact) ?? trade.ratio.map { "× \(Format.exact($0))" } ?? "",
                    trade.price.map { Format.exact($0) + priceCurrency } ?? "",
                    row.entry.map { $0.cashEffect.map { Format.signed($0) } ?? "?" }
                        ?? trade.amount.map { Format.signed($0) } ?? "",
                    trade.fees.map { Format.amount($0) } ?? "", trade.tax.map { Format.amount($0) } ?? "",
                    trade.type == .sell ? (row.entry?.realizedGain.map { Format.signed($0) } ?? "?") : "",
                    trade.id.rawValue,
                ])
            }
            lines += table.lines()
            lines.append("")
            lines.append(Format.count(rows.count, "trade") + (filtered ? " shown." : "."))
            if let ledger, !filtered {
                let positions = ledger.positions(on: today).map { position in
                    "\(position.instrument) \(Format.exact(position.quantity))"
                        + (position.costBasis.map { " (cost \(Format.amount($0)))" } ?? " (cost unknown)")
                }
                let cash = valuator.tradeCash(of: account.id, on: today).map { "cash \(Format.amount($0))" }
                lines.append("Holds on \(today): " + (positions + [cash].compactMap { $0 }).joined(separator: ", ") + ".")
                let issues = ledger.issues.count
                if issues > 0 {
                    lines.append("\(Format.count(issues, "problem")) with these trades: run `retire validate`.")
                }
            }
            return lines
        }

        var json: JSON {
            JSON(account: account.id.rawValue, currency: account.currency.rawValue, recordsTrades: account.recordsTrades,
                 trades: rows.map { row in
                     let trade = row.trade
                     return JSON.TradeRow(
                         id: trade.id.rawValue, date: trade.date.description, type: trade.type.rawValue,
                         instrument: trade.instrument?.rawValue, quantity: trade.quantity?.fileString,
                         price: trade.price?.fileString, currency: trade.currency?.rawValue,
                         amount: trade.amount?.fileString, fees: trade.fees?.fileString, tax: trade.tax?.fileString,
                         cost: trade.cost?.fileString, ratio: trade.ratio?.fileString, note: trade.note,
                         source: trade.source?.rawValue, cashEffect: row.entry?.cashEffect.map { Format.json($0) },
                         realizedGain: row.entry?.realizedGain.map { Format.json($0) },
                         quantityAfter: row.entry?.quantityAfter?.fileString,
                         costAfter: row.entry?.costAfter.map { Format.json($0) })
                 })
        }

        struct JSON: Encodable {
            struct TradeRow: Encodable {
                var id: String
                var date: String
                var type: String
                var instrument: String?
                var quantity: String?
                var price: String?
                var currency: String?
                /// As written in the file.
                var amount: String?
                var fees: String?
                var tax: String?
                var cost: String?
                var ratio: String?
                var note: String?
                var source: String?
                /// What the account's cash changed by, rounded to cents; absent when unknown.
                var cashEffect: String?
                var realizedGain: String?
                var quantityAfter: String?
                var costAfter: String?
            }

            var account: String
            var currency: String
            var recordsTrades: Bool
            var trades: [TradeRow]
        }
    }
}

// MARK: - add

/// `retire trades add <account> --type buy …`: adds one trade, after a backup.
struct TradesAddCommand: RetireSubcommand {
    static let configuration = CommandConfiguration(
        commandName: "add",
        abstract: "Add a trade to an account that records trades.",
        discussion: """
            Give what the type needs (docs/TRADES.md): a buy or sell its --instrument, --quantity and \
            --price (or --amount); a dividend or interest its --amount; a deposit or withdrawal its \
            --amount; a split its --instrument and --ratio; an opening or transfer in its \
            --instrument, --quantity and --cost. Quantities, fees and tax are positive; an --amount is \
            the signed cash effect in the account's currency (negative for a buy), and when given it \
            wins over quantity × price. The files that change are backed up to backups/ first; the \
            flows of later valuations follow, as in the app.
            """)

    @Argument(help: ArgumentHelp("The account's ID.", valueName: "account"))
    var account: String

    @OptionGroup var options: LibraryOptions

    @Option(help: ArgumentHelp("buy, sell, dividend, interest, fee, tax, deposit, withdrawal, transferIn, "
                                   + "transferOut, split or opening.", valueName: "type"))
    var type: String

    @Option(help: ArgumentHelp("The trade date, YYYY-MM-DD. Default: today.", valueName: "date"))
    var date: String?

    @Option(help: ArgumentHelp("The instrument's ID.", valueName: "id"))
    var instrument: String?

    @Option(help: ArgumentHelp("Units, positive.", valueName: "number"))
    var quantity: String?

    @Option(help: ArgumentHelp("The price per unit, in --currency (default: the instrument's).", valueName: "number"))
    var price: String?

    @Option(help: ArgumentHelp("The price's currency, e.g. USD.", valueName: "code"))
    var currency: String?

    @Option(help: ArgumentHelp("The cash effect in the account's currency, signed (negative for a buy, a fee, a tax "
                                   + "or a withdrawal), net of fees and tax.", valueName: "number"))
    var amount: String?

    @Option(help: ArgumentHelp("Commissions, positive, in the account's currency.", valueName: "number"))
    var fees: String?

    @Option(help: ArgumentHelp("Tax withheld or charged, positive, in the account's currency.", valueName: "number"))
    var tax: String?

    @Option(help: ArgumentHelp("The purchase cost carried in (opening, transfer in).", valueName: "number"))
    var cost: String?

    @Option(help: ArgumentHelp("A split's new units per old unit, e.g. 2.", valueName: "number"))
    var ratio: String?

    @Option(help: ArgumentHelp("A note.", valueName: "text"))
    var note: String?

    @Option(help: ArgumentHelp("The trade's ID, a slug. Default: 8 random characters.", valueName: "id"))
    var id: String?

    @Flag(help: "Show what adding would do; write nothing.")
    var dryRun = false

    static let backupLabel = "trades"

    func validate() throws {
        _ = try parseDate(date, option: "--date")
        let type = TradeType(rawValue: type)
        guard type.isKnown else {
            throw ValidationError("--type must be one of \(TradeType.knownValues.map(\.rawValue).joined(separator: ", ")).")
        }
        for (value, option) in [(quantity, "--quantity"), (price, "--price"), (amount, "--amount"), (fees, "--fees"),
                                (tax, "--tax"), (cost, "--cost"), (ratio, "--ratio")] {
            _ = try Self.decimal(value, option: option)
        }
        if let id, !Slug.isValid(id) {
            throw ValidationError("--id must be a slug: lowercase letters, digits and hyphens.")
        }
        if let currency, !CurrencyCode(currency.uppercased()).isWellFormed {
            throw ValidationError("--currency must be a currency code such as EUR or USD.")
        }
    }

    /// A decimal option, written like 102.30 (a dot, no grouping).
    static func decimal(_ text: String?, option: String) throws -> Decimal? {
        guard let text else { return nil }
        guard let value = Decimal(fileString: text) else {
            throw ValidationError("\(option) must be a number written like 102.30, not “\(text)”.")
        }
        return value
    }

    mutating func run() async throws {
        try await run(in: .live())
    }

    func run(in context: CLIContext) async throws {
        let loaded = try options.load(in: context)
        let account = try loaded.account(self.account)
        guard account.recordsTrades else {
            throw CLIError("\(account.id) doesn't record trades (it records \(account.valuationMode.rawValue)). "
                + "Convert it first with `retire trades convert \(account.id) --to trades`.")
        }
        if let instrument, loaded.library.instruments[InstrumentID(instrument)] == nil {
            let known = loaded.library.instruments.keys.sorted().map(\.rawValue)
            throw CLIError("There's no instrument \"\(instrument)\". Instruments: \(known.joined(separator: ", ")).")
        }
        let date = try parseDate(date, option: "--date") ?? context.today
        let taken = loaded.library.trades(for: account.id).filter { $0.date == date }.map(\.id)
        let tradeID = id.map { TradeID($0) } ?? TradeID.random(avoiding: taken)
        if taken.contains(tradeID) {
            throw CLIError("\(account.id) already has a trade \(tradeID) on \(date).")
        }
        let trade = Trade(
            account: account.id, date: date, id: tradeID, type: TradeType(rawValue: type),
            instrument: instrument.map { InstrumentID($0) }, quantity: try Self.decimal(quantity, option: "--quantity"),
            price: try Self.decimal(price, option: "--price"), currency: currency.map { CurrencyCode($0.uppercased()) },
            amount: try Self.decimal(amount, option: "--amount"), fees: try Self.decimal(fees, option: "--fees"),
            tax: try Self.decimal(tax, option: "--tax"), cost: try Self.decimal(cost, option: "--cost"),
            ratio: try Self.decimal(ratio, option: "--ratio"), note: note, source: .manual)
        let errors = trade.problems.filter { $0.severity == .error }
        guard errors.isEmpty else {
            throw CLIError("The trade can't be added: " + errors.map(\.message).joined(separator: " "))
        }

        var library = loaded.library
        let edit = library.addTrade(trade)
        let saved = edit.saved ?? trade
        var lines = [(dryRun ? "Would add " : "Added ") + TradeText.describe(saved, in: library)]
        lines += trade.problems.map { "  Note: \($0.message)" }
        lines += TradeText.followUp(edit, account: account)
        try TradeText.write(library, over: loaded, label: Self.backupLabel, dryRun: dryRun, context: context,
                            lines: &lines)
        context.console.print(lines: lines)
    }
}

// MARK: - remove

/// `retire trades remove <account> <id>`: removes one trade, after a backup.
struct TradesRemoveCommand: RetireSubcommand {
    static let configuration = CommandConfiguration(
        commandName: "remove",
        abstract: "Remove a trade.",
        discussion: """
            The trade's ID is in `retire trades list`. The files that change are backed up to \
            backups/ first; the flows of later valuations follow, as in the app.
            """)

    @Argument(help: ArgumentHelp("The account's ID.", valueName: "account"))
    var account: String

    @Argument(help: ArgumentHelp("The trade's ID.", valueName: "id"))
    var id: String

    @OptionGroup var options: LibraryOptions

    @Option(help: ArgumentHelp("The trade's date, when two trades on different days have the ID.",
                               valueName: "date"))
    var date: String?

    @Flag(help: "Show what removing would do; write nothing.")
    var dryRun = false

    func validate() throws {
        _ = try parseDate(date, option: "--date")
    }

    mutating func run() async throws {
        try await run(in: .live())
    }

    func run(in context: CLIContext) async throws {
        let loaded = try options.load(in: context)
        let account = try loaded.account(self.account)
        let day = try parseDate(date, option: "--date")
        let found = loaded.library.trades(for: account.id).filter { trade in
            trade.id.rawValue == id && (day.map { $0 == trade.date } ?? true)
        }
        guard let trade = found.first else {
            throw CLIError("\(account.id) has no trade \(id)" + (day.map { " on \($0)" } ?? "")
                + ". Its trades' IDs are in `retire trades list \(account.id)`.")
        }
        guard found.count == 1 else {
            throw CLIError("\(account.id) has trades \(id) on \(found.map(\.date.description).joined(separator: " and ")): "
                + "choose one with --date.")
        }
        var library = loaded.library
        var lines = [(dryRun ? "Would remove " : "Removed ") + TradeText.describe(trade, in: library)]
        let edit = library.removeTrade(trade.key)
        lines += TradeText.followUp(edit, account: account)
        try TradeText.write(library, over: loaded, label: TradesAddCommand.backupLabel, dryRun: dryRun,
                            context: context, lines: &lines)
        context.console.print(lines: lines)
    }
}

// MARK: - Shared

extension LoadedLibrary {
    /// The account with this ID, or an error listing the accounts.
    func account(_ id: String) throws -> Account {
        guard let account = library.accounts[AccountID(id)] else {
            let known = library.accounts.keys.sorted().map(\.rawValue)
            throw CLIError("There's no account \"\(id)\". Accounts: \(known.joined(separator: ", ")).")
        }
        return account
    }
}

/// How the trades commands describe and write trades.
enum TradeText {
    /// `the buy of 10 vwce @ 134.75 on 2026-08-12 (q4nkf6gi): cash -1,352.50.`
    static func describe(_ trade: Trade, in library: Library) -> String {
        var text = "the \(trade.type.rawValue)"
        if let quantity = trade.quantity { text += " of \(Format.exact(quantity))" }
        if let instrument = trade.instrument { text += (trade.quantity == nil ? " of " : " ") + instrument.rawValue }
        if let price = trade.price {
            text += " @ \(Format.exact(price))" + (trade.currency.map { " \($0.rawValue)" } ?? "")
        }
        text += " on \(trade.date) (\(trade.id))"
        let entry = Valuator(library: library).ledger(for: trade.account)?.entries.first { $0.trade.key == trade.key }
        if let cash = entry?.cashEffect ?? trade.amount { text += ": cash \(Format.signed(cash))" }
        return text + "."
    }

    /// What an edit did besides the trade: the opening date, later flows, new problems.
    static func followUp(_ edit: TradeEdit, account: Account) -> [String] {
        var lines: [String] = []
        if let from = edit.movedOpeningFrom, let saved = edit.saved {
            lines.append("  \(account.id) now opens on \(saved.date) (was \(from)).")
        }
        if !edit.flows.recomputed.isEmpty {
            lines.append("  The flows of later values were worked out again: "
                + edit.flows.recomputed.map { "\($0.date) (\(Format.signed($0.flow ?? 0)))" }.joined(separator: ", ")
                + ".")
        }
        if !edit.flows.kept.isEmpty {
            lines.append("  Flows typed by hand were kept: " + edit.flows.kept.map(\.date.description)
                .joined(separator: ", ") + ".")
        }
        lines += edit.newIssues.map { "  Problem: \($0.message)" }
        return lines
    }

    /// Writes `library` over the loaded one, after backing up the files it
    /// changes, unless `dryRun`; adds what it did to `lines`.
    static func write(_ library: Library, over loaded: LoadedLibrary, label: String, dryRun: Bool,
                      context: CLIContext, lines: inout [String]) throws {
        let paths = library.files(changedFrom: loaded.library).map(\.path).sorted()
        guard !dryRun else {
            lines.append("Dry run: nothing was written" + (paths.isEmpty ? "." : " (\(Format.count(paths.count, "file")) "
                + "would change)."))
            return
        }
        guard !paths.isEmpty else { return }
        try loaded.checkWritable()
        let backup = try loaded.folder.backup(paths: paths, label: label, date: context.now())
        let saved = try loaded.folder.save(library, previous: loaded.library)
        try loaded.folder.recordResult(of: backup)
        lines.append("Wrote \(Format.count(saved.written.count, "file")): " + saved.written.joined(separator: ", ") + ".")
        lines.append("Backed up the files it changed to \(backup.path).")
    }
}
