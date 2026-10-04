/// `imports/<id>.json`: a saved mapping that says how to read one kind of
/// file and what each column becomes. See IMPORT.md.
public struct ImportProfile: Hashable, Sendable, Identifiable, KnownKeysProviding {
    public var id: ImportProfileID
    public var name: String
    /// How to read the file: encoding, delimiter, header row.
    public var file: ImportFileSettings
    /// Value formats for every column, unless a column overrides them.
    public var defaults: ImportFormat
    public var layout: ImportLayout
    /// Wide layout: the header of the column holding the date.
    public var dateColumn: String?
    /// Long layout: what each row becomes.
    public var target: ImportTarget?
    /// Long layout: fields that are the same for every row, e.g. the account.
    public var constants: ImportConstants
    /// What each column is, identified by header (or position when there is none).
    public var columns: [ImportColumn]
    /// Names in files matched to library IDs, remembered from earlier imports.
    public var matches: ImportMatches
    /// What to do with records that differ from the library, as written.
    /// See ``effectiveOnConflict``.
    public var onConflict: ConflictPolicy?
    /// Trades layout: the file's words for trade types, as written (e.g.
    /// "Acquisto"), mapped to trade types. Matched exactly, then ignoring
    /// case and accents. The value `ignore` leaves the rows of that type out.
    public var tradeTypes: [String: TradeType]

    public init(
        id: ImportProfileID, name: String, file: ImportFileSettings = ImportFileSettings(),
        defaults: ImportFormat = ImportFormat(), layout: ImportLayout, dateColumn: String? = nil,
        target: ImportTarget? = nil, constants: ImportConstants = ImportConstants(), columns: [ImportColumn] = [],
        matches: ImportMatches = ImportMatches(), onConflict: ConflictPolicy? = nil,
        tradeTypes: [String: TradeType] = [:]
    ) {
        self.id = id
        self.name = name
        self.file = file
        self.defaults = defaults
        self.layout = layout
        self.dateColumn = dateColumn
        self.target = target
        self.constants = constants
        self.columns = columns
        self.matches = matches
        self.onConflict = onConflict
        self.tradeTypes = tradeTypes
    }

    /// The conflict policy (default: ask).
    public var effectiveOnConflict: ConflictPolicy {
        onConflict ?? .ask
    }
}

extension ImportProfile: Codable {
    enum CodingKeys: String, CodingKey, CaseIterable {
        case id, name, file, defaults, layout, dateColumn, target, constants, columns, matches, onConflict
        case tradeTypes
    }

    public static var knownKeys: Set<String> { Set(CodingKeys.allCases.map(\.stringValue)) }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(ImportProfileID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        file = try c.decodeIfPresent(ImportFileSettings.self, forKey: .file) ?? ImportFileSettings()
        defaults = try c.decodeIfPresent(ImportFormat.self, forKey: .defaults) ?? ImportFormat()
        layout = try c.decode(ImportLayout.self, forKey: .layout)
        dateColumn = try c.decodeIfPresent(String.self, forKey: .dateColumn)
        target = try c.decodeIfPresent(ImportTarget.self, forKey: .target)
        constants = try c.decodeIfPresent(ImportConstants.self, forKey: .constants) ?? ImportConstants()
        columns = try c.decodeArray([ImportColumn].self, forKey: .columns)
        matches = try c.decodeIfPresent(ImportMatches.self, forKey: .matches) ?? ImportMatches()
        onConflict = try c.decodeIfPresent(ConflictPolicy.self, forKey: .onConflict)
        tradeTypes = try c.decodeIfPresent([String: TradeType].self, forKey: .tradeTypes) ?? [:]
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        if file != ImportFileSettings() { try c.encode(file, forKey: .file) }
        if defaults != ImportFormat() { try c.encode(defaults, forKey: .defaults) }
        try c.encode(layout, forKey: .layout)
        try c.encodeIfPresent(dateColumn, forKey: .dateColumn)
        try c.encodeIfPresent(target, forKey: .target)
        if constants != ImportConstants() { try c.encode(constants, forKey: .constants) }
        try c.encodeIfNotEmpty(columns, forKey: .columns)
        if matches != ImportMatches() { try c.encode(matches, forKey: .matches) }
        try c.encodeIfPresent(onConflict, forKey: .onConflict)
        try c.encodeIfNotEmpty(tradeTypes, forKey: .tradeTypes)
    }
}

/// A profile's `file` section: how to read the file's text and rows.
public struct ImportFileSettings: Hashable, Sendable, KnownKeysProviding {
    /// The text encoding. `nil` means detect it.
    public var encoding: TextEncodingName?
    /// The field delimiter (`,` `;` tab `|`). `nil` means detect it.
    public var delimiter: String?
    /// The 1-based row holding the column headers; rows above it are
    /// skipped. `nil` means detect it; 0 means the file has no header.
    public var headerRow: Int?
    /// Rows to leave out, such as totals: a row is skipped when its first
    /// non-empty cell starts with one of these (ignoring case and accents).
    /// Empty means the importer's default rule, unless ``excludesNoRows``.
    public var excludeRows: [String]
    /// Whether the profile excludes no rows at all, written as an empty list
    /// (`"excludeRows": []`). Only meaningful while ``excludeRows`` is empty;
    /// when it's `false` too, the key is left out and the default rule applies.
    public var excludesNoRows: Bool

