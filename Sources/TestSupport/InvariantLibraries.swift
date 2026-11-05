import Foundation
import Model

/// The libraries the invariant tests run on (layer B of the calculations'
/// checks): the example library, and small made-up households that each
/// add one thing the example library doesn't have. All names and numbers
/// are fake.
///
/// Every small library is ``household``, checked in at each month end from
/// 31 December 2025 through 30 April 2026: a current account (`bank`)
/// paid 4,000 a month that spends 2,000 and pays the mortgage's 800 (500
/// of it principal), 500 a month moved to `savings`, a pension fund the
/// employer pays 300 a month into, and the mortgage, outside plans. Each
/// month saves 2,000 of the 4,300 that came in.
public enum InvariantLibrary: String, CaseIterable, Sendable, CustomStringConvertible {
    /// `Fixtures.exampleLibrary()`.
    case example
    /// The household alone.
    case household
    /// A broker whose first record, a deposit from `bank`, falls between
    /// two check-ins, and savings brought in from outside on 31 March.
    case newAccount
    /// A broker that records trades: an opening, deposits, buys, a
    /// dividend, a sale, a fee, cash recorded mid-January and a residual
    /// on 30 April.
    case trades
    /// A US-dollar current account paid in dollars and a US-dollar broker,
    /// with a rate that moves every month.
    case foreignCurrency
    /// A tax pot outside net worth that `bank` puts 1,000 into every month
    /// and that pays a bill in March, and a tax bill paid from `bank` in
    /// April.
    case taxPot
    /// A car that loses 15% a year, typed again after a repair in March.
    case depreciatingCar
    /// An inheritance of 20,000 into `bank` in February, 15,000 of it
    /// moved to `savings` in March.
    case oneOff

    public var description: String { rawValue }

    /// The library.
    public func library() throws -> Library {
        switch self {
        case .example: try Fixtures.exampleLibrary()
        case .household: Self.household()
        case .newAccount: Self.newAccount()
        case .trades: Self.trades()
        case .foreignCurrency: Self.foreignCurrency()
        case .taxPot: Self.taxPot()
        case .depreciatingCar: Self.depreciatingCar()
        case .oneOff: Self.oneOff()
        }
    }

    /// The small libraries' check-ins.
    public static let monthEnds: [CalendarDate] = ["2025-12-31", "2026-01-31", "2026-02-28", "2026-03-31",
                                                   "2026-04-30"]

    // MARK: - The household

    /// `bank`'s balance at each of ``monthEnds``, before what a variant moves out of it.
    static let bankBalances: [Decimal] = [5000, 5700, 6400, 7100, 7800]

    public static func household() -> Library {
        var library = Library(
            settings: LibrarySettings(baseCurrency: .eur),
            accounts: [
                Account(id: "bank", name: "Bank", kind: .cash, currency: .eur, opened: "2025-01-01"),
                Account(id: "savings", name: "Savings", kind: .savings, currency: .eur, opened: "2025-01-01"),
                Account(id: "pension", name: "Pension", kind: .pensionFund, currency: .eur, opened: "2025-01-01"),
                Account(id: "mortgage", name: "Mortgage", kind: .mortgage, currency: .eur, opened: "2025-01-01",
                        includeIn: IncludeIn(plan: false)),
            ])
        setBank(&library, moved: [0, 0, 0, 0, 0])
        let savings: [(Decimal, Decimal?)] = [(10000, nil), (10510, 10), (11021, 11), (11533, 12), (12046, 13)]
        let pension: [Decimal] = [20000, 20450, 20600, 21100, 21350]
        let mortgage: [Decimal] = [-100_000, -99500, -99000, -98500, -98000]
        for (index, date) in monthEnds.enumerated() {
            let first = index == 0
            library.upsert(Valuation(account: "savings", date: date, balance: savings[index].0,
                                     moneyIn: first ? nil : 0, moneyOut: first ? nil : 0,
                                     interest: savings[index].1))
            library.upsert(Valuation(account: "pension", date: date, balance: pension[index],
                                     saved: first ? nil : 300))
            library.upsert(Valuation(account: "mortgage", date: date, balance: mortgage[index]))
        }
        return library
    }

