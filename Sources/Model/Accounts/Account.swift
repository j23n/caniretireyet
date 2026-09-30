/// `accounts/<id>.json`: an account, open or closed. Its history lives in the
/// monthly files and refers to it by ID.
public struct Account: Hashable, Sendable, Identifiable, KnownKeysProviding {
    /// The slug; same as the file name.
    public var id: AccountID
    /// Display name. Change it whenever you like.
    public var name: String
    public var kind: AccountKind
    /// The currency of this account's balances and cash.
    public var currency: CurrencyCode
    /// The first day the account counts toward net worth.
    public var opened: CalendarDate
    /// The last day it counts. `nil` while the account is active.
    public var closed: CalendarDate?
    /// The bank or broker.
    public var institution: String?
    /// The institution's country. Tax systems and the RW helper may use it.
    public var country: CountryCode?
    /// `valuation` as written in the file. See ``valuationMode`` for the effective value.
    public var valuation: ValuationMode?
    /// The asset mix of a balance account, as written. See ``effectiveAssetClasses``.
    public var assetClasses: AssetMix?
    /// How the planner taxes this account.
    public var tax: AccountTax?
    /// `includeIn` as written. See ``includedInNetWorth`` and ``includedInPlan``.
    public var includeIn: IncludeIn?
    /// The account that replaced this one, so charts stay continuous.
    public var successor: AccountID?
    /// Free-form tags. Omitted from the file when empty.
    public var tags: [String]
    /// Free-form notes.
    public var notes: String?

    public init(
        id: AccountID, name: String, kind: AccountKind, currency: CurrencyCode, opened: CalendarDate,
        closed: CalendarDate? = nil, institution: String? = nil, country: CountryCode? = nil,
        valuation: ValuationMode? = nil, assetClasses: AssetMix? = nil, tax: AccountTax? = nil,
        includeIn: IncludeIn? = nil, successor: AccountID? = nil, tags: [String] = [], notes: String? = nil
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.currency = currency
        self.opened = opened
        self.closed = closed
        self.institution = institution
        self.country = country
        self.valuation = valuation
        self.assetClasses = assetClasses
        self.tax = tax
        self.includeIn = includeIn
        self.successor = successor
        self.tags = tags
        self.notes = notes
    }
}

// MARK: - Defaults and lifecycle

extension Account {
    /// How valuations are recorded: `valuation` if set, otherwise the
    /// default for the kind (brokerage, crypto and metals hold positions).
    public var valuationMode: ValuationMode {
        valuation ?? kind.defaultValuationMode
    }

    /// The asset mix for a balance account: `assetClasses` if set, otherwise
    /// the default for the kind (cash → cash, property → real estate), or
    /// `nil` when there is none (holdings take their mix from instruments).
    public var effectiveAssetClasses: AssetMix? {
        assetClasses ?? kind.defaultAssetClasses
    }

    /// Whether the account counts toward net worth (default true).
    public var includedInNetWorth: Bool {
        includeIn?.netWorth ?? true
    }

    /// Whether the planner includes the account (default true).
    public var includedInPlan: Bool {
        includeIn?.plan ?? true
    }

    /// The account's tax wrapper, if it has one.
    public var wrapper: WrapperID? {
        tax?.wrapper
    }

    /// Whether the account has been closed.
    public var isClosed: Bool {
        closed != nil
    }

    /// Whether the account counts on `date`: between `opened` and `closed`,
    /// both inclusive.
    public func isOpen(on date: CalendarDate) -> Bool {
        date >= opened && (closed.map { date <= $0 } ?? true)
    }
}

// MARK: - Codable

extension Account: Codable {
    enum CodingKeys: String, CodingKey, CaseIterable {
        case id, name, kind, currency, opened, closed, institution, country, valuation, assetClasses, tax,
             includeIn, successor, tags, notes
    }

    public static var knownKeys: Set<String> { Set(CodingKeys.allCases.map(\.stringValue)) }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(AccountID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        kind = try c.decode(AccountKind.self, forKey: .kind)
        currency = try c.decode(CurrencyCode.self, forKey: .currency)
        opened = try c.decode(CalendarDate.self, forKey: .opened)
        closed = try c.decodeIfPresent(CalendarDate.self, forKey: .closed)
        institution = try c.decodeIfPresent(String.self, forKey: .institution)
        country = try c.decodeIfPresent(CountryCode.self, forKey: .country)
        valuation = try c.decodeIfPresent(ValuationMode.self, forKey: .valuation)
        assetClasses = try c.decodeIfPresent(AssetMix.self, forKey: .assetClasses)
        tax = try c.decodeIfPresent(AccountTax.self, forKey: .tax)
        includeIn = try c.decodeIfPresent(IncludeIn.self, forKey: .includeIn)
        successor = try c.decodeIfPresent(AccountID.self, forKey: .successor)
        tags = try c.decodeArray([String].self, forKey: .tags)
        notes = try c.decodeIfPresent(String.self, forKey: .notes)
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(kind, forKey: .kind)
        try c.encode(currency, forKey: .currency)
        try c.encode(opened, forKey: .opened)
        try c.encodeIfPresent(closed, forKey: .closed)
        try c.encodeIfPresent(institution, forKey: .institution)
        try c.encodeIfPresent(country, forKey: .country)
        try c.encodeIfPresent(valuation, forKey: .valuation)
        try c.encodeIfPresent(assetClasses, forKey: .assetClasses)
        try c.encodeIfPresent(tax, forKey: .tax)
        try c.encodeIfPresent(includeIn, forKey: .includeIn)
        try c.encodeIfPresent(successor, forKey: .successor)
        try c.encodeIfNotEmpty(tags, forKey: .tags)
        try c.encodeIfPresent(notes, forKey: .notes)
    }
}

/// An account's `includeIn` object: `{ "netWorth": true, "plan": false }`.
/// Absent flags mean `true`.
public struct IncludeIn: Codable, Hashable, Sendable, KnownKeysProviding {
    public var netWorth: Bool?
    public var plan: Bool?

    public init(netWorth: Bool? = nil, plan: Bool? = nil) {
        self.netWorth = netWorth
        self.plan = plan
    }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case netWorth, plan
    }

    public static var knownKeys: Set<String> { Set(CodingKeys.allCases.map(\.stringValue)) }
}
