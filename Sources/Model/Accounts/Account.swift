import Foundation

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
    /// The institution's country.
    public var country: CountryCode?
    /// `valuation` as written in the file. See ``valuationMode`` for the effective value.
    public var valuation: ValuationMode?
    /// The asset mix of a balance account, as written. See ``effectiveAssetClasses``.
    public var assetClasses: AssetMix?
    /// The age from which plans can draw on the account, e.g. 60 for a
    /// pension fund; `nil` when it can be drawn at any age.
    public var availableFromAge: Int?
    /// `includeIn` as written. See ``includedInNetWorth`` and ``includedInPlan``.
    public var includeIn: IncludeIn?
    /// The account that replaced this one, so charts stay continuous.
    public var successor: AccountID?
    /// Free-form tags. Omitted from the file when empty.
    public var tags: [String]
    /// Free-form notes.
    public var notes: String?
    /// The share of its value a belongings account is estimated to lose a
    /// year, such as `0.15` for a car, above 0 and below 1: after each
    /// value, its value on a later day is estimated from it until the next
    /// value is typed. `nil` means it keeps its value until then. Other
    /// kinds ignore it.
    public var depreciation: Decimal?
    /// `values` as written in the file: where a balance account's values
    /// come from. See ``effectiveValues`` and ``acceptsTypedValues``.
    public var values: ValueEntry?
    /// The share of every amount plans take from the account that goes to
    /// tax, from 0 to 1, set by hand, such as `0.2` for money taxed as income
    /// when it comes out. Set, the account is pre-tax money: plans tax what
    /// they take from it at this rate in place of the plan's rate on
    /// investments. `nil` means it's taxed like any other investment.
    public var withdrawalTaxRate: Decimal?

    public init(
        id: AccountID, name: String, kind: AccountKind, currency: CurrencyCode, opened: CalendarDate,
        closed: CalendarDate? = nil, institution: String? = nil, country: CountryCode? = nil,
        valuation: ValuationMode? = nil, assetClasses: AssetMix? = nil, availableFromAge: Int? = nil,
        includeIn: IncludeIn? = nil, successor: AccountID? = nil, tags: [String] = [],
        notes: String? = nil, depreciation: Decimal? = nil, values: ValueEntry? = nil,
        withdrawalTaxRate: Decimal? = nil
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
        self.availableFromAge = availableFromAge
        self.includeIn = includeIn
        self.successor = successor
        self.tags = tags
        self.notes = notes
        self.depreciation = depreciation
        self.values = values
        self.withdrawalTaxRate = withdrawalTaxRate
    }
}

// MARK: - Defaults and lifecycle

extension Account {
    /// How valuations are recorded: `valuation` if set, otherwise the
    /// default for the kind (brokerage, crypto and metals record trades).
    public var valuationMode: ValuationMode {
        valuation ?? kind.defaultValuationMode
    }

    /// Whether the account's holdings come from its trades
    /// (``ValuationMode/trades``) rather than from its valuations.
    public var recordsTrades: Bool {
        valuationMode == .trades
    }

    /// Whether a valuation's `saved` is information the account's records
    /// can't give: a balance whose kind asks for it (``SavedRule/ask``:
    /// pension funds, TFR, property, other). Only then is it stored.
    /// Every other account's is worked out from its records (its balances,
    /// interest or trades), so a missing one means "computed".
    public var asksForSaved: Bool {
        !recordsTrades && kind.savedRule == .ask
    }

    /// The asset mix for a balance account: `assetClasses` if set, otherwise
    /// the default for the kind (cash → cash, property → real estate), or
    /// `nil` when there is none (holdings take their mix from instruments).
    public var effectiveAssetClasses: AssetMix? {
        assetClasses ?? kind.defaultAssetClasses
    }

    /// Whether the account counts toward net worth (default true, false
    /// for a tax pot: ``AccountKind/isIncludedByDefault``).
    public var includedInNetWorth: Bool {
        includeIn?.netWorth ?? kind.isIncludedByDefault
    }

