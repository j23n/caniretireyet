import Foundation
import Model
import Tracker

/// One trades account's month to open: the account and the check-in's
/// date (Tracker's `BrokerageMonth`), pushed on the months screen's stack.
struct BrokerageRoute: Hashable, Sendable, Identifiable {
    var account: AccountID
    /// The check-in before, where the month starts, as the months list has it.
    var from: CalendarDate?
    var through: CalendarDate

    var id: String { "\(account) \(through)" }
}

/// The words the brokerage month uses (UI.md, "A brokerage month").
enum BrokerageText {
    /// Where a brokerage month stands, as its row says it: "No trades yet",
    /// "1 deposit to add", "Cash off by 19,75 €", "Cash adds up · 2 trades".
    static func status(_ month: BrokerageMonth, currency: CurrencyCode,
                       locale: Locale = .current) -> AmountSentence {
        switch month.status {
        case .notDone:
            return "No trades yet"
        case .depositsToAdd(let count):
            return "\(Wording.count(count, "deposit")) to add"
        case .needsCash:
            return "\(Wording.count(month.trades.count, "trade")), waiting for the broker's cash"
        case .off(let difference):
            let amount = AmountFormat.amount(abs(difference), currency: currency, precision: .cents, locale: locale)
            return "Cash off by \(amount: amount)"
        case .checked:
            return "Cash adds up · \(Wording.count(month.trades.count, "trade"))"
        }
    }
}

/// A trade being typed in (*Add Trade*): its type, day, instrument and
/// numbers as typed, and the trade it makes.
struct TradeDraft: Hashable, Sendable {
    /// The types a trade typed in can have, in the sheet's order.
    static let types: [TradeType] = [.buy, .sell, .deposit, .withdrawal, .dividend, .interest, .fee, .tax]

    var type: TradeType = .buy
    var date: CalendarDate
    var instrument: InstrumentID?
    var quantity: Decimal?
    var price: Decimal?
    var fees: Decimal?
    /// For a trade without a quantity and price: the amount, positive.
    var amount: Decimal?

    /// Whether the type buys or sells units: it takes a quantity and a price.
    var isSecurity: Bool { type == .buy || type == .sell }

    /// Whether the type needs an instrument: a buy, a sell or a dividend.
    var needsInstrument: Bool { isSecurity || type == .dividend }

    /// What the trade does to the account's cash, when its price is in the
    /// account's currency (`sameCurrency`); `nil` when it can't be worked
    /// out yet.
    func cashEffect(sameCurrency: Bool) -> Decimal? {
        if isSecurity {
            guard sameCurrency, let quantity, let price else { return nil }
            let gross = quantity * price
            return type == .buy ? -(gross + (fees ?? 0)) : gross - (fees ?? 0)
        }
        guard let amount else { return nil }
        return Self.isMoneyOut(type) ? -abs(amount) : abs(amount)
    }

    /// Whether a type without a quantity takes money out of the account.
    static func isMoneyOut(_ type: TradeType) -> Bool {
        type == .withdrawal || type == .fee || type == .tax
    }

    /// The trade it makes in `account`; `nil` while something it needs is
    /// missing.
    func trade(in account: AccountID, id: TradeID = .random()) -> Trade? {
        if needsInstrument, instrument == nil { return nil }
        if isSecurity {
            guard let quantity, quantity > 0, let price, price >= 0 else { return nil }
            return Trade(account: account, date: date, id: id, type: type, instrument: instrument, quantity: quantity,
                         price: price, fees: fees.flatMap { $0 == 0 ? nil : abs($0) }, source: .manual)
        }
        guard let amount, amount != 0 else { return nil }
        return Trade(account: account, date: date, id: id, type: type, instrument: needsInstrument ? instrument : nil,
                     amount: Self.isMoneyOut(type) ? -abs(amount) : abs(amount), source: .manual)
    }
}
