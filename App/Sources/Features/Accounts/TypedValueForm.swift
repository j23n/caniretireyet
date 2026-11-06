import Foundation
import Model

// Typing an account's balance, and what moved, by hand (UI.md, "Account
// detail": *Update Value…*), for an account that takes typed values
// (`Account.acceptsTypedValues`). Plain values, so they can be checked on
// Linux.

/// What a typed value of an account records besides its balance, at every
/// value after the account's first (docs/ACCOUNTS.md, "Typed values").
enum TypedWhatMoved: Hashable, Sendable {
    /// A balance only: belongings, debts, and starting estimates, whose
    /// round amount is corrected rather than added to.
    case nothing
    /// What was added since the value before (`saved`): investments,
    /// pensions, property and other accounts (`Account.typedValuesRecordSaved`).
    case added
    /// What came in, what went out and the interest (`moneyIn`, `moneyOut`,
    /// `interest`): savings (`Account.typedValuesRecordMoneyInOut`).
    case moneyInOut

    init(_ account: Account) {
        if account.isStartingEstimate {
            self = .nothing
        } else if account.typedValuesRecordMoneyInOut {
            self = .moneyInOut
        } else if account.typedValuesRecordSaved {
            self = .added
        } else {
            self = .nothing
        }
    }
}

/// The fields of *Update Value* and *Edit Value*: the date, the balance and,
/// after the account's first value, what moved since the value before
/// (``TypedWhatMoved``), every one required, 0 when nothing moved; recorded
/// as typed by hand (`source: manual`) (docs/ACCOUNTS.md, "Typed values").
struct TypedValueForm: Hashable, Sendable {
    let account: AccountID
    /// Whether the account is a debt: its balance is typed as what's owed
    /// and recorded negative (``AmountInput/balance(from:isLiability:locale:)``).
    let isLiability: Bool
    /// What the account's typed values record besides the balance.
    let whatMoved: TypedWhatMoved
    /// "Paid in" for a pension fund or TFR, "You added" otherwise: the
    /// label of ``added``.
    let addedLabel: String
    /// The earliest date of the account's other values (not the one being
    /// edited); `nil` without any. A value after it isn't the first.
    let firstOtherValue: CalendarDate?
    /// The value being edited; `nil` for a new one.
    let original: Valuation?
    var date: CalendarDate
    var balance: String
    /// What was added since the value before (``TypedWhatMoved/added``).
    var added = ""
    /// What came in and went out since the value before, and the interest
    /// (``TypedWhatMoved/moneyInOut``).
    var cameIn = ""
    var wentOut = ""
    var interest = ""

    /// A new value of `account` on `date`, starting from the balance of
    /// `previous`, its latest value before then, if any.
    /// `firstValue` is the date of the account's first value, if it has one.
    init(new account: Account, on date: CalendarDate, previous: Valuation?, firstValue: CalendarDate?,
         locale: Locale = .current) {
        self.account = account.id
        isLiability = account.kind.isLiability
        whatMoved = TypedWhatMoved(account)
        addedLabel = Self.addedLabel(for: account)
        firstOtherValue = firstValue
        original = nil
        self.date = date
        balance = previous?.balance.map {
            AmountInput.balanceText(for: $0, isLiability: account.kind.isLiability, locale: locale)
        } ?? ""
    }

    /// The fields of `valuation`, a value of `account` typed earlier;
    /// `firstOtherValue` is the date of the account's first other value.
    init(editing valuation: Valuation, of account: Account, firstOtherValue: CalendarDate?,
         locale: Locale = .current) {
        self.account = account.id
        isLiability = account.kind.isLiability
        whatMoved = TypedWhatMoved(account)
        addedLabel = Self.addedLabel(for: account)
        self.firstOtherValue = firstOtherValue
        original = valuation
        date = valuation.date
        balance = valuation.balance.map {
            AmountInput.balanceText(for: $0, isLiability: account.kind.isLiability, locale: locale)
        } ?? ""
        func text(_ amount: Decimal?) -> String { amount.map { AmountInput.text(for: $0, locale: locale) } ?? "" }
        added = text(valuation.saved)
        cameIn = text(valuation.moneyIn)
        wentOut = text(valuation.moneyOut)
        interest = text(valuation.interest)
    }

