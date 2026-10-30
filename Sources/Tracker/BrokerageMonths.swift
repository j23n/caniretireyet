import Foundation
import Model

/// A trades account's month up to one check-in (docs/TRADES.md, "A
/// brokerage month"): its trades since the check-in before, the cash they
/// lead to from the cash it opened with, the cash the broker states on the
/// check-in's date, and money moved to it from your other accounts'
/// statements that it has no deposit for yet.
public struct BrokerageMonth: Hashable, Sendable, Identifiable {
    /// Where the month stands.
    public enum Status: Hashable, Sendable {
        /// Nothing yet: no trades, and no cash from the broker.
        case notDone
        /// Money moved to it from another account that it has no deposit
        /// for: this many lines.
        case depositsToAdd(Int)
        /// Trades, but not the cash the broker states.
        case needsCash
        /// The broker's cash less the cash the trades lead to: a trade
        /// missing, or one wrong.
        case off(Decimal)
        /// The trades lead to the broker's cash.
        case checked

        /// Whether the month needs nothing more.
        public var isDone: Bool { self == .checked }
    }

    public var id: String { "\(account) \(through)" }

    public var account: AccountID
    /// The check-in before, where the month starts; `nil` before the first.
    public var from: CalendarDate?
    /// The check-in's date.
    public var through: CalendarDate
    /// The trades dated after ``from`` through ``through``, as the ledger applied them.
    public var trades: [TradeEntry]
    /// The cash on ``from`` by the cash rule (docs/TRADES.md, "Cash"); zero
    /// before the first check-in.
    public var openingCash: Decimal
    /// What the month's trades did to the cash.
    public var tradesCash: Decimal
    /// The cash the broker states on ``through``: the `cash` of the
    /// account's value on that date.
    public var statedCash: Decimal?
    /// Lines of your other accounts that moved money to or from this one
    /// in the month with no deposit or withdrawal of that amount within
    /// four days of them.
    public var depositsToAdd: [BankLine]

    public init(account: AccountID, from: CalendarDate?, through: CalendarDate, trades: [TradeEntry],
                openingCash: Decimal, tradesCash: Decimal, statedCash: Decimal?, depositsToAdd: [BankLine]) {
        self.account = account
        self.from = from
        self.through = through
        self.trades = trades
        self.openingCash = openingCash
        self.tradesCash = tradesCash
        self.statedCash = statedCash
        self.depositsToAdd = depositsToAdd
    }

    /// The cash the trades lead to: the opening cash plus what they did to it.
    public var cashFromTrades: Decimal { openingCash + tradesCash }

    /// The broker's cash less the cash the trades lead to; `nil` without the broker's.
    public var difference: Decimal? { statedCash.map { $0 - cashFromTrades } }

    public var status: Status {
        if !depositsToAdd.isEmpty { return .depositsToAdd(depositsToAdd.count) }
        guard let difference else { return trades.isEmpty ? .notDone : .needsCash }
        return difference == 0 ? .checked : .off(difference)
    }
}

extension BrokerageMonth {
    /// How many days apart a statement's line and a deposit can be dated
    /// and still be the same move.
    public static let matchingDays = 4
}

extension Valuator {
    /// The month of the trades account `account` after `from` through
    /// `through` (``BrokerageMonth``), with the lines of `library`'s other
    /// accounts that moved money to it. `nil` for an account that doesn't
    /// record trades.
    public func brokerageMonth(of account: AccountID, after from: CalendarDate?, through: CalendarDate,
                               in library: Library) -> BrokerageMonth? {
        guard let ledger = ledger(for: account) else { return nil }
        let trades = Array(ledger.entries(after: from, through: through))
        let openingCash = from.flatMap { tradeCash(of: account, on: $0) } ?? 0
        let stated = library.valuations(for: account).first { $0.date == through }?.cash
        return BrokerageMonth(account: account, from: from, through: through, trades: trades,
                              openingCash: openingCash, tradesCash: ledger.cashEffect(after: from, through: through),
                              statedCash: stated,
                              depositsToAdd: Self.depositsToAdd(to: account, after: from, through: through,
                                                                ledger: ledger, library: library))
    }

    /// The months of every trades account open after `from` through
    /// `through`, by name.
    public func brokerageMonths(after from: CalendarDate?, through: CalendarDate,
                                in library: Library) -> [BrokerageMonth] {
        accounts.values
            .filter { account in
                account.recordsTrades
                    && account.isOpen(onAnyDayFrom: from?.adding(days: 1) ?? account.opened, through: through)
            }
            .sorted { ($0.name, $0.id) < ($1.name, $1.id) }
            .compactMap { brokerageMonth(of: $0.id, after: from, through: through, in: library) }
    }

    /// The lines of other accounts moved to or from `account` after `from`
    /// through `through` that no deposit or withdrawal of the account
    /// matches: the same amount the other way, within
    /// ``BrokerageMonth/matchingDays``. Each trade matches one line.
    static func depositsToAdd(to account: AccountID, after from: CalendarDate?, through: CalendarDate,
                              ledger: TradeLedger, library: Library) -> [BankLine] {
        let moved = library.accounts.keys.filter { $0 != account }.flatMap { library.lines(for: $0) }
            .filter { line in
                line.statementClass == .transfer && line.otherAccount == account && !line.isRemoved
                    && line.date <= through && (from.map { line.date > $0 } ?? true)
            }
            .sorted { $0.key < $1.key }
        guard !moved.isEmpty else { return [] }
        let days = BrokerageMonth.matchingDays
        var flows = ledger.entries(after: moved[0].date.adding(days: -days - 1),
                                   through: through.adding(days: days))
            .filter { $0.type == .deposit || $0.type == .withdrawal }
        return moved.filter { line in
            let index = flows.firstIndex { entry in
                entry.amount == -line.amount && entry.date >= line.date.adding(days: -days)
                    && entry.date <= line.date.adding(days: days)
            }
            guard let index else { return true }
            flows.remove(at: index)
            return false
        }
    }
}

// MARK: - Editing a brokerage month

extension Library {
    /// Records `line`, money moved to or from its other account, as that
    /// account's deposit (money out of `line`'s account) or withdrawal, on
    /// the line's day. Nothing for a line that moved money to no account.
    public mutating func addDeposit(for line: BankLine) {
        guard let other = line.otherAccount, line.amount != 0 else { return }
        upsert(Trade(account: other, date: line.date, type: line.amount < 0 ? .deposit : .withdrawal,
                     amount: -line.amount, source: .manual))
    }

    /// Sets the cash the broker states for `account` on `date`: the `cash`
    /// of its value on that date; the value's other fields stay.
    public mutating func setBrokerCash(_ cash: Decimal, of account: AccountID, on date: CalendarDate) {
        var value = valuations(for: account).first { $0.date == date }
            ?? Valuation(account: account, date: date, source: .manual)
        value.cash = cash
        upsert(value)
    }
}
