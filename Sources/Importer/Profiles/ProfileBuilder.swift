import Model

extension ImportSession {
    /// The session's mapping as a profile to save in `imports/<id>.json`,
    /// so the next file of the same shape imports in one step.
    ///
    /// Everything that was detected is written out: the file settings
    /// (encoding, delimiter, header row, footer rule), the date pattern and
    /// the most common number format as `defaults`, and a column `format`
    /// only where a column differs. Columns are listed in file order by
    /// header (by position when the file has none); unknown columns are
    /// saved as ignored, and columns missing from this file are kept. In the
    /// wide layout, accounts and instruments named by headers are written as
    /// IDs; in the long layout, every name that matched is remembered in `matches`.
    ///
    /// Pass the library after the import is applied, so names of accounts
    /// the import created resolve to their IDs.
    public func makeProfile(id: ImportProfileID, name: String, library: Library) -> ImportProfile {
        let bindings = self.bindings
        let isWide = !self.profile.layout.rowIsRecord
        var profile = self.profile
        profile.id = id
        profile.name = name
        profile.file = table.settings

        var defaults = profile.defaults
        if let dateColumn = bindings.dateColumn, let pattern = effectiveFormat(forColumn: dateColumn).date?.pattern {
            var date = defaults.date ?? ImportDateFormat()
            date.pattern = pattern
            defaults.date = date
        }
        let valueColumns = bindings.columns.keys.sorted().filter { column in
            let mapping = self.profile.columns[bindings.columns[column]!]
            return Self.isUsed(mapping) && (mapping.field?.holdsNumbers ?? true)
        }
        let numberFormats = valueColumns.compactMap { effectiveFormat(forColumn: $0).number }
        if let common = FormatDetection.commonSeparators(numberFormats) {
            var number = defaults.number ?? ImportNumberFormat()
            number.decimal = common.decimal
            number.thousands = common.thousands
            defaults.number = number
        }
        profile.defaults = defaults

        let matcher = NameMatcher(library: library, matches: profile.matches)
        var columns: [ImportColumn] = []
        for column in 1...max(table.columnCount, 1) where column <= table.columnCount {
            let header = table.header(of: column)
            if isWide, column == bindings.dateColumn {
                if let header {
                    profile.dateColumn = header
                } else {
                    profile.dateColumn = nil
                    columns.append(ImportColumn(index: column, field: .date))
                }
                continue
            }
            var mapping: ImportColumn
            if let index = bindings.columns[column] {
                mapping = self.profile.columns[index]
            } else if bindings.unknown.contains(column) {
                mapping = isWide ? ImportColumn(target: .ignore) : ImportColumn(field: .ignore)
            } else {
                continue
            }
            mapping.header = header
            mapping.index = header == nil ? column : nil
            if isWide, let header, let target = mapping.target, Self.isUsed(mapping) {
                Self.resolveHeader(header, target: target, in: &mapping, constants: profile.constants,
                                   matcher: matcher)
            }
            mapping.format = formatOverride(forColumn: column, mapping: mapping, defaults: defaults,
                                            isDateColumn: column == bindings.dateColumn)
            columns.append(mapping)
        }
        columns += bindings.missing.map { self.profile.columns[$0] }
        profile.columns = columns

        if !isWide {
            for (field, column) in bindings.columns.sorted(by: { $0.key < $1.key })
                .map({ (self.profile.columns[$0.value].field, $0.key) })
            where field == .account || field == .instrument {
                for name in Set(table.values(inColumn: column).map(\.text)) {
                    if field == .account, let (id, _) = matcher.existingAccount(named: name) {
                        profile.matches.accounts[name] = id
                    } else if field == .instrument, let (id, _) = matcher.existingInstrument(named: name) {
                        profile.matches.instruments[name] = id
                    }
                }
            }
        }
        if profile.layout == .trades {
            // The types as read now, so the next file maps them the same way.
            for value in tradeTypeValues {
                if let type = value.type, TextTools.lookup(value.value, in: profile.tradeTypes) == nil {
                    profile.tradeTypes[value.value] = type
                }
            }
        } else {
            profile.tradeTypes = [:]
        }
        return profile
    }

    /// Writes the account or instrument a wide column's header stands for
    /// into the column, as an ID.
    private static func resolveHeader(_ header: String, target: ImportTarget, in mapping: inout ImportColumn,
                                      constants: ImportConstants, matcher: NameMatcher) {
        let needsAccount = target.needsAccount, needsInstrument = target.needsInstrument
        let account = mapping.account ?? constants.account
        let instrument = mapping.instrument ?? constants.instrument
        if needsAccount, account == nil, !needsInstrument || instrument != nil {
            mapping.account = matcher.existingAccount(named: header)?.0
        } else if needsInstrument, instrument == nil, !needsAccount || account != nil {
            mapping.instrument = matcher.existingInstrument(named: header)?.0
        } else if needsAccount, needsInstrument, account == nil, instrument == nil {
            mapping.instrument = matcher.existingInstrument(named: header)?.0
        }
        if target == .fx, mapping.base == nil, mapping.quote == nil,
           let pair = Keywords.currencyPair(inHeader: header) {
            mapping.base = pair.base
            mapping.quote = pair.quote
        }
    }

    /// A column's `format`: only what differs from the profile's defaults.
    private func formatOverride(forColumn column: Int, mapping: ImportColumn, defaults: ImportFormat,
                                isDateColumn: Bool) -> ImportFormat? {
        var format = mapping.format ?? ImportFormat()
        if isDateColumn, format.date?.pattern == defaults.date?.pattern { format.date?.pattern = nil }
        if Self.isUsed(mapping), mapping.field?.holdsNumbers ?? true,
           let number = effectiveFormat(forColumn: column).number {
            var own = format.number ?? ImportNumberFormat()
            let differs = number.decimal != defaults.number?.decimal || number.thousands != defaults.number?.thousands
            own.decimal = differs ? number.decimal : nil
            own.thousands = differs ? number.thousands : nil
            own.percent = number.percent == true ? true : nil
            format.number = own
        }
        if format.date == ImportDateFormat() { format.date = nil }
        if format.number == ImportNumberFormat() { format.number = nil }
        return format == ImportFormat() ? nil : format
    }
}
