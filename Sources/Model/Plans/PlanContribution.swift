import Foundation

/// A regular payment into a specific account while working, e.g. into the
/// pension fund. The rest of the savings goes to the liquid bucket.
public struct PlanContribution: Hashable, Sendable, KnownKeysProviding {
    public var account: AccountID
    /// Yearly amount in today's euros.
    public var perYear: Decimal
    /// As written. See ``effectiveUntil``.
    public var until: PhaseEnd?

    public init(account: AccountID, perYear: Decimal, until: PhaseEnd? = nil) {
        self.account = account
        self.perYear = perYear
        self.until = until
    }

    /// When contributions stop (default: at retirement).
    public var effectiveUntil: PhaseEnd {
        until ?? .retirement
    }
}

extension PlanContribution: Codable {
    enum CodingKeys: String, CodingKey, CaseIterable {
        case account, perYear, until
    }

    public static var knownKeys: Set<String> { Set(CodingKeys.allCases.map(\.stringValue)) }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        account = try c.decode(AccountID.self, forKey: .account)
        perYear = try c.decodeDecimal(forKey: .perYear)
        until = try c.decodeIfPresent(PhaseEnd.self, forKey: .until)
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(account, forKey: .account)
        try c.encodeDecimal(perYear, forKey: .perYear)
        try c.encodeIfPresent(until, forKey: .until)
    }
}
