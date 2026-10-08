import ArgumentParser
import Foundation
import Model
import Tracker

/// `retire networth`: net worth on a date, or over time.
struct NetWorthCommand: RetireSubcommand {
    static let configuration = CommandConfiguration(
        commandName: "networth",
        abstract: "Print net worth on a date, or over time.",
        discussion: """
            Prints each account's value on the date, a breakdown, the accounts that haven't \
            been valued recently, and the change since the last check-in split into market, \
            new money and other. With --series, prints net worth over time instead, as a \
            table or CSV.
            """)

    /// What `--by` groups by.
    enum Dimension: String, ExpressibleByArgument, CaseIterable {
        case assetClass = "asset-class"
        case group, currency, institution, liquidity

        var dimension: BreakdownDimension {
            switch self {
            case .assetClass: .assetClass
            case .group: .accountGroup
            case .currency: .currency
            case .institution: .institution
            case .liquidity: .liquidity
            }
        }

        var title: String {
            switch self {
            case .assetClass: "By asset class"
            case .group: "By account group"
            case .currency: "By currency"
            case .institution: "By institution"
            case .liquidity: "By liquidity"
            }
        }
    }

    /// The dates `--series` has points on.
    enum Series: String, ExpressibleByArgument, CaseIterable {
        /// The last day of every month.
        case monthly
        /// Every date with a valuation.
        case checkIns = "check-ins"

        var grid: SeriesGrid { self == .monthly ? .monthEnds : .checkIns }
    }

    @OptionGroup var options: LibraryOptions

    @Option(help: ArgumentHelp("The date, YYYY-MM-DD. Default: today.", valueName: "date"))
    var date: String?

    @Option(help: ArgumentHelp("Group the breakdown (or the series) by asset-class, group, currency, institution or "
                                   + "liquidity. Default: asset-class.", valueName: "dimension"))
    var by: Dimension?

    @Option(help: ArgumentHelp("Print net worth over time through the date instead: monthly (month ends) or "
                                   + "check-ins.", valueName: "grid"))
    var series: Series?

    @Flag(help: "With --series, print CSV.")
    var csv = false

    @Flag(help: "Print JSON.")
    var json = false

    @Flag(help: "Only the accounts the planner counts (leaves out e.g. your home and its mortgage).")
    var planAssets = false

    @Option(help: ArgumentHelp("Flag accounts whose latest valuation is more than this many days old.",
                               valueName: "days"))
    var staleAfter = Valuator.defaultStalenessThreshold

    func validate() throws {
        _ = try parseDate(date, option: "--date")
        if csv, series == nil { throw ValidationError("--csv needs --series.") }
        if csv, json { throw ValidationError("Choose --csv or --json, not both.") }
        if staleAfter < 0 { throw ValidationError("--stale-after can't be negative.") }
    }

    mutating func run() async throws {
        try await run(in: .live())
    }

    func run(in context: CLIContext) async throws {
        let loaded = try options.load(in: context)
        let date = try parseDate(date, option: "--date") ?? context.today
        let report = Report(library: loaded.library, date: date, scope: planAssets ? .planAssets : .netWorth,
                            dimension: by ?? .assetClass, staleAfter: staleAfter)
        let console = context.console
        if let series {
            if json {
                console.print(try JSONOutput.string(report.seriesJSON(series, by: by)))
            } else if csv {
                console.print(lines: report.seriesCSV(series, by: by))
            } else {
                console.print(lines: report.seriesLines(series, by: by))
            }
        } else if json {
            console.print(try JSONOutput.string(report.json))
        } else {
            console.print(lines: report.lines())
        }
    }

    /// Net worth on one date, and what goes with it.
    struct Report {
        let library: Library
        let date: CalendarDate
        let scope: NetWorthScope
        let dimension: Dimension
        let staleAfter: Int
        let valuator: Valuator
        let total: NetWorth

        init(library: Library, date: CalendarDate, scope: NetWorthScope, dimension: Dimension, staleAfter: Int) {
            self.library = library
            self.date = date
            self.scope = scope
            self.dimension = dimension
            self.staleAfter = staleAfter
            valuator = Valuator(library: library)
            total = valuator.total(on: date, in: scope)
        }