    /// Whether the planner includes the account (default true, false for
    /// a tax pot: ``AccountKind/isIncludedByDefault``).
    public var includedInPlan: Bool {
        includeIn?.plan ?? kind.isIncludedByDefault
    }

    /// Where the account's values come from: `values` if set, otherwise
    /// ``ValueEntry/imported``.
    public var effectiveValues: ValueEntry {
        values ?? .imported
    }

    /// Whether its values can be switched to typed by hand: a balance
    /// account of a kind that takes them (``AccountKind/takesTypedValues``).
    /// Current accounts, credit cards, tax pots and accounts that record
    /// trades stay import-only, so their money in and out keep coming from
    /// statements.
    public var offersTypedValues: Bool {
        kind.takesTypedValues && valuationMode == .balance
    }

    /// Whether its typed values turn Trends off: an open savings or
    /// investment account in net worth, set to typed values. Trends stands
    /// on the money in and out and the money invested that statements
    /// record, which a typed balance doesn't; an account out of net worth
    /// isn't counted there. A starting estimate doesn't: it's a round
    /// amount until it's replaced.
    public var typedValuesTurnOffTrends: Bool {
        !isClosed && !isStartingEstimate && includedInNetWorth && offersTypedValues && effectiveValues == .typed
            && (kind == .savings || kind.isInvestment)
    }

    /// Whether a balance can be typed for it by hand: an account that
    /// ``offersTypedValues`` and has `values` set to ``ValueEntry/typed``,
    /// or an open starting estimate of any kind (``isStartingEstimate``),
    /// so its round amount can be corrected.
    public var acceptsTypedValues: Bool {
        (offersTypedValues && effectiveValues == .typed) || (isStartingEstimate && !isClosed)
    }

    /// The tag that marks an account as a starting estimate: an account
    /// first launch made from a round amount.
    public static let startingEstimateTag = "estimate"

    /// Whether first launch made it from a round amount
    /// (``startingEstimateTag``).
    public var isStartingEstimate: Bool {
        tags.contains(Self.startingEstimateTag)
    }

    /// Whether the account has been closed.
    public var isClosed: Bool {
        closed != nil
    }

    /// Whether the account is open on at least one day from `start`
    /// through `end`: opened by `end` and not closed before `start`.
    public func isOpen(onAnyDayFrom start: CalendarDate, through end: CalendarDate) -> Bool {
        opened <= end && (closed.map { $0 >= start } ?? true)
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
        case id, name, kind, currency, opened, closed, institution, country, valuation, assetClasses,
             availableFromAge, includeIn, successor, tags, notes, depreciation, values, withdrawalTaxRate
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
        availableFromAge = try c.decodeIfPresent(Int.self, forKey: .availableFromAge)
        includeIn = try c.decodeIfPresent(IncludeIn.self, forKey: .includeIn)
        successor = try c.decodeIfPresent(AccountID.self, forKey: .successor)
        tags = try c.decodeArray([String].self, forKey: .tags)
        notes = try c.decodeIfPresent(String.self, forKey: .notes)
        depreciation = try c.decodeDecimalIfPresent(forKey: .depreciation)
        values = try c.decodeIfPresent(ValueEntry.self, forKey: .values)
        withdrawalTaxRate = try c.decodeDecimalIfPresent(forKey: .withdrawalTaxRate)
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
        try c.encodeIfPresent(availableFromAge, forKey: .availableFromAge)
        try c.encodeIfPresent(includeIn, forKey: .includeIn)
        try c.encodeIfPresent(successor, forKey: .successor)
        try c.encodeIfNotEmpty(tags, forKey: .tags)
        try c.encodeIfPresent(notes, forKey: .notes)
        try c.encodeDecimalIfPresent(depreciation, forKey: .depreciation)
        try c.encodeIfPresent(values, forKey: .values)
        try c.encodeDecimalIfPresent(withdrawalTaxRate, forKey: .withdrawalTaxRate)
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
