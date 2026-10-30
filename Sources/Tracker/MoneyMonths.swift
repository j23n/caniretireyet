import Foundation
import Model

/// One account's money in and out up to one check-in (docs/IMPORT.md,
/// "Your months"): the balance it opens at, its bank lines since its value
/// before, the value on the check-in's date, and whether it's done. Cash
/// and savings accounts and tax pots have one at each check-in.
public struct AccountMonth: Hashable, Sendable, Identifiable {
    /// Where the account's month stands.
    public enum Status: Hashable, Sendable {
        /// Nothing yet: no value on the date, and no lines.
        case notDone
        /// Lines, but no balance on the date to check them against.
        case needsBalance
        /// Money in and out typed with the value, without lines.
        case typed
        /// A balance without money in and out or lines.
        case balanceOnly
        /// The lines don't lead to the balance: the balance less what they
        /// lead to.
        case off(Decimal)
        /// The lines add up, and this many are still suggestions.
        case toCheck(Int)
        /// The lines add up, and every one is confirmed.
        case checked
        /// The account's first month: lines and a closing balance, but no
        /// balance before to check them against; this many lines are still
        /// suggestions.
        case firstMonth(Int)

        /// Whether the month needs nothing more: it adds up and every line
        /// is confirmed, or it has typed totals or a balance alone.
        public var isDone: Bool {
            switch self {
            case .typed, .balanceOnly, .checked: true
            case .firstMonth(let toCheck): toCheck == 0
            case .notDone, .needsBalance, .off, .toCheck: false
            }
        }
    }

    /// The account and the check-in's date.
    public var id: String { "\(account) \(through)" }

    public var account: AccountID
    /// The date of the account's value before, the balance it opens at;
    /// `nil` before its first.
    public var from: CalendarDate?
    /// The check-in's date.
    public var through: CalendarDate
    /// The account's value on ``through``, if it has one.
    public var value: Valuation?
    /// Its lines and whether they add up.
    public var stretch: LineStretch

    public init(account: AccountID, from: CalendarDate?, through: CalendarDate, value: Valuation?,
                stretch: LineStretch) {
        self.account = account
        self.from = from
        self.through = through
        self.value = value
        self.stretch = stretch
    }

    /// The balance it opens at: the value before's.
    public var opening: Decimal? { stretch.opening }

    /// The balance on ``through``: the bank's.
    public var closing: Decimal? { stretch.closing }

    /// Its lines, removed ones too, sorted by key.
    public var lines: [BankLine] { stretch.lines }

    /// The lines still suggestions: not confirmed, and not removed.
    public var linesToCheck: Int { lines.filter { !$0.isConfirmed && !$0.isRemoved }.count }

    /// Where it stands.
    public var status: Status {
        guard !lines.isEmpty else {
            guard let value else { return .notDone }
            return value.hasMoneyInOut ? .typed : .balanceOnly
        }
        guard let difference = stretch.difference else {
            return opening == nil && closing != nil ? .firstMonth(linesToCheck) : .needsBalance
        }
        guard difference == 0 else { return .off(difference) }
        let toCheck = linesToCheck
        return toCheck == 0 ? .checked : .toCheck(toCheck)
    }
}

/// The money in and out of every cash and savings account and tax pot up
/// to one check-in (docs/IMPORT.md, "Your months"), or up to the next one
/// while it's still to come.
public struct MoneyMonth: Hashable, Sendable, Identifiable {
    public var id: CalendarDate { through }

    /// The check-in before, if there is one.
    public var from: CalendarDate?
    /// The check-in's date.
    public var through: CalendarDate
    /// Whether an account has a value on ``through``; otherwise it's the
    /// check-in still to come.
    public var isCheckedIn: Bool
    /// Each account's month, by name.
    public var accounts: [AccountMonth]

    public init(from: CalendarDate?, through: CalendarDate, isCheckedIn: Bool, accounts: [AccountMonth]) {
        self.from = from
        self.through = through
        self.isCheckedIn = isCheckedIn
        self.accounts = accounts
    }

    /// The accounts whose month isn't done.
    public var toDo: [AccountMonth] { accounts.filter { !$0.status.isDone } }
}

extension Library {
    /// The accounts with months (``AccountMonth``): those that record money
    /// in and out, with a balance, open on a day after `from` through
    /// `through`, by name.
    public func moneyMonthAccounts(after from: CalendarDate?, through: CalendarDate) -> [Account] {
        accounts.values
            .filter { account in
                account.kind.recordsMoneyInOut && account.valuationMode == .balance
                    && account.isOpen(onAnyDayFrom: from?.adding(days: 1) ?? account.opened, through: through)
            }
            .sorted { ($0.name, $0.id) < ($1.name, $1.id) }
    }

