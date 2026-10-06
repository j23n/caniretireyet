import Foundation
import Model
import Tracker

// Generated from the test example library (Sources/TestSupport/Resources/
// ExampleLibrary), so previews show the same numbers as the tests. All names
// and amounts are made up. If the example library changes, regenerate this
// file or keep it in step by hand.

/// A made-up library for SwiftUI previews, built in code: ten accounts
/// (current, savings, a broker that records trades of an ETF, a bitcoin
/// wallet, gold coins, a pension fund, TFR, a home and its mortgage, and a
/// closed bank account), month-end check-ins from October 2025 to September
/// 2026, the broker's trades, two plans, an import profile, a baseline and
/// the headlines recorded at each check-in.
///
/// Use it through `AppModel.preview()` / `.previewEnvironment()`, or directly
/// for chart previews (`PreviewLibrary.valuator`).
enum PreviewLibrary {
    /// The whole library.
    static let library: Library = make()

    /// A library with settings and nothing else, for empty states.
    static let empty = Library(settings: settings)

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
            opened: "2018-01-15", institution: "Example Bank", valuation: .trades,
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
                guard let monthEnd = YearMonth(year: year, month: month)?.lastDay,
                      let day = CalendarDate(year: year, month: month, day: 15) else { continue }
                let quote = d(String(format: "%.2f", price))
                copy.upsert(PriceRecord(instrument: "world-etf", date: monthEnd, price: quote, currency: .eur))
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

    static let settings = LibrarySettings(
        baseCurrency: "EUR",
        person: Person(name: "Alex Example", birthDate: "1988-04-12"),
        taxResidence: "IT",
        mainPlan: "base")

    static let accounts: [Account] = [
        Account(
            id: "casa",
            name: "Home",
            kind: .property,
            currency: "EUR",
            opened: "2024-07-15",
            country: "IT",
            includeIn: IncludeIn(plan: false),
            notes: "Made-up estimate of the home's market value."),
        Account(
            id: "conto-deposito",
            name: "Conto deposito",
            kind: .savings,
            currency: "EUR",
            opened: "2025-06-01",
            institution: "Banca Esempio",
            country: "IT"),
        Account(
            id: "conto-fineco",
            name: "Conto Fineco",
            kind: .cash,
            currency: "EUR",
            opened: "2024-03-01",
            institution: "FinecoBank",
            country: "IT",
            tags: ["daily"]),
        Account(
            id: "directa",
            name: "Directa",
            kind: .brokerage,
            currency: "EUR",
            opened: "2021-03-01",
            institution: "Directa SIM",
            country: "IT",
            valuation: .trades,
            tags: ["fire"]),
        Account(
            id: "fondo-pensione",
            name: "Fondo pensione",
            kind: .pensionFund,
            currency: "EUR",
            opened: "2022-01-01",
            institution: "Fondo Esempio",
            country: "IT",
            assetClasses: [.bonds: d("0.4"), .equity: d("0.6")],
            availableFromAge: 67),
        Account(
            id: "gold-coins",
            name: "Gold coins",
            kind: .metals,
            currency: "EUR",
            opened: "2023-02-01",
            country: "IT",
            notes: "Made-up example: coins kept in a safe deposit box."),
        Account(
            id: "ledger-wallet",
            name: "Ledger wallet",
            kind: .crypto,
            currency: "EUR",
            opened: "2022-05-10",
            tags: ["fire"]),
        Account(
            id: "mutuo-casa",
            name: "Mutuo casa",
            kind: .mortgage,
            currency: "EUR",
            opened: "2024-07-15",
            institution: "Banca Esempio",
            country: "IT",
            includeIn: IncludeIn(plan: false),
            notes: "Mortgage on the home; its payments are part of spending in plans."),
        Account(
            id: "old-bank",
            name: "Old bank",
            kind: .cash,
            currency: "EUR",
            opened: "2016-05-01",
            closed: "2025-11-15",
            institution: "Old Bank AG",
            country: "DE",
            successor: "conto-fineco"),
        Account(
            id: "tfr",
            name: "TFR",
            kind: .tfr,
            currency: "EUR",
            opened: "2023-09-01",
            institution: "Employer",
            country: "IT"),
    ]