        var currency: CurrencyCode { library.settings.baseCurrency }
        var breakdown: Breakdown { valuator.breakdown(of: total, by: dimension.dimension) }
        var stale: [StaleAccount] { valuator.staleAccounts(on: date, threshold: staleAfter, in: scope) }
        var change: ChangeReport? { valuator.changeSinceLastCheckIn(asOf: date, in: scope) }

        func name(_ id: AccountID) -> String { library.accounts[id]?.name ?? id.rawValue }

        /// The amount, marked `*` when part of it is missing.
        func value(_ value: AccountValue) -> String {
            if value.status == .noValuation { return "no valuation" }
            return Format.amount(value.knownValue) + (value.isComplete ? "" : " *")
        }

        // MARK: Text

        func lines() -> [String] {
            let what = scope == .planAssets ? "Plan assets" : "Net worth"
            var lines = ["\(what) on \(date): \(Format.amount(total.total)) \(currency)"
                + (total.isComplete ? "" : " (incomplete: see the problems below)")]
            guard !total.accounts.isEmpty else {
                lines.append("")
                lines.append(library.accounts.isEmpty ? "The library has no accounts yet."
                    : "No account counts on this date.")
                return lines
            }

            lines.append("")
            lines.append("Accounts")
            var accounts = TextTable([.left("Account"), .left("Kind"), .left("Valued on"), .right("Value")])
            let sorted = total.accounts.sorted { (name($0.account), $0.account) < (name($1.account), $1.account) }
            for value in sorted {
                let account = library.accounts[value.account]
                accounts.add([name(value.account), account?.kind.rawValue ?? "", value.valuation?.date.description ?? "–",
                              self.value(value)])
            }
            accounts.add(["Total", "", "", Format.amount(total.total)])
            lines += accounts.lines()

            let breakdown = breakdown
            if !breakdown.slices.isEmpty {
                lines.append("")
                lines.append(dimension.title)
                var table = TextTable([.left(""), .right("Value"), .right("Share")])
                for slice in breakdown.slices {
                    table.add([slice.key.description, Format.amount(slice.value), Format.percent(slice.share)])
                }
                lines += table.lines()
            }

            lines.append("")
            lines += changeLines()

            let stale = stale
            lines.append("")
            if stale.isEmpty {
                lines.append("Every account was valued in the last \(staleAfter) days.")
            } else {
                lines.append("Not valued in the last \(staleAfter) days")
                var table = TextTable([.left("Account"), .left("Last valued"), .right("Days ago")])
                for account in stale {
                    table.add([name(account.account), account.lastValuation?.description ?? "never",
                               account.age.map(String.init) ?? "–"])
                }
                lines += table.lines()
            }

            let problems = total.problems.filter { if case .noValuation = $0 { false } else { true } }
            if !problems.isEmpty {
                lines.append("")
                lines.append("Problems (* values leave these out)")
                lines += problems.map { "  \($0)" }
            }
            return lines
        }

        /// The waterfall since the last check-in.
        func changeLines() -> [String] {
            guard let change else { return ["No earlier check-in to compare with."] }
            let parts = change.total
            let relative = parts.relativeChange.map { " (\(Format.signedPercent($0)))" } ?? ""
            var lines = ["Since the last check-in (\(change.from) to \(change.to))"]
            var table = TextTable([.left(""), .right("")], showsHeader: false)
            table.add(["Start", Format.amount(parts.start)])
            table.add(["Market", Format.signed(parts.market)])
            table.add(["New money", Format.signed(parts.newMoney)])
            table.add(["Other", Format.signed(parts.other)])
            table.add(["End", Format.amount(parts.end)])
            lines += table.lines()
            lines.append("  Change \(Format.signed(parts.change))\(relative)")

            let moved = change.accounts.filter { $0.change.start != 0 || $0.change.end != 0 }
            if !moved.isEmpty {
                lines.append("")
                var accounts = TextTable([.left("Account"), .right("Start"), .right("Market"), .right("New money"),
                                          .right("Other"), .right("End")])
                for account in moved.sorted(by: { (name($0.account), $0.account) < (name($1.account), $1.account) }) {
                    let parts = account.change
                    accounts.add([name(account.account), Format.amount(parts.start), Format.signed(parts.market),
                                  Format.signed(parts.newMoney), Format.signed(parts.other), Format.amount(parts.end)])
                }
                lines += accounts.lines()
            }
            let planned = change.plannedFlowAccounts
            if !planned.isEmpty {
                lines.append("  Money in or out not entered for \(Format.list(planned.map(name))): what the main plan "
                    + "pays in counts as new money, the rest as market.")
            }
            let automatic = change.automaticFlowAccounts
            if !automatic.isEmpty {
                lines.append("  Money in or out not recorded for \(Format.list(automatic.map(name))): a balance's "
                    + "whole change since the value before counts as new money, as a check-in fills it in.")
            }
            let unknown = change.unknownFlowAccounts
            if !unknown.isEmpty {
                lines.append("  Money in or out unknown for \(Format.list(unknown.map(name))): a balance's change "
                    + "without a flow counts as other.")
            }
            return lines
        }

