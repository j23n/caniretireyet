import ArgumentParser
import Foundation
import Model
import Storage
import Tracker

/// `retire trades`: the trades of accounts that record them (docs/TRADES.md).
struct TradesGroupCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "trades",
        abstract: "List an account's trades and sum up a year.",
        discussion: """
            retire trades list <account>                   the trades, with their cash and realised gains
            retire trades summary <account> | --all        a year's gains, dividends, interest, fees, taxes

            Trades are added and changed in the app, or imported from a broker's export with \
            `retire import`.
            """,
        subcommands: [TradesListCommand.self, TradesSummaryCommand.self])

    /// What to do about an account that doesn't record trades.
    static let switchHint = "Switch it to recording trades in the app (Switch to Trade History on the account)."
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
            the average cost. A buy, sell, fee or tax paid from or into another account (gold paid \
            from the bank) changes no cash: Outside shows what was paid or received there, which \
            counts as money added or taken out.
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
        try context.console.print(report, json: json)
    }

    /// A trade, with what the ledger made of it (for a trades account).
    struct Row {
        var trade: Trade
        var entry: TradeEntry?
    }

    struct ListReport: CommandReport {
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
                lines.append("  \(account.id) doesn't record trades, so its trades don't count. "
                    + TradesGroupCommand.switchHint)
            }
            guard !rows.isEmpty else {
                lines.append(filtered ? "  No trades match." : "  No trades yet: add one in the app, or "
                    + "import a broker's export with `retire import`.")
                return lines
            }
            // What was paid or received outside the account, when a trade was.
            let showsOutside = rows.contains { $0.trade.isSettledExternally }
            var columns: [TextTable.Column] = [.left("Date"), .left("Type"), .left("Instrument"), .right("Quantity"),
                                               .right("Price"), .right("Cash")]
            if showsOutside { columns.append(.right("Outside")) }
            columns += [.right("Fees"), .right("Tax"), .right("Gain"), .left("ID")]
            var table = TextTable(columns)
            for row in rows {
                let trade = row.trade
                let priceCurrency = trade.currency.map { $0 == account.currency ? "" : " \($0.rawValue)" } ?? ""
                var cells: [String] = [
                    trade.date.description, trade.type.rawValue, trade.instrument?.rawValue ?? "",
                    trade.quantity.map(Format.exact) ?? trade.ratio.map { "× \(Format.exact($0))" } ?? "",
                    trade.price.map { Format.exact($0) + priceCurrency } ?? "",
                    row.entry.map { $0.cashEffect.map { Format.signed($0) } ?? "?" }
                        ?? trade.amount.map { Format.signed($0) } ?? "",
                ]
                if showsOutside { cells.append(Self.outside(row).map { Format.signed($0) } ?? "") }
                let rest: [String] = [
                    trade.fees.map { Format.amount($0) } ?? "", trade.tax.map { Format.amount($0) } ?? "",
                    trade.type == .sell ? (row.entry?.realizedGain.map { Format.signed($0) } ?? "?") : "",
                    trade.id.rawValue,
                ]
                table.add(cells + rest)
            }
            lines += table.lines()
            lines.append("")
            lines.append(Wording.count(rows.count, "trade") + (filtered ? " shown." : "."))
            if let ledger, !filtered {
                let positions = ledger.positions(on: today).map { position in
                    "\(position.instrument) \(Format.exact(position.quantity))"
                        + (position.costBasis.map { " (cost \(Format.amount($0)))" } ?? " (cost unknown)")
                }
                let cash = valuator.tradeCash(of: account.id, on: today).map { "cash \(Format.amount($0))" }
                lines.append("Holds on \(today): " + (positions + [cash].compactMap { $0 }).joined(separator: ", ") + ".")
                let issues = ledger.issues.count
                if issues > 0 {
                    lines.append("\(Wording.count(issues, "problem")) with these trades: run `retire validate`.")
                }
            }
            return lines
        }

        /// What a trade settled outside the account paid (negative) or
        /// received there, as the ledger worked it out (else as written).
        static func outside(_ row: Row) -> Decimal? {
            guard row.trade.isSettledExternally else { return nil }
            return row.entry?.amount ?? row.trade.amount
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
                         source: trade.source?.rawValue, settlement: trade.settlement?.rawValue,
                         cashEffect: row.entry?.cashEffect.map { Format.json($0) },
                         outside: Self.outside(row).map { Format.json($0) },
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
                /// As written: `external` for a trade paid from or into another account.
                var settlement: String?
                /// What the account's cash changed by, rounded to cents; absent when unknown.
                var cashEffect: String?
                /// For a trade settled outside the account: what was paid (negative) or received there,
                /// rounded to cents; it counts as money added or taken out.
                var outside: String?
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
