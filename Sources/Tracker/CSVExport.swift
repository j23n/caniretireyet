import Foundation
import Model

/// The library as CSV tables, to open in a spreadsheet or take to another
/// app (docs/schema/README.md, "CSV export"): what's recorded, record by record,
/// and the values worked out from it at every month end.
///
/// Every file is UTF-8, comma-separated with a header row and CRLF line
/// ends (RFC 4180): dates `YYYY-MM-DD`, decimals with a `.` and no
/// grouping, as in the library's files. Recorded amounts are written
/// exactly; computed values are rounded to cents.
public enum CSVExport {
    /// One CSV file: its name (`accounts.csv`) and its text.
    public struct File: Hashable, Sendable {
        public var name: String
        public var text: String

        public init(name: String, text: String) {
            self.name = name
            self.text = text
        }
    }

    /// Every table of `library`, with values worked out at each month end
    /// through `date` (and on `date` itself when it isn't a month end).
    public static func files(of library: Library, through date: CalendarDate) -> [File] {
        let valuator = Valuator(library: library)
        let months = library.months.values.sorted { $0.month < $1.month }
        return [
            netWorth(valuator, through: date),
            accountValues(valuator, through: date),
            accounts(library),
            instruments(library),
            valuations(months),
            positions(months),
            trades(months),
            prices(months),
            fx(months),
            inflation(months),
        ]
    }

    // MARK: Values worked out

    /// `net-worth.csv`: net worth and plan assets at each month end.
    static func netWorth(_ valuator: Valuator, through date: CalendarDate) -> File {
        let currency = valuator.baseCurrency.rawValue
        let plan = Dictionary(valuator.series(.planAssets, through: date).map { ($0.date, $0) },
                              uniquingKeysWith: { _, last in last })
        let rows = valuator.series(.netWorth, through: date).map { point in
            let planPoint = plan[point.date]
            return [point.date.description, currency, cents(point.value),
                    planPoint.map { cents($0.value) } ?? "",
                    yesNo(point.isComplete && (planPoint?.isComplete ?? true))]
        }
        return table("net-worth.csv", ["date", "currency", "net_worth", "plan_assets", "complete"], rows)
    }

    /// `account-values.csv`: each account's value at each month end while
    /// it's open, in its own currency and in the base currency.
    static func accountValues(_ valuator: Valuator, through date: CalendarDate) -> File {
        var rows: [[String]] = []
        for account in valuator.accounts.values.sorted(by: { $0.id < $1.id }) {
            let own = valuator.series(of: account.id, in: .account, through: date)
            let base = Dictionary(valuator.series(of: account.id, through: date).map { ($0.date, $0) },
                                  uniquingKeysWith: { _, last in last })
            for point in own where account.isOpen(on: point.date) {
                let inBase = base[point.date]
                rows.append([point.date.description, account.id.rawValue, account.name, account.currency.rawValue,
                             cents(point.value), valuator.baseCurrency.rawValue,
                             inBase.map { cents($0.value) } ?? "",
                             yesNo(point.isComplete && (inBase?.isComplete ?? false))])
            }
        }
        rows.sort { ($0[0], $0[1]) < ($1[0], $1[1]) }
        return table("account-values.csv", ["date", "account", "name", "currency", "value", "base_currency",
                                            "value_in_base_currency", "complete"], rows)
    }

    // MARK: What's recorded

    /// `accounts.csv`: one row per account, open or closed.
    static func accounts(_ library: Library) -> File {
        let rows = library.accounts.values.sorted { $0.id < $1.id }.map { account in
            [account.id.rawValue, account.name, account.kind.rawValue, account.currency.rawValue,
             account.institution ?? "", account.country?.rawValue ?? "", account.opened.description,
             account.closed?.description ?? "", account.valuationMode.rawValue,
             account.availableFromAge.map(String.init) ?? "", yesNo(account.includedInNetWorth),
             yesNo(account.includedInPlan), mix(account.assetClasses), yesNo(account.tracksMoneyInOut),
             account.successor?.rawValue ?? "",
             account.tags.joined(separator: "; "), account.notes ?? ""]
        }
        return table("accounts.csv", ["id", "name", "kind", "currency", "institution", "country", "opened", "closed",
                                      "valuation", "available_from_age", "in_net_worth", "in_plans",
                                      "asset_classes", "money_in_out", "successor", "tags", "notes"], rows)
    }

    /// `instruments.csv`: one row per instrument.
    static func instruments(_ library: Library) -> File {
        let rows = library.instruments.values.sorted { $0.id < $1.id }.map { instrument in
            [instrument.id.rawValue, instrument.name, instrument.kind.rawValue, instrument.currency.rawValue,
             instrument.unit.rawValue, instrument.isin ?? "", instrument.ticker ?? "", mix(instrument.assetClasses),
             instrument.priceSource?.provider.rawValue ?? "", instrument.priceSource?.symbol ?? ""]
        }
        return table("instruments.csv", ["id", "name", "kind", "currency", "unit", "isin", "ticker", "asset_classes",
                                         "price_provider", "price_symbol"], rows)
    }