        // MARK: Series

        func seriesRows(_ series: Series, by: Dimension?) -> (keys: [BreakdownKey], rows: [SeriesRow]) {
            if let by {
                let stacked = valuator.breakdownSeries(by: by.dimension, in: scope, grid: series.grid, through: date)
                let rows = stacked.points.map { point in
                    SeriesRow(date: point.date, values: stacked.keys.map { point.value(of: $0) }, total: point.total,
                              isComplete: point.isComplete)
                }
                return (stacked.keys, rows)
            }
            let rows = valuator.series(scope, grid: series.grid, through: date).map {
                SeriesRow(date: $0.date, values: [], total: $0.value, isComplete: $0.isComplete)
            }
            return ([], rows)
        }

        struct SeriesRow {
            var date: CalendarDate
            var values: [Decimal]
            var total: Decimal
            var isComplete: Bool
        }

        func seriesLines(_ series: Series, by: Dimension?) -> [String] {
            let (keys, rows) = seriesRows(series, by: by)
            let what = scope == .planAssets ? "Plan assets" : "Net worth"
            let grid = series == .monthly ? "month ends" : "check-ins"
            guard !rows.isEmpty else { return ["\(what): no valuations on or before \(date)."] }
            var lines = ["\(what) over time (\(grid), \(currency))"]
            var table = TextTable([.left("Date")] + keys.map { .right($0.description) }
                + [.right(what), .right("Change")])
            var previous: Decimal?
            for row in rows {
                let change = previous.map { Format.signed(row.total - $0) } ?? ""
                table.add([row.date.description] + row.values.map { Format.amount($0) }
                    + [Format.amount(row.total) + (row.isComplete ? "" : " *"), change])
                previous = row.total
            }
            lines += table.lines()
            if rows.contains(where: { !$0.isComplete }) {
                lines.append("")
                lines.append("* A price or FX rate is missing; those parts are left out. Run `retire validate`.")
            }
            return lines
        }

        func seriesCSV(_ series: Series, by: Dimension?) -> [String] {
            let (keys, rows) = seriesRows(series, by: by)
            var lines = [CSV.line(["date"] + keys.map(\.jsonKey) + ["total", "complete"])]
            for row in rows {
                lines.append(CSV.line([row.date.description] + row.values.map { Format.json($0) }
                    + [Format.json(row.total), row.isComplete ? "true" : "false"]))
            }
            return lines
        }

        func seriesJSON(_ series: Series, by: Dimension?) -> SeriesJSON {
            let (keys, rows) = seriesRows(series, by: by)
            return SeriesJSON(
                currency: currency.rawValue, scope: scope.rawValue, grid: series.rawValue, by: by?.rawValue,
                keys: keys.map(\.jsonKey),
                points: rows.map { row in
                    SeriesJSON.Point(date: row.date.description, total: Format.json(row.total),
                                     values: by == nil ? nil : Dictionary(uniqueKeysWithValues: zip(
                                         keys.map(\.jsonKey), row.values.map { Format.json($0) })),
                                     complete: row.isComplete)
                })
        }

        // MARK: JSON