    static let instruments: [Instrument] = [
        Instrument(
            id: "btc",
            name: "Bitcoin",
            kind: .crypto,
            currency: "USD",
            unit: "BTC",
            assetClasses: [.crypto: d("1")],
            priceSource: PriceSource(provider: .coingecko, symbol: "bitcoin")),
        Instrument(
            id: "gold",
            name: "Gold (coins and bars)",
            kind: .metal,
            currency: "EUR",
            unit: .gram,
            assetClasses: [.gold: d("1")],
            priceSource: PriceSource(provider: .goldAPI, symbol: "XAU")),
        Instrument(
            id: "vwce",
            name: "Vanguard FTSE All-World UCITS ETF (Acc)",
            kind: .etf,
            currency: "EUR",
            unit: .share,
            assetClasses: [.equity: d("1")],
            isin: "IE00BK5BQT80",
            ticker: "VWCE",
            priceSource: PriceSource(provider: .yahoo, symbol: "VWCE.DE")),
    ]

    // MARK: History

    /// Month-end prices: date, VWCE (EUR per share, Yahoo), bitcoin (USD, CoinGecko), gold (EUR per gram, gold-api).
    private static let priceRows: [(String, String, String, String)] = [
        ("2025-10-31", "128.1", "98500", "92.1"),
        ("2025-11-30", "129.4", "91200", "93.4"),
        ("2025-12-31", "131.05", "94800", "95.2"),
        ("2026-01-31", "132.6", "101300", "96.8"),
        ("2026-02-28", "130.2", "96700", "95.9"),
        ("2026-03-31", "127.85", "88900", "97.3"),
        ("2026-04-30", "131.9", "93400", "98.6"),
        ("2026-05-31", "133.7", "99800", "97.8"),
        ("2026-06-30", "134.15", "104200", "99.1"),
        ("2026-07-31", "136.8", "108900", "100.4"),
        ("2026-08-31", "135.25", "103600", "99.7"),
        ("2026-09-30", "138.42", "111400", "98.4"),
    ]

    /// Month-end EUR/USD rates (1 EUR = rate USD, ECB) and Italy's HICP (Eurostat), when published.
    private static let rateRows: [(String, String, String?)] = [
        ("2025-10-31", "1.0852", "126.1"),
        ("2025-11-30", "1.0911", "125.95"),
        ("2025-12-31", "1.0987", "126.3"),
        ("2026-01-31", "1.1034", "126.05"),
        ("2026-02-28", "1.0968", "126.4"),
        ("2026-03-31", "1.1102", "126.95"),
        ("2026-04-30", "1.1175", "127.3"),
        ("2026-05-31", "1.1229", "127.45"),
        ("2026-06-30", "1.1301", "127.7"),
        ("2026-07-31", "1.1256", "128.1"),
        ("2026-08-31", "1.134", "128.41"),
        ("2026-09-30", "1.1398", nil),
    ]

