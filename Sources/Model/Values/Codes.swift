/// An ISO 4217 currency code, such as `EUR`, `USD` or `CHF`.
public struct CurrencyCode: StringValue {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    public static let eur: CurrencyCode = "EUR"
    public static let usd: CurrencyCode = "USD"
    public static let chf: CurrencyCode = "CHF"
    public static let gbp: CurrencyCode = "GBP"
    public static let jpy: CurrencyCode = "JPY"

    /// Whether the code has the ISO 4217 shape: three uppercase ASCII letters.
    public var isWellFormed: Bool {
        rawValue.unicodeScalars.count == 3 && rawValue.unicodeScalars.allSatisfy { ("A"..."Z").contains($0) }
    }
}

/// An ISO 3166-1 alpha-2 country code, such as `IT`, `IE` or `DE`.
public struct CountryCode: StringValue {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    public static let it: CountryCode = "IT"
    public static let ie: CountryCode = "IE"
    public static let de: CountryCode = "DE"
    public static let fr: CountryCode = "FR"
    public static let es: CountryCode = "ES"
    public static let pt: CountryCode = "PT"
    public static let nl: CountryCode = "NL"
    public static let ch: CountryCode = "CH"
    public static let gb: CountryCode = "GB"
    public static let us: CountryCode = "US"

    /// Whether the code has the ISO 3166-1 alpha-2 shape: two uppercase ASCII letters.
    public var isWellFormed: Bool {
        rawValue.unicodeScalars.count == 2 && rawValue.unicodeScalars.allSatisfy { ("A"..."Z").contains($0) }
    }
}
