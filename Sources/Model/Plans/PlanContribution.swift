import Foundation

/// A payment into a specific account, e.g. into the pension fund, or into a
/// pension scheme (a buy-in, e.g. into a Swiss pension fund): every year
/// while working (`perYear`, until `until`), or once (`amount` in `year`).
/// The rest of the savings goes to the liquid bucket.
///
/// In the file, an entry names `account` or `pension`, and has `perYear` or
/// `amount` and `year`:
///
///     { "account": "fondo-pensione", "perYear": "5000", "until": "retirement" }
///     { "pension": "ch.bvg", "amount": "20000", "year": 2030 }
public struct PlanContribution: Hashable, Sendable, KnownKeysProviding {
    /// The account paid into. Empty when the entry pays into a pension
    /// scheme instead (`pension`) and the file names no account.
    public var account: AccountID
    /// The pension scheme paid into instead of an account, e.g. `ch.bvg`.
    public var pension: PensionSchemeID?
    /// Yearly amount in today's money. 0 for a one-off payment (`amount`)
    /// when the file doesn't write it.
    public var perYear: Decimal
    /// As written. See ``effectiveUntil``.
    public var until: PhaseEnd?
    /// A one-off amount in today's money, paid in `year`, instead of `perYear`.
    public var amount: Decimal?
    /// The calendar year of a one-off `amount`.
    public var year: Int?

    public init(account: AccountID, perYear: Decimal, until: PhaseEnd? = nil) {
        self.account = account
        self.perYear = perYear
        self.until = until
    }

    /// A one-off payment into an account.
    public init(account: AccountID, amount: Decimal, year: Int) {
        self.account = account
        self.perYear = 0
        self.amount = amount
        self.year = year
    }

    /// A yearly payment into a pension scheme.
    public init(pension: PensionSchemeID, perYear: Decimal, until: PhaseEnd? = nil) {
        self.account = ""
        self.pension = pension
        self.perYear = perYear
        self.until = until
    }

    /// A one-off payment into a pension scheme, e.g. a buy-in.
    public init(pension: PensionSchemeID, amount: Decimal, year: Int) {
        self.account = ""
        self.pension = pension
        self.perYear = 0
        self.amount = amount
        self.year = year
    }

    /// When yearly contributions stop (default: at retirement).
    public var effectiveUntil: PhaseEnd {
        until ?? .retirement
    }

    /// Whether it's a one-off payment (`amount` in `year`).
    public var isOneOff: Bool {
        amount != nil
    }
}

extension PlanContribution: Codable {
    enum CodingKeys: String, CodingKey, CaseIterable {
        case account, pension, perYear, until, amount, year
    }

    public static var knownKeys: Set<String> { Set(CodingKeys.allCases.map(\.stringValue)) }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        pension = try c.decodeIfPresent(PensionSchemeID.self, forKey: .pension)
        // An entry for a pension scheme needs no account; any other does.
        account = pension == nil ? try c.decode(AccountID.self, forKey: .account)
                                 : try c.decodeIfPresent(AccountID.self, forKey: .account) ?? ""
        amount = try c.decodeDecimalIfPresent(forKey: .amount)
        year = try c.decodeIfPresent(Int.self, forKey: .year)
        // A one-off payment needs no yearly amount; any other does.
        perYear = amount == nil ? try c.decodeDecimal(forKey: .perYear)
                                : try c.decodeDecimalIfPresent(forKey: .perYear) ?? 0
        until = try c.decodeIfPresent(PhaseEnd.self, forKey: .until)
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        if pension == nil || !account.rawValue.isEmpty { try c.encode(account, forKey: .account) }
        try c.encodeIfPresent(pension, forKey: .pension)
        if amount == nil || perYear != 0 { try c.encodeDecimal(perYear, forKey: .perYear) }
        try c.encodeIfPresent(until, forKey: .until)
        try c.encodeDecimalIfPresent(amount, forKey: .amount)
        try c.encodeIfPresent(year, forKey: .year)
    }
}