    /// Every valuation, in the order of the month files.
    static let valuations: [Valuation] = [
        balance("casa", "2025-10-31", "305000", source: .`import`),
        balance("conto-deposito", "2025-10-31", "15000", source: .`import`),
        balance("conto-fineco", "2025-10-31", "4820.3", source: .`import`),
        cash("directa", "2025-10-31", "215.4", source: .`import`),
        balance("fondo-pensione", "2025-10-31", "16120", source: .`import`),
        holdings("gold-coins", "2025-10-31", positions: [position("gold", "62.2", cost: "5210")], source: .`import`),
        holdings("ledger-wallet", "2025-10-31", positions: [position("btc", "0.4215")], source: .`import`),
        balance("mutuo-casa", "2025-10-31", "-148200", source: .`import`),
        balance("old-bank", "2025-10-31", "850", source: .`import`),
        balance("tfr", "2025-10-31", "8100", source: .`import`),
        balance("conto-deposito", "2025-11-30", "15031.25", flow: "0"),
        balance("conto-fineco", "2025-11-30", "6105.75", flow: "1285.45", note: "includes 850 moved from Old bank"),
        cash("directa", "2025-11-30", "188.9", flow: "1267.5"),
        balance("mutuo-casa", "2025-11-30", "-147550", flow: "650"),
        balance("conto-deposito", "2025-12-31", "15562.1", flow: "500"),
        balance("conto-fineco", "2025-12-31", "3950.4", flow: "-2155.35"),
        cash("directa", "2025-12-31", "402.15", flow: "1523.75"),
        balance("fondo-pensione", "2025-12-31", "16850.4", flow: "1325"),
        balance("mutuo-casa", "2025-12-31", "-146900", flow: "650"),
        balance("tfr", "2025-12-31", "8420.55", flow: "310"),
        balance("conto-deposito", "2026-01-31", "15594.5", flow: "0"),
        balance("conto-fineco", "2026-01-31", "5210.85", flow: "1260.45"),
        cash("directa", "2026-01-31", "256.8", flow: "1180.65"),
        balance("mutuo-casa", "2026-01-31", "-146250", flow: "650"),
        balance("conto-deposito", "2026-02-28", "15626.95", flow: "0"),
        balance("conto-fineco", "2026-02-28", "4780.2", flow: "-430.65"),
        cash("directa", "2026-02-28", "310.45", flow: "1355.65"),
        balance("mutuo-casa", "2026-02-28", "-145600", flow: "650"),
        balance("conto-deposito", "2026-03-31", "16159.5", flow: "500"),
        balance("conto-fineco", "2026-03-31", "5530.1", flow: "749.9"),
        cash("directa", "2026-03-31", "150.2", flow: "1118.25"),
        balance("fondo-pensione", "2026-03-31", "17480.9", flow: "1325"),
        holdings("gold-coins", "2026-03-31", positions: [position("gold", "93.3", cost: "8236.03")], flow: "3026.03", note: "bought a 1 oz coin"),
        holdings("ledger-wallet", "2026-03-31", positions: [position("btc", "0.4515")], flow: "2402.27"),
        balance("mutuo-casa", "2026-03-31", "-144950", flow: "650"),
        balance("conto-deposito", "2026-04-30", "16193.15", flow: "0"),
        balance("conto-fineco", "2026-04-30", "4410.65", flow: "-1119.45"),
        cash("directa", "2026-04-30", "1480.6", flow: "1726.1"),
        balance("mutuo-casa", "2026-04-30", "-144300", flow: "650"),
        balance("conto-deposito", "2026-05-31", "16226.85", flow: "0"),
        balance("conto-fineco", "2026-05-31", "5890.3", flow: "1479.65"),
        cash("directa", "2026-05-31", "402.9", flow: "259.3"),
        balance("mutuo-casa", "2026-05-31", "-143650", flow: "650"),
        balance("casa", "2026-06-30", "312000", note: "estimate from listings nearby"),
        balance("conto-deposito", "2026-06-30", "16760.65", flow: "500"),
        balance("conto-fineco", "2026-06-30", "6240.95", flow: "350.65"),
        cash("directa", "2026-06-30", "290.35", flow: "1228.95"),
        balance("fondo-pensione", "2026-06-30", "17990.35", flow: "1325"),
        balance("mutuo-casa", "2026-06-30", "-143000", flow: "650"),
        balance("tfr", "2026-06-30", "10760.2", flow: "2242.5"),
        balance("conto-deposito", "2026-07-31", "16795.55", flow: "0"),
        balance("conto-fineco", "2026-07-31", "3980.4", flow: "-2260.55"),
        cash("directa", "2026-07-31", "1452.7", flow: "-0.45"),
        balance("mutuo-casa", "2026-07-31", "-142350", flow: "650"),
        balance("conto-deposito", "2026-08-31", "16830.5", flow: "0"),
        balance("conto-fineco", "2026-08-31", "4515.2", flow: "534.8"),
        cash("directa", "2026-08-31", "300.8", flow: "200.6"),
        balance("mutuo-casa", "2026-08-31", "-141700", flow: "650"),
        balance("conto-deposito", "2026-09-30", "17365.55", flow: "500"),
        balance("conto-fineco", "2026-09-30", "4210.55", flow: "-304.65"),
        cash("directa", "2026-09-30", "312.1", flow: "11.3"),
        balance("fondo-pensione", "2026-09-30", "18450.12", flow: "1325", note: "from Q3 statement"),
        balance("mutuo-casa", "2026-09-30", "-141050", flow: "650"),
    ]

