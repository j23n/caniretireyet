import Foundation
import Model

/// An import in progress: the file as read, what was detected in it, and
/// the mapping being built (an ``ImportProfile``).
///
/// Start one from a file alone, and the importer proposes a mapping; or
/// from a file and a saved profile. Edit ``profile`` directly or through the
/// helpers, then call ``preview(against:)``. Nothing here touches the library.
public struct ImportSession: Sendable {
    /// The file's bytes.
    public let data: Data
    /// The file as read with the current settings.
    public private(set) var table: ImportTable
    /// The formats detected in each column.
    public private(set) var detection: FormatDetection
    /// The mapping: how to read the file, its formats, layout, columns,
    /// matches and conflict policy. Values it leaves out are detected.
    public var profile: ImportProfile
    /// Whether re-reading the file proposes a new mapping.
    private var proposesMapping: Bool

    /// Reads a file and proposes a mapping for it. Settings left `nil` are detected.
    public init(data: Data, settings: ImportFileSettings = ImportFileSettings()) throws(ImportError) {
        self.data = data
        table = try ImportTable(data: data, settings: settings)
        detection = FormatDetection(table: table)
        profile = ImportProfile(id: "import", name: "Import", file: settings, layout: .wide)
        proposesMapping = true
        proposeMapping()
    }

    /// Reads a file with a saved profile. A profile with a layout this
    /// version doesn't know is refused.
    public init(data: Data, profile: ImportProfile) throws(ImportError) {
        guard profile.layout.isKnown else { throw .unsupportedLayout(profile.layout.rawValue) }
        self.data = data
        table = try ImportTable(data: data, settings: profile.file)
        detection = FormatDetection(table: table)
        self.profile = profile
        proposesMapping = false
    }

    /// Reads the file again with other settings (encoding, delimiter,
    /// header row, footer rule). A proposed mapping is proposed again; one
    /// from a profile or edited with ``setMapping(_:forColumn:)`` is kept.
    public mutating func reread(with settings: ImportFileSettings) throws(ImportError) {
        table = try ImportTable(data: data, settings: settings)
        detection = FormatDetection(table: table)
        profile.file = settings
        if proposesMapping { proposeMapping() }
    }

    // MARK: - Columns

    /// How each file column is used, in column order.
    public var columnRoles: [ColumnRole] {
        let bindings = self.bindings
        return (1...max(table.columnCount, 1)).filter { $0 <= table.columnCount }.map { column in
            if column == bindings.dateColumn, !profile.layout.rowIsRecord { return .date }
            if let index = bindings.columns[column] { return .mapped(profileColumn: index) }
            if bindings.unknown.contains(column) { return .unknown }
            return .unused
        }
    }

    /// The profile's column that a 1-based file column is bound to.
    public func mapping(forColumn column: Int) -> ImportColumn? {
        bindings.columns[column].map { profile.columns[$0] }
    }

    /// Sets what a file column is. Its header (or, without one, its position)
    /// is filled in, so the mapping finds the column again in the next file.
    public mutating func setMapping(_ mapping: ImportColumn, forColumn column: Int) {
        var mapping = mapping
        if let header = table.header(of: column) {
            mapping.header = header
            mapping.index = nil
        } else {
            mapping.header = nil
            mapping.index = column
        }
        let bindings = self.bindings
        if let index = bindings.columns[column] {
            profile.columns[index] = mapping
        } else {
            profile.columns.append(mapping)
        }
        if !profile.layout.rowIsRecord, bindings.dateColumn == column, mapping.field != .date {
            profile.dateColumn = nil
        }
        proposesMapping = false
    }

    /// Makes a file column the one that holds the dates. The previous date
    /// column is ignored from then on.
    public mutating func setDateColumn(_ column: Int) {
        let bindings = self.bindings
        let others = Set(profile.columns.indices.filter { profile.columns[$0].field == .date }
            + (bindings.columns[column].map { [$0] } ?? []))
        profile.columns = profile.columns.enumerated().filter { !others.contains($0.offset) }.map(\.element)
        if let previous = bindings.dateColumn, previous != column {
            let header = table.header(of: previous)
            profile.columns.append(ImportColumn(header: header, index: header == nil ? previous : nil,
                                                target: profile.layout.rowIsRecord ? nil : .ignore,
                                                field: profile.layout.rowIsRecord ? .ignore : nil))
        }
        if profile.layout.rowIsRecord {
            profile.dateColumn = nil
            setMapping(ImportColumn(field: .date), forColumn: column)
        } else if let header = table.header(of: column) {
            profile.dateColumn = header
        } else {
            profile.dateColumn = nil
            profile.columns.append(ImportColumn(index: column, field: .date))
        }
        proposesMapping = false
    }

