import Foundation

/// A payment into a specific account, e.g. into a pension fund: every year
/// while working (`perYear`, until `until`), or once (`amount` in `year`).
/// It comes out of the year's savings; the rest goes to the money you can draw.
///
///     { "account": "fondo-pensione", "perYear": "5000", "until": "retirement" }
///     { "account": "fondo-pensione", "amount": "20000", "year": 2030 }
public struct PlanContribution: Hashable, Sendable, KnownKeysProviding {
    /// The account paid into.
    public var account: AccountID
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
        case account, perYear, until, amount, year
    }

    public static var knownKeys: Set<String> { Set(CodingKeys.allCases.map(\.stringValue)) }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        account = try c.decode(AccountID.self, forKey: .account)
        amount = try c.decodeDecimalIfPresent(forKey: .amount)
        year = try c.decodeIfPresent(Int.self, forKey: .year)
        // A one-off payment needs no yearly amount; any other does.
        perYear = amount == nil ? try c.decodeDecimal(forKey: .perYear)
                                : try c.decodeDecimalIfPresent(forKey: .perYear) ?? 0
        until = try c.decodeIfPresent(PhaseEnd.self, forKey: .until)
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(account, forKey: .account)
        if amount == nil || perYear != 0 { try c.encodeDecimal(perYear, forKey: .perYear) }
        try c.encodeIfPresent(until, forKey: .until)
        try c.encodeDecimalIfPresent(amount, forKey: .amount)
        try c.encodeIfPresent(year, forKey: .year)
    }
}