    /// Directa's trades: an opening, monthly deposits and buys of VWCE, and a sale in July.
    static let trades: [Trade] = [
        Trade(account: "directa", date: "2025-10-31", id: "puxzhjme", type: .opening, instrument: "vwce",
              quantity: 338, cost: d("38251.63"), note: "valore di carico from the statement", source: .`import`),
        deposit("2025-11-04", "icl5ynvm", "1267.5"),
        buy("2025-11-12", "rqznubop", "10", "128.9"),
        deposit("2025-12-03", "q64lxyd4", "1523.75"),
        buy("2025-12-10", "y7hg7yl3", "10", "130.55"),
        deposit("2026-01-07", "lsd74bp4", "1180.65"),
        buy("2026-01-14", "4i6ropfm", "10", "132.1"),
        deposit("2026-02-04", "mndvn4hx", "1355.65"),
        buy("2026-02-11", "ufj457x7", "10", "129.7"),
        deposit("2026-03-04", "qjmx4d5o", "1118.25"),
        buy("2026-03-12", "ody4ieol", "10", "127.35"),
        deposit("2026-04-03", "6tolmwxn", "1726.1"),
        buy("2026-04-15", "jrkg56ll", "3", "131.4", fees: "1.5"),
        deposit("2026-05-05", "liuzqcoo", "259.3"),
        buy("2026-05-13", "bzcnj6j5", "10", "133.2"),
        deposit("2026-06-03", "gvu5sszm", "1228.95"),
        buy("2026-06-10", "xpvaum4h", "10", "133.65"),
        Trade(account: "directa", date: "2026-07-14", id: "27jvxijw", type: .sell, instrument: "vwce",
              quantity: d("8.5"), price: d("144.56"), amount: d("1162.8"), fees: 5, tax: d("60.95")),
        deposit("2026-08-04", "rkbyjhkx", "200.6"),
        buy("2026-08-12", "q4nkf6gi", "10", "134.75"),
    ]

    // MARK: Plans and projections

