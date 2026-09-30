import Model

extension ImportSession {
    /// Replaces the mapping's layout, date column and columns with a
    /// proposal made from the headers and the detected column kinds.
    ///
    /// - Wide: the first date column holds the dates; every number column
    ///   becomes a balance, or a quantity, price, cash, purchase cost or FX
    ///   rate when its header says so (`BTC (qtà)`, `Prezzo VWCE`,
    ///   `EUR/USD`). Text, percentage and total columns are ignored. The
    ///   account or instrument comes from the header.
    /// - Long: columns become the date, account, instrument, currency and
    ///   value fields by their headers, each value column with its own target.
    ///
    /// With no `layout`, the layout is long when a text column's header
    /// names accounts or instruments, and wide otherwise.
    public mutating func proposeMapping(layout: ImportLayout? = nil) {
        let columns = detection.columns
        let layout = layout ?? Self.guessLayout(columns)
        profile.layout = layout
        profile.dateColumn = nil
        profile.target = nil
        profile.columns = []
        let dateColumn = columns.first { $0.kind == .date }?.column

        func mapping(_ column: Int, target: ImportTarget? = nil, field: ImportField? = nil) -> ImportColumn {
            let header = table.header(of: column)
            return ImportColumn(header: header, index: header == nil ? column : nil, target: target, field: field)
        }

        if layout == .long {
            var used = Set<ImportField>()
            var values: [(Int, ImportTarget)] = []
            for analysis in columns {
                let column = analysis.column
                if column == dateColumn {
                    profile.columns.append(mapping(column, field: .date))
                    continue
                }
                switch analysis.kind {
                case .empty, .date:
                    profile.columns.append(mapping(column, field: .ignore))
                case .text:
                    let field = Self.textField(analysis, used: used)
                    if field != .ignore { used.insert(field) }
                    profile.columns.append(mapping(column, field: field))
                case .number:
                    let target = Self.valueTarget(analysis)
                    values.append((profile.columns.count, target))
                    profile.columns.append(mapping(column, target: target, field: target == .ignore ? .ignore : .value))
                }
            }
            // A market value next to quantities would override them (a balance wins over positions).
            let holdsPositions = values.contains { $0.1 == .quantity }
            for (index, target) in values where holdsPositions && target == .balance {
                profile.columns[index].target = .ignore
                profile.columns[index].field = .ignore
            }
            profile.target = values.map(\.1).first { $0 != .ignore && !(holdsPositions && $0 == .balance) }
        } else {
            if let dateColumn {
                if let header = table.header(of: dateColumn) {
                    profile.dateColumn = header
                } else {
                    profile.columns.append(mapping(dateColumn, field: .date))
                }
            }
            for analysis in columns where analysis.column != dateColumn {
                var column = mapping(analysis.column, target: Self.wideTarget(analysis))
                if column.target == .fx, let header = analysis.header,
                   let pair = Keywords.currencyPair(inHeader: header) {
                    column.base = pair.base
                    column.quote = pair.quote
                }
                profile.columns.append(column)
            }
        }
    }

    static func guessLayout(_ columns: [ColumnAnalysis]) -> ImportLayout {
        let names = columns.contains { analysis in
            analysis.kind == .text
                && Keywords.header(analysis.header,
                                   has: Keywords.account + Keywords.instrument + Keywords.base + Keywords.quote)
        }
        return names ? .long : .wide
    }

    /// Wide layout: what a column's values become.
    static func wideTarget(_ analysis: ColumnAnalysis) -> ImportTarget {
        guard analysis.kind == .number, analysis.number?.percent != true else { return .ignore }
        let header = analysis.header
        if Keywords.header(header, has: Keywords.computed) { return .ignore }
        if let header, Keywords.currencyPair(inHeader: header) != nil { return .fx }
        let target = valueTarget(analysis)
        // A header that is only a value word ("Cash", "Saldo") names an account's balance.
        // A header that is only a value word ("Cash") names an account, not a part of one.
        if [.cash, .quantity, .price, .costBasis].contains(target), let header,
           Keywords.name(fromHeader: header) == TextTools.trim(header) {
            return .balance
        }
        return target
    }

    /// The target a value column's header suggests; a balance by default.
    static func valueTarget(_ analysis: ColumnAnalysis) -> ImportTarget {
        let header = analysis.header
        if analysis.number?.percent == true { return .ignore }
        if Keywords.header(header, has: Keywords.average) { return .ignore }
        if Keywords.header(header, has: Keywords.costBasis) { return .costBasis }
        if Keywords.header(header, has: Keywords.quantity) { return .quantity }
        if Keywords.header(header, has: Keywords.fx) { return .fx }
        if Keywords.header(header, has: Keywords.price) { return .price }
        if Keywords.header(header, has: Keywords.cash) { return .cash }
        return .balance
    }

    /// Long layout: which field a text column holds.
    static func textField(_ analysis: ColumnAnalysis, used: Set<ImportField>) -> ImportField {
        let header = analysis.header
        let candidates: [(ImportField, Bool)] = [
            (.base, Keywords.header(header, has: Keywords.base)),
            (.quote, Keywords.header(header, has: Keywords.quote)),
            (.currency, Keywords.header(header, has: Keywords.currency)),
            (.instrument, Keywords.header(header, has: Keywords.instrument)),
            (.account, Keywords.header(header, has: Keywords.account)),
            (.currency, analysis.samples.allSatisfy { CurrencyMarkers.currency(in: $0) != nil }),
        ]
        return candidates.first { $0.1 && !used.contains($0.0) }?.0 ?? .ignore
    }
}
