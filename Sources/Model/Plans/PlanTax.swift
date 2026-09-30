/// A plan's `tax` section: residence over time, special regimes, threshold
/// indexing and parameter overrides. See TAXES.md.
public struct PlanTax: Hashable, Sendable, KnownKeysProviding {
    /// Which tax system applies from which year. Residence changes on 1 January.
    public var residence: [PlanResidence]
    /// Special regimes such as impatriati. Each knows the years it covers.
    public var overlays: [PlanOverlay]
    /// `indexThresholds` as written. See ``effectiveIndexThresholds``.
    public var indexThresholds: Bool?
    /// Parameter overrides for this plan only, keyed by system-prefixed path,
    /// e.g. `"it.irpef.rates": ["0.23", "0.35", "0.43"]`.
    public var overrides: [String: JSONValue]

    /// Thresholds rise with inflation after the last known tax year unless
    /// the plan says otherwise.
    public static let defaultIndexThresholds = true

    public init(
        residence: [PlanResidence] = [], overlays: [PlanOverlay] = [], indexThresholds: Bool? = nil,
        overrides: [String: JSONValue] = [:]
    ) {
        self.residence = residence
        self.overlays = overlays
        self.indexThresholds = indexThresholds
        self.overrides = overrides
    }

    /// Whether thresholds are indexed to inflation (default true).
    public var effectiveIndexThresholds: Bool {
        indexThresholds ?? Self.defaultIndexThresholds
    }

    /// The residence entry in force in `year`: the latest one starting at or before it.
    public func residence(in year: Int) -> PlanResidence? {
        residence.filter { $0.from <= year }.max { $0.from < $1.from }
    }

    /// Whether nothing is set, in which case the section is left out of the file.
    public var isEmpty: Bool {
        residence.isEmpty && overlays.isEmpty && indexThresholds == nil && overrides.isEmpty
    }
}

extension PlanTax: Codable {
    enum CodingKeys: String, CodingKey, CaseIterable {
        case residence, overlays, indexThresholds, overrides
    }

    public static var knownKeys: Set<String> { Set(CodingKeys.allCases.map(\.stringValue)) }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        residence = try c.decodeArray([PlanResidence].self, forKey: .residence)
        overlays = try c.decodeArray([PlanOverlay].self, forKey: .overlays)
        indexThresholds = try c.decodeIfPresent(Bool.self, forKey: .indexThresholds)
        overrides = try c.decodeObject(forKey: .overrides)
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfNotEmpty(residence, forKey: .residence)
        try c.encodeIfNotEmpty(overlays, forKey: .overlays)
        try c.encodeIfPresent(indexThresholds, forKey: .indexThresholds)
        try c.encodeIfNotEmpty(overrides, forKey: .overrides)
    }
}

/// One entry of the residence timeline: a tax system from a given year.
public struct PlanResidence: Hashable, Sendable, KnownKeysProviding {
    /// The first year this system applies.
    public var from: Int
    public var system: TaxSystemID
    /// The system's options, e.g. `addizionaleRegionale`.
    public var options: [String: JSONValue]

    public init(from: Int, system: TaxSystemID, options: [String: JSONValue] = [:]) {
        self.from = from
        self.system = system
        self.options = options
    }
}

extension PlanResidence: Codable {
    enum CodingKeys: String, CodingKey, CaseIterable {
        case from, system, options
    }

    public static var knownKeys: Set<String> { Set(CodingKeys.allCases.map(\.stringValue)) }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        from = try c.decode(Int.self, forKey: .from)
        system = try c.decode(TaxSystemID.self, forKey: .system)
        options = try c.decodeObject(forKey: .options)
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(from, forKey: .from)
        try c.encode(system, forKey: .system)
        try c.encodeIfNotEmpty(options, forKey: .options)
    }
}

/// A special regime chosen for the plan, with its options.
public struct PlanOverlay: Hashable, Sendable, KnownKeysProviding {
    public var regime: RegimeID
    /// The regime's options, e.g. `movedIn`, `minorChild`.
    public var options: [String: JSONValue]

    public init(regime: RegimeID, options: [String: JSONValue] = [:]) {
        self.regime = regime
        self.options = options
    }
}

extension PlanOverlay: Codable {
    enum CodingKeys: String, CodingKey, CaseIterable {
        case regime, options
    }

    public static var knownKeys: Set<String> { Set(CodingKeys.allCases.map(\.stringValue)) }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        regime = try c.decode(RegimeID.self, forKey: .regime)
        options = try c.decodeObject(forKey: .options)
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(regime, forKey: .regime)
        try c.encodeIfNotEmpty(options, forKey: .options)
    }
}