    static let plans: [PlanDocument] = [
        decode("""
            {
              "assumptions": {
                "correlations": { "equity": { "bonds": "0.1", "crypto": "0.4", "gold": "0.05" } },
                "inflation": "0.02",
                "returns": {
                  "bonds": { "real": "0.01", "volatility": "0.06" },
                  "cash": { "real": "0", "volatility": "0.01" },
                  "crypto": { "medianReal": "0", "real": "0.16629", "volatility": "0.7" },
                  "equity": { "real": "0.045", "volatility": "0.17" },
                  "gold": { "real": "0.01", "volatility": "0.15" }
                }
              },
              "contributions": [
                { "account": "fondo-pensione", "perYear": "5000", "until": "retirement" }
              ],
              "endAge": 95,
              "events": [
                { "age": 62, "amount": "150000", "name": "Inheritance", "probability": "0.8" },
                { "amount": "-25000", "name": "New car", "year": 2031 }
              ],
              "id": "base",
              "name": "Base case",
              "pensions": [
                { "fromAge": 67, "name": "State pension", "perYear": "14000" },
                { "fromAge": 67, "name": "State pension from previous country", "perYear": "4800" }
              ],
              "portfolio": { "start": "latest-check-in", "unrealizedGainShare": "0.2" },
              "retirement": { "age": 55 },
              "simulation": { "confidence": "0.9", "runs": 2000, "seed": 1 },
              "spending": {
                "phases": [{ "factor": "0.9", "fromAge": 75 }, { "factor": "0.8", "fromAge": 85 }],
                "retired": "36000",
                "working": "36000"
              },
              "tax": { "investmentRate": "0.26", "wealthAllowance": "5000", "wealthRate": "0.002" },
              "work": [
                { "from": "2026-01-01", "name": "Employee", "netIncome": "40000", "realGrowth": "0.01", "until": "2028-12-31" },
                { "from": "2029-01-01", "name": "Self-employed", "netIncome": "48000", "until": "retirement" }
              ]
            }
            """),
        decode("""
            {
              "events": [
                { "amount": "-15000", "name": "Sabbatical", "year": 2033 }
              ],
              "id": "part-time-from-50",
              "name": "Part-time from 50",
              "pensions": [
                { "fromAge": 67, "name": "State pension", "perYear": "11000" },
                { "fromAge": 67, "name": "Pension from previous country", "perYear": "4800" }
              ],
              "portfolio": {
                "exclude": ["gold-coins"],
                "start": "2026-06-30",
                "targetMix": { "bonds": "0.2", "equity": "0.8" },
                "targetMixByAge": [
                  { "fromAge": "retirement", "mix": { "bonds": "0.4", "equity": "0.6" } },
                  { "fromAge": 75, "mix": { "bonds": "0.6", "equity": "0.4" } }
                ]
              },
              "retirement": { "age": "earliest" },
              "simulation": { "runs": 500 },
              "spending": { "flexible": { "enabled": false, "floor": "0.85" }, "retired": "32000", "working": "34000" },
              "tax": { "investmentRate": "0.26" },
              "work": [
                { "from": "2026-01-01", "netIncome": "40000", "realGrowth": "0.01", "until": "2038-04-11" },
                { "from": "2038-04-12", "name": "Part-time", "netIncome": "18000", "until": "retirement" }
              ]
            }
            """),
    ]

    static let importProfile: ImportProfile = decode("""
        {
          "columns": [
            { "account": "conto-fineco", "header": "Conto Fineco", "target": "balance" },
            { "account": "directa", "header": "Directa", "target": "balance" },
            { "account": "ledger-wallet", "header": "BTC (qtà)", "instrument": "btc", "target": "quantity" },
            { "account": "gold-coins", "header": "Oro", "target": "balance" },
            { "header": "Note", "target": "ignore" }
          ],
          "dateColumn": "Data",
          "defaults": { "date": { "pattern": "dd/MM/yyyy" }, "empty": "skip", "number": { "decimal": ",", "thousands": "." } },
          "file": { "delimiter": ";", "encoding": "windows-1252", "excludeRows": ["Totale"], "headerRow": 1 },
          "id": "net-worth-sheet",
          "layout": "wide",
          "matches": { "accounts": { "Fineco": "conto-fineco" } },
          "name": "My net worth spreadsheet",
          "onConflict": "ask"
        }
        """)

    /// The yearly baseline of `base` saved on 5 January 2026.
    static var baseline: Baseline {
        Baseline(
            created: "2026-01-05", kind: .yearly, label: "Start of 2026", engine: "0.1.0",
            accounts: ["conto-deposito", "conto-fineco", "directa", "fondo-pensione", "gold-coins", "ledger-wallet", "tfr"],
            headline: HeadlineSummary(confidence: d("0.9"), earliestAge: 55,
                                      successAtTarget: d("0.81")),
            plan: decode(baselinePlan),
            start: BaselineStart(date: "2025-12-31", value: d("121834.6")),
            taxParameters: ["it": 2026],
            years: baselineYears.map { year, expected, p10, p25, p50, p75, p90, savings in
                BaselineYear(year: year, expected: d(expected), p10: d(p10), p25: d(p25), p50: d(p50), p75: d(p75),
                             p90: d(p90), savings: savings.map(d))
            })
    }

