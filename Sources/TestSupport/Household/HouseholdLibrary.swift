import Foundation
import Model

/// What a simulated household's person gives the app, as a `Library`.
extension Household {
    /// The household's accounts, made up.
    public var accountRecords: [Account] {
        typealias A = HouseholdAccount
        var accounts = [
            Account(id: A.current, name: "Everyday Account", kind: .cash, currency: .eur, opened: start,
                    institution: "Harbor Bank"),
            Account(id: A.savings, name: "Rainy Day Savings", kind: .savings, currency: .eur, opened: start,
                    institution: "Harbor Bank"),
            Account(id: A.card, name: "Harbor Visa", kind: .creditCard, currency: .eur, opened: start,
                    institution: "Harbor Bank"),
            Account(id: A.broker, name: "Lighthouse Invest", kind: .brokerage, currency: .eur, opened: start,
                    institution: "Lighthouse", valuation: .trades),
            Account(id: A.pension, name: "Acme Pension Plan", kind: .pensionFund, currency: .eur, opened: start,
                    institution: "Acme Pensions"),
            Account(id: A.mortgage, name: "Home Mortgage", kind: .mortgage, currency: .eur, opened: start,
                    institution: "Harbor Bank"),
        ]
        if hasCar {
            accounts.append(Account(id: A.car, name: "Car", kind: .belongings, currency: .eur, opened: start))
        }
        if let onlineOpened {
            accounts.append(Account(id: A.online, name: "Online Saver", kind: .savings, currency: .eur,
                                    opened: onlineOpened, institution: "Tidewater Bank"))
        }
        return accounts
    }

    /// The instruments the broker can hold.
    public var instrumentRecords: [Instrument] {
        [Instrument(id: HouseholdAccount.etf, name: "World Equity ETF", kind: .etf, currency: .eur, unit: .share,
                    assetClasses: .single(.equity), ticker: "WEQ"),
         Instrument(id: HouseholdAccount.stock, name: "Example Corp", kind: .stock, currency: .usd, unit: .share,
                    assetClasses: .single(.equity), ticker: "EXC")]
            .filter { instruments.contains($0.id) }
    }

    /// What a careful person gives the app: every account's value at each
    /// check-in, the cash and savings accounts' with their money in and out
    /// as their lines' classes say, the pension's with what was paid in
    /// (``HouseholdRecords`` says which values leave it out), the broker's
    /// cash and positions as its statement says them; every trade; and the
    /// prices and rates of the first check-in, every month end and every
    /// trade's day. With `statementValues` false, the cash and savings
    /// accounts have only their first values, for their statements to fill
    /// in (``statementCSV(of:)``).
    public func library(statementValues: Bool = true) -> Library {
        typealias A = HouseholdAccount
        var library = Library(settings: LibrarySettings(baseCurrency: .eur), accounts: accountRecords,
                              instruments: instrumentRecords)
        let truth = truth
        var previous: [AccountID: CalendarDate] = [:]
        for date in checkIns {
            for account in accounts where account != A.online || onlineOpened.map({ $0 <= date }) == true {
                defer { previous[account] = date }
                let statement = HouseholdState.hasStatement(account)
                if statement, !statementValues, previous[account] != nil { continue }
                var value = Valuation(account: account, date: date, source: .import)
                if account == A.broker {
                    value.cash = truth.brokerCash(on: date)
                    value.positions = truth.holdings(on: date).sorted { $0.key < $1.key }
                        .map { Position(instrument: $0.key, quantity: $0.value) }
                } else {
                    value.balance = truth.value(of: account, on: date)
                }
                if let before = previous[account] {
                    if statement {
                        let money = truth.moneyInOut(of: account, after: before, through: date)
                        value.moneyIn = money.moneyIn
                        value.moneyOut = money.moneyOut
                        value.oneOff = money.oneOff == 0 ? nil : money.oneOff
                        value.tax = money.tax == 0 ? nil : money.tax
                        value.interest = money.interest == 0 ? nil : money.interest
                    }
                    if account == A.pension {
                        if records.pensionWithoutSaved.contains(date) {
                            value.source = .manual
                        } else {
                            value.saved = truth.totals(after: before, through: date).pension
                        }
                    }
                }
                if account == A.car { value.source = .manual }
                library.upsert(value)
            }
        }
        for trade in trades { library.upsert(trade) }
        var dates = Set([start] + monthEnds)
        for trade in trades { dates.insert(trade.date) }
        for date in dates {
            for instrument in instruments {
                library.upsert(PriceRecord(instrument: instrument, date: date,
                                           price: markets.price(of: instrument, on: date),
                                           currency: HouseholdMarkets.currency(of: instrument)))
            }
            if hasStock {
                library.upsert(FXRecord(base: .eur, quote: .usd, date: date, rate: markets.rate(on: date)))
            }
        }
        return library
    }

    /// The broker's trades: an opening for each holding on the first
    /// check-in, then the deposits, buys, sales and dividends, each with
    /// what the broker charged or paid.
    public var trades: [Trade] {
        typealias A = HouseholdAccount
        var trades = opening.holdings.keys.sorted().compactMap { instrument in
            opening.holdings[instrument].map {
                Trade(account: A.broker, date: start, id: TradeID(rawValue: "opening-\(instrument)"), type: .opening,
                      instrument: instrument, quantity: $0.quantity, cost: $0.cost)
            }
        }
        for event in events {
            let id = TradeID(rawValue: "e\(event.id)")
            switch event.kind {
            case .deposit(let amount):
                trades.append(Trade(account: A.broker, date: event.date, id: id, type: .deposit, amount: amount))
            case .buy(let instrument, let quantity, let price, let amount, let fees):
                trades.append(Trade(account: A.broker, date: event.date, id: id, type: .buy, instrument: instrument,
                                    quantity: quantity, price: price, amount: -amount, fees: fees))
            case .sell(let instrument, let quantity, let price, let amount, let fees):
                trades.append(Trade(account: A.broker, date: event.date, id: id, type: .sell, instrument: instrument,
                                    quantity: quantity, price: price, amount: amount, fees: fees))
            case .dividend(let instrument, let amount):
                trades.append(Trade(account: A.broker, date: event.date, id: id, type: .dividend,
                                    instrument: instrument, amount: amount))
            default:
                break
            }
        }
        return trades
    }
}
