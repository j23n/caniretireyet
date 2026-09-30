import Foundation

/// Which country taxes a pension.
public struct TaxedIn: OpenEnum {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    /// The country of residence taxes it (the default).
    public static let residence: TaxedIn = "residence"
    /// The paying country taxes it.
    public static let source: TaxedIn = "source"

    public static let knownValues: [TaxedIn] = [.residence, .source]
}

/// A pension in a plan.
///
/// With a scheme such as `it.inps` it's projected from contributions, and
/// the scheme reads its settings (montante, contribution years, …) from
/// `options`. With `fixed` it's `perYear` from `fromAge`, as on a statement.
public struct PlanPension: Hashable, Sendable, KnownKeysProviding {
    public var scheme: PensionSchemeID
    /// Display name, e.g. "State pension from previous country".
    public var name: String?
    /// When to claim, as written. See ``effectiveClaim``.
    public var claim: AgeChoice?
    /// `fixed` pensions: the age payments start.
    public var fromAge: Int?
    /// `fixed` pensions: the gross yearly amount in today's euros.
    public var perYear: Decimal?
    /// As written. See ``effectiveTaxedIn``.
    public var taxedIn: TaxedIn?
    /// The paying country, e.g. for a foreign state pension. Needed when
    /// `taxedIn` is `source`, and for treaty rules.
    public var sourceCountry: CountryCode?
    /// Scheme-specific settings.
    public var options: [String: JSONValue]

    public init(
        scheme: PensionSchemeID, name: String? = nil, claim: AgeChoice? = nil, fromAge: Int? = nil,
        perYear: Decimal? = nil, taxedIn: TaxedIn? = nil, sourceCountry: CountryCode? = nil,
        options: [String: JSONValue] = [:]
    ) {
        self.scheme = scheme
        self.name = name
        self.claim = claim
        self.fromAge = fromAge
        self.perYear = perYear
        self.taxedIn = taxedIn
        self.sourceCountry = sourceCountry
        self.options = options
    }

    /// When to claim: `claim` if set, otherwise the earliest age the scheme allows.
    public var effectiveClaim: AgeChoice {
        claim ?? .earliest
    }

    /// Which country taxes the pension (default: the country of residence).
    public var effectiveTaxedIn: TaxedIn {
        taxedIn ?? .residence
    }
}

extension PlanPension: Codable {
    enum CodingKeys: String, CodingKey, CaseIterable {
        case scheme, name, claim, fromAge, perYear, taxedIn, sourceCountry, options
    }

    public static var knownKeys: Set<String> { Set(CodingKeys.allCases.map(\.stringValue)) }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        scheme = try c.decode(PensionSchemeID.self, forKey: .scheme)
        name = try c.decodeIfPresent(String.self, forKey: .name)
        claim = try c.decodeIfPresent(AgeChoice.self, forKey: .claim)
        fromAge = try c.decodeIfPresent(Int.self, forKey: .fromAge)
        perYear = try c.decodeDecimalIfPresent(forKey: .perYear)
        taxedIn = try c.decodeIfPresent(TaxedIn.self, forKey: .taxedIn)
        sourceCountry = try c.decodeIfPresent(CountryCode.self, forKey: .sourceCountry)
        options = try c.decodeObject(forKey: .options)
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(scheme, forKey: .scheme)
        try c.encodeIfPresent(name, forKey: .name)
        try c.encodeIfPresent(claim, forKey: .claim)
        try c.encodeIfPresent(fromAge, forKey: .fromAge)
        try c.encodeDecimalIfPresent(perYear, forKey: .perYear)
        try c.encodeIfPresent(taxedIn, forKey: .taxedIn)
        try c.encodeIfPresent(sourceCountry, forKey: .sourceCountry)
        try c.encodeIfNotEmpty(options, forKey: .options)
    }
}