    /// The copy of the plan the baseline was computed from.
    private static let baselinePlan = """
        {
          "assumptions": {
            "correlations": { "equity": { "bonds": "0.1", "crypto": "0.4", "gold": "0.05" } },
            "inflation": "0.02",
            "returns": {
              "bonds": { "real": "0.01", "volatility": "0.06" },
              "cash": { "real": "0", "volatility": "0.01" },
              "crypto": { "medianReal": "0", "real": "0.16629", "volatility": "0.7" },
              "equity": { "real": "0.045", "volatility": "0.17" },
              "gold": { "real": "0.01", "volatility": "0.15" }
            }
          },
          "contributions": [
            { "account": "fondo-pensione", "perYear": "5000", "until": "retirement" }
          ],
          "endAge": 95,
          "events": [
            { "age": 62, "amount": "150000", "name": "Inheritance", "probability": "0.8" },
            { "amount": "-25000", "name": "New car", "year": 2031 }
          ],
          "id": "base",
          "name": "Base case",
          "pensions": [
            { "fromAge": 67, "name": "State pension", "perYear": "14000" },
            { "fromAge": 67, "name": "State pension from previous country", "perYear": "4800" }
          ],
          "portfolio": { "start": "latest-check-in", "unrealizedGainShare": "0.2" },
          "retirement": { "age": 55 },
          "simulation": { "confidence": "0.9", "runs": 2000, "seed": 1 },
          "spending": {
            "phases": [{ "factor": "0.9", "fromAge": 75 }, { "factor": "0.8", "fromAge": 85 }],
            "retired": "34000",
            "working": "36000"
          },
          "tax": { "investmentRate": "0.26", "wealthAllowance": "5000", "wealthRate": "0.002" },
          "work": [
            { "from": "2026-01-01", "name": "Employee", "netIncome": "40000", "realGrowth": "0.01", "until": "2028-12-31" },
            { "from": "2029-01-01", "name": "Self-employed", "netIncome": "48000", "until": "retirement" }
          ]
        }
        """

