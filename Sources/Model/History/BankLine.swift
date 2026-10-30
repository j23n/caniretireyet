import Foundation

/// One line of a cash, savings or tax-pot account's statement, kept so you
/// can check and change it later (docs/IMPORT.md, "Lines"): a payment, a
/// salary, money moved to another of your accounts. Lines are records in
/// the monthly history files, next to valuations and trades, keyed by
/// account + date + ``id``; each keeps its own date, whatever check-ins
/// the account has.
///
/// What a line is (``statementClass``) is suggested by the import until
/// you confirm it (``isConfirmed``). A removed line (``isRemoved``) stays
/// in the file, so importing the same statement again doesn't bring it
/// back, but counts in nothing.
public struct BankLine: Hashable, Sendable, KeyedRecord, KnownKeysProviding {
    public var account: AccountID
    /// The day the bank booked it.
    public var date: CalendarDate
    /// Unique among the account's lines on its date. An imported line's is
    /// made from the line (``BankLineID/stable(account:date:amount:text:ordinal:)``),
    /// so importing the file again finds it and keeps your changes.
    public var id: BankLineID
    /// Money in positive, money out negative, in the account's currency.
    public var amount: Decimal
    /// The bank's text for the line: its description and counterparty, as
    /// the file writes them. Empty for a line typed by hand without one.
    public var text: String
    /// What the line is: income, spending, tax, interest, a one-off, money
    /// moved between your accounts, or not counted (``StatementClass/ignore``).
    public var statementClass: StatementClass
    /// For money moved between your accounts (``StatementClass/transfer``):
    /// the other account, when it's known.
    public var otherAccount: AccountID?
    /// Your note.
    public var note: String?
    /// Whether you removed it, such as a duplicate: it counts in nothing.
    /// Stored only when true.
    public var removed: Bool?
    /// Whether you confirmed what it is; otherwise it's the import's
    /// suggestion. Stored only when true.
    public var confirmed: Bool?
    /// Where the line came from: `import`, or `manual` for one typed in.
    public var source: DataSource?

    public init(
        account: AccountID, date: CalendarDate, id: BankLineID, amount: Decimal, text: String = "",
        statementClass: StatementClass, otherAccount: AccountID? = nil, note: String? = nil,
        removed: Bool? = nil, confirmed: Bool? = nil, source: DataSource? = nil
    ) {
        self.account = account
        self.date = date
        self.id = id
        self.amount = amount
        self.text = text
        self.statementClass = statementClass
        self.otherAccount = otherAccount
        self.note = note
        self.removed = removed
        self.confirmed = confirmed
        self.source = source
    }

    public var key: BankLineKey { BankLineKey(account: account, date: date, id: id) }

    /// Whether you removed the line (``removed``).
    public var isRemoved: Bool { removed ?? false }

    /// Whether you confirmed what the line is (``confirmed``).
    public var isConfirmed: Bool { confirmed ?? false }
}

extension BankLine: Codable {
    enum CodingKeys: String, CodingKey, CaseIterable {
        case account, date, id, amount, text
        case statementClass = "class"
        case otherAccount, note, removed, confirmed, source
    }

    public static var knownKeys: Set<String> { Set(CodingKeys.allCases.map(\.stringValue)) }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        account = try c.decode(AccountID.self, forKey: .account)
        date = try c.decode(CalendarDate.self, forKey: .date)
        id = try c.decode(BankLineID.self, forKey: .id)
        amount = try c.decodeDecimal(forKey: .amount)
        text = try c.decodeIfPresent(String.self, forKey: .text) ?? ""
        statementClass = try c.decode(StatementClass.self, forKey: .statementClass)
        otherAccount = try c.decodeIfPresent(AccountID.self, forKey: .otherAccount)
        note = try c.decodeIfPresent(String.self, forKey: .note)
        removed = try c.decodeIfPresent(Bool.self, forKey: .removed)
        confirmed = try c.decodeIfPresent(Bool.self, forKey: .confirmed)
        source = try c.decodeIfPresent(DataSource.self, forKey: .source)
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(account, forKey: .account)
        try c.encode(date, forKey: .date)
        try c.encode(id, forKey: .id)
        try c.encodeDecimal(amount, forKey: .amount)
        if !text.isEmpty { try c.encode(text, forKey: .text) }
        try c.encode(statementClass, forKey: .statementClass)
        try c.encodeIfPresent(otherAccount, forKey: .otherAccount)
        try c.encodeIfPresent(note, forKey: .note)
        if isRemoved { try c.encode(true, forKey: .removed) }
        if isConfirmed { try c.encode(true, forKey: .confirmed) }
        try c.encodeIfPresent(source, forKey: .source)
    }
}

