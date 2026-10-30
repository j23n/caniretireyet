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
    /// ``BrokerageMonth/matchingDays``. Each trade matches one line, over
    /// all the account's months at once, so a deposit near a month's end
    /// isn't matched in both months. Only lines of accounts in the trades
    /// account's currency count: a trade's amount is in its own account's.
    static func depositsToAdd(to account: AccountID, after from: CalendarDate?, through: CalendarDate,
                              ledger: TradeLedger, library: Library) -> [BankLine] {
        guard let currency = library.accounts[account]?.currency else { return [] }
        var moved: [BankLine] = []
        for (id, other) in library.accounts where id != account && other.currency == currency {
            moved += library.lines(for: id).filter { isMove($0, to: account) }
        }
        let dates = moved.map(\.date)
        guard let first = dates.min(), let last = dates.max() else { return [] }
        moved.sort { $0.key < $1.key }
        let days = BrokerageMonth.matchingDays
        let nearby: ArraySlice<TradeEntry> = ledger.entries(after: first.adding(days: -days - 1),
                                                            through: last.adding(days: days))
        var flows: [TradeEntry] = nearby.filter { $0.type == .deposit || $0.type == .withdrawal }
        var unmatched: [BankLine] = []
        for line in moved {
            if let index = flows.firstIndex(where: { matches($0, line, days: days) }) {
                flows.remove(at: index)
            } else if line.date <= through, from.map({ line.date > $0 }) ?? true {
                unmatched.append(line)
            }
        }
        return unmatched
    }

    /// Whether `line` moved money to or from `account`.
    private static func isMove(_ line: BankLine, to account: AccountID) -> Bool {
        line.statementClass == .transfer && line.otherAccount == account && !line.isRemoved
    }

    /// Whether `entry` is the other side of `line`: the same amount the
    /// other way, within `days` days of it.
    private static func matches(_ entry: TradeEntry, _ line: BankLine, days: Int) -> Bool {
        guard let amount = entry.amount, amount == -line.amount else { return false }
        let earliest: CalendarDate = line.date.adding(days: -days)
        let latest: CalendarDate = line.date.adding(days: days)
        return entry.date >= earliest && entry.date <= latest
    }
}

// MARK: - Editing a brokerage month

extension Library {
    /// Records `line`, money moved to or from its other account, as that
    /// account's deposit (money out of `line`'s account) or withdrawal, on
    /// the line's day. Nothing for a line that moved money to no account.
    /// Nothing when the two accounts' currencies differ, since a trade's
    /// amount is in its own account's currency.
    public mutating func addDeposit(for line: BankLine) {
        guard let other = line.otherAccount, line.amount != 0,
              accounts[other]?.currency == accounts[line.account]?.currency else { return }
        upsert(Trade(account: other, date: line.date, type: line.amount < 0 ? .deposit : .withdrawal,
                     amount: -line.amount, source: .manual))
    }

    /// Keeps the deposits that saved lines stand for in step with them
    /// (docs/TRADES.md, "A brokerage month"), so money moved to an account
    /// that records trades counts as saved as soon as the line says so: a
    /// line that now moves money to such an account, and that no deposit
    /// or withdrawal matches, gets one (``addDeposit(for:)``); a line that
    /// no longer moves it there loses the one recorded for it
    /// (``DepositMove/isRecorded(_:)``). Another line that deposit answered,
    /// such as the same move typed by hand, gets one back. A deposit from
    /// the broker's own file that matched the line's has its day and ID, so
    /// it goes too, and comes back when that file is imported again.
    mutating func recordDeposits(changing before: [BankLine], to after: [BankLine]) {
        let saved = Dictionary(after.map { ($0.key, $0) }) { $1 }
        // Each line's own: two lines of one day and amount take two trades.
        var gone: [(account: AccountID, trade: TradeKey)] = []
        for old in before {
            guard let move = depositMove(old), depositMove(saved[old.key]) != move,
                  let trade = trades(for: move.account).first(where: { trade in
                      move.isRecorded(trade) && !gone.contains { $0.trade == trade.key }
                  })
            else { continue }
            gone.append((move.account, trade.key))
        }
        let moves = after.compactMap { line in depositMove(line).map { (line: line, move: $0) } }
        let keys = Set(moves.map { $0.line.key })
        let accounts = Set(moves.map { $0.move.account } + gone.map { $0.account }).sorted()
        // The lines waiting for a deposit already, before any is taken away.
        let firstPass = accounts.map { unmatchedMoves(to: $0) }
        let waiting = Set(firstPass.joined().map { $0.key })
        for removed in gone { removeTradeRecord(removed.trade) }
        for (account, unmatched) in zip(accounts, firstPass) {
            let now = gone.isEmpty ? unmatched : unmatchedMoves(to: account)
            for line in now where keys.contains(line.key) || !waiting.contains(line.key) {
                addDeposit(for: line)
            }
        }
    }

    /// The lines moving money to `account` that no deposit or withdrawal
    /// matches (``Valuator/depositsToAdd(to:after:through:ledger:library:)``), over all its months.
    private func unmatchedMoves(to account: AccountID) -> [BankLine] {
        guard let through = months.keys.max()?.lastDay,
              let ledger = Valuator(library: self).ledger(for: account) else { return [] }
        return Valuator.depositsToAdd(to: account, after: nil, through: through, ledger: ledger, library: self)
    }

    /// The deposit or withdrawal `line` stands for: money it moved to an
    /// account that records trades, in its own account's currency and open
    /// by the line's day. `nil` for any other line.
    private func depositMove(_ line: BankLine?) -> DepositMove? {
        guard let line, !line.isRemoved, line.statementClass == .transfer, line.amount != 0,
              let other = line.otherAccount, let account = accounts[other], account.recordsTrades,
              account.currency == accounts[line.account]?.currency, account.opened <= line.date
        else { return nil }
        return DepositMove(account: other, date: line.date, amount: -line.amount)
    }
}

/// Money a line moved to an account that records trades: a deposit of
/// ``amount``, or a withdrawal when it's below zero.
private struct DepositMove: Hashable {
    var account: AccountID
    var date: CalendarDate
    var amount: Decimal

    var type: TradeType { amount > 0 ? .deposit : .withdrawal }

    /// Whether `trade` is the one recorded for it, on its day, of its
    /// amount: by hand (``Library/addDeposit(for:)``), or by the
    /// statement's import, with the import's stable ID (docs/IMPORT.md,
    /// "Moved to or from an account").
    func isRecorded(_ trade: Trade) -> Bool {
        guard trade.date == date, trade.amount == amount, trade.type == type else { return false }
        if trade.source == .manual { return true }
        guard trade.source == .import else { return false }
        let identity = Trade(account: account, date: date, type: type, amount: amount, source: .import)
        // Moves of the same amount on one day are numbered by the import.
        return (0..<Self.ordinals).contains { TradeID.stable(for: identity, ordinal: $0) == trade.id }
    }

    /// How many moves of one amount on one day ``isRecorded(_:)`` looks for.
    private static let ordinals = 8
}

extension Library {
    /// Sets the cash the broker states for `account` on `date`: the `cash`
    /// of its value on that date; the value's other fields stay.
    public mutating func setBrokerCash(_ cash: Decimal, of account: AccountID, on date: CalendarDate) {
        var value = valuations(for: account).first { $0.date == date }
            ?? Valuation(account: account, date: date, source: .manual)
        value.cash = cash
        upsert(value)
    }
}
