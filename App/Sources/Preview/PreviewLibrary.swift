import Foundation
import Model
import Storage
import Tracker

/// A made-up library for SwiftUI previews and the UI tests: the tests'
/// example library (Sources/TestSupport/Resources/ExampleLibrary, which
/// project.yml bundles with the app), read as the app reads a library.
/// Ten accounts (current, savings, a broker that records trades of an ETF,
/// a bitcoin wallet, gold coins, a pension fund, TFR, a home and its
/// mortgage, and a closed bank account), month-end check-ins from October
/// 2025 to September 2026, the broker's trades, two plans, two import
/// profiles, a baseline and the headlines recorded at each check-in. All
/// names and amounts are made up.
///
/// Use it through `AppModel.preview()` / `.previewEnvironment()`, or directly
/// for chart previews (`PreviewLibrary.valuator`).
enum PreviewLibrary {
    /// The whole library.
    static let library: Library = {
        guard let folder = Bundle.main.url(forResource: "ExampleLibrary", withExtension: nil),
              let loaded = try? LibraryFolder(root: folder).load() else {
            preconditionFailure("The app's ExampleLibrary resource is missing (project.yml)")
        }
        return loaded.library
    }()

    /// A library with settings and nothing else, for empty states.
    static let empty = Library(settings: library.settings)

    /// ``library`` with Directa's September check-in listing the positions
    /// of a made-up broker statement that shows 10 VWCE more than the
    /// trades give, and a buy without a price, for the trades account's
    /// banners (a reconciliation mismatch and a trade that needs a look).
    static let withStatementMismatch: Library = {
        var copy = PreviewLibrary.library
        copy.upsert(Valuation(account: "directa", date: "2026-09-30", cash: d("312.1"),
                              positions: [Position(instrument: "vwce", quantity: d("424.5"))], flow: d("11.3")))
        copy.upsert(Trade(account: "directa", date: "2026-09-18", id: "nopricex", type: .buy, instrument: "vwce",
                          quantity: 2, source: .manual))
        return copy
    }()

    /// ``library`` with a made-up dollar brokerage account, "US brokerage",
    /// whose history was imported without filling in past prices: dollar
    /// balances from June 2018, all of it taken out on 1 January 2022, and
    /// no USD rate before October 2025. Its detail shows dollars with a
    /// full chart, says net worth leaves those values out (*Fill In Past
    /// Prices…*), and suggests closing it rather than calling it stale.
    static let withForeignAccount: Library = {
        var copy = PreviewLibrary.library
        copy.accounts[foreignAccount] = Account(
            id: foreignAccount, name: "US brokerage", kind: .brokerage, currency: .usd, opened: "2018-06-01",
            institution: "Example Brokerage Inc.", country: "US",
            notes: "Made-up example: imported from a spreadsheet, without past exchange rates.")
        for (date, balance, flow) in [
            ("2018-06-30", "80000", "80000"), ("2018-12-31", "76500", "0"), ("2019-06-30", "88200", "2500"),
            ("2019-12-31", "97400", "0"), ("2020-06-30", "92100", "0"), ("2020-12-31", "109800", "5000"),
            ("2021-06-30", "118600", nil), ("2021-11-30", "123959", nil), ("2022-01-01", "0", "-123959"),
        ] as [(String, String, String?)] {
            copy.upsert(Valuation(account: foreignAccount, date: CalendarDate(date)!, balance: d(balance),
                                  flow: flow.map(d), source: .`import`))
        }
        return copy
    }()

    /// The dollar account of ``withForeignAccount``.
    static let foreignAccount: AccountID = "us-brokerage"

    /// ``library`` with a made-up ETF savings plan since January 2018,
    /// recorded as trades, and no check-ins before October 2025: Progress
    /// values the years before from what it held and its prices, as for
    /// someone who imported their history and started checking in late.
    /// Without the January baseline, which knew nothing of the plan.
    static let withLongHistory: Library = {
        var copy = PreviewLibrary.library
        copy.accounts[longHistoryAccount] = Account(
            id: longHistoryAccount, name: "ETF savings plan", kind: .brokerage, currency: "EUR",
            opened: "2018-01-01", institution: "Example Bank", valuation: .trades,
            notes: "Made-up example: a monthly savings plan, imported as trades.")
        copy.instruments["world-etf"] = Instrument(
            id: "world-etf", name: "World equity ETF (made up)", kind: .etf, currency: "EUR", unit: .share,
            assetClasses: [.equity: d("1")])
        copy.projections["base"]?.baselines = [:]
        // Each year's made-up return, spread over its months, with a fall
        // in March 2020, and what goes in each month.
        let years: [(year: Int, growth: Double, monthly: Int)] = [
            (2018, -0.06, 400), (2019, 0.26, 450), (2020, 0.06, 500), (2021, 0.27, 550), (2022, -0.13, 600),
            (2023, 0.18, 650), (2024, 0.24, 700), (2025, 0.08, 750), (2026, 0.09, 800),
        ]
        var price = 50.0
        // Trade IDs of letters, as random ones are, the deposit's first: "lhaaa", "lhaab", ….
        let letters = Array("abcdefghijklmnopqrstuvwxyz")
        var index = 0
        for (year, growth, monthly) in years {
            for month in 1...(year == 2026 ? 9 : 12) {
                defer { index += 1 }
                price *= pow(1 + growth, 1.0 / 12)
                if year == 2020 && month == 3 { price *= 0.78 }
                if year == 2020 && (4...8).contains(month) { price *= 1.05 }
                // Bought at the month's end, at its price.
                guard let day = YearMonth(year: year, month: month)?.lastDay else { continue }
                let quote = d(String(format: "%.2f", price))
                copy.upsert(PriceRecord(instrument: "world-etf", date: day, price: quote, currency: .eur))
                let amount = year == 2018 && month == 1 ? 10_000 : monthly
                let id = "lh" + String(letters[index / 26]) + String(letters[index % 26])
                copy.upsert(Trade(account: longHistoryAccount, date: day, id: TradeID(rawValue: id + "a"),
                                  type: .deposit, amount: Decimal(amount)))
                let quantity = d(String(format: "%.4f", floor(Double(amount) / price * 10_000) / 10_000))
                copy.upsert(Trade(account: longHistoryAccount, date: day, id: TradeID(rawValue: id + "b"),
                                  type: .buy, instrument: "world-etf", quantity: quantity, price: quote))
            }
        }
        return copy
    }()

    /// The savings plan of ``withLongHistory``.
    static let longHistoryAccount: AccountID = "etf-plan"

    /// A valuator over ``library``.
    static var valuator: Tracker.Valuator { Tracker.Valuator(library: library) }

    /// The date of the latest check-in: 30 September 2026.
    static let latestCheckIn: CalendarDate = "2026-09-30"

    /// A decimal from its exact text (never through `Double`).
    static func d(_ text: String) -> Decimal {
        guard let value = Decimal(fileString: text) else { preconditionFailure("Bad decimal \(text)") }
        return value
    }
}