/// A bank line's key: account + date + line ID.
public struct BankLineKey: Hashable, Comparable, Sendable, CustomStringConvertible {
    public var date: CalendarDate
    public var account: AccountID
    public var id: BankLineID

    public init(account: AccountID, date: CalendarDate, id: BankLineID) {
        self.account = account
        self.date = date
        self.id = id
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        (lhs.date, lhs.account, lhs.id) < (rhs.date, rhs.account, rhs.id)
    }

    /// `2026-03-12 conto-fineco k3q7vz2m`
    public var description: String { "\(date) \(account) \(id)" }
}

/// The ID of a bank line: a slug, unique among its account's lines on its
/// date. An imported line's is stable (``stable(account:date:amount:text:ordinal:)``);
/// a line typed in gets a random one, like a trade's (``TradeID/random()``).
public struct BankLineID: StringValue {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    /// A new random ID of 8 lowercase base32 characters.
    public static func random() -> BankLineID {
        BankLineID(rawValue: TradeID.random().rawValue)
    }

    /// A stable ID for an imported line: 8 lowercase base32 characters made
    /// from a hash of its account, date, amount (in its exact file form) and
    /// text, and `ordinal`, its position among the file's lines with all of
    /// these equal, from 0, so two identical payments on one day stay two
    /// lines. Importing the same file again gives the same IDs.
    public static func stable(account: AccountID, date: CalendarDate, amount: Decimal, text: String,
                              ordinal: Int = 0) -> BankLineID {
        BankLineID(rawValue: TradeID.hashed([
            "line", account.rawValue, date.description, amount.fileString, text, String(ordinal),
        ]))
    }
}

/// What statement lines add to a value's money in, money out, one-off, tax
/// and interest (docs/IMPORT.md, "Classes"), added up.
public struct LineAmounts: Hashable, Sendable {
    public var moneyIn: Decimal = 0
    /// Lowered by money paid back, so it can be below zero.
    public var moneyOut: Decimal = 0
    public var oneOff: Decimal = 0
    /// Tax paid, lowered by a refund: part of money out.
    public var tax: Decimal = 0
    public var interest: Decimal = 0

    public init(moneyIn: Decimal = 0, moneyOut: Decimal = 0, oneOff: Decimal = 0, tax: Decimal = 0,
                interest: Decimal = 0) {
        self.moneyIn = moneyIn
        self.moneyOut = moneyOut
        self.oneOff = oneOff
        self.tax = tax
        self.interest = interest
    }

    /// What one line of `amount` (money in positive) adds. Income that came
    /// in is money in, and so is interest unless the account records
    /// interest (`recordsInterest`); a one-off that came in is a one-off.
    /// Money in that is spending lowers money out. Any of them that went
    /// out is money out. Tax is money out and tax both ways: paid, it adds
    /// to them; refunded, it lowers them. A transfer, a line not counted and
    /// a class this version doesn't know add nothing.
    public init(_ statementClass: StatementClass, amount: Decimal, recordsInterest: Bool) {
        switch statementClass {
        case .interest where recordsInterest: interest = amount
        case .income, .interest, .oneOff:
            if amount < 0 {
                moneyOut = -amount
            } else if statementClass == .oneOff {
                oneOff = amount
            } else {
                moneyIn = amount
            }
        case .spending: moneyOut = -amount
        case .tax:
            moneyOut = -amount
            tax = -amount
        default: break
        }
    }

    /// Both added up.
    public static func + (lhs: Self, rhs: Self) -> Self {
        LineAmounts(moneyIn: lhs.moneyIn + rhs.moneyIn, moneyOut: lhs.moneyOut + rhs.moneyOut,
                    oneOff: lhs.oneOff + rhs.oneOff, tax: lhs.tax + rhs.tax, interest: lhs.interest + rhs.interest)
    }

    /// What was spent: money out less the tax in it.
    public var spent: Decimal { moneyOut - tax }
}

extension BankLine {
    /// What the line adds to its value's amounts (``LineAmounts``): nothing
    /// once it's removed.
    public func amounts(recordsInterest: Bool) -> LineAmounts {
        isRemoved ? LineAmounts() : LineAmounts(statementClass, amount: amount, recordsInterest: recordsInterest)
    }
}