    /// Remembers that a name in the file is this account.
    public mutating func match(account name: String, to id: AccountID) {
        profile.matches.accounts[name] = id
    }

    /// Remembers that a name in the file is this instrument.
    public mutating func match(instrument name: String, to id: InstrumentID) {
        profile.matches.instruments[name] = id
    }

    // MARK: - Formats

    /// The formats a column is read with: the column's own `format`, then
    /// the profile's `defaults`, then what was detected.
    public func effectiveFormat(forColumn column: Int) -> ImportFormat {
        let own = mapping(forColumn: column)?.format
        let detected = detection.column(column)
        let dateLayers = [own?.date, profile.defaults.date, detected?.date, detection.defaults.date]
        let date = ImportDateFormat(
            pattern: dateLayers.lazy.compactMap { $0?.pattern }.first ?? "yyyy-MM-dd",
            monthOnly: [own?.date, profile.defaults.date].lazy.compactMap { $0?.monthOnly }.first,
            timeZone: [own?.date, profile.defaults.date].lazy.compactMap { $0?.timeZone }.first)
        let numberLayers = [own?.number, profile.defaults.number, detected?.number, detection.defaults.number]
            .compactMap { $0 }
        let decimal = numberLayers.lazy.compactMap(\.decimal).first ?? "."
        let thousands = numberLayers.lazy.filter { $0.decimal == nil || $0.decimal == decimal }
            .compactMap(\.thousands).first { $0 != decimal }
        let percent = numberLayers.lazy.compactMap(\.percent).first
        return ImportFormat(date: date, number: ImportNumberFormat(decimal: decimal, thousands: thousands,
                                                                   percent: percent),
                            empty: own?.empty ?? profile.defaults.empty ?? .skip,
                            liabilitySign: own?.liabilitySign ?? profile.defaults.liabilitySign ?? .auto,
                            amountSign: own?.amountSign ?? profile.defaults.amountSign ?? .auto)
    }

    /// What the file leaves open and the mapping hasn't settled yet: only
    /// for the delimiter (unless set), the date column and mapped columns
    /// whose format isn't set.
    public var ambiguities: [ImportAmbiguity] {
        let bindings = self.bindings
        return detection.ambiguities.filter { ambiguity in
            guard let column = ambiguity.column else { return profile.file.delimiter == nil }
            let own = mapping(forColumn: column)
            let isDateColumn = column == bindings.dateColumn
            switch ambiguity.kind {
            case .delimiter:
                return profile.file.delimiter == nil
            case .dateFormat, .dateOrNumber:
                return isDateColumn && own?.format?.date?.pattern == nil && profile.defaults.date?.pattern == nil
            case .numberFormat:
                guard let own, !isDateColumn, Self.isUsed(own) else { return false }
                return own.format?.number?.decimal == nil && profile.defaults.number?.decimal == nil
            }
        }
    }

    /// Settles an ambiguity with one of its options (by index): sets the
    /// delimiter and re-reads, or sets the column's format.
    public mutating func choose(_ option: Int, for ambiguity: ImportAmbiguity) throws(ImportError) {
        switch ambiguity.kind {
        case .delimiter:
            guard ambiguity.delimiters.indices.contains(option) else { return }
            var settings = profile.file
            settings.delimiter = ambiguity.delimiters[option]
            try reread(with: settings)
        case .dateFormat, .dateOrNumber, .numberFormat:
            guard let column = ambiguity.column, ambiguity.options.indices.contains(option) else { return }
            let chosen = ambiguity.options[option]
            if let date = chosen.date {
                var defaults = profile.defaults.date ?? ImportDateFormat()
                defaults.pattern = date.pattern
                profile.defaults.date = defaults
            } else if let number = chosen.number {
                if ambiguity.kind == .dateOrNumber {
                    setMapping(ImportColumn(target: .balance, format: ImportFormat(number: number)), forColumn: column)
                } else if var mapping = mapping(forColumn: column) {
                    var format = mapping.format ?? ImportFormat()
                    format.number = number
                    mapping.format = format
                    setMapping(mapping, forColumn: column)
                }
            }
        }
    }

