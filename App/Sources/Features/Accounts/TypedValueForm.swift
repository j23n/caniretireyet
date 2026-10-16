import Foundation
import Model

// Typing an account's balance by hand (UI.md, "Account detail": *Update
// Value…*), for an account that takes typed values
// (`Account.acceptsTypedValues`). Plain values, so they can be checked on
// Linux.

/// The date and balance of *Update Value* and *Edit Value*: a balance only,
/// recorded as typed by hand (`source: manual`), with no money in and out
/// (docs/ACCOUNTS.md, "Typed values").
struct TypedValueForm: Hashable, Sendable {
    let account: AccountID
    /// Whether the account is a debt: its balance is typed as what's owed
    /// and recorded negative (``AmountInput/balance(from:isLiability:locale:)``).
    let isLiability: Bool
    /// The value being edited; `nil` for a new one.
    let original: Valuation?
    var date: CalendarDate
    var balance: String

    /// A new value of `account` on `date`, starting from the balance of
    /// `previous`, its latest value before then, if any.
    init(new account: Account, on date: CalendarDate, previous: Valuation?, locale: Locale = .current) {
        self.account = account.id
        isLiability = account.kind.isLiability
        original = nil
        self.date = date
        balance = previous?.balance.map {
            AmountInput.balanceText(for: $0, isLiability: account.kind.isLiability, locale: locale)
        } ?? ""
    }

    /// The fields of `valuation`, a value of `account` typed earlier.
    init(editing valuation: Valuation, of account: Account, locale: Locale = .current) {
        self.account = account.id
        isLiability = account.kind.isLiability
        original = valuation
        date = valuation.date
        balance = valuation.balance.map {
            AmountInput.balanceText(for: $0, isLiability: account.kind.isLiability, locale: locale)
        } ?? ""
    }

    /// Whether `valuation` of `account` can be edited here: a value typed
    /// by hand, of an account that takes typed values. Imported values
    /// stay as their file wrote them.
    static func canEdit(_ valuation: Valuation, of account: Account) -> Bool {
        account.acceptsTypedValues && valuation.source == .manual && valuation.account == account.id
    }

    /// The latest date a value of `account` can be on: today, or the day
    /// it closed if that's earlier.
    static func latestDate(of account: Account, today: CalendarDate) -> CalendarDate {
        account.closed.map { min($0, today) } ?? today
    }

    /// The date as a `Date` (noon, this device's time zone), for a date picker.
    var dateValue: Date {
        get { date.dateValue }
        set { date = CalendarDate(newValue, in: .current) }
    }

    /// What stops Save, in order: no balance, one that can't be read, or a
    /// date after today or after the account closed.
    func problems(for account: Account, today: CalendarDate, locale: Locale = .current) -> [String] {
        var problems: [String] = []
        switch AmountInput.parse(balance, locale: locale) {
        case .empty: problems.append("Enter the balance. To record nothing owed or held, type 0.")
        case .unreadable: problems.append("The balance can't be read.")
        case .value: break
        }
        if date > today {
            problems.append("Choose a date up to today.")
        } else if let closed = account.closed, date > closed {
            problems.append("Choose a date up to the day the account closed.")
        }
        return problems
    }

    /// The value to save, or `nil` while the balance can't be read: a
    /// balance only. An edited value keeps its note and any keys this
    /// version doesn't know, and drops what it recorded besides the balance
    /// (money in and out, saved, interest, a one-off, tax).
    func valuation(locale: Locale = .current) -> Valuation? {
        guard let amount = AmountInput.balance(from: balance, isLiability: isLiability, locale: locale) else {
            return nil
        }
        var valuation = original ?? Valuation(account: account, date: date)
        valuation.date = date
        valuation.balance = amount
        valuation.cash = nil
        valuation.positions = []
        valuation.saved = nil
        valuation.moneyIn = nil
        valuation.moneyOut = nil
        valuation.oneOff = nil
        valuation.tax = nil
        valuation.interest = nil
        valuation.source = .manual
        return valuation
    }

    /// Whether saving replaces another value of the account already on
    /// the date (not the one being edited).
    func replacesValue(in library: Library) -> Bool {
        library.valuations(for: account).contains { $0.date == date && $0.key != original?.key }
    }
}

/// What saving a typed value does besides writing it, in words.
extension AccountValueNotes {
    /// "Saving moves the opening date from 30 Sep 2026 to 31 Mar 2024.",
    /// when `date` is before the day `account` opened; `nil` otherwise.
    static func openingMove(date: CalendarDate, account: Account, locale: Locale = .current) -> String? {
        guard date < account.opened else { return nil }
        return "Saving moves the opening date from \(AmountFormat.mediumDate(account.opened, locale: locale)) "
            + "to \(AmountFormat.mediumDate(date, locale: locale))."
    }
}