    public init(encoding: TextEncodingName? = nil, delimiter: String? = nil, headerRow: Int? = nil,
                excludeRows: [String] = [], excludesNoRows: Bool = false) {
        self.encoding = encoding
        self.delimiter = delimiter
        self.headerRow = headerRow
        self.excludeRows = excludeRows
        self.excludesNoRows = excludesNoRows && excludeRows.isEmpty
    }

    /// The footer rule as written: `nil` when left out (the importer's
    /// default applies), `[]` when no row is excluded.
    public var writtenExcludeRows: [String]? {
        excludeRows.isEmpty && !excludesNoRows ? nil : excludeRows
    }
}

extension ImportFileSettings: Codable {
    enum CodingKeys: String, CodingKey, CaseIterable {
        case encoding, delimiter, headerRow, excludeRows
    }

    public static var knownKeys: Set<String> { Set(CodingKeys.allCases.map(\.stringValue)) }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        encoding = try c.decodeIfPresent(TextEncodingName.self, forKey: .encoding)
        delimiter = try c.decodeIfPresent(String.self, forKey: .delimiter)
        headerRow = try c.decodeIfPresent(Int.self, forKey: .headerRow)
        let written = try c.decodeIfPresent([String].self, forKey: .excludeRows)
        excludeRows = written ?? []
        excludesNoRows = written?.isEmpty ?? false
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(encoding, forKey: .encoding)
        try c.encodeIfPresent(delimiter, forKey: .delimiter)
        try c.encodeIfPresent(headerRow, forKey: .headerRow)
        try c.encodeIfPresent(writtenExcludeRows, forKey: .excludeRows)
    }
}

/// One column of the file and what it holds.
///
/// In the wide layout a column has a `target`; the fields that target needs
/// come from the constants here (`account`, `instrument`, …) or from the
/// header. In the long layout a column has a `field` instead.
public struct ImportColumn: Hashable, Sendable, KnownKeysProviding {
    /// The column's header text. Columns are matched by header, so reordered columns still import.
    public var header: String?
    /// The 1-based column position, used only when the file has no header.
    public var index: Int?
    /// Wide layout: what the column's values become.
    public var target: ImportTarget?
    /// Long layout: which field of the row's record the column holds.
    public var field: ImportField?
    public var account: AccountID?
    public var instrument: InstrumentID?
    /// The currency of amounts or prices in this column.
    public var currency: CurrencyCode?
    /// FX columns: the pair, in the ECB convention (1 base = rate × quote).
    public var base: CurrencyCode?
    public var quote: CurrencyCode?
    /// Overrides of the profile's default formats for this column.
    public var format: ImportFormat?

    public init(
        header: String? = nil, index: Int? = nil, target: ImportTarget? = nil, field: ImportField? = nil,
        account: AccountID? = nil, instrument: InstrumentID? = nil, currency: CurrencyCode? = nil,
        base: CurrencyCode? = nil, quote: CurrencyCode? = nil, format: ImportFormat? = nil
    ) {
        self.header = header
        self.index = index
        self.target = target
        self.field = field
        self.account = account
        self.instrument = instrument
        self.currency = currency
        self.base = base
        self.quote = quote
        self.format = format
    }
}

extension ImportColumn: Codable {
    enum CodingKeys: String, CodingKey, CaseIterable {
        case header, index, target, field, account, instrument, currency, base, quote, format
    }

    public static var knownKeys: Set<String> { Set(CodingKeys.allCases.map(\.stringValue)) }
}

/// Long layout: fields that are the same for every row of the file.
public struct ImportConstants: Codable, Hashable, Sendable, KnownKeysProviding {
    public var account: AccountID?
    public var instrument: InstrumentID?
    public var currency: CurrencyCode?
    public var base: CurrencyCode?
    public var quote: CurrencyCode?
    /// Trades layout: where every buy, sell, fee and tax of the file was
    /// paid from or into, when no column says (`external`: another
    /// account, e.g. a dealer's invoices paid from the bank).
    public var settlement: TradeSettlement?

    public init(account: AccountID? = nil, instrument: InstrumentID? = nil, currency: CurrencyCode? = nil,
                base: CurrencyCode? = nil, quote: CurrencyCode? = nil, settlement: TradeSettlement? = nil) {
        self.account = account
        self.instrument = instrument
        self.currency = currency
        self.base = base
        self.quote = quote
        self.settlement = settlement
    }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case account, instrument, currency, base, quote, settlement
    }

    public static var knownKeys: Set<String> { Set(CodingKeys.allCases.map(\.stringValue)) }
}

/// Names found in files, matched to library IDs. Every match you confirm is
/// remembered here, e.g. both "Fineco" and "Conto Fineco" → `conto-fineco`.
public struct ImportMatches: Hashable, Sendable, KnownKeysProviding {
    public var accounts: [String: AccountID]
    public var instruments: [String: InstrumentID]

    public init(accounts: [String: AccountID] = [:], instruments: [String: InstrumentID] = [:]) {
        self.accounts = accounts
        self.instruments = instruments
    }
}

extension ImportMatches: Codable {
    enum CodingKeys: String, CodingKey, CaseIterable {
        case accounts, instruments
    }

    public static var knownKeys: Set<String> { Set(CodingKeys.allCases.map(\.stringValue)) }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        accounts = try c.decodeIfPresent([String: AccountID].self, forKey: .accounts) ?? [:]
        instruments = try c.decodeIfPresent([String: InstrumentID].self, forKey: .instruments) ?? [:]
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfNotEmpty(accounts, forKey: .accounts)
        try c.encodeIfNotEmpty(instruments, forKey: .instruments)
    }
}