    /// Writes `bank`'s values: ``bankBalances`` less what `moved` takes out
    /// of it by each month end, added up (more moved to the variant's
    /// accounts), with pay of 4,000 and money out of 2,800 a month plus
    /// `extraOut`.
    static func setBank(_ library: inout Library, moved: [Decimal], extraOut: [Decimal] = [0, 0, 0, 0, 0],
                        oneOffs: [Decimal] = [0, 0, 0, 0, 0], tax: [Decimal] = [0, 0, 0, 0, 0]) {
        var takenOut: Decimal = 0
        var paidOut: Decimal = 0
        var inherited: Decimal = 0
        for (index, date) in monthEnds.enumerated() {
            takenOut += moved[index]
            paidOut += extraOut[index]
            inherited += oneOffs[index]
            let balance = bankBalances[index] - takenOut - paidOut + inherited
            if index == 0 {
                library.upsert(Valuation(account: "bank", date: date, balance: balance))
            } else {
                library.upsert(Valuation(account: "bank", date: date, balance: balance, moneyIn: 4000,
                                         moneyOut: 2800 + extraOut[index],
                                         oneOff: oneOffs[index] == 0 ? nil : oneOffs[index],
                                         tax: tax[index] == 0 ? nil : tax[index]))
            }
        }
    }

    static let fund = Instrument(id: "fund", name: "World fund", kind: .etf, currency: .eur, unit: .share,
                                 assetClasses: .single(.equity))

    static func price(_ library: inout Library, _ instrument: InstrumentID, _ prices: [(CalendarDate, Decimal)],
                      currency: CurrencyCode = .eur) {
        for (date, price) in prices {
            library.upsert(PriceRecord(instrument: instrument, date: date, price: price, currency: currency))
        }
    }

    // MARK: - The variants

    static func newAccount() -> Library {
        var library = household()
        library.accounts["broker"] = Account(id: "broker", name: "Broker", kind: .brokerage, currency: .eur,
                                             opened: "2026-02-01", valuation: .trades)
        library.instruments["fund"] = fund
        setBank(&library, moved: [0, 0, 1000, 0, 0])
        library.upsert(Trade(account: "broker", date: "2026-02-10", id: "dep-feb", type: .deposit, amount: 1000))
        library.upsert(Trade(account: "broker", date: "2026-02-12", id: "buy-feb", type: .buy, instrument: "fund",
                             quantity: 8, price: 100))
        price(&library, "fund", [("2026-02-12", 100), ("2026-02-28", 102), ("2026-03-31", 105), ("2026-04-30", 103)])
        library.accounts["old-savings"] = Account(id: "old-savings", name: "Old savings", kind: .savings,
                                                  currency: .eur, opened: "2026-03-01")
        library.upsert(Valuation(account: "old-savings", date: "2026-03-31", balance: 5000))
        library.upsert(Valuation(account: "old-savings", date: "2026-04-30", balance: 5010, moneyIn: 0,
                                 moneyOut: 0, interest: 10))
        return library
    }

    static func trades() -> Library {
        var library = household()
        library.accounts["broker"] = Account(id: "broker", name: "Broker", kind: .brokerage, currency: .eur,
                                             opened: "2025-06-01", valuation: .trades)
        library.instruments["fund"] = fund
        setBank(&library, moved: [0, 500, 500, 500, 500])
        let trades = [
            Trade(account: "broker", date: "2025-12-31", id: "open", type: .opening, instrument: "fund",
                  quantity: 10, cost: 900),
            Trade(account: "broker", date: "2026-01-05", id: "dep-jan", type: .deposit, amount: 500),
            Trade(account: "broker", date: "2026-01-10", id: "buy-jan", type: .buy, instrument: "fund", quantity: 4,
                  price: 101, fees: 2),
            Trade(account: "broker", date: "2026-02-05", id: "dep-feb", type: .deposit, amount: 500),
            Trade(account: "broker", date: "2026-02-12", id: "buy-feb", type: .buy, instrument: "fund", quantity: 5,
                  price: 99, fees: 2),
            Trade(account: "broker", date: "2026-03-05", id: "dep-mar", type: .deposit, amount: 500),
            Trade(account: "broker", date: "2026-03-15", id: "div-mar", type: .dividend, instrument: "fund",
                  amount: Decimal(string: "14.8"), tax: Decimal(string: "5.2")),
            Trade(account: "broker", date: "2026-03-20", id: "sell-mar", type: .sell, instrument: "fund",
                  quantity: 6, price: 106, fees: 2, tax: 3),
            Trade(account: "broker", date: "2026-04-05", id: "dep-apr", type: .deposit, amount: 500),
            Trade(account: "broker", date: "2026-04-08", id: "fee-apr", type: .fee, fees: 5),
        ]
        for trade in trades { library.upsert(trade) }
        library.upsert(Valuation(account: "broker", date: "2025-12-31", cash: 1000))
        // Mid-January, the broker's cash, as its trades give it: a check-in of the broker alone.
        library.upsert(Valuation(account: "broker", date: "2026-01-15", cash: 1094))
        // The trades give 2,737.80: 3.10 came in that no trade recorded.
        library.upsert(Valuation(account: "broker", date: "2026-04-30", cash: Decimal(string: "2740.9")))
        price(&library, "fund", [("2025-12-31", 90), ("2026-01-10", 101), ("2026-01-15", 100), ("2026-01-31", 102),
                                 ("2026-02-12", 99), ("2026-02-28", 103), ("2026-03-20", 106), ("2026-03-31", 107),
                                 ("2026-04-30", 104)])
        return library
    }