    /// The date of the first of `account`'s values in `library` other than
    /// the one with `key`, for ``firstOtherValue``.
    static func firstValue(of account: AccountID, in library: Library, besides key: ValuationKey? = nil)
        -> CalendarDate? {
        library.valuations(for: account).first { $0.key != key }?.date
    }

    private static func addedLabel(for account: Account) -> String {
        account.kind == .pensionFund || account.kind == .tfr ? "Paid in" : "You added"
    }

    /// Whether the value asks for what moved: an account whose typed values
    /// record it, on a date after its first other value.
    var asksWhatMoved: Bool {
        whatMoved != .nothing && (firstOtherValue.map { $0 < date } ?? false)
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

    /// Whether what moved is asked for and a field of it is still empty.
    func isMissingWhatMoved(locale: Locale = .current) -> Bool {
        guard asksWhatMoved else { return false }
        let fields = whatMoved == .added ? [added] : whatMoved == .moneyInOut ? [cameIn, wentOut, interest] : []
        return fields.contains { AmountInput.parse($0, locale: locale) == .empty }
    }

    /// What stops Save, in order: no balance, one that can't be read, a
    /// date after today or after the account closed, and what moved left
    /// empty, unreadable or, for money in and out, negative.
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
        guard asksWhatMoved else { return problems }
        switch whatMoved {
        case .nothing:
            break
        case .added:
            switch AmountInput.parse(added, locale: locale) {
            case .empty: problems.append("Enter what you added since the last value. If nothing, type 0.")
            case .unreadable: problems.append("What you added can't be read.")
            case .value: break
            }
        case .moneyInOut:
            let fields = [cameIn, wentOut, interest].map { AmountInput.parse($0, locale: locale) }
            if fields.contains(.empty) {
                problems.append("Enter what came in, what went out and the interest since the last value. "
                    + "If nothing, type 0.")
            }
            if fields.contains(.unreadable) {
                problems.append("An amount can't be read.")
            }
            if [fields[0].value, fields[1].value].contains(where: { ($0 ?? 0) < 0 }) {
                problems.append("Type what came in and what went out without a sign.")
            }
        }
        return problems
    }

    /// The value to save, or `nil` while the balance, or what moved when
    /// it's asked for, can't be read: the balance and what moved. An edited
    /// value keeps its note and any keys this version doesn't know, and
    /// drops anything else it recorded (a one-off, tax, and what moved
    /// when it isn't asked for).
    func valuation(locale: Locale = .current) -> Valuation? {
        guard let amount = AmountInput.balance(from: balance, isLiability: isLiability, locale: locale) else {
            return nil
        }
        func read(_ text: String) -> Decimal? { AmountInput.parse(text, locale: locale).value }
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
        if asksWhatMoved {
            switch whatMoved {
            case .nothing:
                break
            case .added:
                guard let added = read(added) else { return nil }
                valuation.saved = added
            case .moneyInOut:
                guard let cameIn = read(cameIn), let wentOut = read(wentOut), let interest = read(interest)
                else { return nil }
                valuation.moneyIn = cameIn
                valuation.moneyOut = wentOut
                valuation.interest = interest
            }
        }
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

/// The words that say what a typed value records.
enum TypedValueText {
    /// Under *Since the last value* in *Update Value*.
    static func whatMovedFooter(_ whatMoved: TypedWhatMoved) -> String {
        switch whatMoved {
        case .nothing:
            ""
        case .added:
            "What you put in since the last value, less what you took out. The rest of the change is markets. "
                + "If nothing, type 0."
        case .moneyInOut:
            "Came in and went out are money from and to outside your accounts, such as pay and bills; moves "
                + "between your own accounts don't count. If nothing, type 0."
        }
    }

    /// Under *Values* in Edit Account, with *Typed by you* offered.
    static func valuesFooter(_ whatMoved: TypedWhatMoved) -> String {
        switch whatMoved {
        case .nothing:
            "Typed values are balances only."
        case .added:
            "Each value you type after the first also asks what you added since the last one, so the rest of "
                + "the change counts as markets."
        case .moneyInOut:
            "Each value you type after the first also asks what came in, what went out and the interest since "
                + "the last one, so So far keeps counting them."
        }
    }
}