    /// The baseline's year-end values: year, expected, p10, p25, p50, p75, p90, savings.
    private static let baselineYears: [(Int, String, String, String, String, String, String, String?)] = [
        (2026, "143490", "133445", "138468", "142485", "148512", "153534", "18000"),
        (2027, "165794", "149382", "157588", "164153", "174001", "182207", "18000"),
        (2028, "188768", "165881", "177325", "186479", "200212", "211655", "18000"),
        (2029, "212431", "182691", "197561", "209457", "227301", "242172", "18000"),
        (2030, "236804", "199738", "218271", "233098", "255337", "273870", "18000"),
        (2031, "261908", "217000", "239454", "257417", "284362", "306816", "18000"),
        (2032, "287766", "234471", "261118", "282436", "314413", "341060", "18000"),
        (2033, "314398", "252151", "283275", "308174", "345522", "376646", "18000"),
        (2034, "341830", "270046", "305938", "334652", "377723", "413615", "18000"),
        (2035, "370085", "288163", "329124", "361893", "411046", "452007", "18000"),
        (2036, "399188", "306511", "352849", "389920", "445526", "491865", "18000"),
        (2037, "429164", "325097", "377130", "418757", "481197", "533230", "18000"),
        (2038, "460038", "343930", "401984", "448428", "518093", "576147", "18000"),
        (2039, "491840", "363019", "427429", "478958", "556250", "620660", "18000"),
        (2040, "524595", "382373", "453484", "510373", "595706", "666817", "18000"),
        (2041, "558333", "401999", "480166", "542699", "636499", "714666", "18000"),
        (2042, "593083", "421909", "507496", "575965", "678670", "764257", "18000"),
        (2043, "574875", "404146", "489510", "557802", "660240", "745604", nil),
        (2044, "556121", "386436", "471279", "539153", "640964", "725807", nil),
        (2045, "536805", "368758", "452782", "520000", "620828", "704852", nil),
        (2046, "516909", "351095", "434002", "500328", "599816", "682723", nil),
        (2047, "496416", "333428", "414922", "480118", "577910", "659404", nil),
        (2048, "475309", "315744", "395526", "459352", "555091", "634874", nil),
        (2049, "453568", "298027", "375797", "438014", "531339", "609110", nil),
        (2050, "581175", "377764", "479470", "560834", "682881", "784587", nil),
        (2051, "562610", "361797", "462204", "542529", "663017", "763424", nil),
        (2052, "553289", "352041", "452665", "533164", "653913", "754537", nil),
        (2053, "543687", "342303", "442995", "523549", "644380", "745072", nil),
        (2054, "533798", "332577", "433187", "513676", "634409", "735019", nil),
        (2055, "528412", "325816", "427114", "508152", "629710", "731008", nil),
        (2056, "522864", "319081", "420973", "502486", "624756", "726647", nil),
        (2057, "517150", "312369", "414760", "496672", "619541", "721931", nil),
        (2058, "511265", "305675", "408470", "490706", "614060", "716854", nil),
        (2059, "505203", "298996", "402099", "484582", "608306", "711410", nil),
        (2060, "498959", "292327", "395643", "478296", "602275", "705590", nil),
        (2061, "492528", "285666", "389097", "471841", "595958", "699389", nil),
        (2062, "485903", "279009", "382456", "465214", "589351", "692798", nil),
        (2063, "479081", "272353", "375717", "458408", "582444", "685808", nil),
        (2064, "472053", "265695", "368874", "451417", "575232", "678411", nil),
        (2065, "464815", "259032", "361923", "444236", "567706", "670597", nil),
        (2066, "457359", "252362", "354861", "436859", "559857", "662356", nil),
        (2067, "449680", "245682", "347681", "429280", "551679", "653678", nil),
        (2068, "441770", "238988", "340379", "421492", "543161", "644552", nil),
        (2069, "433623", "232280", "332952", "413489", "534295", "634966", nil),
        (2070, "425232", "225554", "325393", "405264", "525071", "624910", nil),
        (2071, "416589", "218808", "317698", "396811", "515479", "614370", nil),
        (2072, "407687", "212039", "309863", "388122", "505510", "603334", nil),
        (2073, "398517", "205247", "301882", "379190", "495152", "591788", nil),
        (2074, "389073", "198427", "293750", "370008", "484395", "579718", nil),
        (2075, "379345", "191579", "285462", "360568", "473228", "567111", nil),
        (2076, "369325", "184700", "277012", "350863", "461638", "553951", nil),
        (2077, "359005", "177787", "268396", "340883", "449614", "540222", nil),
        (2078, "348375", "170840", "259608", "330622", "437142", "525910", nil),
        (2079, "337426", "163857", "250641", "320069", "424211", "510996", nil),
        (2080, "326149", "156834", "241492", "309218", "410807", "495464", nil),
        (2081, "314534", "149771", "232152", "298057", "396915", "479296", nil),
        (2082, "302570", "142665", "222617", "286579", "382522", "462474", nil),
        (2083, "290247", "135515", "212881", "274774", "367613", "444978", nil),
    ]

    /// The headline recorded at each check-in of 2026 for `base`: date,
    /// earliest age, FI progress, plan hash, success at the target age,
    /// readiness and the coast age, which only the later records have (as in
    /// the example library).
    private static let headlineRows: [(String, Int, String, String, String, String?, Int?)] = [
        ("2026-01-31", 55, "0.37", "5c1f0a9e", "0.81", nil, nil),
        ("2026-02-28", 55, "0.38", "5c1f0a9e", "0.8", nil, nil),
        ("2026-03-31", 55, "0.37", "5c1f0a9e", "0.78", nil, nil),
        ("2026-04-30", 55, "0.37", "5c1f0a9e", "0.79", nil, nil),
        ("2026-05-31", 55, "0.38", "7d24b6c1", "0.82", nil, nil),
        ("2026-06-30", 54, "0.39", "7d24b6c1", "0.83", nil, 69),
        ("2026-07-31", 54, "0.4", "7d24b6c1", "0.85", nil, 68),
        ("2026-08-31", 54, "0.4", "7d24b6c1", "0.84", "0.24", 67),
        ("2026-09-30", 54, "0.41", "7d24b6c1", "0.86", "0.25", 67),
    ]