    /// Every check-in of the accounts with months, newest first, each with
    /// those accounts' months (``MoneyMonth``). With `next`, the check-in
    /// still to come on that date comes first, when it's after the last.
    /// With `limit`, only that many of the newest.
    public func moneyMonths(next: CalendarDate? = nil, limit: Int? = nil) -> [MoneyMonth] {
        let money = accounts.values.filter { $0.kind.recordsMoneyInOut && $0.valuationMode == .balance }
        let dates = Set(money.flatMap { valuations(for: $0.id).map(\.date) }).sorted()
        var ends = dates.map { (date: $0, isCheckedIn: true) }
        if let next, dates.last.map({ next > $0 }) ?? true { ends.append((next, false)) }
        let first = limit.map { max(ends.count - $0, 0) } ?? 0
        return ends.indices.dropFirst(first).reversed().map { index in
            let previous = index > 0 ? ends[index - 1].date : nil
            let end = ends[index]
            let accountMonths = moneyMonthAccounts(after: previous, through: end.date).compactMap {
                accountMonth(of: $0.id, through: end.date)
            }
            return MoneyMonth(from: previous, through: end.date, isCheckedIn: end.isCheckedIn, accounts: accountMonths)
        }
    }

    /// How many check-ins ``moneyMonths(next:limit:)`` lists without a limit.
    public func moneyMonthCount(next: CalendarDate? = nil) -> Int {
        let money = accounts.values.filter { $0.kind.recordsMoneyInOut && $0.valuationMode == .balance }
        let dates = Set(money.flatMap { valuations(for: $0.id).map(\.date) })
        guard let next else { return dates.count }
        return dates.count + (dates.max().map { next > $0 } ?? true ? 1 : 0)
    }

    /// An account's month up to `through` (``AccountMonth``): its lines
    /// after its value before through that date. `nil` for an account
    /// that isn't in the library.
    public func accountMonth(of account: AccountID, through date: CalendarDate) -> AccountMonth? {
        guard let details = accounts[account] else { return nil }
        let values = valuations(for: account)
        let previous = values.last { $0.date < date }
        let value = values.first { $0.date == date }
        let inside = lines(for: account).filter { line in
            line.date <= date && (previous.map { line.date > $0.date } ?? true)
        }
        let recordsInterest = details.kind.recordsInterest
        let amounts = inside.reduce(LineAmounts()) { $0 + $1.amounts(recordsInterest: recordsInterest) }
        let stretch = LineStretch(account: account, from: previous?.date, through: date,
                                  opening: previous?.amountForLines, closing: value?.amountForLines,
                                  lines: inside, amounts: amounts)
        return AccountMonth(account: account, from: previous?.date, through: date, value: value, stretch: stretch)
    }

    /// An account's months after `date`, oldest first: one at each of its
    /// later values, then the lines after its last, up to `next` when given.
    /// A change to a month's lines or balance shows here, since each opens
    /// at the balance before.
    public func accountMonths(of account: AccountID, after date: CalendarDate,
                              next: CalendarDate? = nil) -> [AccountMonth] {
        var ends = valuations(for: account).map(\.date).filter { $0 > date }
        if let next, next > ends.last ?? date { ends.append(next) }
        return ends.compactMap { accountMonth(of: account, through: $0) }
    }
}


// MARK: - Editing a month

extension Library {
    /// Saves changed or new bank lines, then writes the money in and out
    /// of their accounts' values from them again (``countLines(of:)``), and
    /// keeps the deposits of money they move to an account that records
    /// trades in step with them (``recordDeposits(changing:to:)``).
    public mutating func save(_ lines: [BankLine]) {
        let before = lines.compactMap { line($0.key) }
        lines.forEach { upsert($0) }
        for account in Set(lines.map(\.account)) { countLines(of: account) }
        recordDeposits(changing: before, to: lines)
    }

    /// Sets the balance the bank shows for `account` on `date`, the end of
    /// a month whose lines are checked against it; a value already on that
    /// date keeps its other fields. Then the account's money in and out
    /// are written from its lines again, so the month's lines count into
    /// it once they add up.
    public mutating func setBankBalance(_ balance: Decimal, of account: AccountID, on date: CalendarDate) {
        var value = valuations(for: account).first { $0.date == date }
            ?? Valuation(account: account, date: date, source: .manual)
        value.balance = balance
        upsert(value)
        countLines(of: account)
    }

    /// Saves a month's totals typed without lines (docs/IMPORT.md, "Typed
    /// totals"): the bank's balance on `date`, with what came in, what was
    /// spent and the tax paid. What moved between your accounts is the
    /// rest, so it isn't stored. Other fields of a value already on that
    /// date stay.
    public mutating func saveTypedTotals(of account: AccountID, on date: CalendarDate, balance: Decimal,
                                         cameIn: Decimal, spent: Decimal, tax: Decimal) {
        var value = valuations(for: account).first { $0.date == date }
            ?? Valuation(account: account, date: date, source: .manual)
        value.balance = balance
        value.moneyIn = cameIn
        value.moneyOut = spent + tax
        value.tax = tax != 0 && accounts[account]?.kind != .taxPot ? tax : nil
        upsert(value)
    }
}
