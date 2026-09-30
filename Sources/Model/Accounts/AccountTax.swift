/// The ID of a tax wrapper: how the planner taxes an account. Defined by a
/// tax system (`it.ordinary`, `it.pensionFund`, `it.tfr`) or generic.
public struct WrapperID: StringValue {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    /// Generic: taxed on realised gains and income.
    public static let taxable: WrapperID = "taxable"
    /// Generic: contributions relieved, payouts taxed.
    public static let taxDeferred: WrapperID = "taxDeferred"
    /// Generic: no tax on growth or payouts.
    public static let taxFree: WrapperID = "taxFree"
}

/// An account's `tax` object: the wrapper plus wrapper-specific details,
/// e.g. `{ "joined": "2022-01-01", "wrapper": "it.pensionFund" }`.
///
/// Every key other than `wrapper` is kept in `details`, so this type
/// preserves unknown keys by itself.
public struct AccountTax: Hashable, Sendable {
    /// The wrapper that defines how the account is taxed.
    public var wrapper: WrapperID
    /// Wrapper-specific details, interpreted by the tax system.
    public var details: [String: JSONValue]

    public init(wrapper: WrapperID, details: [String: JSONValue] = [:]) {
        self.wrapper = wrapper
        self.details = details
    }

    /// `details["joined"]` as a date: when you joined a pension fund, which
    /// sets the payout tax rate and the 5-year minimum.
    public var joined: CalendarDate? {
        details["joined"]?.stringValue.flatMap(CalendarDate.init)
    }
}

extension AccountTax: Codable {
    private static let wrapperKey = AnyCodingKey("wrapper")

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: AnyCodingKey.self)
        wrapper = try container.decode(WrapperID.self, forKey: Self.wrapperKey)
        var details: [String: JSONValue] = [:]
        for key in container.allKeys where key != Self.wrapperKey {
            details[key.stringValue] = try container.decode(JSONValue.self, forKey: key)
        }
        self.details = details
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: AnyCodingKey.self)
        for (key, value) in details where key != Self.wrapperKey.stringValue {
            try container.encode(value, forKey: AnyCodingKey(key))
        }
        try container.encode(wrapper, forKey: Self.wrapperKey)
    }
}