    static func foreignCurrency() -> Library {
        var library = household()
        library.accounts["usd-bank"] = Account(id: "usd-bank", name: "US bank", kind: .cash, currency: .usd,
                                               opened: "2025-01-01")
        library.accounts["usd-broker"] = Account(id: "usd-broker", name: "US broker", kind: .brokerage,
                                                 currency: .usd, opened: "2025-01-01", valuation: .trades)
        library.instruments["spy"] = Instrument(id: "spy", name: "US fund", kind: .etf, currency: .usd, unit: .share,
                                                assetClasses: .single(.equity))
        let rates: [Decimal] = [d("1.08"), d("1.1"), d("1.07"), d("1.12"), d("1.09")]
        let buys: [(CalendarDate, Decimal)] = [("2026-01-10", 121), ("2026-02-10", 118), ("2026-03-10", 125),
                                              ("2026-04-10", 124)]
        for (index, date) in monthEnds.enumerated() {
            library.upsert(FXRecord(base: .eur, quote: .usd, date: date, rate: rates[index]))
            if index == 0 {
                library.upsert(Valuation(account: "usd-bank", date: date, balance: 2000))
                library.upsert(Valuation(account: "usd-broker", date: date, cash: 0))
                continue
            }
            library.upsert(Valuation(account: "usd-bank", date: date, balance: 2000 + 300 * Decimal(index),
                                     moneyIn: 1000, moneyOut: 200))
            let month = date.yearMonth
            library.upsert(Trade(account: "usd-broker", date: month.firstDay.adding(days: 2), id: TradeID("dep-\(index)"),
                                 type: .deposit, amount: 500))
            let buy = buys[index - 1]
            library.upsert(Trade(account: "usd-broker", date: buy.0, id: TradeID("buy-\(index)"), type: .buy,
                                 instrument: "spy", quantity: 4, price: buy.1))
        }
        price(&library, "spy", [("2025-12-31", 120), ("2026-01-31", 123), ("2026-02-28", 119), ("2026-03-31", 126),
                                ("2026-04-30", 128)] + buys, currency: .usd)
        return library
    }

    static func taxPot() -> Library {
        var library = household()
        library.accounts["pot"] = Account(id: "pot", name: "Taxes", kind: .taxPot, currency: .eur,
                                          opened: "2025-01-01")
        setBank(&library, moved: [0, 1000, 1000, 1000, 1000], extraOut: [0, 0, 0, 0, 1200], tax: [0, 0, 0, 0, 1200])
        let pot: [(Decimal, Decimal)] = [(2000, 0), (3000, 0), (4000, 0), (500, 4500), (1500, 0)]
        for (index, date) in monthEnds.enumerated() {
            let first = index == 0
            library.upsert(Valuation(account: "pot", date: date, balance: pot[index].0, moneyIn: first ? nil : 0,
                                     moneyOut: first ? nil : pot[index].1))
        }
        return library
    }

    static func depreciatingCar() -> Library {
        var library = household()
        library.accounts["car"] = Account(id: "car", name: "Car", kind: .belongings, currency: .eur,
                                          opened: "2025-01-01", depreciation: d("0.15"))
        // A repair of 240 in March, paid from the bank.
        setBank(&library, moved: [0, 0, 0, 0, 0], extraOut: [0, 0, 0, 240, 0])
        library.upsert(Valuation(account: "car", date: "2025-12-31", balance: 20000))
        library.upsert(Valuation(account: "car", date: "2026-03-31", balance: 19500))
        return library
    }