    /// `valuations.csv`: every recorded value, as recorded; positions are in `positions.csv`.
    static func valuations(_ months: [MonthFile]) -> File {
        let rows = months.flatMap(\.valuations).sortedByKey().map { valuation in
            [valuation.date.description, valuation.account.rawValue, exact(valuation.balance), exact(valuation.cash),
             String(valuation.positions.count), exact(valuation.flow), exact(valuation.moneyIn),
             exact(valuation.moneyOut), valuation.note ?? "",
             valuation.source?.rawValue ?? ""]
        }
        return table("valuations.csv", ["date", "account", "balance", "cash", "positions", "flow", "money_in",
                                         "money_out", "note", "source"], rows)
    }

    /// `positions.csv`: the quantities recorded in valuations.
    static func positions(_ months: [MonthFile]) -> File {
        let rows = months.flatMap(\.valuations).sortedByKey().flatMap { valuation in
            valuation.positions.map { position in
                [valuation.date.description, valuation.account.rawValue, position.instrument.rawValue,
                 position.quantity.fileString, exact(position.costBasis)]
            }
        }
        return table("positions.csv", ["date", "account", "instrument", "quantity", "cost_basis"], rows)
    }

    /// `trades.csv`: every trade, as recorded.
    static func trades(_ months: [MonthFile]) -> File {
        let rows = months.flatMap(\.trades).sortedByKey().map { trade in
            [trade.date.description, trade.account.rawValue, trade.id.rawValue, trade.type.rawValue,
             trade.instrument?.rawValue ?? "", exact(trade.quantity), exact(trade.price),
             trade.currency?.rawValue ?? "", exact(trade.amount), exact(trade.fees), exact(trade.tax),
             exact(trade.cost), exact(trade.ratio), trade.settlement?.rawValue ?? "", trade.note ?? "",
             trade.source?.rawValue ?? ""]
        }
        return table("trades.csv", ["date", "account", "id", "type", "instrument", "quantity", "price", "currency",
                                    "amount", "fees", "tax", "cost", "ratio", "settlement", "note", "source"], rows)
    }

    /// `prices.csv`: every recorded price, per the instrument's unit.
    static func prices(_ months: [MonthFile]) -> File {
        let rows = months.flatMap(\.prices).sortedByKey().map { price in
            [price.date.description, price.instrument.rawValue, price.price.fileString, price.currency.rawValue,
             price.source?.rawValue ?? ""]
        }
        return table("prices.csv", ["date", "instrument", "price", "currency", "source"], rows)
    }

    /// `fx.csv`: every recorded exchange rate: 1 base = rate × quote.
    static func fx(_ months: [MonthFile]) -> File {
        let rows = months.flatMap(\.fx).sortedByKey().map { rate in
            [rate.date.description, rate.base.rawValue, rate.quote.rawValue, rate.rate.fileString,
             rate.source?.rawValue ?? ""]
        }
        return table("fx.csv", ["date", "base", "quote", "rate", "source"], rows)
    }

    /// `inflation.csv`: every recorded consumer-price-index value.
    static func inflation(_ months: [MonthFile]) -> File {
        let rows = months.flatMap(\.indices).sortedByKey().map { value in
            [value.date.description, value.index.rawValue, value.value.fileString, value.source?.rawValue ?? ""]
        }
        return table("inflation.csv", ["date", "index", "value", "source"], rows)
    }

    // MARK: Writing

    /// A CSV file from its header and rows: fields with a comma, a quote or
    /// a line break are quoted, with quotes doubled.
    static func table(_ name: String, _ header: [String], _ rows: [[String]]) -> File {
        let lines = ([header] + rows).map { $0.map(field).joined(separator: ",") }
        return File(name: name, text: lines.map { $0 + "\r\n" }.joined())
    }

    /// One CSV field: quoted when it holds a comma, a quote or a line
    /// break, with quotes doubled.
    public static func field(_ text: String) -> String {
        guard text.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" }) else { return text }
        return "\"" + text.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    private static func exact(_ value: Decimal?) -> String {
        value?.fileString ?? ""
    }

    private static func cents(_ value: Decimal) -> String {
        value.rounded(scale: 2).fileString
    }

    private static func yesNo(_ value: Bool) -> String {
        value ? "yes" : "no"
    }

    /// `equity=0.6; bonds=0.4`.
    private static func mix(_ mix: AssetMix?) -> String {
        guard let mix else { return "" }
        return mix.assetClasses.map { "\($0.rawValue)=\(mix[$0].fileString)" }.joined(separator: "; ")
    }
}