    static var headlines: [Headline] {
        headlineRows.map { date, age, progress, hash, success, readiness, coastAge in
            Headline(date: CalendarDate(date)!, coastAge: coastAge, confidence: d("0.9"), earliestAge: age,
                     engine: "0.1.0", fiProgress: d(progress), planHash: hash, readiness: readiness.map(d),
                     successAtTarget: d(success), taxParameters: ["it": 2026])
        }
    }

    // MARK: Building

    static func make() -> Library {
        var library = Library(
            settings: settings, accounts: accounts, instruments: instruments, plans: plans,
            importProfiles: [importProfile],
            projections: ["base": PlanProjections(baselines: ["2026-01-05": baseline], headlines: [2026: HeadlineFile(headlines: headlines)])])
        for (date, vwce, btc, gold) in priceRows {
            let day = CalendarDate(date)!
            library.upsert(PriceRecord(instrument: "btc", date: day, price: d(btc), currency: .usd, source: .coingecko))
            library.upsert(PriceRecord(instrument: "gold", date: day, price: d(gold), currency: .eur, source: .goldAPI))
            library.upsert(PriceRecord(instrument: "vwce", date: day, price: d(vwce), currency: .eur, source: .yahoo))
        }
        for (date, rate, hicp) in rateRows {
            let day = CalendarDate(date)!
            library.upsert(FXRecord(base: .eur, quote: .usd, date: day, rate: d(rate), source: .ecb))
            if let hicp { library.upsert(IndexRecord(index: .hicpIT, date: day, value: d(hicp), source: .eurostat)) }
        }
        for valuation in valuations {
            library.upsert(valuation)
        }
        for trade in trades {
            library.upsert(trade)
        }
        return library
    }

    /// A decimal from its exact text (never through `Double`).
    static func d(_ text: String) -> Decimal {
        guard let value = Decimal(fileString: text) else { preconditionFailure("Bad decimal \(text)") }
        return value
    }

    private static func balance(_ account: AccountID, _ date: String, _ amount: String, flow: String? = nil,
                                note: String? = nil, source: DataSource? = nil) -> Valuation {
        Valuation(account: account, date: CalendarDate(date)!, balance: d(amount), flow: flow.map(d), note: note,
                  source: source)
    }

    private static func holdings(_ account: AccountID, _ date: String, cash: String? = nil, positions: [Position],
                                 flow: String? = nil, note: String? = nil, source: DataSource? = nil) -> Valuation {
        Valuation(account: account, date: CalendarDate(date)!, cash: cash.map(d), positions: positions,
                  flow: flow.map(d), note: note, source: source)
    }

    private static func cash(_ account: AccountID, _ date: String, _ cash: String, flow: String? = nil,
                             source: DataSource? = nil) -> Valuation {
        Valuation(account: account, date: CalendarDate(date)!, cash: d(cash), flow: flow.map(d), source: source)
    }

    private static func deposit(_ date: String, _ id: TradeID, _ amount: String) -> Trade {
        Trade(account: "directa", date: CalendarDate(date)!, id: id, type: .deposit, amount: d(amount))
    }

    private static func buy(_ date: String, _ id: TradeID, _ quantity: String, _ price: String,
                            fees: String = "5") -> Trade {
        Trade(account: "directa", date: CalendarDate(date)!, id: id, type: .buy, instrument: "vwce",
              quantity: d(quantity), price: d(price), fees: d(fees))
    }

    private static func position(_ instrument: InstrumentID, _ quantity: String, cost: String? = nil) -> Position {
        Position(instrument: instrument, quantity: d(quantity), costBasis: cost.map(d))
    }

    private static func decode<T: Decodable>(_ json: String) -> T {
        do {
            return try JSONDecoder().decode(T.self, from: Data(json.utf8))
        } catch {
            preconditionFailure("PreviewLibrary: \(error)")
        }
    }
}
