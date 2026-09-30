/// A ledger profile's `ledger` section: how a plain-text accounting journal
/// (ledger-cli, hledger) becomes valuations. See IMPORT.md, "Ledger journals".
///
/// Which ledger account goes to which library account, and which commodity
/// is which instrument, is remembered in the profile's `matches`: a ledger
/// account there stands for its whole subtree.
public struct LedgerImportSettings: Hashable, Sendable, KnownKeysProviding {
    /// The top-level accounts (or account prefixes) that count toward net
    /// worth. Empty means ``defaultRoots``. See ``effectiveRoots``.
    public var roots: [String]
    /// Ledger accounts left out, with their subaccounts.
    public var ignore: [String]
    /// Income and expense accounts whose postings are returns rather than
    /// money added or taken out (dividends, interest, fees), with their
    /// subaccounts.
    public var returns: [String]
    /// Accounts whose postings are money added or taken out, although their
    /// names suggest returns. With ``returns``, the closest one to an account wins.
    public var flows: [String]
    /// Commodities left out.
    public var ignoreCommodities: [String]
    /// How often valuations are written, as written. See ``effectiveFrequency``.
    public var frequency: LedgerSnapshotFrequency?
    /// Whether `@` prices on transactions become price records, as written.
    /// See ``effectiveTransactionPrices``.
    public var transactionPrices: Bool?

    public init(roots: [String] = [], ignore: [String] = [], returns: [String] = [], flows: [String] = [],
                ignoreCommodities: [String] = [], frequency: LedgerSnapshotFrequency? = nil,
                transactionPrices: Bool? = nil) {
        self.roots = roots
        self.ignore = ignore
        self.returns = returns
        self.flows = flows
        self.ignoreCommodities = ignoreCommodities
        self.frequency = frequency
        self.transactionPrices = transactionPrices
    }

    /// The accounts that count toward net worth when `roots` is empty: assets
    /// and liabilities, in English and in a few other languages.
    public static let defaultRoots = [
        "Assets", "Asset", "Liabilities", "Liability", "Attività", "Passività", "Attivo", "Passivo",
        "Aktiva", "Passiva", "Actifs", "Passifs", "Activos", "Pasivos",
    ]

    /// ``roots``, or ``defaultRoots`` when there are none.
    public var effectiveRoots: [String] { roots.isEmpty ? Self.defaultRoots : roots }

    /// The snapshot frequency (default: month ends).
    public var effectiveFrequency: LedgerSnapshotFrequency { frequency ?? .month }

    /// Whether `@` prices become price records (default: yes).
    public var effectiveTransactionPrices: Bool { transactionPrices ?? true }
}

extension LedgerImportSettings: Codable {
    enum CodingKeys: String, CodingKey, CaseIterable {
        case roots, ignore, returns, flows, ignoreCommodities, frequency, transactionPrices
    }

    public static var knownKeys: Set<String> { Set(CodingKeys.allCases.map(\.stringValue)) }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        roots = try c.decodeArray([String].self, forKey: .roots)
        ignore = try c.decodeArray([String].self, forKey: .ignore)
        returns = try c.decodeArray([String].self, forKey: .returns)
        flows = try c.decodeArray([String].self, forKey: .flows)
        ignoreCommodities = try c.decodeArray([String].self, forKey: .ignoreCommodities)
        frequency = try c.decodeIfPresent(LedgerSnapshotFrequency.self, forKey: .frequency)
        transactionPrices = try c.decodeIfPresent(Bool.self, forKey: .transactionPrices)
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfNotEmpty(roots, forKey: .roots)
        try c.encodeIfNotEmpty(ignore, forKey: .ignore)
        try c.encodeIfNotEmpty(returns, forKey: .returns)
        try c.encodeIfNotEmpty(flows, forKey: .flows)
        try c.encodeIfNotEmpty(ignoreCommodities, forKey: .ignoreCommodities)
        try c.encodeIfPresent(frequency, forKey: .frequency)
        try c.encodeIfPresent(transactionPrices, forKey: .transactionPrices)
    }
}

/// When a journal import writes valuations.
public struct LedgerSnapshotFrequency: OpenEnum {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    /// At each month end.
    public static let month: LedgerSnapshotFrequency = "month"
    /// At each quarter end.
    public static let quarter: LedgerSnapshotFrequency = "quarter"
    /// On every date with a posting in the account.
    public static let activity: LedgerSnapshotFrequency = "activity"

    public static let knownValues: [LedgerSnapshotFrequency] = [.month, .quarter, .activity]
}

extension ImportProfile {
    /// Whether this profile reads ledger journals rather than spreadsheets.
    public var isLedger: Bool { layout == .ledger }
}
