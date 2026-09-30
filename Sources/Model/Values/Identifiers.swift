/// The ID of an account: `accounts/<id>.json`.
public struct AccountID: SlugID {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
}

/// The ID of an instrument: `instruments/<id>.json`.
public struct InstrumentID: SlugID {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
}

/// The ID of a plan: `plans/<id>.json`, and its `projections/<id>/` folder.
public struct PlanID: SlugID {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
}

/// The ID of an import profile: `imports/<id>.json`.
public struct ImportProfileID: SlugID {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
}

/// The ID of a saved baseline: its file name in `projections/<plan>/baselines/`,
/// normally the date it was created (`"2026-01-05"`).
public struct BaselineID: SlugID {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
}