        var json: JSON {
            let change = change
            return JSON(
                date: date.description, currency: currency.rawValue, scope: scope.rawValue,
                total: Format.json(total.total), complete: total.isComplete,
                accounts: total.accounts.map { value in
                    JSON.Account(id: value.account.rawValue, name: name(value.account),
                                 kind: library.accounts[value.account]?.kind.rawValue ?? "",
                                 valuedOn: value.valuation?.date.description,
                                 value: value.status == .noValuation ? nil : Format.json(value.knownValue),
                                 complete: value.isComplete, problems: value.problems.map(\.description))
                },
                breakdown: JSON.Breakdown(by: dimension.rawValue, slices: breakdown.slices.map { slice in
                    JSON.Slice(key: slice.key.jsonKey, label: slice.key.description, value: Format.json(slice.value),
                               share: slice.share.map { Format.json($0, places: 4) },
                               accounts: slice.accounts.map(\.rawValue))
                }),
                stale: stale.map {
                    JSON.Stale(account: $0.account.rawValue, name: name($0.account),
                               lastValuation: $0.lastValuation?.description, ageDays: $0.age)
                },
                change: change.map { report in
                    JSON.Change(from: report.from.description, to: report.to.description,
                                total: JSON.Parts(report.total, account: nil),
                                accounts: report.accounts.map { JSON.Parts($0.change, account: $0) },
                                unknownFlowAccounts: report.unknownFlowAccounts.map(\.rawValue),
                                plannedFlowAccounts: report.plannedFlowAccounts.map(\.rawValue),
                                automaticFlowAccounts: report.automaticFlowAccounts.map(\.rawValue))
                },
                problems: total.problems.map(\.description))
        }

        struct JSON: Encodable {
            struct Account: Encodable {
                var id: String
                var name: String
                var kind: String
                var valuedOn: String?
                var value: String?
                var complete: Bool
                var problems: [String]
            }

            struct Breakdown: Encodable {
                var by: String
                var slices: [Slice]
            }

            struct Slice: Encodable {
                var key: String
                var label: String
                var value: String
                var share: String?
                var accounts: [String]
            }

            struct Stale: Encodable {
                var account: String
                var name: String
                var lastValuation: String?
                var ageDays: Int?
            }

            struct Parts: Encodable {
                var account: String?
                var start: String
                var market: String
                var newMoney: String
                var other: String
                var end: String
                var flowKnown: Bool?

                init(_ change: ValueChange, account: AccountChange?) {
                    self.account = account?.account.rawValue
                    start = Format.json(change.start)
                    market = Format.json(change.market)
                    newMoney = Format.json(change.newMoney)
                    other = Format.json(change.other)
                    end = Format.json(change.end)
                    flowKnown = account?.isFlowKnown
                }
            }

            struct Change: Encodable {
                var from: String
                var to: String
                var total: Parts
                var accounts: [Parts]
                var unknownFlowAccounts: [String]
                /// Balances whose new money is what the main plan pays in.
                var plannedFlowAccounts: [String]
                /// Balances whose new money is what a check-in would fill in.
                var automaticFlowAccounts: [String]
            }

            var date: String
            var currency: String
            var scope: String
            var total: String
            var complete: Bool
            var accounts: [Account]
            var breakdown: Breakdown
            var stale: [Stale]
            var change: Change?
            var problems: [String]
        }

        struct SeriesJSON: Encodable {
            struct Point: Encodable {
                var date: String
                var total: String
                var values: [String: String]?
                var complete: Bool
            }

            var currency: String
            var scope: String
            var grid: String
            var by: String?
            var keys: [String]
            var points: [Point]
        }
    }
}

extension BreakdownKey {
    /// A stable key for CSV and JSON: `equity`, `debts`, `investments`,
    /// `USD`, the institution's name (empty for none), `locked`.
    var jsonKey: String {
        switch self {
        case .assetClass(let assetClass): assetClass.rawValue
        case .debts: "debts"
        case .accountGroup(let group): group.rawValue
        case .currency(let code): code.rawValue
        case .institution(let name): name ?? ""
        case .liquidity(let liquidity): liquidity.rawValue
        }
    }
}