    static func oneOff() -> Library {
        var library = household()
        setBank(&library, moved: [0, 0, 0, 15000, 0], oneOffs: [0, 0, 20000, 0, 0])
        library.upsert(Valuation(account: "savings", date: "2026-03-31", balance: 26533, moneyIn: 0, moneyOut: 0,
                                 interest: 12))
        library.upsert(Valuation(account: "savings", date: "2026-04-30", balance: 27046, moneyIn: 0, moneyOut: 0,
                                 interest: 13))
        return library
    }
}

// MARK: - Variants of a library

extension InvariantLibrary {
    /// `library` with nothing unknown that a value can leave unknown: every
    /// value after an account's first, of an account that asks for what it
    /// saved (``Model/Account/asksForSaved``) and without it, saved 0, so
    /// its change is markets. Prices and rates are left as they are.
    public static func everythingKnown(_ library: Library) -> Library {
        var library = library
        var seen: Set<AccountID> = []
        for month in library.months.keys.sorted() {
            guard var file = library.months[month] else { continue }
            file.valuations = file.valuations.sortedByKey()
            for index in file.valuations.indices {
                let valuation = file.valuations[index]
                let isFirst = seen.insert(valuation.account).inserted
                guard !isFirst, valuation.saved == nil,
                      library.accounts[valuation.account]?.asksForSaved ?? false else { continue }
                file.valuations[index].saved = 0
            }
            library.months[month] = file
        }
        return library
    }

    /// `library` with every amount of money `factor` times as large:
    /// values, what they saved, money in and out, one-offs, tax, interest,
    /// purchase costs, trades' prices, amounts, fees, taxes and costs, and
    /// prices. Quantities, rates and dates stay.
    public static func scaled(_ library: Library, by factor: Decimal) -> Library {
        func times(_ amount: Decimal?) -> Decimal? { amount.map { $0 * factor } }
        var library = library
        for (month, file) in library.months {
            var file = file
            file.valuations = file.valuations.map { valuation in
                var valuation = valuation
                valuation.balance = times(valuation.balance)
                valuation.cash = times(valuation.cash)
                valuation.positions = valuation.positions.map { position in
                    Position(instrument: position.instrument, quantity: position.quantity,
                             costBasis: times(position.costBasis))
                }
                valuation.saved = times(valuation.saved)
                valuation.moneyIn = times(valuation.moneyIn)
                valuation.moneyOut = times(valuation.moneyOut)
                valuation.oneOff = times(valuation.oneOff)
                valuation.tax = times(valuation.tax)
                valuation.interest = times(valuation.interest)
                return valuation
            }
            file.trades = file.trades.map { trade in
                var trade = trade
                trade.price = times(trade.price)
                trade.amount = times(trade.amount)
                trade.fees = times(trade.fees)
                trade.tax = times(trade.tax)
                trade.cost = times(trade.cost)
                return trade
            }
            file.prices = file.prices.map { price in
                var price = price
                price.price *= factor
                return price
            }
            library.months[month] = file
        }
        return library
    }

    /// `library` with every exchange rate between the euro and the US
    /// dollar set to `rate` (1 EUR = `rate` USD), one more on the day of
    /// its first record, and `base` as its base currency.
    public static func constantDollar(_ library: Library, rate: Decimal, base: CurrencyCode) -> Library {
        var library = library
        library.settings.baseCurrency = base
        var first: CalendarDate?
        for (month, file) in library.months {
            var file = file
            file.fx = file.fx.map { record in
                var record = record
                if Set([record.base, record.quote]) == [.eur, .usd] {
                    record = FXRecord(base: .eur, quote: .usd, date: record.date, rate: rate, source: record.source)
                }
                return record
            }
            library.months[month] = file
            let dates = file.valuations.map(\.date) + file.trades.map(\.date) + file.prices.map(\.date)
            if let earliest = dates.min() { first = min(first ?? earliest, earliest) }
        }
        if let first { library.upsert(FXRecord(base: .eur, quote: .usd, date: first, rate: rate)) }
        return library
    }
}