    // MARK: - Problems before matching

    /// Problems with the mapping that don't depend on the library: unknown
    /// and missing columns, no date column, broken quotes.
    public var issues: [ImportIssue] {
        let bindings = self.bindings
        var issues: [ImportIssue] = []
        if bindings.dateColumn == nil { issues.append(ImportIssue(kind: .noDateColumn)) }
        if !profile.layout.rowIsRecord, let header = profile.dateColumn, bindings.dateColumn == nil {
            issues.append(ImportIssue(kind: .missingColumn, header: header))
        }
        for index in bindings.missing {
            let column = profile.columns[index]
            issues.append(ImportIssue(kind: .missingColumn, column: column.index, header: column.header))
        }
        for column in bindings.unknown {
            issues.append(ImportIssue(kind: .unknownColumn, column: column, header: table.header(of: column)))
        }
        if let column = bindings.dateColumn,
           let pattern = effectiveFormat(forColumn: column).date?.pattern, !DateParser.isValidPattern(pattern) {
            issues.append(ImportIssue(kind: .invalidDatePattern(pattern), column: column,
                                      header: table.header(of: column)))
        }
        issues += table.brokenQuoteRows.map { ImportIssue(kind: .unterminatedQuote(row: $0)) }
        return issues
    }

    // MARK: - Bindings

    /// Which file column each part of the profile uses.
    struct Bindings: Hashable {
        var dateColumn: Int?
        /// File column → index in `profile.columns`.
        var columns: [Int: Int] = [:]
        /// File columns with values that the profile doesn't know.
        var unknown: [Int] = []
        /// Indices in `profile.columns` of columns the file doesn't have.
        var missing: [Int] = []
    }

    /// Columns are found by header text (exactly, then ignoring case and
    /// accents), and by position only when the file or the column has no header.
    var bindings: Bindings {
        var bindings = Bindings()
        var claimed = Set<Int>()
        let count = table.columnCount
        let isWide = !profile.layout.rowIsRecord

        func find(header: String?, index: Int?) -> Int? {
            guard count > 0 else { return nil }
            if let header, table.hasHeader {
                let trimmed = TextTools.trim(header), folded = TextTools.fold(header)
                if let column = (1...count).first(where: { !claimed.contains($0) && table.headers[$0 - 1] == trimmed })
                    ?? (1...count).first(where: {
                        !claimed.contains($0) && TextTools.fold(table.headers[$0 - 1]) == folded
                    }) {
                    return column
                }
            }
            if let index, !table.hasHeader || header == nil, (1...count).contains(index), !claimed.contains(index) {
                return index
            }
            return nil
        }

        if isWide, let header = profile.dateColumn, let column = find(header: header, index: nil) {
            bindings.dateColumn = column
            claimed.insert(column)
        }
        for (index, mapping) in profile.columns.enumerated() {
            guard let column = find(header: mapping.header, index: mapping.index) else {
                if Self.isUsed(mapping) { bindings.missing.append(index) }
                continue
            }
            claimed.insert(column)
            if isWide, mapping.field == .date {
                if bindings.dateColumn == nil { bindings.dateColumn = column }
                continue
            }
            bindings.columns[column] = index
            if !isWide, mapping.field == .date, bindings.dateColumn == nil { bindings.dateColumn = column }
        }
        for column in 1...max(count, 1) where column <= count && !claimed.contains(column) {
            if table.header(of: column) != nil || !table.values(inColumn: column).isEmpty {
                bindings.unknown.append(column)
            }
        }
        return bindings
    }

    /// Whether a mapped column is imported (not ignored).
    static func isUsed(_ mapping: ImportColumn) -> Bool {
        if let field = mapping.field { return field != .ignore }
        if let target = mapping.target { return target != .ignore }
        return false
    }
}

/// How a file column is used by the mapping.
public enum ColumnRole: Hashable, Sendable {
    /// It holds the dates (wide layout).
    case date
    /// It's bound to `profile.columns[profileColumn]`.
    case mapped(profileColumn: Int)
    /// It has values but the profile doesn't know it: flagged, not imported.
    case unknown
    /// It's empty.
    case unused
}
