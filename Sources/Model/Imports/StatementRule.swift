/// What a line of a bank statement is, for money in and out (docs/IMPORT.md,
/// "Bank statements").
public struct StatementClass: OpenEnum {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    /// Income from outside your tracked accounts: pay, a pension, rent,
    /// a client's payment. Money in.
    public static let income: StatementClass = "income"
    /// Money that left your tracked accounts: shopping, rent, bills, and
    /// payments of a credit card, a loan or a mortgage. Money out.
    public static let spending: StatementClass = "spending"
    /// Money that came back: a refund, a friend's share of a bill, an
    /// insurance payout. It lowers money out, since it isn't income.
    public static let paidBack: StatementClass = "paidBack"
    /// Money from outside that is neither income nor spending: an
    /// inheritance, a gift you keep, the sale of something you didn't
    /// track. A value's `oneOff`.
    public static let oneOff: StatementClass = "oneOff"
    /// Money moved between two of your tracked accounts: neither money in
    /// nor money out.
    public static let transfer: StatementClass = "transfer"
    /// Interest earned: a savings account's `interest`, a current account's money in.
    public static let interest: StatementClass = "interest"
    /// Left out of money in and out; it still counts in the balance.
    public static let ignore: StatementClass = "ignore"

    public static let knownValues: [StatementClass] = [
        .income, .spending, .paidBack, .oneOff, .transfer, .interest, .ignore,
    ]
}

/// Statement layout: a phrase in a line's description or counterparty, and
/// the class every line with it gets. Saved in the profile, so a correction
/// made once applies to the next statement too.
public struct StatementRule: Codable, Hashable, Sendable, KnownKeysProviding {
    /// The phrase, found in the line's text ignoring case, accents and
    /// punctuation, as whole words.
    public var match: String
    /// The class of the lines it matches.
    public var statementClass: StatementClass

    public init(match: String, statementClass: StatementClass) {
        self.match = match
        self.statementClass = statementClass
    }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case match
        case statementClass = "class"
    }

    public static var knownKeys: Set<String> { Set(CodingKeys.allCases.map(\.stringValue)) }
}
